-- expire_store_subscription: 同一プランのクロスプラットフォーム乗り換えで、
-- 購入したばかりの新契約が旧契約のEXPIRATIONに巻き込まれて消える問題の修正。
--
-- 20260927000000で入れたガードは「他にactiveなmappingが残っていればFreeフォール
-- バックをスキップする」というもので、乗り換え先が別tier(=別のplan行)の場合しか
-- 効かない。subscription_plansは1tier1行でstore_product_id(Apple)と
-- stripe_price_id(Stripe)を同じ行が両方持つ設計のため、同一tierでの乗り換え
-- (例: Stripe Standard → Apple Standard)では両プラットフォームが同じplan行を
-- 共有し、user_subscription_mappingsも(user_id, plan_id)のUNIQUEにより1行しかない。
--
-- その結果、Stripe→Apple(同一tier)で次の順序が確定的に発生していた:
--   1. Apple INITIAL_PURCHASE → grant_store_subscription_credits が
--      「Standard行」をactive化し、Appleの期間・クレジットを書き込む
--   2. 同じwebhookハンドラ内で _attempt_cancel_stripe_for_platform_switch が
--      Stripeサブスクを即時解約する
--   3. その解約を受けてRevenueCatがStripeのEXPIRATIONを送ってくる
--   4. expire_store_subscription が同じ「Standard行」を解決し、1でactiveに
--      したばかりの行をexpiredにする
--   5. 既存ガードの exists(active) は何も見つけられず、Freeフォールバックが走り
--      Apple分のクレジットを全てゼロ化してFreeに落とす
-- ユーザーはAppleに課金された直後にFreeへ落ちる。
--
-- 対策: 「対象plan行が、まだactiveかつcurrent_period_endが十分先」の場合は、
-- 届いたEXPIRATIONを『既に終わった旧契約のもの』とみなして完全に無視する。
-- 自然満了の正規のEXPIRATIONでは current_period_end ≒ now() になるため、
-- 1時間の余裕を持たせて両者を区別する(乗り換え直後の再active化では
-- current_period_endが1ヶ月先になっている)。
--
-- トレードオフ: このガードにより「期間の途中で即時解約されたサブスク」の
-- EXPIRATIONも無視される。通常フローで即時解約が起きるのは
-- _cancel_stripe_subscription_for_platform_switch(=まさに乗り換え)だけなので
-- 実害は無いが、運営がStripeダッシュボードから手動で即時解約した場合は、
-- 元の期間終了までプランとクレジットが残る(credit_grantsのexpires_atは
-- period_end + 6時間なので、いずれにせよそこで自然に失効する)。即時失効
-- させたい場合はmappingを直接expiredにする運用が必要。
--
-- 20260927000000の定義から、このガードの追加以外は一切変更しない。

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

  -- ガード1: 同じplan行が、このEXPIRATIONが示す期間よりずっと先まで有効な
  -- 状態でactiveになっている = 別プラットフォームで契約し直された後である。
  -- この場合、届いたEXPIRATIONは既に終わった旧契約のものなので、mappingにも
  -- クレジットにも一切触らずに終える(1tier1行のためApple契約とStripe契約が
  -- 同じ行を共有する設計上、行を見ただけではどちらの契約か区別できない)。
  if exists (
    select 1 from user_subscription_mappings
    where user_id = p_user_id
      and plan_id = v_plan.id
      and status = 'active'
      and current_period_end > now() + interval '1 hour'
  ) then
    return;
  end if;

  update user_subscription_mappings
    set status = 'expired'
    where user_id = p_user_id
      and plan_id = v_plan.id
      and status = 'active';

  -- ガード2: 既に他プラットフォーム/他tierの契約に乗り換え済みで、そちらが
  -- まだactiveならFreeフォールバックはスキップする。乗り換えたばかりの
  -- 新プランのクレジットを、後から届いた旧プランのEXPIRATIONで誤って消して
  -- しまう(新プランの課金だけは継続する)のを防ぐガード。
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
