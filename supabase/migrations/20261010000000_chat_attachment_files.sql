-- ============================================================
-- チャットの資料添付: ファイル(PDF・Word・PowerPoint・画像)
-- docs/chatbot_context_and_retrieval_roadmap.md 10章「ファイルの添付」(2026-10-05〜06に合意)
--
-- 流れ:
--   1. 端末が画像・docx・pptxの中の画像を縮めてから(PDFはそのまま)、バックエンドに
--      アップロード先を頼む → 行を status='draft'(thread_id無し)で作り、R2の署名付きURLを返す
--   2. 端末がR2へ直接PUT → バックエンドがLLMを使わずに中身を取り出す(PDFの文字層・docx/pptxの本文、
--      画像として読むページ・画像の決定)。結果は extraction に入れ、送る前に件数・文字数・エラーを見せる
--   3. 送信で draft をスレッドとメッセージに結び付けて processing に → そのターンの最初に、
--      画像として読む部分をビジョン(GPT-6 Luna)で書き起こし、本文に差し込んでから、
--      テキストの資料と同じ審査・目次・要約をする(ready / blocked / failed)
--   送られなかった draft は24時間で行もR2のファイルも消す(保守ジョブ)。
--
-- 元のファイルと、ビジョン用に縮めた画像はR2の {uid}/chat_attachments/{id}/ の下
-- (アカウント削除の {uid}/ 一括削除に含まれる。外したら・スレッドを消したらその場で消す)。
-- ============================================================

ALTER TABLE public.chat_attachments
    DROP CONSTRAINT chat_attachments_kind_check;

ALTER TABLE public.chat_attachments
    ADD CONSTRAINT chat_attachments_kind_check
    CHECK (kind IN ('text', 'pdf', 'docx', 'pptx', 'image'));

ALTER TABLE public.chat_attachments
    DROP CONSTRAINT chat_attachments_status_check;

-- draft: アップロード済み・まだ送っていない(どのスレッドにも属さない)
ALTER TABLE public.chat_attachments
    ADD CONSTRAINT chat_attachments_status_check
    CHECK (status IN ('draft', 'processing', 'ready', 'blocked', 'failed'));

ALTER TABLE public.chat_attachments
    ALTER COLUMN thread_id DROP NOT NULL;

ALTER TABLE public.chat_attachments
    ADD CONSTRAINT chat_attachments_thread_unless_draft
    CHECK (status = 'draft' OR thread_id IS NOT NULL);

ALTER TABLE public.chat_attachments
    -- R2のフォルダ({uid}/chat_attachments/{id}/)。テキストの資料はNULL
    ADD COLUMN storage_prefix text,
    ADD COLUMN file_name text,
    ADD COLUMN mime_type text,
    ADD COLUMN file_size bigint,
    -- PDFのページ数・pptxのスライド数
    ADD COLUMN page_count integer,
    -- LLMなしの取り出しの結果(draftの間だけ使う。送った後のターンが書き起こしに使う):
    -- {"units": [{"label": "p.3", "text": "...", "images": ["p3"], "hint": true}], "images": {"p3": "img/p3.jpg"},
    --  "vision_count": 3, "warnings": [...]}
    ADD COLUMN extraction jsonb,
    -- 画像の資料: 回答役に渡す画像(R2のキー)。全文で読む(選択中)ときだけ毎ターン渡す
    ADD COLUMN image_path text;

-- 本人のdraftを数える(作りすぎの上限)・古いdraftを掃除する
CREATE INDEX idx_chat_attachments_drafts
    ON public.chat_attachments (user_id, created_at)
    WHERE status = 'draft';
