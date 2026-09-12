-- プラン予約(pending downgrade/crossgrade)の可視化。
--
-- Appleの同一サブスクリプショングループ内のダウングレード/クロスグレードは
-- 即時には何も変わらず、次回更新日に切り替わることが「予約」されるだけ。
-- クライアントSDK(purchases_flutter)は予約状態を直接教えてくれないが、
-- RevenueCatは予約された瞬間にPRODUCT_CHANGE Webhookイベントを即座に送る
-- (実際の切り替えを待たない)。ペイロードのnew_product_idを使って、この
-- 「予約状態」だけをDBに記録する。実際のクレジット付与・プラン切り替えは
-- 従来通り本物のRENEWALイベントが来た時にのみ行う(ここは変更しない)。

-- 1. カラム追加: 今アクティブな行が、将来切り替わる予定の別プランID。
ALTER TABLE public.user_subscription_mappings
  ADD COLUMN pending_plan_id uuid REFERENCES public.subscription_plans(id);

-- 2. set_pending_plan_change: PRODUCT_CHANGEイベント専用のハンドラ。
--    予約・予約し直し・予約取り消し(現在のプランへ選び直す)の3パターンを
--    「新しい予約先がactiveなプランと同じかどうか」の1判定で吸収する
--    (RevenueCat公式の「最後に選んだ変更が常に有効」という仕様と自然に一致)。
CREATE OR REPLACE FUNCTION public.set_pending_plan_change(
  p_user_id        uuid,
  p_event_id       text,
  p_new_product_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_new_plan subscription_plans;
  v_mapping user_subscription_mappings;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'PRODUCT_CHANGE')
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  select * into v_new_plan from subscription_plans where store_product_id = p_new_product_id;
  if v_new_plan.id is null then
    raise exception 'unknown_store_product: %', p_new_product_id;
  end if;

  select * into v_mapping from user_subscription_mappings
    where user_id = p_user_id and status = 'active'
    limit 1;

  if v_mapping.id is null then
    -- 予約通知が届いた時点でアクティブなmappingが無い(順序が前後した等)。
    -- 実際の切り替えは後続のRENEWALが正しく処理するため、ここは無視してよい。
    return;
  end if;

  update user_subscription_mappings
    set pending_plan_id = case when v_new_plan.id = v_mapping.plan_id then null else v_new_plan.id end
    where id = v_mapping.id;
end;
$function$;

-- 3. grant_store_subscription_credits: 実際に切り替えが発効した瞬間に
--    pending_plan_idを必ずクリアする(既存本体は20260911000000から変更なし)。
CREATE OR REPLACE FUNCTION public.grant_store_subscription_credits(
  p_user_id     uuid,
  p_event_id    text,
  p_event_type  text,
  p_product_id  text,
  p_period_end  timestamp with time zone
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
  v_source text;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, p_event_type)
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
      and plan_id <> v_plan.id
      and status = 'active';

  -- ↑と同じ対象(乗り換え元のプラン)の未消化クレジットもロールオーバーさせない。
  update credit_grants
    set remaining_amount = 0
    where user_id = p_user_id
      and plan_id <> v_plan.id
      and plan_id is not null
      and remaining_amount > 0;

  insert into user_subscription_mappings
      (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id)
    values (p_user_id, v_plan.id, 'active', now(), p_period_end, null)
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_end = excluded.current_period_end,
          pending_plan_id = null;

  v_source := case when p_event_type = 'INITIAL_PURCHASE'
                then 'subscription_initial_store'
                else 'subscription_renewal_store' end;

  update credit_grants
    set remaining_amount = 0
    where user_id = p_user_id
      and plan_id = v_plan.id
      and source in ('subscription_initial_store', 'subscription_renewal_store')
      and remaining_amount > 0;

  perform grant_credits(p_user_id, v_plan.monthly_credit_amount, v_source, v_plan.id, p_period_end);
end;
$function$;

-- 4. expire_store_subscription: Freeフォールバックのinsert/upsertにも
--    pending_plan_id = null を追加(既存本体は20260911010000から変更なし)。
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

  select * into v_free_plan from subscription_plans
    where claim_mode = 'self_serve' and disabled_at is null
    order by created_at asc
    limit 1;

  if v_free_plan.id is not null then
    v_free_period_end := now() + (v_free_plan.billing_interval_months || ' months')::interval;

    update credit_grants
      set remaining_amount = 0
      where user_id = p_user_id
        and plan_id <> v_free_plan.id
        and plan_id is not null
        and remaining_amount > 0;

    insert into user_subscription_mappings
        (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id)
      values (p_user_id, v_free_plan.id, 'active', now(), v_free_period_end, null)
      on conflict (user_id, plan_id) do update
        set status = 'active',
            current_period_start = now(),
            current_period_end = v_free_period_end,
            pending_plan_id = null;

    perform grant_credits(p_user_id, v_free_plan.monthly_credit_amount, 'subscription_initial', v_free_plan.id, v_free_period_end);
  end if;
end;
$function$;

-- 5. get_credit_summary: pending_plan_idを返り値に追加。
--    RETURNS TABLEの列構成(OUT引数)を変える場合、CREATE OR REPLACEでは
--    「既存関数の戻り値の型は変更できない」というエラーになるため、
--    先に明示的にDROPしてから作り直す必要がある。
DROP FUNCTION IF EXISTS public.get_credit_summary(uuid);

CREATE FUNCTION public.get_credit_summary(p_user_id uuid)
 RETURNS TABLE(
   credit_balance bigint,
   monthly_allocation bigint,
   extra_credit_balance bigint,
   has_active_plan boolean,
   current_period_end timestamp with time zone,
   pending_plan_id uuid
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_mapping user_subscription_mappings;
  v_plan subscription_plans;
begin
  select coalesce(sum(remaining_amount), 0) into credit_balance
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now());

  select * into v_mapping from user_subscription_mappings
    where user_id = p_user_id and status = 'active'
    limit 1;

  if v_mapping.id is not null then
    has_active_plan := true;
    current_period_end := v_mapping.current_period_end;
    pending_plan_id := v_mapping.pending_plan_id;
    select * into v_plan from subscription_plans where id = v_mapping.plan_id;
    monthly_allocation := v_plan.monthly_credit_amount;
  else
    has_active_plan := false;
  end if;

  select coalesce(sum(remaining_amount), 0) into extra_credit_balance
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now())
      and source not in (
        'subscription_initial', 'subscription_renewal',
        'subscription_initial_store', 'subscription_renewal_store'
      );

  return next;
end;
$function$;
