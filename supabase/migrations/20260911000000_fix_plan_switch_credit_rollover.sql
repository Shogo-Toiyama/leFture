-- バグ修正: プラン乗り換え時、旧プランの未消化クレジットがロールオーバーして
-- 新プランの分と合算されてしまっていた。
--
-- 例: Freeプラン(1500クレジット、有効期限1ヶ月後)をclaim → その後Standardを
-- 購入 → grant_store_subscription_creditsはFreeのuser_subscription_mappings
-- (mapping)をstatus='expired'にするだけで、Freeのcredit_grants自体(まだ
-- 期限内)はそのまま残っていた。get_credit_summaryはmappingの状態を見ず
-- 有効期限内のcredit_grantsを全部合算するため、Free分1500 + Standard分の
-- 新規grantが両方カウントされ、残高が意図せず積み上がってしまう
-- (実例: Standard失効後にEntryへ切り替えたユーザーが、Entryの1200クレジット
-- ではなくFreeの残り1500+Entryの1200=2700クレジットになった)。
--
-- 修正方針: 他のmappingをexpiredにするのと同じタイミングで、そのプランに
-- 紐づくcredit_grants(plan_idが一致するもの)の未消化分もゼロにする。
-- plan_idがnullのgrant(クーポン・goodwill等、特定プランに紐付かないボーナス)
-- は対象外なので誤って巻き込まれない。

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

  -- ↑と同じ対象(乗り換え元のプラン)の未消化クレジットもロールオーバーさせない。
  update credit_grants
    set remaining_amount = 0
    where user_id = p_user_id
      and plan_id <> v_plan.id
      and plan_id is not null
      and remaining_amount > 0;

  insert into user_subscription_mappings
      (user_id, plan_id, status, current_period_start, current_period_end)
    values (p_user_id, v_plan.id, 'active', now(), p_period_end)
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_end = excluded.current_period_end;

  v_source := case when p_event_type = 'INITIAL_PURCHASE'
                then 'subscription_initial_store'
                else 'subscription_renewal_store' end;

  update credit_grants
    set remaining_amount = 0
    where user_id = p_user_id
      and plan_id = v_plan.id
      and source in ('subscription_initial_store', 'subscription_renewal_store')
      and remaining_amount > 0;

  perform grant_credits(p_user_id, v_plan.monthly_credit_amount, v_source, v_plan.id, p_period_end);
end;
$function$;
