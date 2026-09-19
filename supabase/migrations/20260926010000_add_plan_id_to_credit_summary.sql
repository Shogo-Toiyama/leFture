-- get_credit_summaryに現在のplan_idを追加する。
--
-- これまでサマリーはmonthly_allocation(クレジット量)しか返しておらず、
-- クライアント側は「プラン一覧の中でmonthly_credit_amountがmonthly_allocationと
-- 一致するもの」を現在のプランとみなすしかなかった。クレジット量が同じプランが
-- 2つあると誤判定するうえ、実際に「別プランなのに現在のプラン扱いされて
-- アップグレードボタンが消える」という事故が起きたため、plan_idを直接返す。
--
-- 注意: RETURNS TABLEの変更はCREATE OR REPLACEでは行えない
-- ("cannot change return type of existing function")ため、DROPしてから作り直す。
-- 引数シグネチャ(uuid)は変えていないので、20260925000000のような
-- オーバーロード事故は起きない。

DROP FUNCTION IF EXISTS public.get_credit_summary(uuid);

CREATE FUNCTION public.get_credit_summary(p_user_id uuid)
 RETURNS TABLE(
   credit_balance bigint,
   monthly_allocation bigint,
   extra_credit_balance bigint,
   has_active_plan boolean,
   current_period_end timestamp with time zone,
   pending_plan_id uuid,
   plan_id uuid
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
    plan_id := v_mapping.plan_id;
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
