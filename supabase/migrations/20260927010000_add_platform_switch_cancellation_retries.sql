-- クロスプラットフォーム(Stripe→Apple)アップグレード対応: Apple購入成功後に
-- 実行するStripe即時解約+返金(_cancel_stripe_subscription_for_platform_switch、
-- lefture_backend/app/main.py)が失敗した場合の再試行キュー。
--
-- 呼び出し元は2つ: (1) RevenueCat webhookでApple INITIAL_PURCHASEを検知した
-- 直後にバックエンド自身がベストエフォートで解約を試みる経路、(2) Flutter側が
-- 購入直後に明示的に叩く/billing/stripe/cancel-for-platform-switch。どちらも
-- 失敗した場合にここへ行を積み、_patrol_reconcile_cross_platform_subscriptions
-- (PATROL_CHECKS、30分おき)が再試行する。成功したら行を消す。
--
-- あくまで「このユーザーについてApple購入成功後にStripe解約が必要なはず」と
-- 判明した時だけ行を積む設計。Stripeの現在の契約プランとDBのplan_idを機械的に
-- 突き合わせて不一致を検出する方式は、同一プラットフォーム内アップグレード
-- 直後(Stripe価格は既に新プランだが、RevenueCatの折り返しwebhookがDBの
-- plan_idを更新するまでの数秒〜数十秒の伝播待ちの間)にも誤って「不一致」と
-- 判定してしまい、現在進行形で正常に使われているStripeサブスクを誤解約・
-- 誤返金するリスクがあるため採用しない。

CREATE TABLE public.platform_switch_cancellation_retries (
  user_id     uuid PRIMARY KEY,
  created_at  timestamp with time zone NOT NULL DEFAULT now()
);

-- 他の全テーブルと同じ方針: service_role以外はポリシー無し=アクセス不可。
ALTER TABLE public.platform_switch_cancellation_retries ENABLE ROW LEVEL SECURITY;
