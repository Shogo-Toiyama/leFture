-- RevenueCat TRANSFER イベントの処理。
--
-- 背景: RevenueCatプロジェクトのTransfer Behaviorは「Transfer to new App User ID」。
-- 同じApple IDの購入を別アカウントで復元(またはsyncPurchases/購入)すると、
-- RevenueCatは購入を移動先に付け替え、移動元からは取り消す。しかしバックエンドは
-- TRANSFERを無視していたため、
--   - 移動元: 課金プランのmappingがactiveのまま残る(EXPIRATIONは移動元には来ない)
--   - 移動先: 次のRENEWALまでFreeのまま(本番では最大1ヶ月)
-- となっていた。
--
-- 実際のTRANSFER payload(2026-11-04, billing_webhook_log id=1で確認):
--   app_user_id 無し / product_id 無し / expiration_at_ms 無し
--   transferred_from: [<uuid>, "$RCAnonymousID:..."]
--   transferred_to:   [<uuid>, "$RCAnonymousID:..."]
--   store: "APP_STORE", environment: "SANDBOX"
-- 商品IDも期限も来ないので、移動元のDB上のactiveな課金プランを正とし、
-- そのmappingと「残っている」サブスク由来クレジットをそのまま移動先へ移す。
--
-- ★ 新規に満額付与は絶対にしない。2アカウント間で復元を往復するだけで
--   クレジットを無限に増やせてしまうため。移動元のFreeフォールバックも、
--   直近1請求期間内にFree付与済みなら付け直さない(同じ理由)。
--
-- 1. user_subscription_mappings.store を追加し、grant_store_subscription_credits
--    で設定する。1tier1行の設計上、mappingだけではApple契約かStripe契約か
--    区別できず、App StoreのTRANSFERでStripe契約を誤って移してしまうため。
--    既存行はNULL(不明)。TRANSFER時はNULLも移動対象として扱う(今後の
--    INITIAL_PURCHASE/RENEWALで順次埋まる)。

-- ---------------------------------------------------------------------------
-- 1. store 列
-- ---------------------------------------------------------------------------
ALTER TABLE public.user_subscription_mappings
  ADD COLUMN store text;

