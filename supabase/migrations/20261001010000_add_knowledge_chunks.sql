-- ============================================================
-- 横断チャットボット 段階0: Embedding基盤 (knowledge_chunks)
--
-- 設計の要点 (2026-09-27 セッションで合意):
-- - 全ソース(Review Card/Deep Notes/Keyword/Announcement/トランスクリプト/
--   Fun Fact/講義サマリー/トピック要約/Lecture Moment)を1つの
--   knowledge_chunksテーブルに統一する。
-- - 検索は必ず本人のUIDの行だけに絞る。RLSに加え、検索RPC内でも
--   auth.uid()で明示的に絞る(多重防御)。RPCにuser_id引数は作らない
--   (呼び出し側が誰のデータかを指定できる余地自体を無くすため)。
-- - 埋め込みの計算(外部API呼び出し)はDBトリガの中では行わない。
--   トリガは軽い同期処理(キューへのINSERT、または削除の反映)だけを行い、
--   実際の埋め込み計算はバックエンドのpatrol/FINALIZE_JOBが
--   knowledge_index_queueを非同期に処理する形にする。
-- - 論理削除(ゴミ箱)は「knowledge_chunks側もdeleted_atを立てるだけ」。
--   物理削除(パージ/アカウント削除)は本当にDELETEする(ON DELETE CASCADE)。
--   これにより、ゴミ箱からの復元は埋め込みの再計算なしで一瞬で終わる。
-- ============================================================

-- pgvectorは既存のbaselineで有効化されていない(uuid-ossp等と同じ
-- extensionsスキーマに揃える)。
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;


-- ------------------------------------------------------------
-- 1. knowledge_chunks: 検索対象の本体
-- ------------------------------------------------------------
CREATE TABLE public.knowledge_chunks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    source_type text NOT NULL,
    source_id uuid NOT NULL,
    chunk_index integer NOT NULL DEFAULT 0,
    course_id uuid,
    lecture_id uuid,
    content text NOT NULL,
    content_hash text NOT NULL,
    embedding extensions.vector(768),
    embedding_model text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.knowledge_chunks
    ADD CONSTRAINT knowledge_chunks_pkey PRIMARY KEY (id);

-- source_type/source_idの許可リストと同じ組み合わせをコード側
-- (knowledge_index.py)でも管理する。ここでは典型的な打ち間違い
-- (例: "review_cards"のような複数形)を防ぐためだけの軽いCHECK。
ALTER TABLE ONLY public.knowledge_chunks
    ADD CONSTRAINT knowledge_chunks_source_type_check
    CHECK (source_type IN (
        'review_card', 'deep_note', 'keyword', 'announcement',
        'transcript_topic', 'topic_summary', 'fun_fact',
        'lecture_summary', 'lecture_moment'
    ));

-- upsertの衝突キー。同じ元行・同じchunk番号の重複を防ぎ、
-- インデクサが何度実行されても安全(冪等)になるようにする。
ALTER TABLE ONLY public.knowledge_chunks
    ADD CONSTRAINT knowledge_chunks_source_chunk_unique
    UNIQUE (source_type, source_id, chunk_index);

ALTER TABLE ONLY public.knowledge_chunks
    ADD CONSTRAINT knowledge_chunks_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE TRIGGER trg_set_updated_at
    BEFORE UPDATE ON public.knowledge_chunks
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 検索は必ず「本人×未削除」で絞られるので、その形の部分インデックスにする。
CREATE INDEX idx_knowledge_chunks_user_active
    ON public.knowledge_chunks (user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_knowledge_chunks_course
    ON public.knowledge_chunks (course_id)
    WHERE deleted_at IS NULL AND course_id IS NOT NULL;

CREATE INDEX idx_knowledge_chunks_lecture
    ON public.knowledge_chunks (lecture_id)
    WHERE deleted_at IS NULL AND lecture_id IS NOT NULL;

-- 想定規模(1ユーザーあたり数万件)ではHNSW/IVFFlatによる近似検索は不要かつ
-- user_idでの絞り込みと相性が悪い(近似インデックスは事前絞り込みを
-- 苦手とする)。まずuser_idで絞ってから総当たりで類似度計算する方が
-- 速く、取りこぼしもない。将来1ユーザーが数十万件規模になったら
-- 見直す。

ALTER TABLE public.knowledge_chunks ENABLE ROW LEVEL SECURITY;

-- 書き込みポリシーは作らない(サービスロールのみが書き込む=RLSを
-- バイパスする)。ユーザー側には読み取りだけを許可する。
CREATE POLICY "select own knowledge chunks"
    ON public.knowledge_chunks
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());


