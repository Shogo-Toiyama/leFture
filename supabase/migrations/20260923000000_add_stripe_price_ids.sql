-- Web版のStripe決済対応(自前Stripeアカウント + RevenueCat連携、追加クレジットのみ
-- RevenueCatを経由しない自前webhook)の第一歩。
--
-- 設計: subscription_plans/credit_packsの各行に、既存のApple用store_product_id列とは
-- 別にstripe_price_id列を追加する(行を複製しない)。理由は、既存のgrant系関数群が
-- すべて(user_id, plan_id)をキーにupsertする設計になっているため、同じtierを
-- 「1行」で表現し続けることで、あるユーザーがApple版を解約してStripe版の同じtierへ
-- 乗り換えた場合でも、同一のuser_subscription_mappings行がそのまま引き継がれる
-- (プラン変更予約set_pending_plan_changeのid比較ロジックも含めて、プラットフォームを
-- 跨いでも同一プランとして正しく扱われる)。
--
-- 既存のstore_product_id検索(`where store_product_id = p_product_id`)をすべて
-- `where store_product_id = p_product_id or stripe_price_id = p_product_id`に広げる。
-- stripe_price_idがNULLの既存行(未対応プラン)には一切影響しない。

-- ---------------------------------------------------------------------------
-- 1. カラム追加
-- ---------------------------------------------------------------------------

ALTER TABLE public.subscription_plans
  ADD COLUMN stripe_price_id text;

CREATE UNIQUE INDEX subscription_plans_stripe_price_id_uidx
  ON public.subscription_plans (stripe_price_id)
  WHERE stripe_price_id IS NOT NULL;

ALTER TABLE public.credit_packs
  ADD COLUMN stripe_price_id text;

CREATE UNIQUE INDEX credit_packs_stripe_price_id_uidx
  ON public.credit_packs (stripe_price_id)
  WHERE stripe_price_id IS NOT NULL AND disabled_at IS NULL;

-- ---------------------------------------------------------------------------
-- 2. 既存行へのStripe Price ID割り当て(Stripe Sandbox上で作成済みのProduct/Price)
-- ---------------------------------------------------------------------------

UPDATE public.subscription_plans SET stripe_price_id = 'price_1UGZplJ0KiP32P3AdoEOhHEW' -- sub_lite_monthly
  WHERE store_product_id = 'com.lefture.app.sub.starter';
UPDATE public.subscription_plans SET stripe_price_id = 'price_1UGZqBJ0KiP32P3AtEHpSOzP' -- sub_core_monthly
  WHERE store_product_id = 'com.lefture.app.sub.standard';
UPDATE public.subscription_plans SET stripe_price_id = 'price_1UGZqZJ0KiP32P3Am4zv1Af3' -- sub_max_monthly
  WHERE store_product_id = 'com.lefture.app.sub.premium';

UPDATE public.credit_packs SET stripe_price_id = 'price_1UGZrPJ0KiP32P3AaGXtv8S2' -- credits_100
  WHERE store_product_id = 'com.lefture.app.credits.100';
UPDATE public.credit_packs SET stripe_price_id = 'price_1UGZrrJ0KiP32P3A1TwTOqmI' -- credits_500
  WHERE store_product_id = 'com.lefture.app.credits.500';
UPDATE public.credit_packs SET stripe_price_id = 'price_1UGZsIJ0KiP32P3AAmUI4Zdp' -- credits_2000
  WHERE store_product_id = 'com.lefture.app.credits.2000';

-- ---------------------------------------------------------------------------
-- 3. サブスク系: store_product_id検索をstripe_price_idにも広げる
--    (各関数の本体は現行の最新定義から、検索条件の1行以外は変更しない)
-- ---------------------------------------------------------------------------

-- grant_store_subscription_credits: 20260921010000の定義+検索条件のみ変更。
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
    where store_product_id = p_product_id or stripe_price_id = p_product_id;
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
      (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id)
    values (p_user_id, v_plan.id, 'active', now(), p_period_end, null)
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_end = excluded.current_period_end,
          pending_plan_id = null;

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

-- expire_store_subscription: 20260919000000の定義+検索条件のみ変更。
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
    where store_product_id = p_product_id or stripe_price_id = p_product_id;
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

-- set_pending_plan_change: 20260912000000の定義+検索条件のみ変更。
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

  select * into v_new_plan from subscription_plans
    where store_product_id = p_new_product_id or stripe_price_id = p_new_product_id;
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

-- handle_billing_issue: 20260921010000の定義+検索条件のみ変更。
CREATE OR REPLACE FUNCTION public.handle_billing_issue(
  p_user_id     uuid,
  p_event_id    text,
  p_product_id  text,
  p_period_end  timestamp with time zone
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
  v_zeroed_amount bigint;
  v_balance_after bigint;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'BILLING_ISSUE')
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  perform materialize_expired_grants(p_user_id);

  select * into v_plan from subscription_plans
    where store_product_id = p_product_id or stripe_price_id = p_product_id;
  if v_plan.id is null then
    raise exception 'unknown_store_product: %', p_product_id;
  end if;

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

  perform grant_credits(
    p_user_id, v_plan.monthly_credit_amount, 'subscription_grace_period', v_plan.id,
    p_period_end + interval '6 hours'
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. 追加クレジット: grant_credit_pack_purchaseの検索条件を広げ、event_typeを
--    引数化する(自前Stripe webhookからも同じ関数を呼び、'NON_RENEWING_PURCHASE'
--    ではなくStripe由来と分かるevent_typeを渡せるようにするため)。
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.grant_credit_pack_purchase(
  p_user_id    uuid,
  p_event_id   text,
  p_product_id text,
  p_event_type text DEFAULT 'NON_RENEWING_PURCHASE'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_pack credit_packs;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, p_event_type)
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  select * into v_pack from credit_packs
    where (store_product_id = p_product_id or stripe_price_id = p_product_id)
      and disabled_at is null;
  if v_pack.id is null then
    raise exception 'unknown_credit_pack: %', p_product_id;
  end if;

  perform grant_credits(p_user_id, v_pack.credit_amount, 'credit_pack_purchase', NULL, NULL);
end;
$function$;
