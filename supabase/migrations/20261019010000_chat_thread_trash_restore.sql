-- ============================================================
-- チャットのスレッドをゴミ箱から復元できるようにする。
--
-- 背景 (2026-10-19):
-- - スレッドの削除は論理削除(deleted_at)だが、ゴミ箱に出ず、復元も
--   30日後の物理削除も無かった。復元と物理削除はバックエンド(main.py)が行い、
--   ここではその土台を用意する。
-- - 物理削除はchat_threadsをDELETEするだけでよい。chat_messages /
--   chat_attachments / chat_summary_blocks / profile_observationsはthread_idの
--   ON DELETE CASCADEで消え、knowledge_chunksはメッセージ・資料のDELETEトリガで消える。
-- ============================================================


-- ------------------------------------------------------------
-- 1. 資料の検索インデックスにも復元の分岐を足す
--
-- これまではゴミ箱行きの分岐しか無く、資料のdeleted_atをnullに戻しても
-- 後ろの「readyになったときだけ積む」に落ちて何も起きず、チャンクは
-- 論理削除されたままになっていた。chat_turn(fn_knowledge_index_chat_trigger)
-- と同じく、deleted_atを戻すだけにする(中身は送った後に変わらないので
-- 埋め込みの再計算は要らない)。
-- 20261009000000の本体に復元の分岐を足しただけで、それ以外は不変。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_knowledge_index_attachment_trigger() RETURNS trigger
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
    -- スレッドの復元で一緒に戻った: チャンクも戻す
    IF NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL THEN
      UPDATE public.knowledge_chunks SET deleted_at = NULL
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


-- ------------------------------------------------------------
-- 2. スレッドの復元
--
-- deleted_atはスレッドの削除以外でも使われている:
-- - 編集して送り直したときの後方削除(chat_edit_truncate)で消えたメッセージ・資料
-- - 本人が個別に外した資料(R2の実ファイルもその場で消えている)
-- これらまで戻すと、編集前の古い分岐が会話に混ざり、実ファイルの無い資料が
-- 復活してしまう。スレッドの削除(DELETE /chat/threads/{id})はメッセージ・資料・
-- スレッドに同じ時刻を付けるので、「スレッドと同じdeleted_atの行」だけを戻す。
--
-- 観察(profile_observations)は戻さない。代わりにprofile_observed_untilを
-- 最初に戻し、復元後の会話全体を観察し直してもらう(観察のタスクはバックエンドが
-- 積む)。消した時点の観察は論理削除済みなので、読み直しても二重にはならない。
-- 観察が消えてorphanedになったプロフィール項目もそのままにする。
--
-- 1つの関数にしたのは、メッセージ・資料・スレッドの更新を1トランザクションに
-- まとめるため(途中で失敗して「スレッドだけ戻って中身が空」等にならないように)。
-- user_idを引数に取るので、service_role以外からは呼べないようにする。
-- 戻り値: 復元したらtrue。本人のゴミ箱に無いスレッドならfalse。
-- ------------------------------------------------------------
CREATE FUNCTION public.restore_chat_thread(p_thread_id uuid, p_user_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    SET search_path = ''
    AS $$
DECLARE
  v_deleted_at timestamp with time zone;
BEGIN
  SELECT deleted_at INTO v_deleted_at
    FROM public.chat_threads
    WHERE id = p_thread_id AND user_id = p_user_id
    FOR UPDATE;
  IF v_deleted_at IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.chat_messages SET deleted_at = NULL
    WHERE thread_id = p_thread_id AND deleted_at = v_deleted_at;
  UPDATE public.chat_attachments SET deleted_at = NULL
    WHERE thread_id = p_thread_id AND deleted_at = v_deleted_at;
  UPDATE public.chat_threads
    SET deleted_at = NULL, profile_observed_until = NULL
    WHERE id = p_thread_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.restore_chat_thread FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restore_chat_thread TO service_role;
