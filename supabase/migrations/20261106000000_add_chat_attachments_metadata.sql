-- chat_attachments.metadata: 資料ごとの補足情報(今は LLMLingua-2 で圧縮したかどうか {"compressed": true})。
--
-- 126428e(2026-10-24、LLMLingua-2 圧縮の導入)で、バックエンドが資料の読み込み完了時に
-- "metadata" を書くようになったが、列を追加するマイグレーションが無かった。そのため
-- 更新が PGRST204(Could not find the 'metadata' column)で失敗し、画像以外の資料
-- (テキスト・PDF等)は読み込みに成功しても全て status='failed' になっていた
-- (2026-11-06 に「テスト範囲宿題」の添付で発覚。以降のターンで資料が回答役に渡らなかった)。
--
-- 既存の行は空のオブジェクトにする(Attachment.from_row は metadata.compressed を見るだけ)。

ALTER TABLE public.chat_attachments
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
