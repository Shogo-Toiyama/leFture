-- クロスプラットフォーム(Apple⇔Stripe)アップグレード対応の前提工事。
--
-- 1. user_subscription_mappingsにauto_renew_disabled列を追加。
--    Appleの契約が「解約予約済み(自動更新オフ)」であることを示すフラグ。
--    これが立っているときに限り、/billing/stripe/switch-plan側でApple残存
--    期間分を割引してのStripe即時購入を許可する(別マイグレーション/PRで
--    実装予定、このマイグレーションはその判定材料を用意するだけ)。
--
-- 2. expire_store_subscriptionの安全ガード。
--    現行の実装(20260926000000_add_stripe_product_id_lookup.sql)は、
--    該当プランのmappingをexpiredにした直後、ユーザーに他のactiveな契約が
--    残っているかを一切確認せずFreeプランへのフォールバックとクレジット
--    ゼロ化を無条件に行っていた。このため、あるプラットフォームの契約から
--    別プラットフォームの契約へ乗り換えた場合、乗り換え元の契約が自然
--    満了してEXPIRATIONが届いた瞬間、乗り換えたばかりの新しい契約の
--    クレジットが誤って消され、Freeに落とされてしまう(新しい契約側の
--    課金だけは継続する)。これは今回の新機能を待たず単独で直すべき
--    既存バグなので先行して直す。
--
-- 3. grant_store_subscription_creditsのupsertにauto_renew_disabled=falseを
--    追加。INITIAL_PURCHASE/RENEWAL/UNCANCELLATIONのいずれでもリセットし、
--    ユーザーが自動更新を再度ONに戻した場合に正しく反映されるようにする。
--
-- 4. 新規RPC mark_apple_subscription_auto_renew_disabled。
--    RevenueCatのCANCELLATIONイベント(Apple由来、event["store"] ==
--    "APP_STORE"のときのみmain.py側で呼ばれる)を受けてauto_renew_disabled
--    をtrueにするだけ。ステータス・クレジットには一切触れない
--    (expire_store_subscriptionと同じく、既存の設計方針を踏襲)。

-- ---------------------------------------------------------------------------
-- 1. カラム追加
-- ---------------------------------------------------------------------------

ALTER TABLE public.user_subscription_mappings
  ADD COLUMN auto_renew_disabled boolean NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------------
-- 2. expire_store_subscription: 他にactiveな契約が残っていればFreeフォール
--    バックをスキップするガードを追加。検索条件自体は20260926000000から
--    変更しない。
-- ---------------------------------------------------------------------------

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
  v_zeroed_amount bigint;
  v_balance_after bigint;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'EXPIRATION')
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  perform materialize_expired_grants(p_user_id);

  select * into v_plan from subscription_plans
    where store_product_id = p_product_id
       or stripe_price_id = p_product_id
       or stripe_product_id = p_product_id;
  if v_plan.id is null then
    raise exception 'unknown_store_product: %', p_product_id;
  end if;

  update user_subscription_mappings
    set status = 'expired'
    where user_id = p_user_id
      and plan_id = v_plan.id
      and status = 'active';

  -- 既に他プラットフォームの契約に乗り換え済みで、そちらがまだactiveなら
  -- Freeフォールバックはスキップする。乗り換えたばかりの新プランの
  -- クレジットを、後から届いた旧プランのEXPIRATIONで誤って消してしまう
  -- (新プランの課金だけは継続する)のを防ぐガード。
  if exists (
    select 1 from user_subscription_mappings
    where user_id = p_user_id and status = 'active'
  ) then
    return;
  end if;

  select * into v_free_plan from subscription_plans
    where claim_mode = 'self_serve' and disabled_at is null
    order by created_at asc
    limit 1;

  if v_free_plan.id is not null then
    v_free_period_end := now() + (v_free_plan.billing_interval_months || ' months')::interval;

    select coalesce(sum(remaining_amount), 0) into v_zeroed_amount
      from credit_grants
      where user_id = p_user_id
        and plan_id <> v_free_plan.id
        and plan_id is not null
        and remaining_amount > 0;

    if v_zeroed_amount > 0 then
      update credit_grants
        set remaining_amount = 0
        where user_id = p_user_id
          and plan_id <> v_free_plan.id
          and plan_id is not null
          and remaining_amount > 0;

      select coalesce(sum(remaining_amount), 0) into v_balance_after
        from credit_grants
        where user_id = p_user_id
          and remaining_amount > 0
          and (expires_at is null or expires_at > now());

      insert into credit_transactions (user_id, delta, balance_after, reason)
        values (p_user_id, -v_zeroed_amount, v_balance_after, 'credit_reset_plan_changed');
    end if;

    insert into user_subscription_mappings
        (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id)
      values (p_user_id, v_free_plan.id, 'active', now(), v_free_period_end, null)
      on conflict (user_id, plan_id) do update
        set status = 'active',
            current_period_start = now(),
            current_period_end = v_free_period_end,
            pending_plan_id = null;

    perform grant_credits(p_user_id, v_free_plan.monthly_credit_amount, 'subscription_initial', v_free_plan.id, v_free_period_end + interval '6 hours');
  end if;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. grant_store_subscription_credits: upsertにauto_renew_disabled=falseを
