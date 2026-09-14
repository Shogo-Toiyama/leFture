-- lectures テーブルに audio_chunks_cleaned カラムを追加する。
-- R2上の音声チャンク(audio_chunks/)の自動削除済みフラグを明示的なBooleanカラムとして保持し、
-- PostgRESTのJSONB抽出クエリによる取りこぼしを防ぎ、高速なインデックス検索を可能にする。

-- 1. カラムの追加 (既定値 false)
ALTER TABLE public.lectures
  ADD COLUMN IF NOT EXISTS audio_chunks_cleaned boolean NOT NULL DEFAULT false;

-- 2. 既存の metadata 内のフラグからバックフィル移行
UPDATE public.lectures
  SET audio_chunks_cleaned = true
  WHERE metadata->>'audio_chunks_cleaned' = 'true';

-- 3. 定期パトロール(_patrol_enqueue_audio_chunks_cleanup)の抽出クエリ用インデックス
CREATE INDEX IF NOT EXISTS idx_lectures_audio_chunks_cleanup
  ON public.lectures (audio_chunks_cleaned, created_at);
