-- RevenueCat REST API による課金状態の突き合わせ(store_reconcile.py)用。
--
-- webhookだけでは救えないケースがある:
--   - アカウント作成前に匿名ID($RCAnonymousID)で成立した購入。webhookは匿名ID宛てで
--     届き(uuidでないので処理できない)、ログイン時のaliasでは新しいイベントが来ない
--     (2026-10-31 fdae3630 で実例)。
--   - EXPIRATION等の取りこぼしで、期限切れの課金プランがactiveのまま残る
--     (4859e134 で実例: 期限2026-10-19のMaxがactive)。
-- バックエンドがRevenueCatの実際の契約を問い合わせ、ずれていればwebhookと同じ
-- SQL関数(grant_store_subscription_credits / expire_store_subscription)で直す。

-- 1. ユーザーごとの最終チェック時刻(問い合わせの間引き用)
CREATE TABLE public.store_subscription_sync_state (
  user_id     uuid PRIMARY KEY,
  checked_at  timestamptz NOT NULL DEFAULT now(),
  result      jsonb,
  error       text
);
ALTER TABLE public.store_subscription_sync_state ENABLE ROW LEVEL SECURITY;

-- 2. 間引きの枠を原子的に取る。前回チェックから p_min_interval_seconds 以上
--    経っていれば checked_at を now() に更新して true、そうでなければ false。
--    同時に複数リクエストが来ても1つしか true にならない。
CREATE FUNCTION public.claim_store_sync_slot(
  p_user_id uuid,
  p_min_interval_seconds integer
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  insert into store_subscription_sync_state (user_id, checked_at)
    values (p_user_id, now())
    on conflict (user_id) do update
      set checked_at = now()
      where store_subscription_sync_state.checked_at
            < now() - make_interval(secs => p_min_interval_seconds);
  return found;
end;
$function$;

REVOKE ALL ON FUNCTION public.claim_store_sync_slot(uuid, integer) FROM PUBLIC, anon, authenticated;

-- 3. 突き合わせでDBを変更した場合も billing_webhook_log に残す(source='reconcile')。
ALTER TABLE public.billing_webhook_log DROP CONSTRAINT billing_webhook_log_source_check;
ALTER TABLE public.billing_webhook_log
  ADD CONSTRAINT billing_webhook_log_source_check
  CHECK (source IN ('revenuecat', 'stripe', 'reconcile'));
