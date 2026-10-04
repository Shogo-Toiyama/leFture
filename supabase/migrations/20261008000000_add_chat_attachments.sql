-- ============================================================
-- チャットの資料添付: chat_attachments
--
-- 設計(2026-10-04に合意、docs/chatbot_context_and_retrieval_roadmap.md 10章):
-- - 資料はスレッドごと(別スレッドからは見えない)。1スレッド30本・1本10万字まで
--   (上限はバックエンドのコードで止める)。
-- - 添付はメッセージの送信と一緒に届き、そのターンの最初に審査・要約・目次づくりをする
--   (processing → ready / blocked / failed)。送った後は中身を変えない(編集不可)。
-- - 読み取りは本人のみ(RLS)。書き込みはすべてバックエンド(サービスロール)が行う
--   (chat_messagesと同じ方針。審査を通っていない中身を回答役に渡さないため)。
-- - 外す(本人の操作)・スレッドの削除は論理削除(deleted_at)。アカウント削除時は
--   user_idのON DELETE CASCADEで物理削除される(_delete_account側でも明示的に削除する)。
-- ============================================================

CREATE TABLE public.chat_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    thread_id uuid NOT NULL,
    -- 添付したuserメッセージ(会話の中で「どこで貼ったか」を見せるため)
    message_id uuid,
    -- 今はtextだけ。PDF・画像も同じ表に入れる(取り出したテキストをcontentに入れる)
    kind text DEFAULT 'text'::text NOT NULL,
    status text DEFAULT 'processing'::text NOT NULL,
    -- 本人が付けた名前(無ければ要約役が付けた名前)
    title text,
    content text NOT NULL,
    char_count integer NOT NULL,
    -- 要約役の2〜3文の要約(振り分け役・探索役・回答役の一覧に毎ターン渡す)
    summary text,
    -- 目次: [{"index": 1, "title": "...", "description": "...", "start": 0, "end": 2400}, ...]
    -- start/endはcontentの文字位置(節の本文はcontent[start:end])
    sections jsonb DEFAULT '[]'::jsonb NOT NULL,
    -- 審査・要約にかかったトークンと原価(請求はそのターンの返答の行に含まれる)
    usage jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.chat_attachments
    ADD CONSTRAINT chat_attachments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.chat_attachments
    ADD CONSTRAINT chat_attachments_kind_check
    CHECK (kind IN ('text', 'pdf', 'image'));

-- processing: 審査・目次づくりの途中 / ready: 使える / blocked: 審査で断った(課金なし)
-- failed: 処理に失敗した(課金なし。そのターンもエラーになる)
ALTER TABLE ONLY public.chat_attachments
    ADD CONSTRAINT chat_attachments_status_check
    CHECK (status IN ('processing', 'ready', 'blocked', 'failed'));

ALTER TABLE ONLY public.chat_attachments
    ADD CONSTRAINT chat_attachments_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.chat_attachments
    ADD CONSTRAINT chat_attachments_thread_id_fkey
    FOREIGN KEY (thread_id) REFERENCES public.chat_threads(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.chat_attachments
    ADD CONSTRAINT chat_attachments_message_id_fkey
    FOREIGN KEY (message_id) REFERENCES public.chat_messages(id) ON DELETE SET NULL;

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.chat_attachments
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- スレッドの資料を添付順に引く(毎ターンの組み立て・画面の一覧)
CREATE INDEX idx_chat_attachments_thread_created
    ON public.chat_attachments (thread_id, created_at)
    WHERE deleted_at IS NULL;

ALTER TABLE public.chat_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "select own chat attachments"
    ON public.chat_attachments
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());