-- ---------------------------------------------------------------------------
-- 2. grant_store_subscription_credits: store を記録する以外は
--    20260927000000_add_apple_auto_renew_disabled.sql の定義から変更なし。
--    Apple由来は subscription_plans.store_product_id と一致、Stripe由来は
--    stripe_price_id / stripe_product_id と一致する。
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

  perform grant_credits(p_user_id, v_plan.monthly_credit_amount, v_source, v_plan.id, p_period_end + interval '6 hours');
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. transfer_store_subscription
--    p_from_user_ids: transferred_from のうちuuidのもの(匿名IDはPython側で除外)
--    p_to_user_id:    transferred_to のうち最初のuuid。無ければNULL
--                     (匿名ユーザーへの移動 = 移動元から外すだけ)
--    p_store:         event.store ('APP_STORE' 等)
--    戻り値: 処理内容のjsonb(billing_webhook_log.resultに残る)
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.transfer_store_subscription(
  p_event_id      text,
  p_from_user_ids uuid[],
  p_to_user_id    uuid,
  p_store         text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_from uuid;
  v_map user_subscription_mappings;
  v_grant credit_grants;
  v_free_plan subscription_plans;
  v_free_map user_subscription_mappings;
  v_free_period_end timestamptz;
  v_amount bigint;
  v_moved_total bigint;
  v_balance_after bigint;
  v_results jsonb := '[]'::jsonb;
  v_free_granted boolean;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'TRANSFER')
    on conflict (event_id) do nothing;
  if not found then
    return jsonb_build_object('status', 'duplicate');
  end if;

  foreach v_from in array coalesce(p_from_user_ids, '{}'::uuid[]) loop
    continue when p_to_user_id is not null and v_from = p_to_user_id;

    perform materialize_expired_grants(v_from);

    -- 移動元のactiveな課金プラン(同じストア由来、または由来不明の既存行)。
    select m.* into v_map
      from user_subscription_mappings m
      join subscription_plans p on p.id = m.plan_id
      where m.user_id = v_from
        and m.status = 'active'
        and p.claim_mode = 'store_purchase'
        and (m.store is null or m.store = p_store)
      order by m.current_period_end desc
      limit 1
      for update of m;

    if v_map.id is null then
      v_results := v_results || jsonb_build_object('from', v_from, 'result', 'no_source_subscription');
      continue;
    end if;

    v_moved_total := 0;

    -- ---- 移動先: 既存プランを畳んでから移す(grant_store_subscription_creditsと同じ扱い)
    if p_to_user_id is not null then
      perform materialize_expired_grants(p_to_user_id);

      update user_subscription_mappings
        set status = 'expired'
        where user_id = p_to_user_id
          and plan_id <> v_map.plan_id
          and status = 'active';

      -- 移動先のプラン由来クレジット(Free・他プラン・同プランの古い分)は全て畳む。
      -- 同プランを残すと、同じサブスク1本分のクレジットが二重に存在してしまう。
      select coalesce(sum(remaining_amount), 0) into v_amount
        from credit_grants
        where user_id = p_to_user_id
          and plan_id is not null
          and remaining_amount > 0;
      if v_amount > 0 then
        update credit_grants
          set remaining_amount = 0
          where user_id = p_to_user_id
            and plan_id is not null
            and remaining_amount > 0;
        select coalesce(sum(remaining_amount), 0) into v_balance_after
          from credit_grants
          where user_id = p_to_user_id
            and remaining_amount > 0
            and (expires_at is null or expires_at > now());
        insert into credit_transactions (user_id, delta, balance_after, reason)
          values (p_to_user_id, -v_amount, v_balance_after, 'credit_reset_plan_changed');
      end if;

      insert into user_subscription_mappings
          (user_id, plan_id, status, current_period_start, current_period_end,
           pending_plan_id, auto_renew_disabled, store)
        values (p_to_user_id, v_map.plan_id, 'active', now(), v_map.current_period_end,
                v_map.pending_plan_id, v_map.auto_renew_disabled, coalesce(v_map.store, p_store))
        on conflict (user_id, plan_id) do update
          set status = 'active',
              current_period_start = now(),
              current_period_end = excluded.current_period_end,
              pending_plan_id = excluded.pending_plan_id,
              auto_renew_disabled = excluded.auto_renew_disabled,
              store = excluded.store;

      -- 残クレジットを元のsource・期限のまま複製する(sourceを変えると、
      -- 次のRENEWALでの同一プランreset対象やget_credit_summaryの
      -- extra判定から外れてしまうため)。
      for v_grant in
        select * from credit_grants
          where user_id = v_from
            and plan_id = v_map.plan_id
            and source in ('subscription_initial_store', 'subscription_renewal_store', 'subscription_grace_period')
            and remaining_amount > 0
            and (expires_at is null or expires_at > now())
          order by created_at
      loop
        perform grant_credits(p_to_user_id, v_grant.remaining_amount, v_grant.source,
                              v_grant.plan_id, v_grant.expires_at);
        v_moved_total := v_moved_total + v_grant.remaining_amount;
      end loop;
    end if;

    -- ---- 移動元: プランを外し、サブスク由来クレジットを0にする
    update user_subscription_mappings set status = 'expired' where id = v_map.id;

    select coalesce(sum(remaining_amount), 0) into v_amount
      from credit_grants
      where user_id = v_from
        and plan_id = v_map.plan_id
        and source in ('subscription_initial_store', 'subscription_renewal_store', 'subscription_grace_period')
        and remaining_amount > 0;
    if v_amount > 0 then
      update credit_grants
        set remaining_amount = 0
        where user_id = v_from
          and plan_id = v_map.plan_id
          and source in ('subscription_initial_store', 'subscription_renewal_store', 'subscription_grace_period')
          and remaining_amount > 0;
      select coalesce(sum(remaining_amount), 0) into v_balance_after
        from credit_grants
        where user_id = v_from
          and remaining_amount > 0
          and (expires_at is null or expires_at > now());
      insert into credit_transactions (user_id, delta, balance_after, reason)
        values (v_from, -v_amount, v_balance_after, 'credit_reset_plan_changed');
    end if;

    -- ---- 移動元のFreeフォールバック(他にactiveが無い場合のみ)
    v_free_granted := false;
    if not exists (
      select 1 from user_subscription_mappings where user_id = v_from and status = 'active'
    ) then
      select * into v_free_plan from subscription_plans
        where claim_mode = 'self_serve' and disabled_at is null
        order by created_at asc
        limit 1;

      if v_free_plan.id is not null then
        select * into v_free_map from user_subscription_mappings
          where user_id = v_from and plan_id = v_free_plan.id;

        -- 直近1請求期間内にFreeを付与済みなら、mappingを戻すだけで付け直さない。
        if exists (
          select 1 from credit_grants
            where user_id = v_from
              and plan_id = v_free_plan.id
              and created_at > now() - (v_free_plan.billing_interval_months || ' months')::interval
        ) and v_free_map.id is not null and v_free_map.current_period_end > now() then
          update user_subscription_mappings
            set status = 'active', pending_plan_id = null
            where id = v_free_map.id;
        else
          v_free_period_end := now() + (v_free_plan.billing_interval_months || ' months')::interval;
          insert into user_subscription_mappings
              (user_id, plan_id, status, current_period_start, current_period_end, pending_plan_id)
            values (v_from, v_free_plan.id, 'active', now(), v_free_period_end, null)
            on conflict (user_id, plan_id) do update
              set status = 'active',
                  current_period_start = now(),
                  current_period_end = v_free_period_end,
                  pending_plan_id = null;
          perform grant_credits(v_from, v_free_plan.monthly_credit_amount, 'subscription_initial',
                                v_free_plan.id, v_free_period_end + interval '6 hours');
          v_free_granted := true;
        end if;
      end if;
    end if;

    v_results := v_results || jsonb_build_object(
      'from', v_from,
      'result', case when p_to_user_id is null then 'removed_from_source' else 'moved' end,
      'plan_id', v_map.plan_id,
      'period_end', v_map.current_period_end,
      'moved_micro_credits', v_moved_total,
      'source_zeroed_micro_credits', v_amount,
      'source_free_granted', v_free_granted
    );
  end loop;

  return jsonb_build_object('status', 'processed', 'to', p_to_user_id, 'transfers', v_results);
end;
$function$;
