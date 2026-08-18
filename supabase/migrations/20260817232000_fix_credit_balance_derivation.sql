-- クレジット残高の二重管理を解消するバグ修正。
--
-- 背景: user_credit_balances は「grant_credits/consume_credits が呼ばれた
-- 瞬間のスナップショット」でしかなく、credit_grants の行が時間経過(expires_at)
-- で失効しても誰も更新しない。そのため、あるユーザーのサブスクリプション由来
-- クレジット(150クレジット, credit_expiry_days=2)が請求期間(1ヶ月)より先に
-- 失効し、実際の残高は0になっていたにもかかわらず、アプリは23日間
-- 「まだ68.5クレジットある」という古いキャッシュを表示し続けた。
-- その後の最初のconsume_credits呼び出しで、真実(=0)から再計算した値が
-- キャッシュへ書き戻され、残高表示が突然0/負値へ落ちた
-- (=消費した分が残高を溶かしたのではなく、幻の残高が精算されただけ)。
--
-- 方針: 残高は「有効なcredit_grantsの合計」を唯一の定義とし、
-- user_credit_balancesは参考値のキャッシュへ降格させる。

-- 1. get_credit_summary: credit_balanceをキャッシュではなくcredit_grantsから
--    毎回導出する(extra_credit_balanceは元々こうなっており、それに合わせる)。
CREATE OR REPLACE FUNCTION public.get_credit_summary(p_user_id uuid)
 RETURNS TABLE(credit_balance bigint, monthly_allocation bigint, extra_credit_balance bigint, has_active_plan boolean, current_period_end timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_mapping user_subscription_mappings;
  v_plan subscription_plans;
begin
  -- 旧実装はここで user_credit_balances のキャッシュ行を読んでいたため、
  -- grantの失効が反映されず古い値を返し続けていた。
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
      and source not in ('subscription_initial', 'subscription_renewal');

  return next;
end;
$function$;

-- 2. consume_credits: balance_afterを「引く前の合計 - 請求額」ではなく、
--    減算ループを終えた後の実際の残量から再計算する。
--    (旧実装はgrantsが請求額に足りない場合、履歴と実残量が食い違っていた。)
CREATE OR REPLACE FUNCTION public.consume_credits(p_user_id uuid, p_amount bigint, p_reason text, p_job_id uuid DEFAULT NULL::uuid)
 RETURNS credit_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_remaining_to_charge bigint := p_amount;
  v_grant record;
  v_balance_after bigint;
  v_shortfall bigint;
  v_tx credit_transactions;
begin
  if p_amount <= 0 then
    raise exception 'invalid_amount: amount must be positive, got %', p_amount;
  end if;

  perform 1 from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now())
    order by expires_at nulls last, created_at
    for update;

  for v_grant in
    select id, remaining_amount from credit_grants
      where user_id = p_user_id
        and remaining_amount > 0
        and (expires_at is null or expires_at > now())
      order by expires_at nulls last, created_at
  loop
    exit when v_remaining_to_charge <= 0;

    if v_grant.remaining_amount >= v_remaining_to_charge then
      update credit_grants set remaining_amount = remaining_amount - v_remaining_to_charge
        where id = v_grant.id;
      v_remaining_to_charge := 0;
    else
      update credit_grants set remaining_amount = 0
        where id = v_grant.id;
      v_remaining_to_charge := v_remaining_to_charge - v_grant.remaining_amount;
    end if;
  end loop;

  -- grantsだけでは請求額を賄いきれなかった分。旧実装はこれを黙って捨てていた
  -- (v_remaining_to_chargeが使われず消える)。オーバードラフトとして許容しつつ、
  -- 事実は記録に残す。
  v_shortfall := v_remaining_to_charge;
  if v_shortfall > 0 then
    raise warning 'consume_credits: user % had insufficient grants, % of % micro-credits unbacked (reason=%)',
      p_user_id, v_shortfall, p_amount, p_reason;
  end if;

  -- 減算を終えた後の実際の残量から計算する(引く前の合計からの単純減算ではない)。
  select coalesce(sum(remaining_amount), 0) into v_balance_after
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now());

  insert into credit_transactions (user_id, delta, balance_after, reason, related_job_id, metadata)
    values (
      p_user_id, -p_amount, v_balance_after, p_reason, p_job_id,
      case when v_shortfall > 0 then jsonb_build_object('unbacked_shortfall', v_shortfall) else null end
    )
    returning * into v_tx;

  insert into user_credit_balances (user_id, credit_balance, updated_at)
    values (p_user_id, v_balance_after, now())
    on conflict (user_id) do update set credit_balance = excluded.credit_balance, updated_at = now();

  return v_tx;
end;
$function$;

-- 3. renew_subscription: サブスク由来grantの有効期限を請求期間の終わりに
--    一致させる(旧実装はsubscription_plans.credit_expiry_daysという独立した
--    値を使っており、これがbilling_interval_monthsより短いと今回のバグの
--    ような「請求期間はまだ生きているのにクレジットだけ先に失効する」空白が
--    発生した)。期限が一致していれば、失効した瞬間に次のgrantが来るため、
--    ロールオーバー防止のための明示的なゼロ化も不要になる。
--
--    current_period_endの前進もnow()起点ではなく前回のcurrent_period_end
--    起点にする(パトロールの実行が遅れても契約期間が縮まないように)。
CREATE OR REPLACE FUNCTION public.renew_subscription(p_mapping_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_mapping user_subscription_mappings;
  v_plan subscription_plans;
  v_new_period_end timestamp with time zone;
begin
  select * into v_mapping from user_subscription_mappings
    where id = p_mapping_id for update;

  if v_mapping.current_period_end > now() then
    return; -- 冪等
  end if;

  select * into v_plan from subscription_plans where id = v_mapping.plan_id;

  if v_plan.disabled_at is not null and now() >= v_plan.disabled_at then
    update user_subscription_mappings set status = 'expired' where id = p_mapping_id;
    return;
  end if;

  v_new_period_end := v_mapping.current_period_end + (v_plan.billing_interval_months || ' months')::interval;

  perform grant_credits(
    v_mapping.user_id, v_plan.monthly_credit_amount, 'subscription_renewal', v_mapping.plan_id,
    v_new_period_end
  );

  update user_subscription_mappings
    set current_period_start = v_mapping.current_period_end,
        current_period_end = v_new_period_end
    where id = p_mapping_id;
end;
$function$;
