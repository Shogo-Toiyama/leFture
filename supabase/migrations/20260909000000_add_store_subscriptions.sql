-- RevenueCat経由のApp Store課金プラン(Entry/Standard/Premium)と、
-- 既存のβ特別プラン("Welcome Bonus")を置き換えるFree Planを追加する。
--
-- 今回のスコープはプランごとに配布するクレジット量を変えることのみ。
-- 機能制限(feature gating)は対象外。RevenueCatのWebhookをそのまま信頼境界
-- とし、クライアントから送られたレシートをサーバーが自前でApple/Google
-- Server APIに問い合わせて検証する方式(main.py:678-681のTODOが想定していた
-- もの)は採用しない — RevenueCatが既にサーバー側でレシート検証を代行して
-- いるため。

-- ---------------------------------------------------------------------------
-- 1. スキーマ変更
-- ---------------------------------------------------------------------------

-- プランと App Store 商品IDの紐付け(self_serveプランはNULLのまま)
ALTER TABLE public.subscription_plans
  ADD COLUMN store_product_id text;

CREATE UNIQUE INDEX subscription_plans_store_product_id_uidx
  ON public.subscription_plans (store_product_id)
  WHERE store_product_id IS NOT NULL;

-- RevenueCat Webhookの冪等性台帳。同じevent_idの再送(RevenueCatは非2xx応答時に
-- リトライする)で二重にクレジットを付与しないためのガード。
CREATE TABLE public.revenuecat_webhook_events (
  event_id     text PRIMARY KEY,
  event_type   text NOT NULL,
  received_at  timestamp with time zone NOT NULL DEFAULT now(),
  raw_payload  jsonb
);

-- ---------------------------------------------------------------------------
-- 2. 新規プラン行
-- ---------------------------------------------------------------------------
-- micro-credits = 表示クレジット x 1,000,000。
-- price_usdはstore_purchaseプランではNULL(実価格はApp Store Connect/RevenueCat側の
-- ローカライズ価格が正であり、このDB列はself_serve向けの表示専用情報)。
-- credit_expiry_daysは20260817234500_fix_claim_plan_credit_expiry.sqlの時点で
-- 死んだ列になっているため、ここでも設定しない。
--
-- Freeプランのmonthly_credit_amountは暫定的に1500クレジット(廃止する
-- "Welcome Bonus"と同額)にしてある。課金プラン一式が完全に安定稼働するまでは
-- 既存のテストユーザーの取り分を減らさないための措置で、本来の設計値は
-- 500クレジット。切り替え時はこの値をUPDATE一発で500に下げるだけでよく
-- (Supabase側で直接変更可能、マイグレーション不要)、コード変更は不要。

INSERT INTO public.subscription_plans
  (name, monthly_credit_amount, price_usd, claim_mode, billing_interval_months, store_product_id, metadata)
VALUES
  ('Free',     1500000000, 0,    'self_serve',    1, NULL,                            '{"tier": "free"}'::jsonb),
  ('Entry',    1200000000, NULL, 'store_purchase', 1, 'com.lefture.app.sub.starter',   '{"tier": "entry"}'::jsonb),
  ('Standard', 2000000000, NULL, 'store_purchase', 1, 'com.lefture.app.sub.standard',  '{"tier": "standard"}'::jsonb),
  ('Premium',  3000000000, NULL, 'store_purchase', 1, 'com.lefture.app.sub.premium',   '{"tier": "premium"}'::jsonb);

-- ---------------------------------------------------------------------------
-- 3. 既存βプラン("Welcome Bonus")の廃止
-- ---------------------------------------------------------------------------
-- idは実装時に本番DBへ直接確認済み(select id, name, claim_mode, disabled_at,
-- monthly_credit_amount from subscription_plans; の結果、該当行はこの1件のみ)。
-- 既存user_subscription_mappings行は一切触らない — renew_subscription()が
-- 「プランがdisabledなら次回更新時にstatus='expired'にする」処理を既に持って
-- いるため、既存利用者は次回更新タイミングで自然に失効する。