-- ------------------------------------------------------------
-- 2. knowledge_index_queue: 「埋め込みを計算し直してね」の予約票
--
-- 削除(ゴミ箱行き含む)はトリガがその場で反映するのでここには
-- 積まれない。ここに積まれるのは「新規作成/編集/ゴミ箱からの復元」
-- のような、埋め込みの(再)計算が必要になり得るケースだけ。
-- ------------------------------------------------------------
CREATE TABLE public.knowledge_index_queue (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    source_type text NOT NULL,
    source_id uuid NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone
);

ALTER TABLE ONLY public.knowledge_index_queue
    ADD CONSTRAINT knowledge_index_queue_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.knowledge_index_queue
    ADD CONSTRAINT knowledge_index_queue_status_check
    CHECK (status IN ('PENDING', 'PROCESSING', 'FAILED'));

-- 「同じ元行がまだ処理待ちなら積み直さない」を保証するpartial unique
-- index。トリガ側はON CONFLICT (source_type, source_id) WHERE
-- status='PENDING' DO NOTHINGでこれを使う。
CREATE UNIQUE INDEX uq_knowledge_index_queue_pending
    ON public.knowledge_index_queue (source_type, source_id)
    WHERE status = 'PENDING';

CREATE INDEX idx_knowledge_index_queue_status
    ON public.knowledge_index_queue (status, created_at);

-- サービスロールのみが触るテーブル。RLSは有効化するがポリシーは
-- 作らない(=authenticated/anonからは一切見えない)。他の新規テーブル
-- (credit_packs等)と同じ方針。
ALTER TABLE public.knowledge_index_queue ENABLE ROW LEVEL SECURITY;


-- ------------------------------------------------------------
-- 3. 汎用トリガ関数
--
-- 対象テーブルに`id`列と`deleted_at`列がある(=このアプリの
-- コンテンツ系テーブル共通の形)ことを前提にした汎用実装。
-- TG_ARGV[0]にsource_typeを渡してCREATE TRIGGERする。
-- ------------------------------------------------------------
CREATE FUNCTION public.fn_knowledge_index_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_source_type text := TG_ARGV[0];
BEGIN
  -- 物理削除: 埋め込み計算は不要なので、その場でチャンクも消す。
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.knowledge_chunks
      WHERE source_type = v_source_type AND source_id = OLD.id;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- ゴミ箱行き(deleted_at: null → 値あり): チャンクは消さず、
    -- 論理削除だけ反映する。埋め込みは温存し、復元時に使い回す。
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
      UPDATE public.knowledge_chunks
        SET deleted_at = NEW.deleted_at
        WHERE source_type = v_source_type AND source_id = NEW.id;
      RETURN NEW;
    END IF;

    -- ゴミ箱からの復元(deleted_at: 値あり → null): 内容はゴミ箱に
    -- いる間変わっていない前提なので、埋め込みの再計算はせず
    -- deleted_atを戻すだけにする(キューにも積まない)。
    IF NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL THEN
      UPDATE public.knowledge_chunks
        SET deleted_at = NULL
        WHERE source_type = v_source_type AND source_id = NEW.id;
      RETURN NEW;
    END IF;
  END IF;

  -- ここに来るのは「INSERT」または「deleted_atが変化していないUPDATE
  -- (=通常の編集)」。生成直後から既に削除済みのような通常起きない
  -- ケースは安全側に倒してキューに積まない。
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- 実際にテキストが変わったかどうかはここでは判定しない
  -- (deleted_at以外の列名はテーブルごとに違うため)。積むこと自体は
  -- 気軽に行い、コストのかかる判定(ハッシュ比較・埋め込み要否)は
  -- インデクサ側の1箇所に集約する。
  INSERT INTO public.knowledge_index_queue (source_type, source_id)
    VALUES (v_source_type, NEW.id)
    ON CONFLICT (source_type, source_id) WHERE status = 'PENDING' DO NOTHING;

  RETURN NEW;
END;
$$;


-- ------------------------------------------------------------
-- 4. 各テーブルへのトリガ設置
--
-- lecture_topicsだけ、1つの行から2種類のsource_type
-- (topic_summary: トピック要約 / transcript_topic: そのsid範囲の
-- トランスクリプト本文)を作るため、トリガを2つ設置する。
-- transcript_topicの実際のテキストはlecture_transcriptsから
-- インデクサが読むが、再インデックスのきっかけはlecture_topics側
-- (start_sid/end_sidが確定するタイミング)にする。
-- ------------------------------------------------------------
CREATE TRIGGER trg_knowledge_index_review_cards
    AFTER INSERT OR DELETE OR UPDATE ON public.review_cards
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('review_card');

CREATE TRIGGER trg_knowledge_index_deep_notes
    AFTER INSERT OR DELETE OR UPDATE ON public.deep_notes
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('deep_note');

