-- ============================================================
-- 横断チャットボット: スレッド要約のブロック (ロードマップ ステップ2)
--
-- 設計の正本は docs/chatbot_context_and_retrieval_roadmap.md の 2-1〜2-14。
-- - 未要約の往復が15になったら、古い10往復を1段目のブロック1つに畳む。
--   書くのはバックエンド(/worker/chat-summary、サービスロール)だけ。
-- - 一度書いたブロックは書き直さない。編集でその範囲が消えたときは
--   invalidated_atを立てるだけにして、次に畳むときに作り直される。
-- - header はそのブロックを畳んだ時点の「会話の前提」。編集で後ろのブロックが
--   無効になれば、残った最後のブロックのheaderがそのまま今の前提になる。
-- - level=2 は1段目のブロック10個(=100往復)をさらに畳んだもの(child_block_ids)。
--   まだ作っていないが、列だけ先に用意しておく。
-- - 読み取りは本人のみ(将来「AIが覚えていること」を見せる可能性があるため)。
-- ============================================================

CREATE TABLE public.chat_summary_blocks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    thread_id uuid NOT NULL,
    user_id uuid NOT NULL,
    level smallint DEFAULT 1 NOT NULL,
    -- スレッド・段ごとの通し番号(1始まり)
    block_index integer NOT NULL,
    -- 畳んだ往復の番号の範囲(完了した往復だけで数えた、スレッド内の通し番号)
    turn_start integer NOT NULL,
    turn_end integer NOT NULL,
    start_message_id uuid NOT NULL,
    end_message_id uuid NOT NULL,
    -- 「ここより後ろが未要約」の境目。end_message_idの行のcreated_at
    end_message_created_at timestamp with time zone NOT NULL,
    -- [{turn, user_message_id, assistant_message_id}] 節の往復番号から原文を開くため
    turn_map jsonb DEFAULT '[]'::jsonb NOT NULL,
    -- [{handle, title, bullets[], turns[]}] handleはスレッド内の通し番号で、一度付けたら変わらない
    sections jsonb NOT NULL,
    -- {style_preferences|context|purpose|unresolved: [{text, source_turn}]}
    header jsonb NOT NULL,
    child_block_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    summary_language text,
    model text,
    usage jsonb,
    cost_usd numeric,
    credits_charged_micro bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    invalidated_at timestamp with time zone
);

ALTER TABLE ONLY public.chat_summary_blocks
    ADD CONSTRAINT chat_summary_blocks_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.chat_summary_blocks
    ADD CONSTRAINT chat_summary_blocks_level_check CHECK (level IN (1, 2));

ALTER TABLE ONLY public.chat_summary_blocks
    ADD CONSTRAINT chat_summary_blocks_thread_id_fkey
    FOREIGN KEY (thread_id) REFERENCES public.chat_threads(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.chat_summary_blocks
    ADD CONSTRAINT chat_summary_blocks_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 同じスレッドで畳む処理が2つ同時に走っても、同じ番号のブロックは1つしか残らない。
-- 無効にしたブロックは数えないので、同じ番号で作り直せる。
CREATE UNIQUE INDEX uq_chat_summary_blocks_active_index
    ON public.chat_summary_blocks (thread_id, level, block_index)
    WHERE invalidated_at IS NULL;

ALTER TABLE public.chat_summary_blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "select own chat summary blocks"
    ON public.chat_summary_blocks
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());
