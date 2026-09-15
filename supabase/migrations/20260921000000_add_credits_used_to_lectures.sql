-- 講義（lectures）ごとの消費クレジット記録用カラムを追加。
-- 単位はマイクロクレジット（bigint: 1クレジット = 1,000,000 micro-credits）。
-- FINALIZE_JOBで固定消費されたクレジット量が直接書き込まれる。

ALTER TABLE public.lectures
  ADD COLUMN IF NOT EXISTS credits_used bigint;

-- 既存の完了済み講義に対する初期データ埋め合わせ（backfill）
-- 1. credit_transactionsのmetadata.lecture_idから取得
UPDATE public.lectures l
SET credits_used = abs(tx.delta)
FROM public.credit_transactions tx
WHERE tx.reason = 'LECTURE_ANALYSIS'
  AND (tx.metadata->>'lecture_id')::text = l.id::text
  AND l.credits_used IS NULL;

-- 2. audio_duration_secondsが記録されている講義でまだnullのものは時間から逆算して補完
UPDATE public.lectures
SET credits_used = CASE
  WHEN audio_duration_seconds <= 1800 THEN 60 * 1000000
  WHEN audio_duration_seconds <= 5400 THEN 80 * 1000000
  WHEN audio_duration_seconds <= 9000 THEN 100 * 1000000
  ELSE 120 * 1000000
END
WHERE credits_used IS NULL
  AND audio_duration_seconds IS NOT NULL;
