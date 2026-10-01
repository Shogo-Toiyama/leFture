-- ============================================================
-- 横断チャットボット ステップ4: 過去のチャットも検索対象にする
-- docs/chatbot_context_and_retrieval_roadmap.md の 3-14 ④ (2026-09-30 合意)
--
-- - knowledge_chunksのsource_typeに'chat_turn'を足す(1往復=1チャンク、
--   source_id = 返答のメッセージのID)。埋め込みの計算自体は既存の
--   knowledge_index_queue → drain_knowledge_index_queue() の経路をそのまま使う。
-- - 対象はchat_messagesのrole='assistant' かつ status='complete' の行だけ
--   (断った/危機対応/失敗/生成中/userの発言は積まない)。既存の
--   fn_knowledge_index_trigger()は「id列とdeleted_at列を持つテーブル」
--   前提の汎用実装で、role/statusの条件分岐が無いため使えない。
--   ここだけ専用のトリガ関数にする。
-- - スレッドで絞る検索(chat.thread)のため、search_knowledge_chunksに
--   filter_thread_idを足す。knowledge_chunksにthread_id列は増やさず、
--   metadata->>'thread_id'で絞る(1ユーザーの件数規模ではHNSW等の
--   近似索引が要らないのと同じ理由で、ここも専用の列・索引までは不要と判断)。
-- ============================================================

ALTER TABLE public.knowledge_chunks
    DROP CONSTRAINT knowledge_chunks_source_type_check;

ALTER TABLE public.knowledge_chunks
    ADD CONSTRAINT knowledge_chunks_source_type_check
    CHECK (source_type IN (
        'review_card', 'deep_note', 'keyword', 'announcement',
        'transcript_topic', 'topic_summary', 'fun_fact',
        'lecture_summary', 'lecture_moment', 'chat_turn'
    ));

-- ------------------------------------------------------------
-- chat_messages専用のトリガ関数。
-- ------------------------------------------------------------
CREATE FUNCTION public.fn_knowledge_index_chat_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.knowledge_chunks
      WHERE source_type = 'chat_turn' AND source_id = OLD.id;
    RETURN OLD;
  END IF;

  -- userの発言・LLMが作る前の空行(status='streaming')は対象外。
  -- 発言そのものではなく往復(student+assistant)をチャンクにするため、
  -- assistant側の行が完了した時点でまとめて積む。
  IF NEW.role <> 'assistant' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- ゴミ箱行き(スレッド削除・編集での後方削除): チャンクは消さず
    -- deleted_atだけ反映する(他のsource_typeと同じ方針)。
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
      UPDATE public.knowledge_chunks SET deleted_at = NEW.deleted_at
        WHERE source_type = 'chat_turn' AND source_id = NEW.id;
      RETURN NEW;
    END IF;
    -- 今のチャットに復元の機能は無いが、念のため対称に扱う。
    IF NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL THEN
      UPDATE public.knowledge_chunks SET deleted_at = NULL
        WHERE source_type = 'chat_turn' AND source_id = NEW.id;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- 完了した返答だけを積む。実際にcompleteになる経路は
  -- _finalize()の1回のUPDATE(content・statusを同時に確定)のみなので、
  -- OLD.statusとの比較で「今回完了した」ものだけに絞れる。
  IF NEW.status = 'complete'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status OR OLD.content IS DISTINCT FROM NEW.content) THEN
    INSERT INTO public.knowledge_index_queue (source_type, source_id)
      VALUES ('chat_turn', NEW.id)
      ON CONFLICT (source_type, source_id) WHERE status = 'PENDING' DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_knowledge_index_chat_messages
    AFTER INSERT OR UPDATE OR DELETE ON public.chat_messages
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_chat_trigger();


-- ------------------------------------------------------------
-- search_knowledge_chunksにfilter_thread_idを足す(既存の引数・返り値は不変)。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.search_knowledge_chunks(
    query_embedding extensions.vector(768),
    match_count integer DEFAULT 20,
    filter_source_types text[] DEFAULT NULL,
    filter_course_id uuid DEFAULT NULL,
    filter_lecture_id uuid DEFAULT NULL,
    filter_thread_id text DEFAULT NULL
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
        1 - (kc.embedding OPERATOR(extensions.<=>) query_embedding) AS similarity
    FROM public.knowledge_chunks kc
    WHERE kc.user_id = auth.uid()
      AND kc.deleted_at IS NULL
      AND kc.embedding IS NOT NULL
      AND (filter_source_types IS NULL OR kc.source_type = ANY(filter_source_types))
      AND (filter_course_id IS NULL OR kc.course_id = filter_course_id)
      AND (filter_lecture_id IS NULL OR kc.lecture_id = filter_lecture_id)
      AND (filter_thread_id IS NULL OR kc.metadata->>'thread_id' = filter_thread_id)
    ORDER BY kc.embedding OPERATOR(extensions.<=>) query_embedding
    LIMIT match_count;
$$;
