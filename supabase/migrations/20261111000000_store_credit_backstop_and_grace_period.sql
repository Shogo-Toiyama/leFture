-- ストア課金(App Store / Stripe)のクレジット失効を、RevenueCatの契約状態に合わせる。
--
-- これまで: 付与するクレジットの expires_at = 契約の期間終了 + 6時間。
--   更新(RENEWAL)が遅れる・届かないと、ストア側はまだ有効(Billing Grace Period 28日など)でも
--   数時間でクレジットが消えた。BILLING_ISSUE の特別処理は「ゼロにして満額を再付与」していて、
--   元の設計メモ(20260921010000)の「同額を再付与」とも食い違っていた(=決済失敗のたびに満額に戻る)。
--
-- これから:
--   * クレジットを消す主役は RevenueCat の信号(EXPIRATION / TRANSFER / プラン変更 / reconcile)。
--   * expires_at は「信号を取りこぼしたときの保険」。契約の期間終了 + 30日(= Grace Period 28日 + 2日)。
--     Grace Period 中にRENEWAL/BILLING_ISSUEが届かなくても、Apple が有効としている間は消えない。
--   * BILLING_ISSUE: クレジットを増やさない・減らさない。期限(保険)を、ストアが報告した
--     Grace Period の終了日 + 2日まで延ばすだけ(今より短くはしない)。
--     決済が回復すれば RENEWAL が通常どおり(ゼロ化→月額付与)、回復しなければ EXPIRATION で
--     Free に戻る(従来どおり expire_store_subscription)。
--   * 自己申告型プラン(Free / Welcome Bonus)の6時間はここでは触らない(別の仕組み)。

CREATE OR REPLACE FUNCTION public.store_credit_backstop()
RETURNS interval
LANGUAGE sql
IMMUTABLE
AS $$ SELECT interval '30 days' $$;

-- grant_store_subscription_credits: 20261104010000 の定義のうち、期限の
-- `p_period_end + interval '6 hours'` を `p_period_end + store_credit_backstop()` に変えただけ。
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
  v_store text;
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

  v_store := case when v_plan.store_product_id = p_product_id then 'APP_STORE' else 'STRIPE' end;

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
      (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id, auto_renew_disabled, store)
    values (p_user_id, v_plan.id, 'active', now(), p_period_end, null, false, v_store)
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_end = excluded.current_period_end,
          pending_plan_id = null,
          auto_renew_disabled = false,
          store = excluded.store;

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

  perform grant_credits(p_user_id, v_plan.monthly_credit_amount, v_source, v_plan.id, p_period_end + public.store_credit_backstop());
end;
$function$;

-- handle_billing_issue: ゼロ化も再付与もしない。期限(保険)を延ばすだけ。
-- p_period_end は RevenueCat の grace_period_expiration_at_ms(無ければ expiration_at_ms)。
-- expiration_at_ms は取引自体の期限で、Grace Period 分は延びない(RevenueCat公式)ため、
-- 後者を渡された場合は既存の期限(期間終了 + 30日)より短くなり、何も変わらない。
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
  v_new_expiry timestamptz;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'BILLING_ISSUE')
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

  -- materialize_expired_grants は呼ばない(期限切れ直後に届いた場合でも、
  -- 残高をゼロにせず、ここで期限を延ばして生かすため)。
  v_new_expiry := p_period_end + interval '2 days';

  update credit_grants
    set expires_at = v_new_expiry
    where user_id = p_user_id
      and plan_id = v_plan.id
      and source in ('subscription_initial_store', 'subscription_renewal_store', 'subscription_grace_period')
      and remaining_amount > 0
      and expires_at is not null
      and expires_at < v_new_expiry;
end;
$function$;

REVOKE ALL ON FUNCTION public.store_credit_backstop() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.store_credit_backstop() TO service_role;
