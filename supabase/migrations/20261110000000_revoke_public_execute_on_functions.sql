-- ★ セキュリティ修正: public スキーマの関数を anon / authenticated から呼べないようにする。
--
-- Supabase は public スキーマに作った関数へ、デフォルトで anon / authenticated の
-- EXECUTE を付ける。課金系の SECURITY DEFINER 関数(grant_store_subscription_credits,
-- grant_credits, claim_plan, consume_credits 等)の多くは REVOKE されておらず、
-- アプリに埋め込まれた公開キー(sb_publishable_...)だけで PostgREST の
-- /rest/v1/rpc/<関数名> から直接実行できた(2026-11-10 に存在しない商品IDでの
-- 呼び出しが "unknown_store_product" まで到達することを確認)。本物の商品IDを渡せば
-- 誰でも任意のアカウントにプランとクレジットを付与できる状態だった。
--
-- 対策:
--   1. 既存の public 関数すべてから PUBLIC / anon / authenticated の EXECUTE を外し、
--      service_role には明示的に付ける(バックエンドは service_role で呼ぶ)。
--      ただし以下は対象外:
--        - クライアント(ユーザーJWT)から呼ぶ関数(許可リスト。authenticated に付け直す)
--            get_my_tier_level()       … artifact_worker / アプリ
--            touch_activity(text,int)  … アプリ・Web
--            search_knowledge_chunks   … バックエンドがユーザー権限のクライアントで呼ぶ
--        - トリガー関数(戻り値が trigger。RPCとしては呼べず、トリガー実行には
--          呼び出しユーザーのEXECUTE権限は使われない)
--        - 拡張機能に属する関数
--   2. 今後 postgres ロールが public に作る関数にも、デフォルトで EXECUTE を
--      付けないようにする(新しくクライアント向け関数を作るときは、各マイグレーションで
--      明示的に GRANT する。既存の get_my_tier_level 等と同じ運用)。
--
-- RLSポリシー・ビューの中で public 関数は使っていない(auth.uid() のみ。2026-11-10 に
-- マイグレーション全体を grep で確認)ので、この REVOKE で既存の読み書きは壊れない。

DO $$
DECLARE
  fn record;
  allow text[] := array['get_my_tier_level', 'touch_activity', 'search_knowledge_chunks'];
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS sig, p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prokind = 'f'
       AND p.prorettype <> 'trigger'::regtype
       AND NOT EXISTS (
         SELECT 1 FROM pg_depend d
          WHERE d.objid = p.oid AND d.deptype = 'e'
       )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn.sig);
    IF fn.proname = ANY (allow) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn.sig);
    END IF;
  END LOOP;
END
$$;

-- Supabaseが付けている「public スキーマの関数は anon/authenticated に EXECUTE」を外す。
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO service_role;
-- Postgres組み込みの「関数は PUBLIC に EXECUTE」はスキーマ単位(IN SCHEMA)の設定では
-- 取り消せない(スキーマ単位の既定権限は付け足すことしかできない)ため、ロール全体で外す。
-- 対象は postgres ロールが今後作る関数のみ(auth等のスキーマの関数は別ロールが作る)。
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
