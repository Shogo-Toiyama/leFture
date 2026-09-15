-- 追加クレジットパック(都度課金、非サブスク)の購入機能。
-- subscription_plans/store_product_idと同じ「DBがクレジット量の真実の源、
-- RevenueCatは価格表示専用」という既存方針をそのまま踏襲する。
--
-- 有効期限ポリシー: 購入クレジットはexpires_at = NULL(無期限)とする。
-- Appleの規約上、アプリ内課金で得たクレジット類は無期限にする必要がある
-- という方針をユーザーが確認済み(ボーナス/お詫び配布用の期限ポリシーとは別物)。
-- consume_credits()は`order by expires_at nulls last, created_at`のため、
-- サブスク分(有限期限)が自動的に先に消費され、購入分は自然に温存される
-- (優先消費のための追加ロジックは不要)。

CREATE TABLE public.credit_packs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name text NOT NULL,
    credit_amount bigint NOT NULL,      -- マイクロクレジット単位(表示クレジット × 1,000,000)
    price_usd numeric,
    store_product_id text NOT NULL,
    disabled_at timestamp with time zone
);

CREATE UNIQUE INDEX credit_packs_store_product_id_uidx
  ON public.credit_packs (store_product_id) WHERE disabled_at IS NULL;

INSERT INTO public.credit_packs (name, credit_amount, store_product_id) VALUES
  ('100 Credits',  100000000,  'com.lefture.app.credits.100'),
  ('500 Credits',  500000000,  'com.lefture.app.credits.500'),
  ('2000 Credits', 2000000000, 'com.lefture.app.credits.2000');

-- grant_store_subscription_credits(20260919000000...sql)と同じ
-- revenuecat_webhook_eventsによる冪等性パターンを使うが、サブスク固有の
-- mapping更新・乗り換えロールオーバーロジックは一切持ち込まない単純な形。
CREATE OR REPLACE FUNCTION public.grant_credit_pack_purchase(
  p_user_id    uuid,
  p_event_id   text,
  p_product_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_pack credit_packs;
begin
  insert into revenuecat_webhook_events (event_id, event_type)
    values (p_event_id, 'NON_RENEWING_PURCHASE')
    on conflict (event_id) do nothing;
  if not found then
    return;
  end if;

  select * into v_pack from credit_packs
    where store_product_id = p_product_id and disabled_at is null;
  if v_pack.id is null then
    raise exception 'unknown_credit_pack: %', p_product_id;
  end if;

  -- expires_at = NULL(無期限)。grant_credits内部でmaterialize_expired_grants
  -- も呼ばれる。ソース名'credit_pack_purchase'はget_credit_summaryの
  -- extra_credit_balance除外リスト(subscription_*のみ)に含まれないため、
  -- 追加のSQL変更なしに自動的に「追加クレジット」として集計される。
  perform grant_credits(p_user_id, v_pack.credit_amount, 'credit_pack_purchase', NULL, NULL);
end;
$function$;
