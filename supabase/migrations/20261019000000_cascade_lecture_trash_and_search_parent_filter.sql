-- ============================================================
-- 講義・コースのゴミ箱行き/復元を、配下のデータへDB側で連動させる。
-- あわせて、チャットの検索で「親(講義・コース)がゴミ箱にいるチャンク」を
-- 必ず除くようにする。
--
-- 背景 (2026-10-19):
-- - knowledge_chunksの論理削除は、元の行(review_cards等)のdeleted_atの
--   変化をfn_knowledge_index_triggerが反映する仕組み。講義そのものを
--   ゴミ箱に入れても、配下の子データのdeleted_atが立たなければ、
--   その講義の復習カード・Deep Notes等はチャットの検索に出続けていた。
-- - 子データへの連動はFlutterのクライアントコードにしか無く
--   (lecture_controller.dart / course_repository_supabase.dart)、
--   - Webアプリの講義/コース削除は親のdeleted_atを立てるだけ
--   - Flutterの連動はbest-effort(オフライン時に取りこぼす)で、
--     lecture_momentsが対象外
--   - 講義単体の復元はWeb/Flutterとも子データを戻していなかった
--   という穴があった。ルールをDBに一本化し、どのクライアント(旧ビルド含む)
--   から deleted_at を変えても同じ結果になるようにする。
--
-- ルール:
-- - 講義のゴミ箱行き: 配下の子データのうち、まだ生きている行に
--   講義と同じdeleted_atを立てる(個別に削除済みの行は上書きしない)。
-- - 講義の復元: 配下の子データのうち deleted_at >= 講義のdeleted_at の行を
--   戻す。個別の削除は講義をゴミ箱に入れる前にしか起きないため、これで
--   「講義と一緒に消えた行」だけを区別できる。Flutterはクライアントの時計で
--   講義→子の順に(子の方が後の時刻で)論理削除するので、旧ビルドが
--   自前で連動させた分もこの条件で戻る。
-- - コースのゴミ箱行き: 配下の生きている講義を同じdeleted_atでゴミ箱へ入れ、
--   Flutterと同じmetadata.deleted_via_course_cascade=trueを付ける
--   (子データへの連動は上の講義トリガが行う)。
-- - コースの復元: deleted_via_course_cascadeの付いた講義だけを戻し、
--   フラグを外す(個別に削除されていた講義はゴミ箱に残す)。
--
-- Flutterの既存の連動コードはこのトリガと冪等に共存する(既に連動済みの行は
-- 0件更新になるだけ)。
-- ============================================================


-- ------------------------------------------------------------
-- 1. 講義 → 子データ
--
-- SECURITY DEFINER: Webアプリ/Flutterは本人のJWT(RLS適用下)で講義を
-- 更新する。子テーブルのUPDATEポリシーに依存せず確実に連動させるため、
-- fn_knowledge_index_triggerと同じくDEFINERにする。トリガを起こせるのは
-- RLSを通って講義行を更新できた本人だけで、さらにuser_idの一致でも絞るので、
-- 他人の行には触れない(2026-10-19時点で子テーブルにuser_idがNULLの行は0件)。
-- ------------------------------------------------------------
CREATE FUNCTION public.fn_cascade_lecture_trash() RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = ''
    AS $$
BEGIN
  IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    UPDATE public.announcements SET deleted_at = NEW.deleted_at
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at IS NULL;
    UPDATE public.review_cards SET deleted_at = NEW.deleted_at
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at IS NULL;
    UPDATE public.fun_facts SET deleted_at = NEW.deleted_at
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at IS NULL;
    UPDATE public.lecture_topics SET deleted_at = NEW.deleted_at
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at IS NULL;
    UPDATE public.deep_notes SET deleted_at = NEW.deleted_at
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at IS NULL;
    UPDATE public.keywords SET deleted_at = NEW.deleted_at
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at IS NULL;
    UPDATE public.lecture_moments SET deleted_at = NEW.deleted_at
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at IS NULL;
  ELSIF NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL THEN
    UPDATE public.announcements SET deleted_at = NULL
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at >= OLD.deleted_at;
    UPDATE public.review_cards SET deleted_at = NULL
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at >= OLD.deleted_at;
    UPDATE public.fun_facts SET deleted_at = NULL
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at >= OLD.deleted_at;
    UPDATE public.lecture_topics SET deleted_at = NULL
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at >= OLD.deleted_at;
    UPDATE public.deep_notes SET deleted_at = NULL
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at >= OLD.deleted_at;
    UPDATE public.keywords SET deleted_at = NULL
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at >= OLD.deleted_at;
    UPDATE public.lecture_moments SET deleted_at = NULL
      WHERE lecture_id = NEW.id AND user_id = NEW.user_id AND deleted_at >= OLD.deleted_at;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cascade_lecture_trash
    AFTER UPDATE OF deleted_at ON public.lectures
    FOR EACH ROW
    WHEN (OLD.deleted_at IS DISTINCT FROM NEW.deleted_at)
    EXECUTE FUNCTION public.fn_cascade_lecture_trash();


