-- クレジット/プラン周りの二重管理を整理する。
--
-- 1. subscription_plans.credit_expiry_days: 2026-08-17の障害対応
--    (20260817232000/20260817234500)で、claim_plan/renew_subscriptionの
--    どちらからも参照されなくなった「事実上死んだ列」。当時は列自体の削除を
--    スコープ外としていたが、紛らわしいだけで実害が無いので今回削除する。
--    (クレジットの失効日は、常にcredit_grants.expires_atの1箇所だけが真実
--    ——付与した瞬間の契約期間終了日と必ず一致させる、という設計に統一済み)
ALTER TABLE public.subscription_plans
  DROP COLUMN credit_expiry_days;

-- 2. user_credit_balances: 「grant_credits/consume_creditsが呼ばれた瞬間の
--    スナップショット」でしかないキャッシュテーブル。credit_grantsが時間経過
--    (expires_at)で失効しても誰も更新しないため、直近でgrant/consumeが
--    呼ばれていないユーザーほど古い値が残り続ける。
--
--    get_credit_summary(/billing/summary)は2026-08-17の修正で既にこの
--    キャッシュを見なくなっているが、main.pyの/start-analysis(新規ジョブ
--    受付のクレジットゲート)だけが今もこのキャッシュを直接読んでおり、
--    「クレジットが本当は切れているのに新しいジョブを受け付けてしまう」
--    という同種の潜在バグが残っていた。真実の源はcredit_grantsの1つだけに
--    统一し、このキャッシュテーブル自体を廃止する。
--
--    grant_credits/consume_creditsからキャッシュへの書き込みを削除
--    (それ以外の本体ロジックは変更なし)。

CREATE OR REPLACE FUNCTION public.grant_credits(
  p_user_id uuid,
  p_amount bigint,
  p_source text,
  p_plan_id uuid DEFAULT NULL::uuid,
  p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone
) RETURNS public.credit_grants
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_grant credit_grants;
  v_balance_after bigint;
begin
  if p_amount <= 0 then
    raise exception 'invalid_amount: amount must be positive, got %', p_amount;
  end if;

  insert into credit_grants (user_id, amount, remaining_amount, source, plan_id, expires_at)
    values (p_user_id, p_amount, p_amount, p_source, p_plan_id, p_expires_at)
    returning * into v_grant;

  select coalesce(sum(remaining_amount), 0) into v_balance_after
    from credit_grants
    where user_id = p_user_id
      and remaining_amount > 0
      and (expires_at is null or expires_at > now());

  insert into credit_transactions (user_id, delta, balance_after, reason, related_grant_id)
    values (p_user_id, p_amount, v_balance_after, p_source, v_grant.id);

  return v_grant;
end;
$function$;

CREATE OR REPLACE FUNCTION public.consume_credits(
  p_user_id uuid,
  p_amount bigint,
  p_reason text,
  p_job_id uuid DEFAULT NULL::uuid
) RETURNS credit_transactions
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

  v_shortfall := v_remaining_to_charge;
  if v_shortfall > 0 then
    raise warning 'consume_credits: user % had insufficient grants, % of % micro-credits unbacked (reason=%)',
      p_user_id, v_shortfall, p_amount, p_reason;
  end if;

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

  return v_tx;
end;
$function$;

DROP TABLE public.user_credit_balances;
