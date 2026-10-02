-- ============================================================
-- get_my_tier_level: 呼び出した本人のプランのtier_levelを返す
--
-- artifact_worker(Cloudflare)がR2のpipeline_logs/(トランスクリプト等の
-- 中間JSON)を返す前に、本人のプランがCore以上か確認するために使う。
--
-- - subscription_plans / user_subscription_mappingsには本人向けのSELECT
--   ポリシーが無く(RLSで全拒否)、workerはシークレット(service role)を
--   持たない設計なので、本人のJWTで呼べるSECURITY DEFINER関数で
--   tier_levelだけを返す(プランの他の列や他人の割当は一切見せない)。
-- - 引数でuser_idを受け取らず、必ずauth.uid()で本人に絞る
--   (search_knowledge_chunksと同じ方針)。
-- - 判定はバックエンドのplan_features.get_user_tier_levelと同じ:
--   status='active'の割当のplan_id側のtier_level、無ければ0(Free)。
-- - SET search_path = '' はSECURITY DEFINER関数の定石(本文は完全修飾)。
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_my_tier_level()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE((
        SELECT sp.tier_level::integer
        FROM public.user_subscription_mappings usm
        JOIN public.subscription_plans sp ON sp.id = usm.plan_id
        WHERE usm.user_id = auth.uid()
          AND usm.status = 'active'
        LIMIT 1
    ), 0);
$$;

REVOKE ALL ON FUNCTION public.get_my_tier_level() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_tier_level() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_tier_level() TO authenticated;