-- ------------------------------------------------------------
-- 2. コース → 講義
--
-- 講義をUPDATEすると上の講義トリガが走り、子データまで連動する。
-- metadataのフラグはFlutter(course_repository_supabase.dart)と同じ形
-- (JSONのtrue)にして、Flutter側の復元コードとも食い違わないようにする。
-- ------------------------------------------------------------
CREATE FUNCTION public.fn_cascade_course_trash() RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = ''
    AS $$
BEGIN
  IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    UPDATE public.lectures
      SET deleted_at = NEW.deleted_at,
          metadata = COALESCE(metadata, '{}'::jsonb) || '{"deleted_via_course_cascade": true}'::jsonb
      WHERE course_id = NEW.id AND user_id = NEW.user_id AND deleted_at IS NULL;
  ELSIF NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL THEN
    UPDATE public.lectures
      SET deleted_at = NULL,
          metadata = metadata - 'deleted_via_course_cascade'
      WHERE course_id = NEW.id AND user_id = NEW.user_id
        AND deleted_at IS NOT NULL
        AND metadata -> 'deleted_via_course_cascade' = 'true'::jsonb;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cascade_course_trash
    AFTER UPDATE OF deleted_at ON public.courses
    FOR EACH ROW
    WHEN (OLD.deleted_at IS DISTINCT FROM NEW.deleted_at)
    EXECUTE FUNCTION public.fn_cascade_course_trash();


-- ------------------------------------------------------------
-- 3. 検索RPC: 親がゴミ箱にいるチャンクを除く
--
-- 子データの連動は上のトリガで行うが、それをすり抜けた行
-- (講義の削除後にパイプラインが生成した行など)も含め、検索の側でも
-- 必ず親の状態を見る。chat_turn/chat_attachmentはlecture_id/course_idが
-- NULLなので、この条件の影響を受けない。
-- 既存の引数・返り値は 20261005000000 から不変。
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
      AND NOT EXISTS (
          SELECT 1 FROM public.lectures l
          WHERE l.id = kc.lecture_id AND l.deleted_at IS NOT NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM public.courses c
          WHERE c.id = kc.course_id AND c.deleted_at IS NOT NULL
      )
    ORDER BY kc.embedding OPERATOR(extensions.<=>) query_embedding
    LIMIT match_count;
$$;


-- ------------------------------------------------------------
-- 4. 既存データのバックフィル(冪等)
--
-- 2026-10-19に本番で数えた時点では、どちらも対象0件だった
-- (ゴミ箱のコース10件の配下に生きている講義は無く、ゴミ箱の講義4件の
-- 配下に生きている子データも無い)。migrationを反映するまでの間に
-- Webアプリから削除された分を拾うために残す。
-- 順番: コース配下の講義を先に入れる(講義トリガが子データまで連動する)。
-- その後、講義トリガが無かった時代にゴミ箱へ入った講義の子データを入れる。
-- 子データの更新でfn_knowledge_index_triggerが走り、チャンク側にも反映される。
-- ------------------------------------------------------------
UPDATE public.lectures l
  SET deleted_at = c.deleted_at,
      metadata = COALESCE(l.metadata, '{}'::jsonb) || '{"deleted_via_course_cascade": true}'::jsonb
  FROM public.courses c
  WHERE l.course_id = c.id AND l.user_id = c.user_id
    AND c.deleted_at IS NOT NULL AND l.deleted_at IS NULL;

UPDATE public.announcements ch SET deleted_at = l.deleted_at
  FROM public.lectures l
  WHERE ch.lecture_id = l.id AND ch.user_id = l.user_id
    AND l.deleted_at IS NOT NULL AND ch.deleted_at IS NULL;
UPDATE public.review_cards ch SET deleted_at = l.deleted_at
  FROM public.lectures l
  WHERE ch.lecture_id = l.id AND ch.user_id = l.user_id
    AND l.deleted_at IS NOT NULL AND ch.deleted_at IS NULL;
UPDATE public.fun_facts ch SET deleted_at = l.deleted_at
  FROM public.lectures l
  WHERE ch.lecture_id = l.id AND ch.user_id = l.user_id
    AND l.deleted_at IS NOT NULL AND ch.deleted_at IS NULL;
UPDATE public.lecture_topics ch SET deleted_at = l.deleted_at
  FROM public.lectures l
  WHERE ch.lecture_id = l.id AND ch.user_id = l.user_id
    AND l.deleted_at IS NOT NULL AND ch.deleted_at IS NULL;
UPDATE public.deep_notes ch SET deleted_at = l.deleted_at
  FROM public.lectures l
  WHERE ch.lecture_id = l.id AND ch.user_id = l.user_id
    AND l.deleted_at IS NOT NULL AND ch.deleted_at IS NULL;
UPDATE public.keywords ch SET deleted_at = l.deleted_at
  FROM public.lectures l
  WHERE ch.lecture_id = l.id AND ch.user_id = l.user_id
    AND l.deleted_at IS NOT NULL AND ch.deleted_at IS NULL;
UPDATE public.lecture_moments ch SET deleted_at = l.deleted_at
  FROM public.lectures l
  WHERE ch.lecture_id = l.id AND ch.user_id = l.user_id
    AND l.deleted_at IS NOT NULL AND ch.deleted_at IS NULL;
