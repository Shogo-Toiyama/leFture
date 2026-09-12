-- クレジット履歴(Usage History)で、プラン切替・更新のたびに古いクレジットが
-- 消える瞬間が「見えない」問題を直す。
--
-- 背景: grant_store_subscription_credits()/expire_store_subscription()は、
-- 乗り換え元プランや重複した同一プランの未消化クレジットを
-- `UPDATE credit_grants SET remaining_amount = 0`で直接消していた。この操作は
-- credit_transactions(台帳)に一切記録が残らないため、/billing/historyが
-- 「前回の表示残高との差分」で付与額を逆算する際にこの見えない減少を
-- 巻き込んでしまい、本来+2000のはずの付与が+800のように見えたり、
-- ダウングレード時に何も表示されなかったりしていた。
--
-- 方針: 実際に0より大きい額をゼロ化する時だけ、対応するcredit_transactions
-- 行を残す(reason: credit_reset_renewed=同一プランの更新、
-- credit_reset_plan_changed=プラン乗り換え/Freeへのフォールバック)。
-- 具体的な数字はUsage History上では見せない設計(区切りの意味だけ伝える)
-- なので、ここでは正しいbalance_afterの整合性のためだけに実額を記録する。

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

  -- 同一プランの重複grant防止(サンドボックスの重複/前後したRENEWAL配信対策)。
  select coalesce(sum(remaining_amount), 0) into v_zeroed_amount
    from credit_grants
    where user_id = p_user_id
      and plan_id = v_plan.id
      and source in ('subscription_initial_store', 'subscription_renewal_store')
      and remaining_amount > 0;

  if v_zeroed_amount > 0 then
    update credit_grants
      set remaining_amount = 0
      where user_id = p_user_id
        and plan_id = v_plan.id
        and source in ('subscription_initial_store', 'subscription_renewal_store')
        and remaining_amount > 0;

    select coalesce(sum(remaining_amount), 0) into v_balance_after
      from credit_grants
      where user_id = p_user_id
        and remaining_amount > 0
        and (expires_at is null or expires_at > now());

    insert into credit_transactions (user_id, delta, balance_after, reason)
      values (p_user_id, -v_zeroed_amount, v_balance_after, 'credit_reset_renewed');
  end if;

  perform grant_credits(p_user_id, v_plan.monthly_credit_amount, v_source, v_plan.id, p_period_end);
end;
$function$;

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

    perform grant_credits(p_user_id, v_free_plan.monthly_credit_amount, 'subscription_initial', v_free_plan.id, v_free_period_end);
  end if;
end;
$function$;
