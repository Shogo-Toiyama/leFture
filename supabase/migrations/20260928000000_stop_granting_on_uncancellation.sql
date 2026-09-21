-- UNCANCELLATIONでのクレジット再付与を止める。
--
-- 背景: main.pyはINITIAL_PURCHASE/RENEWAL/UNCANCELLATIONを同じ
-- grant_store_subscription_credits()に流していた。同関数は「同一プランの
-- 重複grant防止」として既存グラントの残高を0にしてから満額を付与し直す
-- (RENEWALなら正しい)。しかしUNCANCELLATIONは「期限切れ前のサブスクの
-- 自動更新をオンに戻しただけ」のイベントで、期間は進んでおらず決済も
-- 発生しない。結果、iOS設定で自動更新をオフ→オンと往復する(またはWebで
-- 解約→再開を往復する)だけで、同一期間内に何度でも残高が満額に戻っていた。
--
-- UNCANCELLATIONで必要な処理は、Apple由来のCANCELLATIONが立てた
-- auto_renew_disabledフラグを戻すことだけ。クレジット・ステータス・
-- current_period_end・pending_plan_idには一切触れない。

CREATE FUNCTION public.mark_apple_subscription_auto_renew_enabled(
  p_user_id    uuid,
  p_event_id   text,
  p_product_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_plan subscription_plans;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'UNCANCELLATION')
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

  update user_subscription_mappings
    set auto_renew_disabled = false
    where user_id = p_user_id
      and plan_id = v_plan.id
      and status = 'active';
end;
$function$;
