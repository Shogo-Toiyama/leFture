-- revenuecat_webhook_events(20260909000000_add_store_subscriptions.sqlで作成)は
-- 全29テーブル中唯一RLSが有効化されていなかった。raw_payloadに全ユーザー分の
-- app_user_id・商品ID・価格情報を含む生Webhookペイロードが入るため、この状態は
-- 匿名/ログイン済みクライアントから直接read/write可能な情報漏洩・改ざん経路
-- だった(他の全テーブルと同じくservice_role以外はポリシー無し=アクセス不可、
-- が本来の方針)。
ALTER TABLE public.revenuecat_webhook_events ENABLE ROW LEVEL SECURITY;
