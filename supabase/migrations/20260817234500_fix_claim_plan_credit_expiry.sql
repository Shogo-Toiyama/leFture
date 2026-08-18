-- claim_plan: サブスクgrantの有効期限を請求期間の終わりに一致させる。
--
-- 20260817232000_fix_credit_balance_derivation.sql でrenew_subscription
-- (=2回目以降の月次更新)には同じ修正を入れたが、claim_plan
-- (=最初にプランへ加入する時)には同じバグが残っていた。実際、あなたが
-- 07-23に踏んだバグの元grant(150クレジット, 2日で失効)はまさにこの
-- claim_plan経由で作られたもの。ここを直さない限り、テストプランを
-- 付け直しても同じ理由で再び早期失効する。
--
-- 修正内容はrenew_subscriptionと同じ考え方: credit_expiry_daysという
-- 独立した日数ではなく、直前で確定させたcurrent_period_endをそのまま
-- 使う。こうすることで「契約期間はまだ生きているのにクレジットだけ
-- 先に失効する」空白が構造的に起きなくなる。
--
-- 注記: subscription_plans.credit_expiry_daysは、claim_plan/
-- renew_subscriptionのどちらからも参照されなくなり、事実上死んだ
-- 列になった。誤って「まだ効いている」と思われないよう記録だけ残す
-- (今回は列自体の削除はスコープ外)。
CREATE OR REPLACE FUNCTION public.claim_plan(p_user_id uuid, p_plan_id uuid)
 RETURNS user_subscription_mappings
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
  v_mapping user_subscription_mappings;
begin
  select * into v_plan from subscription_plans where id = p_plan_id;

  if v_plan.id is null then
    raise exception 'plan_not_found';
  end if;

  if v_plan.claim_mode <> 'self_serve' then
    raise exception 'plan_not_self_serve';
  end if;

  if v_plan.disabled_at is not null and now() >= v_plan.disabled_at then
    raise exception 'plan_expired';
  end if;

  -- (user_id, plan_id)のユニーク制約が最終防波堤。ここでの事前チェックは
  -- わかりやすいエラーメッセージを返すためだけのもの(実際の排他性はDB制約が担保)。
  if exists (
    select 1 from user_subscription_mappings
    where user_id = p_user_id and plan_id = p_plan_id
  ) then
    raise exception 'plan_already_claimed';
  end if;

  insert into user_subscription_mappings (user_id, plan_id, status, current_period_start, current_period_end)
    values (
      p_user_id, p_plan_id, 'active', now(),
      now() + (v_plan.billing_interval_months || ' months')::interval
    )
    returning * into v_mapping;

  perform grant_credits(
    p_user_id, v_plan.monthly_credit_amount, 'subscription_initial', p_plan_id,
    v_mapping.current_period_end
  );

  return v_mapping;
end;
$function$;
