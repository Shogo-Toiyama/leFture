-- 「使い切る→アップグレード→使い切る→アップグレード→ダウングレード予約」を
-- 繰り返してプロレーション課金で満額クレジットを抜く行為の検出。
--
-- 方針: コードで防がない(付与額の日割りやクールダウンは正規ユーザーの体験を
-- 損なう)。代わりに規約で禁止し、日次パトロールがこの関数で疑わしい
-- アカウントを拾って運営にメールし、人が判断して警告・停止する。
--
-- トリガー条件(引数で調整可):
--   - 直近 p_window_days 日のストア課金付与(credit_grants.source が
--     subscription_initial_store / subscription_renewal_store)が p_min_grants 件以上
--   - かつ、そのうち1件が過去 p_recent_hours 時間以内
-- 後者は重複抑止: 付与が起きた日にだけ通知され、同じ人が毎日通知されない。
--
-- 普段使いの想定: 月次更新のみ=1件/月、「足りないから1段上げる」=2件。
-- 60日/3件なら「2週間ごとに使い切って上げる」程度までは引っかからず、
-- それより速い駆け上がりだけが「少し怪しい」として上がる。
--
-- 返り値は運営が感覚で判断するための材料で、閾値判定はしない:
--   grants: 各付与の日時/プラン/付与額/切替時点の旧プラン残高
--           (credit_reset_plan_changed の額。null = ゼロ化するものが無かった
--            = 使い切ってから上げた、が最も怪しいサイン)
--   consumed_in_window: 期間内の消費合計(reset/expiredを除く負のdelta)
--   pending_plan_name: 現在ダウングレード予約があればその先のプラン名

CREATE OR REPLACE FUNCTION public.detect_upgrade_cycling_suspects(
  p_window_days  integer DEFAULT 60,
  p_min_grants   integer DEFAULT 3,
  p_recent_hours integer DEFAULT 24
) RETURNS TABLE (
  user_id            uuid,
  email              text,
  user_created_at    timestamp with time zone,
  grant_count        integer,
  granted_in_window  bigint,
  consumed_in_window bigint,
  current_plan_name  text,
  pending_plan_name  text,
  grants             jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $function$
  with window_grants as (
    select g.user_id, g.id, g.created_at, g.amount, g.plan_id, g.source
      from credit_grants g
      where g.source in ('subscription_initial_store', 'subscription_renewal_store')
        and g.created_at >= now() - make_interval(days => p_window_days)
  ),
  suspects as (
    select wg.user_id,
           count(*)::integer       as grant_count,
           sum(wg.amount)::bigint  as granted_in_window
      from window_grants wg
      group by wg.user_id
      having count(*) >= p_min_grants
         and max(wg.created_at) >= now() - make_interval(hours => p_recent_hours)
  ),
  grant_details as (
    select wg.user_id,
           jsonb_agg(
             jsonb_build_object(
               'granted_at',   wg.created_at,
               'plan_name',    sp.name,
               'source',       wg.source,
               'amount',       wg.amount,
               'reset_amount', (
                 select -ct.delta from credit_transactions ct
                   where ct.user_id = wg.user_id
                     and ct.reason = 'credit_reset_plan_changed'
                     and ct.created_at = wg.created_at
                   limit 1
               )
             )
             order by wg.created_at
           ) as grants
      from window_grants wg
      join suspects s on s.user_id = wg.user_id
      left join subscription_plans sp on sp.id = wg.plan_id
      group by wg.user_id
  ),
  consumption as (
    select ct.user_id, coalesce(sum(-ct.delta), 0)::bigint as consumed
      from credit_transactions ct
      join suspects s on s.user_id = ct.user_id
      where ct.delta < 0
        and ct.reason not like 'credit_reset%'
        and ct.reason <> 'credit_expired'
        and ct.created_at >= now() - make_interval(days => p_window_days)
      group by ct.user_id
  ),
  current_mapping as (
    select distinct on (m.user_id) m.user_id, m.plan_id, m.pending_plan_id
      from user_subscription_mappings m
      join suspects s on s.user_id = m.user_id
      where m.status = 'active'
      order by m.user_id, m.current_period_end desc nulls last
  )
  select s.user_id,
         u.email::text,
         u.created_at,
         s.grant_count,
         s.granted_in_window,
         coalesce(c.consumed, 0)::bigint,
         cur.name::text,
         pend.name::text,
         gd.grants
    from suspects s
    left join auth.users u on u.id = s.user_id
    left join grant_details gd on gd.user_id = s.user_id
    left join consumption c on c.user_id = s.user_id
    left join current_mapping cm on cm.user_id = s.user_id
    left join subscription_plans cur on cur.id = cm.plan_id
    left join subscription_plans pend on pend.id = cm.pending_plan_id
    order by s.grant_count desc, s.granted_in_window desc;
$function$;

REVOKE ALL ON FUNCTION public.detect_upgrade_cycling_suspects(integer, integer, integer) FROM public, anon, authenticated;
