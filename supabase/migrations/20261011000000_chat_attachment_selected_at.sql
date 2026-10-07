-- ============================================================
-- チャットの資料: 全文で読む枠の入れ替え(2026-10-07にユーザーと合意)
--
-- 資料は本文の中で指す(メンション、⟦att:<id>⟧)か、全文で添付する。新しく添付した資料はいつも全文で添付。
-- 全文で読む資料の合計がMAX_SELECTED_TOKENS(3万トークン)を超えるときは、全文にした・最後に指した時刻が
-- 古いものから外す(chat_attachments.plan_pins)。気づかずに次々と貼っても、最新の資料は必ず全文で読まれ、
-- 1ターンの費用は枠で頭打ちになる。外したことは返答のcontext.attachment_noticeで画面に知らせる。
-- ============================================================

ALTER TABLE public.chat_attachments
    ADD COLUMN selected_at timestamp with time zone;

-- いま全文で読んでいる資料は、添付した時刻を全文にした時刻とみなす
UPDATE public.chat_attachments
SET selected_at = created_at
WHERE selected AND selected_at IS NULL;
