-- billing_webhook_log: 課金系Webhook(RevenueCat / Stripe)の受信ログ(追記専用)。
--
-- revenuecat_webhook_events は「このevent_idは処理済み」という冪等性台帳であり、
-- 各SQL関数(grant_store_subscription_credits等)が「行があれば即return」する
-- ガードとして使っている。そのため、無視したイベント(TRANSFER等)・失敗した
-- イベント・再送は台帳に一切残らず、raw_payload列も一度も書かれていなかった。
-- (2026-11 に、同一Apple IDの購入が別アカウントへTRANSFERされた件を調査した際、
--  環境・app_user_id・TRANSFER元/先のいずれもDBから辿れなかった。)
--
-- 台帳にログ用途を混ぜると、失敗イベントを記録した瞬間に再送が「処理済み」として
-- 握りつぶされ「課金済みなのにクレジット未付与」になりうるため、台帳とは完全に
-- 分離した別テーブルにする。課金ロジック(SQL関数)には一切触れない。
--
-- 1配信(再送含む)= 1行。event_idはUNIQUEにしない。
-- user_idにFKを張らないのは、ユーザー削除後もログを残すため / app_user_idが
-- 実在しないuuidでも記録自体は失敗させないため。

CREATE TABLE public.billing_webhook_log (
  id                    bigserial PRIMARY KEY,
  source                text NOT NULL CHECK (source IN ('revenuecat', 'stripe')),
  event_id              text,
  event_type            text,
  app_user_id           text,          -- $RCAnonymousID も入るため uuid にしない
  user_id               uuid,          -- app_user_id(またはTRANSFER先)がuuidの場合のみ
  original_app_user_id  text,
  aliases               text[],
  transferred_from      text[],        -- TRANSFERのみ
  transferred_to        text[],        -- TRANSFERのみ
  environment           text,          -- SANDBOX / PRODUCTION (Stripeは livemode から)
  store                 text,
  product_id            text,          -- 実際に照合に使ったID(price_id優先)
  expiration_at         timestamptz,
  event_timestamp       timestamptz,
  raw_payload           jsonb,         -- PII系フィールドは除去済み
  status                text NOT NULL DEFAULT 'received'
                          CHECK (status IN ('received', 'processed', 'ignored', 'duplicate', 'error')),
  result                jsonb,         -- ハンドラの戻り値
  error                 text,
  received_at           timestamptz NOT NULL DEFAULT now(),
  processed_at          timestamptz
);

CREATE INDEX billing_webhook_log_user_id_received_at_idx
  ON public.billing_webhook_log (user_id, received_at DESC);
CREATE INDEX billing_webhook_log_app_user_id_idx
  ON public.billing_webhook_log (app_user_id);
CREATE INDEX billing_webhook_log_event_id_idx
  ON public.billing_webhook_log (event_id);
CREATE INDEX billing_webhook_log_received_at_idx
  ON public.billing_webhook_log (received_at DESC);
CREATE INDEX billing_webhook_log_transferred_from_idx
  ON public.billing_webhook_log USING gin (transferred_from);
CREATE INDEX billing_webhook_log_transferred_to_idx
  ON public.billing_webhook_log USING gin (transferred_to);

-- 他テーブルと同じく service_role 以外はポリシー無し = アクセス不可。
ALTER TABLE public.billing_webhook_log ENABLE ROW LEVEL SECURITY;
