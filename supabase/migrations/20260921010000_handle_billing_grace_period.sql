-- Apple App Store ConnectでBilling Grace Period(28日)を設定したことで、
-- 決済失敗時にAppleは最大28日間サブスクを「有効」として扱うが、これまで
-- RevenueCatのBILLING_ISSUEイベントはCANCELLATIONと同じ扱いで完全に無視
-- していた(main.py参照)。CANCELLATIONは無視して正しい(current_period_end
-- がそのまま有効なため)が、BILLING_ISSUEは違う: 次のRENEWALが来ないまま
-- 前回付与したcredit_grants.expires_at(前回current_period_end + 6時間)が
-- 過ぎるため、Apple側はまだGrace Period中(最大28日)のつもりでも、こちらの
-- クレジットは数時間で消えてしまっていた。
--
-- 方針: BILLING_ISSUE受信時、決済がまだ成功していないので新規クレジットの
-- 「積み増し」は行わない。既存の当該プラン分クレジットをゼロ化してから、
-- RevenueCatが返すexpiration_at_ms(Grace Period終了日として延長された値)を
-- 期限とする同額のクレジットを専用ソース'subscription_grace_period'で
-- 再付与する。後でRENEWALが成功すれば、grant_store_subscription_credits側の
-- 重複grant防止ロジック(このソースも対象に追加)がこのgrace grantをゼロ化
-- してから正式なRENEWAL分を付与する。28日経ってもRENEWALが来ずEXPIRATIONが
-- 届けば、既存のexpire_store_subscriptionがFreeプランへのフォールバックを
-- 行う(このソースも通常のstore系グラントと同様にロールオーバー対象外として
-- ゼロ化される、変更不要)。

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

  select * into v_plan from subscription_plans where store_product_id = p_product_id;
  if v_plan.id is null then
    raise exception 'unknown_store_product: %', p_product_id;
  end if;

  -- 同一プランの既存クレジット(通常付与・Grace Period付与のどちらも)を
  -- ゼロ化してから、Grace Period終了日を期限に同額を再付与する
  -- (grant_store_subscription_creditsの重複grant防止ロジックと同じパターン)。
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

-- grant_store_subscription_credits: 重複grant防止の対象ソースに
-- 'subscription_grace_period'を追加する以外は20260919000000の定義のまま。
-- これにより、Grace Period中にRENEWALが成功した際、grace grantをゼロ化
-- してから正式なRENEWAL分を付与するようになり、二重付与を防ぐ。
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

  select * into v_plan from subscription_plans where store_product_id = p_product_id;
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

-- get_credit_summary: extra_credit_balanceの除外リストに
-- 'subscription_grace_period'を追加する以外は20260919000000の定義のまま
-- (これが無いと、Grace Period中のクレジットが「追加クレジット(購入分)」
-- として誤って表示されてしまう)。
CREATE OR REPLACE FUNCTION public.get_credit_summary(p_user_id uuid)
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
  perform materialize_expired_grants(p_user_id);

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
        'subscription_initial_store', 'subscription_renewal_store',
        'subscription_grace_period'
      );

  return next;
end;
$function$;