CREATE TRIGGER trg_knowledge_index_keywords
    AFTER INSERT OR DELETE OR UPDATE ON public.keywords
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('keyword');

CREATE TRIGGER trg_knowledge_index_announcements
    AFTER INSERT OR DELETE OR UPDATE ON public.announcements
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('announcement');

CREATE TRIGGER trg_knowledge_index_fun_facts
    AFTER INSERT OR DELETE OR UPDATE ON public.fun_facts
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('fun_fact');

CREATE TRIGGER trg_knowledge_index_lecture_summary
    AFTER INSERT OR DELETE OR UPDATE ON public.lectures
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('lecture_summary');

CREATE TRIGGER trg_knowledge_index_lecture_moments
    AFTER INSERT OR DELETE OR UPDATE ON public.lecture_moments
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('lecture_moment');

CREATE TRIGGER trg_knowledge_index_topic_summary
    AFTER INSERT OR DELETE OR UPDATE ON public.lecture_topics
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('topic_summary');

CREATE TRIGGER trg_knowledge_index_transcript_topic
    AFTER INSERT OR DELETE OR UPDATE ON public.lecture_topics
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_trigger('transcript_topic');


-- ------------------------------------------------------------
-- 5. キューの取り出し(claim)用RPC
--
-- 「PENDING行をロックして掴み、PROCESSINGに変える」を1つの
-- アトミックな操作にする。FOR UPDATE SKIP LOCKEDにより、
-- patrolとFINALIZE_JOBが同時に動いても同じ行を二重処理しない。
-- サービスロールのみが呼ぶ想定(RLSは無関係、テーブル自体に
-- ポリシーが無いため通常のロールからはそもそも行が見えない)。
-- ------------------------------------------------------------
CREATE FUNCTION public.claim_knowledge_index_queue_batch(p_limit integer DEFAULT 200)
    RETURNS SETOF public.knowledge_index_queue
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  UPDATE public.knowledge_index_queue
  SET status = 'PROCESSING', attempts = attempts + 1
  WHERE id IN (
    SELECT id FROM public.knowledge_index_queue
    WHERE status = 'PENDING'
    ORDER BY created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$;


-- ------------------------------------------------------------
-- 6. 検索RPC
--
-- user_id引数を持たない: 呼び出し元が「誰のデータを検索するか」を
-- 指定できる余地自体を無くすのが狙い。auth.uid()は呼び出し時の
-- JWT(ユーザー本人のアクセストークン)から解決されるため、
-- チャットの検索はサービスロールキーではなく必ずユーザー本人の
-- JWTで(supabase-py: postgrest_client.auth(user_jwt)相当で)呼ぶこと。
-- SECURITY INVOKERなので呼び出しロールのRLSがそのままかかる
-- (=明示的なuser_id絞り込みと二重に効く)。
-- ------------------------------------------------------------
CREATE FUNCTION public.search_knowledge_chunks(
    query_embedding extensions.vector(768),
    match_count integer DEFAULT 20,
    filter_source_types text[] DEFAULT NULL,
    filter_course_id uuid DEFAULT NULL,
    filter_lecture_id uuid DEFAULT NULL
)
    RETURNS TABLE (
        id uuid,
        source_type text,
        source_id uuid,
        chunk_index integer,
        course_id uuid,
        lecture_id uuid,
        content text,
        metadata jsonb,
        similarity double precision
    )
    LANGUAGE sql
    STABLE
    SECURITY INVOKER
    AS $$
    SELECT
        kc.id,
        kc.source_type,
        kc.source_id,
        kc.chunk_index,
        kc.course_id,
        kc.lecture_id,
        kc.content,
        kc.metadata,
        -- vector型/<=>演算子はextensionsスキーマに入れているため、
        -- OPERATOR(schema.op)で明示的にスキーマ修飾する必要がある。
        -- 素の"<=>"だと、この関数を解析するセッションのsearch_pathに
        -- extensionsが含まれない環境で「演算子が存在しない」エラーになる
        -- (実際に2026-10-01のsupabase db pushで踏んだ)。
        1 - (kc.embedding OPERATOR(extensions.<=>) query_embedding) AS similarity
    FROM public.knowledge_chunks kc
    WHERE kc.user_id = auth.uid()
      AND kc.deleted_at IS NULL
      AND kc.embedding IS NOT NULL
      AND (filter_source_types IS NULL OR kc.source_type = ANY(filter_source_types))
      AND (filter_course_id IS NULL OR kc.course_id = filter_course_id)
      AND (filter_lecture_id IS NULL OR kc.lecture_id = filter_lecture_id)
    ORDER BY kc.embedding OPERATOR(extensions.<=>) query_embedding
    LIMIT match_count;
$$;

GRANT EXECUTE ON FUNCTION public.search_knowledge_chunks TO authenticated;
