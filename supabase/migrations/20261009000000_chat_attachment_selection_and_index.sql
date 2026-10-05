-- ============================================================
-- チャットの資料添付: 選んだ資料だけ全文で読む + 資料の中の検索
-- docs/chatbot_context_and_retrieval_roadmap.md 10章「選んだ資料だけ全文で読む」(2026-10-04に合意)
--
-- - selected: 回答役・確かめ役に全文を渡す資料(本人が＋メニュー・資料の一覧で選ぶ。
--   新しく添付した資料は、上限に収まればバックエンドが自動で選ぶ)。上限(選択中の合計
--   3万トークン)はバックエンドのコードで確かめる。
-- - token_count: 全文を渡したときのトークン数の概算。ceil(ASCII文字数/4) + ASCII以外の文字数
--   (日本語を多めに見積もる安全側。chat_attachments.estimate_tokens()と同じ式)。
-- - 選んでいない資料は、目次と資料の中のベクトル検索で読む。knowledge_chunksに
--   'chat_attachment'(1節=1チャンク、metadata.thread_id/attachment_id/section)を足す。
--   埋め込みは既存のknowledge_index_queue → drain_knowledge_index_queue()の経路。
--   readyになった時点で積み、外した(deleted_at)らチャンクも外す。
-- ============================================================

-- - forbids_ai_code: 課題の資料が、AIでコードを書くことを禁止しているか(要約役が読むときに判定する)。
--   trueなら回答役に毎ターン「提出物に入るコードは書かない」と明示する。

ALTER TABLE public.chat_attachments
    ADD COLUMN selected boolean DEFAULT false NOT NULL,
    ADD COLUMN token_count integer,
    ADD COLUMN forbids_ai_code boolean DEFAULT false NOT NULL;

UPDATE public.chat_attachments
SET token_count =
    ceil((char_length(content) - char_length(regexp_replace(content, '[\x01-\x7F]', '', 'g'))) / 4.0)::integer
    + char_length(regexp_replace(content, '[\x01-\x7F]', '', 'g'));

ALTER TABLE public.chat_attachments
    ALTER COLUMN token_count SET NOT NULL;


ALTER TABLE public.knowledge_chunks
    DROP CONSTRAINT knowledge_chunks_source_type_check;

ALTER TABLE public.knowledge_chunks
    ADD CONSTRAINT knowledge_chunks_source_type_check
    CHECK (source_type IN (
        'review_card', 'deep_note', 'keyword', 'announcement',
        'transcript_topic', 'topic_summary', 'fun_fact',
        'lecture_summary', 'lecture_moment', 'chat_turn', 'chat_attachment'
    ));

-- ------------------------------------------------------------
-- chat_attachments専用のトリガ関数(status='ready'になったものだけを積むため、
-- 汎用のfn_knowledge_index_triggerは使えない。chat_turnと同じ理由)。
-- ------------------------------------------------------------
CREATE FUNCTION public.fn_knowledge_index_attachment_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.knowledge_chunks
      WHERE source_type = 'chat_attachment' AND source_id = OLD.id;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- 外した・スレッドを削除した: チャンクも検索から外す(他のsource_typeと同じく論理削除)
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
      UPDATE public.knowledge_chunks SET deleted_at = NEW.deleted_at
        WHERE source_type = 'chat_attachment' AND source_id = NEW.id;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- 審査・目次づくりが終わった(readyになった)ときだけ積む。selectedの切り替えでは積まない
  -- (中身は送った後に変わらないので、埋め込み直す必要が無い)。
  IF NEW.status = 'ready'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    INSERT INTO public.knowledge_index_queue (source_type, source_id)
      VALUES ('chat_attachment', NEW.id)
      ON CONFLICT (source_type, source_id) WHERE status = 'PENDING' DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_knowledge_index_chat_attachments
    AFTER INSERT OR UPDATE OR DELETE ON public.chat_attachments
    FOR EACH ROW EXECUTE FUNCTION public.fn_knowledge_index_attachment_trigger();

-- すでにreadyの資料(このmigrationより前に添付したもの)も検索できるように積む
INSERT INTO public.knowledge_index_queue (source_type, source_id)
SELECT 'chat_attachment', id FROM public.chat_attachments
WHERE status = 'ready' AND deleted_at IS NULL
ON CONFLICT (source_type, source_id) WHERE status = 'PENDING' DO NOTHING;
