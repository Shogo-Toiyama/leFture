-- 1. claim_plan(): 「過去に一度でもclaimしたら二度とclaimできない」という
--    判定を、「今アクティブなら不可」に緩和する。
--
-- 背景: 元々はβ特別プランを想定した「一度きりのボーナス」の重複取得防止
-- だったが、Freeプランを「サブスク失効時に自動で戻ってくる恒久的な
-- フォールバック階層」として使う方針に変えたため、一度expiredになった
-- 後の再claimを禁止したままだと、ユーザーがFreeへ二度と戻れなくなる。
CREATE OR REPLACE FUNCTION public.claim_plan(p_user_id uuid, p_plan_id uuid)
 RETURNS user_subscription_mappings
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
  v_mapping user_subscription_mappings;
begin
  select * into v_plan from subscription_plans where id = p_plan_id;

  if v_plan.id is null then
    raise exception 'plan_not_found';
  end if;

  if v_plan.claim_mode <> 'self_serve' then
    raise exception 'plan_not_self_serve';
  end if;

  if v_plan.disabled_at is not null and now() >= v_plan.disabled_at then
    raise exception 'plan_expired';
  end if;

  if exists (
    select 1 from user_subscription_mappings
    where user_id = p_user_id and plan_id = p_plan_id and status = 'active'
  ) then
    raise exception 'plan_already_claimed';
  end if;

  insert into user_subscription_mappings (user_id, plan_id, status, current_period_start, current_period_end)
    values (
      p_user_id, p_plan_id, 'active', now(),
      now() + (v_plan.billing_interval_months || ' months')::interval
    )
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_start = now(),
          current_period_end = excluded.current_period_end
    returning * into v_mapping;

  perform grant_credits(
    p_user_id, v_plan.monthly_credit_amount, 'subscription_initial', p_plan_id,
    v_mapping.current_period_end
  );

  return v_mapping;
end;
$function$;

-- 2. expire_store_subscription(): 有料プランが本当に失効(EXPIRATION)した時、
--    ユーザーを「何のプランにも属さない」状態のまま放置せず、自動的に
--    Freeプランへフォールバックさせる。
--    (サブスクのキャンセルはApp Store側でしかできないため、私たちが
--     「キャンセルされた」ことを知れるのは実質EXPIRATIONイベントのみ。
--     CANCELLATION(自動更新オフ)は期間終了まで有効なままなので、ここでは
--     一切触らない — main.py側のイベント振り分けで元々EXPIRATIONだけが
--     この関数を呼ぶ設計になっている)。
CREATE OR REPLACE FUNCTION public.expire_store_subscription(
  p_user_id    uuid,
  p_event_id   text,
  p_product_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
  v_free_plan subscription_plans;
  v_free_period_end timestamptz;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'EXPIRATION')
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  select * into v_plan from subscription_plans where store_product_id = p_product_id;
  if v_plan.id is null then
    raise exception 'unknown_store_product: %', p_product_id;
  end if;

  update user_subscription_mappings
    set status = 'expired'
    where user_id = p_user_id
      and plan_id = v_plan.id
      and status = 'active';

  -- ユーザーは必ずどこかのプランに属している状態にする。claim_mode='self_serve'
  -- の中で一番古い(=Freeプラン想定)行を探して自動付与する。
  select * into v_free_plan from subscription_plans
    where claim_mode = 'self_serve' and disabled_at is null
    order by created_at asc
    limit 1;

  if v_free_plan.id is not null then
    v_free_period_end := now() + (v_free_plan.billing_interval_months || ' months')::interval;

    -- 失効した有料プラン以外の、まだ残っている未消化クレジットも
    -- ロールオーバーさせない(grant_store_subscription_creditsと同じ思想)。
    update credit_grants
      set remaining_amount = 0
      where user_id = p_user_id
        and plan_id <> v_free_plan.id
        and plan_id is not null
        and remaining_amount > 0;

    insert into user_subscription_mappings
        (user_id, plan_id, status, current_period_start, current_period_end)
      values (p_user_id, v_free_plan.id, 'active', now(), v_free_period_end)
      on conflict (user_id, plan_id) do update
        set status = 'active',
            current_period_start = now(),
            current_period_end = v_free_period_end;

    perform grant_credits(p_user_id, v_free_plan.monthly_credit_amount, 'subscription_initial', v_free_plan.id, v_free_period_end);
  end if;
end;
$function$;
