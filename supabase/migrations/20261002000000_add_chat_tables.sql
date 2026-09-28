-- ============================================================
-- 横断チャットボット 段階1(MVP): chat_threads / chat_messages
--
-- 設計の要点(2026-09-28のセッションで合意):
-- - 読み取りは本人のみ(RLS)。書き込みはすべてバックエンド(サービス
--   ロール)が行い、クライアント用の書き込みポリシーは作らない。
--   ユーザーがassistantの発言を偽造できると、その内容が以降の会話履歴や
--   (段階3の)プロフィール抽出に混入してしまうため。
-- - スレッドの名前変更・削除もバックエンドのエンドポイント経由。
-- - 削除はこのアプリの他テーブルと同じく論理削除(deleted_at)。
--   アカウント削除時はuser_idのON DELETE CASCADEで物理削除される
--   (加えて_delete_account側でも明示的に削除する、既存の方針どおり)。
-- ============================================================


-- ------------------------------------------------------------
-- 1. chat_threads
-- ------------------------------------------------------------
CREATE TABLE public.chat_threads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title text,
    mode text DEFAULT 'learning'::text NOT NULL,
    -- スレッドを講義画面から開始した場合、その講義(検索の優先対象に使う)
    context_lecture_id uuid,
    last_message_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.chat_threads
    ADD CONSTRAINT chat_threads_pkey PRIMARY KEY (id);

-- MVPはlearningのみ。モードを増やすときはここに足す。
ALTER TABLE ONLY public.chat_threads
    ADD CONSTRAINT chat_threads_mode_check
    CHECK (mode IN ('learning'));

ALTER TABLE ONLY public.chat_threads
    ADD CONSTRAINT chat_threads_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 講義が物理削除されてもスレッド自体は残す(文脈の講義が無くなるだけ)。
ALTER TABLE ONLY public.chat_threads
    ADD CONSTRAINT chat_threads_context_lecture_id_fkey
    FOREIGN KEY (context_lecture_id) REFERENCES public.lectures(id) ON DELETE SET NULL;

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.chat_threads
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- スレッド一覧は「本人の未削除スレッドを新しい順」でしか引かない。
CREATE INDEX idx_chat_threads_user_recent
    ON public.chat_threads (user_id, last_message_at DESC)
    WHERE deleted_at IS NULL;

ALTER TABLE public.chat_threads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "select own chat threads"
    ON public.chat_threads
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());


-- ------------------------------------------------------------
-- 2. chat_messages
-- ------------------------------------------------------------
CREATE TABLE public.chat_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    thread_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'complete'::text NOT NULL,
    -- クライアントが送信ごとに振るUUID。通信の再送で同じ発言が二重に
    -- 保存・二重に課金されるのを防ぐ(userメッセージにのみ入る)。
    client_message_id uuid,
    -- userメッセージ: 送信時に見ていた講義・選択していたテキスト等
    context jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- assistantメッセージ: 本文中で実際に引用された出典だけ
    citations jsonb DEFAULT '[]'::jsonb NOT NULL,
    -- assistantメッセージ: 振り分け役の出力(分析・原因調査用)
    router jsonb,
    -- assistantメッセージ: モデルごとのトークン数・原価の内訳
    usage jsonb,
    cost_usd numeric,
    credits_charged_micro bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_role_check
    CHECK (role IN ('user', 'assistant'));

-- streaming: 生成中 / complete: 完了 / error: 失敗(課金なし)
-- blocked: 不適切な内容として断った(課金なし、以降の会話履歴に入れない)
-- crisis: 危機対応の定型文を返した(課金なし)
ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_status_check
    CHECK (status IN ('streaming', 'complete', 'error', 'blocked', 'crisis'));

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_thread_id_fkey
    FOREIGN KEY (thread_id) REFERENCES public.chat_threads(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.chat_messages
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE UNIQUE INDEX uq_chat_messages_client_message_id
    ON public.chat_messages (user_id, client_message_id)
    WHERE client_message_id IS NOT NULL;

-- スレッド内のメッセージを時系列で引く(画面表示・会話履歴の組み立て)
CREATE INDEX idx_chat_messages_thread_created
    ON public.chat_messages (thread_id, created_at)
    WHERE deleted_at IS NULL;

-- 送信頻度制限・断られた回数の上限を「本人の直近N分」で数えるため
CREATE INDEX idx_chat_messages_user_created
    ON public.chat_messages (user_id, created_at DESC);

-- 生成中のまま取り残された行をpatrolで拾うため
CREATE INDEX idx_chat_messages_streaming
    ON public.chat_messages (created_at)
    WHERE status = 'streaming';

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "select own chat messages"
    ON public.chat_messages
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());