--    追加。それ以外は20260926000000から変更しない。
-- ---------------------------------------------------------------------------

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
  v_zeroed_amount bigint;
  v_balance_after bigint;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, p_event_type)
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  perform materialize_expired_grants(p_user_id);

  select * into v_plan from subscription_plans
    where store_product_id = p_product_id
       or stripe_price_id = p_product_id
       or stripe_product_id = p_product_id;
  if v_plan.id is null then
    raise exception 'unknown_store_product: %', p_product_id;
  end if;

  update user_subscription_mappings
    set status = 'expired'
    where user_id = p_user_id
      and plan_id <> v_plan.id
      and status = 'active';

  -- 乗り換え元プランの未消化クレジットをロールオーバーさせない。
  select coalesce(sum(remaining_amount), 0) into v_zeroed_amount
    from credit_grants
    where user_id = p_user_id
      and plan_id <> v_plan.id
      and plan_id is not null
      and remaining_amount > 0;

  if v_zeroed_amount > 0 then
    update credit_grants
      set remaining_amount = 0
      where user_id = p_user_id
        and plan_id <> v_plan.id
        and plan_id is not null
        and remaining_amount > 0;

    select coalesce(sum(remaining_amount), 0) into v_balance_after
      from credit_grants
      where user_id = p_user_id
        and remaining_amount > 0
        and (expires_at is null or expires_at > now());

    insert into credit_transactions (user_id, delta, balance_after, reason)
      values (p_user_id, -v_zeroed_amount, v_balance_after, 'credit_reset_plan_changed');
  end if;

  insert into user_subscription_mappings
      (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id, auto_renew_disabled)
    values (p_user_id, v_plan.id, 'active', now(), p_period_end, null, false)
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_end = excluded.current_period_end,
          pending_plan_id = null,
          auto_renew_disabled = false;

  v_source := case when p_event_type = 'INITIAL_PURCHASE'
                then 'subscription_initial_store'
                else 'subscription_renewal_store' end;

  -- 同一プランの重複grant防止(サンドボックスの重複/前後したRENEWAL配信対策、
  -- およびGrace Period中に付与したgrace grantの解消)。
  select coalesce(sum(remaining_amount), 0) into v_zeroed_amount
    from credit_grants
    where user_id = p_user_id
      and plan_id = v_plan.id
      and source in ('subscription_initial_store', 'subscription_renewal_store', 'subscription_grace_period')
      and remaining_amount > 0;

  if v_zeroed_amount > 0 then
    update credit_grants
      set remaining_amount = 0
      where user_id = p_user_id
        and plan_id = v_plan.id
        and source in ('subscription_initial_store', 'subscription_renewal_store', 'subscription_grace_period')
        and remaining_amount > 0;

    select coalesce(sum(remaining_amount), 0) into v_balance_after
      from credit_grants
      where user_id = p_user_id
        and remaining_amount > 0
        and (expires_at is null or expires_at > now());

    insert into credit_transactions (user_id, delta, balance_after, reason)
      values (p_user_id, -v_zeroed_amount, v_balance_after, 'credit_reset_renewed');
  end if;

  perform grant_credits(p_user_id, v_plan.monthly_credit_amount, v_source, v_plan.id, p_period_end + interval '6 hours');
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. 新規RPC: mark_apple_subscription_auto_renew_disabled
--    Apple由来のCANCELLATIONイベントでのみ呼ばれる(main.py側でevent["store"]
--    == "APP_STORE"を確認済み)。ステータス・クレジットには一切触れない。
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.mark_apple_subscription_auto_renew_disabled(
  p_user_id    uuid,
  p_event_id   text,
  p_product_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'CANCELLATION')
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  select * into v_plan from subscription_plans
    where store_product_id = p_product_id
       or stripe_price_id = p_product_id
       or stripe_product_id = p_product_id;
  if v_plan.id is null then
    raise exception 'unknown_store_product: %', p_product_id;
  end if;

  update user_subscription_mappings
    set auto_renew_disabled = true
    where user_id = p_user_id
      and plan_id = v_plan.id
      and status = 'active';
end;
$function$;
