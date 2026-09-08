-- ユーザーごとにチュートリアル講義(metadata.is_tutorial = true)は1件までしか
-- 持てないよう、DBレベルで強制する。
--
-- /seed-tutorial は「既存行が無ければinsert」という冪等チェックを持つが、
-- SELECTしてからINSERTする間にレースウィンドウがあり、クライアント側の
-- 再実行(Riverpodプロバイダの再評価等)によるほぼ同時の2回呼び出しが両方とも
-- 「既存行なし」と判定してしまい、チュートリアル講義が2件(例: ja/en が1件ずつ)
-- できてしまう不具合が実際に発生した。SELECT+INSERTのアプリケーション側
-- チェックだけでは原理的にこのレースを防げないため、部分ユニークインデックスで
-- 直列化する。/seed-tutorialは一意制約違反(23505)を捕捉し、既存行を
-- 再取得して返すことでこれを冪等に扱う。
--
-- ステップ0: 既存の重複データをクリーンアップする(重複が残っている状態では
-- CREATE UNIQUE INDEXがそのまま失敗するため)。

-- 0a. 上記バグで実際に二重生成されてしまったことが判明している特定アカウント。
--     既存ユーザー向けの本来の仕様(Cloudチュートリアルを新規作成しない)に
--     合わせて、チュートリアル講義自体を0件に戻す(1件だけ残す、ではない)。
DO $$
DECLARE
  affected_user uuid := 'a0368beb-867a-48ce-a9a1-c1421a72fc65';
  affected_lecture_ids uuid[];
BEGIN
  SELECT array_agg(id) INTO affected_lecture_ids
  FROM public.lectures
  WHERE user_id = affected_user
    AND deleted_at IS NULL
    AND (metadata ->> 'is_tutorial') = 'true';

  IF affected_lecture_ids IS NOT NULL THEN
    -- review_cards/deep_notesはlecture_idにON DELETE CASCADEが無いため、
    -- lectures本体より先に消す必要がある(keywords/fun_facts/announcements/
    -- lecture_topicsはCASCADE設定済みなのでlectures削除で自動的に消える)。
    DELETE FROM public.review_cards WHERE lecture_id = ANY(affected_lecture_ids);
    DELETE FROM public.deep_notes WHERE lecture_id = ANY(affected_lecture_ids);
    DELETE FROM public.lectures WHERE id = ANY(affected_lecture_ids);
  END IF;
END $$;

-- 0b. 念のため、他のアカウントにも同種の重複が残っていた場合の一般的な保険。
--     作成日時が最も古い1件だけを残し、それ以外を削除する。
CREATE TEMP TABLE _tutorial_dupes AS
SELECT id FROM (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY user_id
      ORDER BY created_at ASC, id ASC
    ) AS rn
  FROM public.lectures
  WHERE deleted_at IS NULL
    AND (metadata ->> 'is_tutorial') = 'true'
) ranked
WHERE rn > 1;

DELETE FROM public.review_cards WHERE lecture_id IN (SELECT id FROM _tutorial_dupes);
DELETE FROM public.deep_notes WHERE lecture_id IN (SELECT id FROM _tutorial_dupes);
DELETE FROM public.lectures WHERE id IN (SELECT id FROM _tutorial_dupes);

DROP TABLE _tutorial_dupes;

-- ステップ1: 以後の再発をDBレベルで防ぐ。
CREATE UNIQUE INDEX IF NOT EXISTS lectures_one_tutorial_per_user
ON public.lectures (user_id)
WHERE deleted_at IS NULL AND (metadata ->> 'is_tutorial') = 'true';