UPDATE public.subscription_plans
  SET disabled_at = now()
  WHERE id = '867586ee-bf33-439f-93a0-1e6737c51137' -- "Welcome Bonus"
    AND disabled_at IS NULL;

-- ---------------------------------------------------------------------------
-- 4. 付与用RPC: grant_store_subscription_credits
-- ---------------------------------------------------------------------------
-- INITIAL_PURCHASE / RENEWAL / UNCANCELLATION イベントで呼ばれる。

CREATE FUNCTION public.grant_store_subscription_credits(
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
  -- 冪等性: 同じevent_idを既に処理済みなら何もしない。
  -- INSERT ... ON CONFLICT DO NOTHINGで実際に行が挿入されなかった場合、
  -- plpgsqlのFOUNDはfalseになる。
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

  -- 「同時にactiveなmappingは1ユーザー1件」の不変条件を維持する
  -- (get_credit_summaryはstatus='active'をORDER BYなしのlimit 1で拾うため、
  --  プラン乗り換え時に2件activeになるのを防ぐ)。
  update user_subscription_mappings
    set status = 'expired'
    where user_id = p_user_id
      and plan_id <> v_plan.id
      and status = 'active';

  insert into user_subscription_mappings
      (user_id, plan_id, status, current_period_start, current_period_end)
    values (p_user_id, v_plan.id, 'active', now(), p_period_end)
    on conflict (user_id, plan_id) do update
      set status = 'active',
          current_period_end = excluded.current_period_end;

  -- 同プランの未消化store系grantをロールオーバーさせない
  -- (renew_subscriptionが自己申告期限に合わせて自動失効させるのと同じ発想だが、
  --  store系はRevenueCatのexpiration_at_msをそのまま使うため明示的にゼロ化する)。
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

-- ---------------------------------------------------------------------------
-- 5. 失効用RPC: expire_store_subscription
-- ---------------------------------------------------------------------------
-- EXPIRATIONイベントでのみ呼ばれる。CANCELLATION(自動更新オフ、期間内は有効)
-- では絶対に呼ばない — バックエンド側(main.py)のイベント種別振り分けで保証する。
-- クレジットの取り消しは行わない(付与済みの残クレジットはexpires_atが来るまで
-- 自然消化に任せる。renew_subscriptionと同じ思想)。

CREATE FUNCTION public.expire_store_subscription(
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
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. get_credit_summary: store系grant sourceも「月次配布分」として扱う
-- ---------------------------------------------------------------------------
-- 20260817232000_fix_credit_balance_derivation.sqlの現行版と同一本体、
-- extra_credit_balanceの除外条件にのみ store 系ソースを追加。これがないと、
-- store購入者の月次クレジットが「追加クレジット」として二重計上されて見える。

CREATE OR REPLACE FUNCTION public.get_credit_summary(p_user_id uuid)
 RETURNS TABLE(credit_balance bigint, monthly_allocation bigint, extra_credit_balance bigint, has_active_plan boolean, current_period_end timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_mapping user_subscription_mappings;
  v_plan subscription_plans;
begin
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
      and source not in (
        'subscription_initial', 'subscription_renewal',
        'subscription_initial_store', 'subscription_renewal_store'
      );

  return next;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. renew_subscription: store_purchaseプランのmappingを誤って更新しない
-- ---------------------------------------------------------------------------
-- 主防御はPython側のパトロールクエリ(_patrol_renew_subscriptions、
-- claim_mode='self_serve'のみをenqueueする)。ここでは、仮に将来の変更で
-- store_purchase系mappingが誤って渡された場合でも二重付与しないための
-- 二重防御として、claim_modeガードを追加する以外は現行版と同一本体。

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

  if v_plan.claim_mode <> 'self_serve' then
    return; -- store_purchaseの更新はRevenueCat Webhook経由のみ
  end if;

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
