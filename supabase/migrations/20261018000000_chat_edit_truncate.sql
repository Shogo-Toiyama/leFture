-- ============================================================
-- 横断チャットボット: メッセージの編集・作り直し(docs/chatbot_context_and_retrieval_roadmap.md 2-12, 2026-10-17に合意)
--
-- 一本道(木にしない)。ユーザーのメッセージを編集して送ると、そのメッセージ自身と、それより後ろを
-- 論理削除してから、新しい往復を書く。「作り直す」は、最後の質問を同じ内容で編集して送るのと同じ。
--
-- 削除・無効化は、この関数1つのトランザクションでまとめて行う(途中で失敗しても中途半端に消えない)。
-- 呼ぶのはバックエンド(サービスロール)だけ。事前チェック(残高・送信頻度・生成中か)が全部通った後に
-- 呼ぶので、弾かれた送信では何も消えない。新しい往復の書き込みはこの後(prepare_chat_turn)。
--
-- 連動させるもの:
--   - chat_messages: 編集したメッセージ自身と、それより後ろを論理削除。検索インデックス(chat_turn)は
--     既存のトリガが deleted_at を見て外す。
--   - chat_attachments: 後ろのメッセージで添付した資料を論理削除(「無かったことに」と揃える)。
--     編集したメッセージ自身の資料は残し、バックエンドが新しいメッセージに付け替える。
--   - chat_summary_blocks: 消えた範囲を含むブロックとその後ろ(1段目・2段目)を無効化。次に畳むときに
--     作り直される。ヘッダーは残った最後のブロックのものに戻る。
--   - profile_observations: 消えたメッセージを根拠にした、まだ項目に使っていない観察メモを論理削除。
--     項目に使われたもの(used)は触らない(本人がプロフィール画面で直せる)。
--   - クレジットは戻さない(削除した回答の原価は発生済み)。
-- ============================================================

CREATE OR REPLACE FUNCTION public.truncate_chat_thread_from(
    p_thread_id uuid,
    p_user_id uuid,
    p_message_id uuid
) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path = public
    AS $$
DECLARE
  v_from timestamp with time zone;
  v_message_ids uuid[];
  v_attachments integer;
  v_blocks integer;
  v_observations integer;
BEGIN
  SELECT created_at INTO v_from
    FROM public.chat_messages
    WHERE id = p_message_id AND thread_id = p_thread_id AND user_id = p_user_id
      AND role = 'user' AND deleted_at IS NULL;
  IF v_from IS NULL THEN
    RAISE EXCEPTION 'MESSAGE_NOT_FOUND';
  END IF;

  WITH deleted AS (
    UPDATE public.chat_messages SET deleted_at = now()
      WHERE thread_id = p_thread_id AND deleted_at IS NULL AND created_at >= v_from
      RETURNING id
  )
  SELECT coalesce(array_agg(id), '{}') INTO v_message_ids FROM deleted;

  UPDATE public.chat_attachments SET deleted_at = now()
    WHERE thread_id = p_thread_id AND deleted_at IS NULL
      AND message_id = ANY(v_message_ids) AND message_id <> p_message_id;
  GET DIAGNOSTICS v_attachments = ROW_COUNT;

  UPDATE public.chat_summary_blocks SET invalidated_at = now()
    WHERE thread_id = p_thread_id AND invalidated_at IS NULL AND end_message_created_at >= v_from;
  GET DIAGNOSTICS v_blocks = ROW_COUNT;

  UPDATE public.profile_observations SET deleted_at = now()
    WHERE thread_id = p_thread_id AND deleted_at IS NULL AND status = 'open'
      AND source_message_ids && v_message_ids;
  GET DIAGNOSTICS v_observations = ROW_COUNT;

  RETURN jsonb_build_object(
    'messages', cardinality(v_message_ids),
    'attachments', v_attachments,
    'summary_blocks', v_blocks,
    'observations', v_observations
  );
END;
$$;

-- クライアントから呼べないようにする(書き込みはバックエンドだけ。chat_*の方針どおり)
REVOKE ALL ON FUNCTION public.truncate_chat_thread_from(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.truncate_chat_thread_from(uuid, uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.truncate_chat_thread_from(uuid, uuid, uuid) TO service_role;
