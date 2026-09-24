-- Adminダッシュボード用の集計・検索関数。
--
-- 設計の前提:
--   1. すべてSECURITY DEFINER + `REVOKE ... FROM PUBLIC, anon, authenticated`。
--      つまりservice_role(＝バックエンド)からしか実行できない。RLSには
--      一切手を入れない —— admin用のポリシーを1つでも足すと、その判定の
--      バグが全テーブルの全行漏洩に直結するため。
--   2. 個人を跨ぐ生データはフロントに出さない。集計はここ(SQL)で閉じ、
--      返すのはカウントと率だけにする。
--   3. 講義の中身(タイトル・要約・トランスクリプト・生成コンテンツ)は
--      どの関数も一切返さない。講義音声は教授やクラスメイトという
--      「ユーザー本人ではない第三者」の声を含むため、運営であっても
--      覗いてよいものではない。返すのは件数・長さ・ステータス・消費
--      クレジットといったメタデータのみ。
--   4. メールアドレスは既定でマスクして返す。生のメールはadmin_user_email()
--      という専用関数でのみ取得でき、呼び出し側(バックエンド)が必ず
--      admin_audit_logに記録する。

-- ---------------------------------------------------------------------------
-- メールマスク
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_mask_email(p_email text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_email IS NULL OR position('@' IN p_email) = 0 THEN NULL
    ELSE substr(split_part(p_email, '@', 1), 1, 2) || '***@' || split_part(p_email, '@', 2)
  END;
$$;

-- ---------------------------------------------------------------------------
-- 全体サマリー
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_overview_stats()
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT json_build_object(
    'generated_at', now(),

    'users', json_build_object(
      'total',      (SELECT count(*) FROM auth.users),
      'new_24h',    (SELECT count(*) FROM auth.users WHERE created_at >= now() - interval '24 hours'),
      'new_7d',     (SELECT count(*) FROM auth.users WHERE created_at >= now() - interval '7 days'),
      'new_30d',    (SELECT count(*) FROM auth.users WHERE created_at >= now() - interval '30 days'),
      'confirmed',  (SELECT count(*) FROM auth.users WHERE email_confirmed_at IS NOT NULL),
      'suspended',  (SELECT count(*) FROM public.account_suspensions)
    ),

    -- 「アクティブ」は2段階で出す。
    --   active_*        : アプリを開いていた人(user_activity_hours。クライアントが
    --                     明示的にpingを打って記録する)
    --   created_lecture_*: そのうち「講義を作った」人だけ(このアプリの中核操作)
    -- auth.users.last_sign_in_at は使わない —— あれはリフレッシュトークンによる
    -- セッション更新では更新されず、「最後に再ログインを強いられた時刻」でしかない
    -- (使い続けている人ほど古くなる逆指標)。詳細は
    -- migration 20260930005000_add_user_activity_hours.sql のコメント。
    'active', json_build_object(
      'active_24h', (SELECT count(DISTINCT user_id) FROM public.user_activity_hours WHERE bucket_at >= now() - interval '24 hours'),
      'active_7d',  (SELECT count(DISTINCT user_id) FROM public.user_activity_hours WHERE bucket_at >= now() - interval '7 days'),
      'active_30d', (SELECT count(DISTINCT user_id) FROM public.user_activity_hours WHERE bucket_at >= now() - interval '30 days'),
      'created_lecture_24h', (SELECT count(DISTINCT user_id) FROM public.lectures WHERE created_at >= now() - interval '24 hours'),
      'created_lecture_7d',  (SELECT count(DISTINCT user_id) FROM public.lectures WHERE created_at >= now() - interval '7 days'),
      'created_lecture_30d', (SELECT count(DISTINCT user_id) FROM public.lectures WHERE created_at >= now() - interval '30 days')
    ),

    'lectures', json_build_object(
      'total',       (SELECT count(*) FROM public.lectures WHERE deleted_at IS NULL),
      'trashed',     (SELECT count(*) FROM public.lectures WHERE deleted_at IS NOT NULL),
      'new_24h',     (SELECT count(*) FROM public.lectures WHERE created_at >= now() - interval '24 hours'),
      'new_7d',      (SELECT count(*) FROM public.lectures WHERE created_at >= now() - interval '7 days'),
      'new_30d',     (SELECT count(*) FROM public.lectures WHERE created_at >= now() - interval '30 days'),
      'audio_hours_30d', (
        SELECT round(coalesce(sum(audio_duration_seconds), 0) / 3600.0, 1)
        FROM public.lectures WHERE created_at >= now() - interval '30 days'
      )
    ),

    'jobs', json_build_object(
      'running',     (SELECT count(*) FROM public.processing_jobs WHERE status NOT IN ('COMPLETED','FAILED','ERROR','CANCELLED')),
      'completed_24h', (SELECT count(*) FROM public.processing_jobs WHERE status = 'COMPLETED' AND created_at >= now() - interval '24 hours'),
      'failed_24h',  (SELECT count(*) FROM public.processing_jobs WHERE status IN ('FAILED','ERROR') AND created_at >= now() - interval '24 hours'),
      'failed_7d',   (SELECT count(*) FROM public.processing_jobs WHERE status IN ('FAILED','ERROR') AND created_at >= now() - interval '7 days'),
      'total_7d',    (SELECT count(*) FROM public.processing_jobs WHERE created_at >= now() - interval '7 days')
    ),

    -- クレジットはμクレジット(1クレジット = 1,000,000)で保持しているため、
    -- ここで表示単位のクレジットに直して返す。
    'credits', json_build_object(
      'consumed_24h', (SELECT round(coalesce(sum(-delta), 0) / 1000000.0, 2) FROM public.credit_transactions WHERE delta < 0 AND created_at >= now() - interval '24 hours'),
      'consumed_30d', (SELECT round(coalesce(sum(-delta), 0) / 1000000.0, 2) FROM public.credit_transactions WHERE delta < 0 AND created_at >= now() - interval '30 days'),
      'granted_30d',  (SELECT round(coalesce(sum(amount), 0) / 1000000.0, 2) FROM public.credit_grants WHERE created_at >= now() - interval '30 days'),
      'outstanding',  (SELECT round(coalesce(sum(remaining_amount), 0) / 1000000.0, 2) FROM public.credit_grants WHERE remaining_amount > 0 AND (expires_at IS NULL OR expires_at > now()))
    ),

    -- 原価(LLM/ASR等の実コスト)。usage_recordsは課金ではなく可視化専用の記録。
    'cost', json_build_object(
      'usd_24h', (SELECT round(coalesce(sum(cost_usd), 0), 2) FROM public.usage_records WHERE created_at >= now() - interval '24 hours'),
      'usd_30d', (SELECT round(coalesce(sum(cost_usd), 0), 2) FROM public.usage_records WHERE created_at >= now() - interval '30 days')
    ),

    -- 有効なサブスクの月額換算合計。実際の入金額はStripe/App Store側が正なので、
    -- これはあくまでDB上の契約状態から見た概算(請求の照合には使わないこと)。
    'mrr_usd_estimate', (
      SELECT round(coalesce(sum(p.price_usd / greatest(p.billing_interval_months, 1)), 0), 2)
      FROM public.user_subscription_mappings m
      JOIN public.subscription_plans p ON p.id = m.plan_id
      WHERE m.status = 'active'
    ),

    'support', json_build_object(
      'open',  (SELECT count(*) FROM public.support_tickets WHERE status = 'open'),
      'total', (SELECT count(*) FROM public.support_tickets)
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- 日次の時系列(グラフ用)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_daily_series(p_days integer DEFAULT 30)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  WITH days AS (
    SELECT generate_series(
      (now() at time zone 'utc')::date - (least(greatest(p_days, 1), 365) - 1),
      (now() at time zone 'utc')::date,
      interval '1 day'
    )::date AS d
  ),
  activity AS (
    SELECT a.user_id, (a.bucket_at at time zone 'utc')::date AS d
    FROM public.user_activity_hours a
    WHERE a.bucket_at >= (now() at time zone 'utc')::date - (least(greatest(p_days, 1), 365) - 1)
  )
  SELECT coalesce(json_agg(item ORDER BY item->>'date'), '[]'::json) FROM (
    SELECT json_build_object(
      'date', days.d,
      'signups',        (SELECT count(*) FROM auth.users u WHERE (u.created_at at time zone 'utc')::date = days.d),
      'active_users',   (SELECT count(DISTINCT a.user_id) FROM activity a WHERE a.d = days.d),
      'lectures',       (SELECT count(*) FROM public.lectures l WHERE (l.created_at at time zone 'utc')::date = days.d),
      'jobs_completed', (SELECT count(*) FROM public.processing_jobs j WHERE j.status = 'COMPLETED' AND (j.created_at at time zone 'utc')::date = days.d),
      'jobs_failed',    (SELECT count(*) FROM public.processing_jobs j WHERE j.status IN ('FAILED','ERROR') AND (j.created_at at time zone 'utc')::date = days.d),
      'credits_consumed', (SELECT round(coalesce(sum(-t.delta), 0) / 1000000.0, 2) FROM public.credit_transactions t WHERE t.delta < 0 AND (t.created_at at time zone 'utc')::date = days.d),
      'cost_usd',       (SELECT round(coalesce(sum(r.cost_usd), 0), 2) FROM public.usage_records r WHERE (r.created_at at time zone 'utc')::date = days.d)
    ) AS item
    FROM days
  ) s;
$$;

-- ---------------------------------------------------------------------------
-- 時間帯ごとの利用分布
--
-- ★ ローカル時刻で見ること。UTCの時刻で集計すると、日本の学生とアメリカの
--    学生が混ざって分布が平らに潰れ、「何時に使われているか」が読めなくなる。
--    tz_offset_minutes(東が正)を足してローカル時刻を復元する。
--    オフセット不明の行(バックフィルで入れた過去分)はローカル分布から除外し、
--    UTC分布にだけ含める。
--
-- users     : その時間帯にアプリを開いていた延べ人数(distinct user)
-- engagement: pingの合計。pingは10分おきなので、1時間ずっと使っていれば6、
--             ちょっと開いただけなら1。「開いた回数」ではなく「どれだけ
--             使われたか」の目安になる。
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_hourly_distribution(p_days integer DEFAULT 30)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH win AS (
    SELECT * FROM public.user_activity_hours
    WHERE bucket_at >= now() - (least(greatest(p_days, 1), 365) || ' days')::interval
  ),
  hours AS (SELECT generate_series(0, 23) AS h)
  SELECT json_build_object(
    'window_days', least(greatest(p_days, 1), 365),

    'local', (
      SELECT coalesce(json_agg(x ORDER BY (x->>'hour')::int), '[]'::json) FROM (
        SELECT json_build_object(
          'hour',       hours.h,
          'users',      (SELECT count(DISTINCT w.user_id) FROM win w
                          WHERE w.tz_offset_minutes IS NOT NULL
                            AND extract(hour FROM (w.bucket_at at time zone 'utc') + make_interval(mins => w.tz_offset_minutes)) = hours.h),
          'engagement', (SELECT coalesce(sum(w.ping_count), 0) FROM win w
                          WHERE w.tz_offset_minutes IS NOT NULL
                            AND extract(hour FROM (w.bucket_at at time zone 'utc') + make_interval(mins => w.tz_offset_minutes)) = hours.h)
        ) AS x
        FROM hours
      ) l
    ),

    'utc', (
      SELECT coalesce(json_agg(x ORDER BY (x->>'hour')::int), '[]'::json) FROM (
        SELECT json_build_object(
          'hour',       hours.h,
          'users',      (SELECT count(DISTINCT w.user_id) FROM win w WHERE extract(hour FROM w.bucket_at at time zone 'utc') = hours.h),
          'engagement', (SELECT coalesce(sum(w.ping_count), 0) FROM win w WHERE extract(hour FROM w.bucket_at at time zone 'utc') = hours.h)
        ) AS x
        FROM hours
      ) u
    ),

    -- 曜日別(0=日曜)。ローカル時刻ベース。
    'by_weekday', (
      SELECT coalesce(json_agg(x ORDER BY (x->>'weekday')::int), '[]'::json) FROM (
        SELECT json_build_object(
          'weekday', d.wd,
          'users',   (SELECT count(DISTINCT w.user_id) FROM win w
                       WHERE w.tz_offset_minutes IS NOT NULL
                         AND extract(dow FROM (w.bucket_at at time zone 'utc') + make_interval(mins => w.tz_offset_minutes)) = d.wd)
        ) AS x
        FROM (SELECT generate_series(0, 6) AS wd) d
      ) wk
    ),

    -- プラットフォーム別の利用者数。webとモバイルのどちらが使われているかが分かる。
    -- 'unknown' はバックフィルで埋めた過去分(実測ではない)。
    'by_platform', (
      SELECT coalesce(json_agg(x ORDER BY x->>'platform'), '[]'::json) FROM (
        SELECT json_build_object(
          'platform', w.platform,
          'users',    count(DISTINCT w.user_id),
          'hours',    count(*)
        ) AS x
        FROM win w GROUP BY w.platform
      ) pf
    ),

    -- タイムゾーン分布。ユーザーが地理的にどこに散らばっているかの目安。
    'by_tz_offset', (
      SELECT coalesce(json_agg(x ORDER BY (x->>'offset_minutes')::int), '[]'::json) FROM (
        SELECT json_build_object(
          'offset_minutes', w.tz_offset_minutes,
          'users',          count(DISTINCT w.user_id)
        ) AS x
        FROM win w WHERE w.tz_offset_minutes IS NOT NULL GROUP BY w.tz_offset_minutes
      ) tz
    )
  );
$$;


-- ---------------------------------------------------------------------------
-- パイプラインの健康状態(タスク種別ごとの失敗率と所要時間)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_pipeline_health(p_days integer DEFAULT 7)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH window_tasks AS (
    SELECT * FROM public.processing_tasks
    WHERE created_at >= now() - (least(greatest(p_days, 1), 90) || ' days')::interval
  )
  SELECT json_build_object(
    'window_days', least(greatest(p_days, 1), 90),
    'by_task_type', (
      SELECT coalesce(json_agg(x ORDER BY x->>'task_type'), '[]'::json) FROM (
        SELECT json_build_object(
          'task_type', task_type,
          'total',     count(*),
          'completed', count(*) FILTER (WHERE status = 'COMPLETED'),
          'failed',    count(*) FILTER (WHERE status IN ('FAILED','ERROR')),
          'running',   count(*) FILTER (WHERE status IN ('PENDING','QUEUED','WAITING','RUNNING')),
          'failure_rate', round(
            count(*) FILTER (WHERE status IN ('FAILED','ERROR'))::numeric
            / greatest(count(*) FILTER (WHERE status IN ('COMPLETED','FAILED','ERROR')), 1), 4
          ),
          'avg_seconds', round(coalesce(
            avg(extract(epoch FROM (updated_at - created_at))) FILTER (WHERE status = 'COMPLETED'), 0
          )::numeric, 1)
        ) AS x
        FROM window_tasks GROUP BY task_type
      ) t
    ),
    -- 直近の失敗タスク。error_messageはパイプラインの例外文字列で、まれに
    -- LLMの応答断片を含みうるため300文字で切る(講義本文の閲覧手段には
    -- しないこと。原因調査に必要な最小限だけを出す)。
    'recent_failures', (
      SELECT coalesce(json_agg(x ORDER BY x->>'updated_at' DESC), '[]'::json) FROM (
        SELECT json_build_object(
          'task_id',    t.id,
          'job_id',     t.job_id,
          'task_type',  t.task_type,
          'updated_at', t.updated_at,
          'error',      left(coalesce(t.error_message, ''), 300)
        ) AS x
        FROM window_tasks t
        WHERE t.status IN ('FAILED','ERROR')
        ORDER BY t.updated_at DESC
        LIMIT 50
      ) f
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- プラン別の契約数
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_plan_distribution()
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(json_agg(x ORDER BY x->>'name'), '[]'::json) FROM (
    SELECT json_build_object(
      'plan_id',    p.id,
      'name',       p.name,
      'price_usd',  p.price_usd,
      'claim_mode', p.claim_mode,
      'billing_interval_months', p.billing_interval_months,
      'disabled',   (p.disabled_at IS NOT NULL AND now() >= p.disabled_at),
      'active',     count(m.id) FILTER (WHERE m.status = 'active'),
      'inactive',   count(m.id) FILTER (WHERE m.status IS DISTINCT FROM 'active')
    ) AS x
    FROM public.subscription_plans p
    LEFT JOIN public.user_subscription_mappings m ON m.plan_id = p.id
    GROUP BY p.id, p.name, p.price_usd, p.claim_mode, p.billing_interval_months, p.disabled_at
  ) s;
$$;

-- ---------------------------------------------------------------------------
-- ユーザー検索(メールは必ずマスクして返す)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_user_search(
  p_query  text DEFAULT NULL,
  p_limit  integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  WITH recent_activity AS (
    -- 1回のスキャンでユーザーごとに畳む(行ごとにサブクエリを回すより速い)。
    SELECT a.user_id, max(a.last_seen_at) AS last_active_at
    FROM public.user_activity_hours a
    GROUP BY a.user_id
  )
  SELECT coalesce(json_agg(x ORDER BY x->>'created_at' DESC), '[]'::json) FROM (
    SELECT json_build_object(
      'user_id',         u.id,
      'email_masked',    public.admin_mask_email(u.email),
      'username',        pr.username,
      'created_at',      u.created_at,
      -- 実際の利用状況はこちらを見ること。
      'last_active_at',  act.last_active_at,
      -- 「最後に再ログインを強いられた時刻」であって利用状況ではない。
      -- セッションは裏で自動更新されるため、毎日使っていてもここは古いまま。
      'last_reauth_at',  u.last_sign_in_at,
      'confirmed',       (u.email_confirmed_at IS NOT NULL),
      'suspended',       (s.user_id IS NOT NULL),
      'plan_name',       pl.name,
      'lecture_count',   (SELECT count(*) FROM public.lectures l WHERE l.user_id = u.id AND l.deleted_at IS NULL)
    ) AS x
    FROM auth.users u
    LEFT JOIN recent_activity act ON act.user_id = u.id
    LEFT JOIN public.user_profiles pr ON pr.id = u.id
    LEFT JOIN public.account_suspensions s ON s.user_id = u.id
    LEFT JOIN public.user_subscription_mappings m ON m.user_id = u.id AND m.status = 'active'
    LEFT JOIN public.subscription_plans pl ON pl.id = m.plan_id
    WHERE p_query IS NULL
       OR p_query = ''
       OR u.email ILIKE '%' || p_query || '%'
       OR pr.username ILIKE '%' || p_query || '%'
       OR u.id::text = p_query
    ORDER BY u.created_at DESC
    LIMIT least(greatest(p_limit, 1), 200)
    OFFSET greatest(p_offset, 0)
  ) s;
$$;

-- ---------------------------------------------------------------------------
-- ユーザー詳細(メタデータのみ。講義のタイトル・本文は一切返さない)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_user_detail(p_user_id uuid)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT json_build_object(
    'user_id',         u.id,
    'email_masked',    public.admin_mask_email(u.email),
    'created_at',      u.created_at,
    -- 実際の利用状況。
    'last_active_at',  (
      SELECT max(a.last_seen_at) FROM public.user_activity_hours a WHERE a.user_id = u.id
    ),
    'active_days_30d', (
      SELECT count(DISTINCT (a.bucket_at at time zone 'utc')::date)
      FROM public.user_activity_hours a
      WHERE a.user_id = u.id AND a.bucket_at >= now() - interval '30 days'
    ),
    -- 「最後に再ログインを強いられた時刻」。利用状況の指標ではない
    -- (セッションは裏で自動更新され、last_sign_in_atは更新されない)。
    'last_reauth_at',  u.last_sign_in_at,
    'confirmed',       (u.email_confirmed_at IS NOT NULL),
    'providers',       coalesce(u.raw_app_meta_data->'providers', '[]'::jsonb),
    'username',        (SELECT pr.username FROM public.user_profiles pr WHERE pr.id = u.id),

    'suspension', (
      SELECT json_build_object('suspended_at', s.suspended_at, 'reason', s.reason, 'suspended_by', s.suspended_by)
      FROM public.account_suspensions s WHERE s.user_id = u.id
    ),

    'subscription', (
      SELECT json_build_object(
        'plan_id',    m.plan_id,
        'plan_name',  pl.name,
        'price_usd',  pl.price_usd,
        'status',     m.status,
        'current_period_start', m.current_period_start,
        'current_period_end',   m.current_period_end,
        'pending_plan_id',      m.pending_plan_id
      )
      FROM public.user_subscription_mappings m
      LEFT JOIN public.subscription_plans pl ON pl.id = m.plan_id
      WHERE m.user_id = u.id AND m.status = 'active'
      LIMIT 1
    ),

    'credits', json_build_object(
      'balance', (
        SELECT round(coalesce(sum(remaining_amount), 0) / 1000000.0, 2)
        FROM public.credit_grants
        WHERE user_id = u.id AND remaining_amount > 0 AND (expires_at IS NULL OR expires_at > now())
      ),
      'granted_total',  (SELECT round(coalesce(sum(amount), 0) / 1000000.0, 2) FROM public.credit_grants WHERE user_id = u.id),
      'consumed_total', (SELECT round(coalesce(sum(-delta), 0) / 1000000.0, 2) FROM public.credit_transactions WHERE user_id = u.id AND delta < 0)
    ),

    'usage', json_build_object(
      'lectures',        (SELECT count(*) FROM public.lectures WHERE user_id = u.id AND deleted_at IS NULL),
      'lectures_trashed',(SELECT count(*) FROM public.lectures WHERE user_id = u.id AND deleted_at IS NOT NULL),
      'courses',         (SELECT count(*) FROM public.courses WHERE user_id = u.id AND deleted_at IS NULL),
      'audio_hours',     (SELECT round(coalesce(sum(audio_duration_seconds), 0) / 3600.0, 1) FROM public.lectures WHERE user_id = u.id),
      'cost_usd',        (SELECT round(coalesce(sum(cost_usd), 0), 2) FROM public.usage_records WHERE user_id = u.id),
      'devices',         (SELECT count(*) FROM public.user_devices WHERE user_id = u.id),
      'jobs_failed',     (SELECT count(*) FROM public.processing_jobs WHERE user_id = u.id AND status IN ('FAILED','ERROR'))
    )
  )
  FROM auth.users u
  WHERE u.id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- 講義の一覧(メタデータのみ)
--
-- ★ title / title_generated / summary は意図的に返していない。講義の中身は
--    運営であっても見ないというのがこのダッシュボードの前提のため。
--    ここに列を足したくなったら、その前にその方針を見直すこと。
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_user_lectures(p_user_id uuid, p_limit integer DEFAULT 100)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(json_agg(x ORDER BY x->>'created_at' DESC), '[]'::json) FROM (
    SELECT json_build_object(
      'lecture_id',   l.id,
      'course_id',    l.course_id,
      'created_at',   l.created_at,
      'deleted_at',   l.deleted_at,
      'duration_seconds', l.audio_duration_seconds,
      'credits_used', round(coalesce(l.credits_used, 0) / 1000000.0, 2),
      'recording_language', l.recording_language,
      'job_status',   (
        SELECT j.status FROM public.processing_jobs j
        WHERE j.lecture_id = l.id ORDER BY j.created_at DESC LIMIT 1
      ),
      'job_id',       (
        SELECT j.id FROM public.processing_jobs j
        WHERE j.lecture_id = l.id ORDER BY j.created_at DESC LIMIT 1
      )
    ) AS x
    FROM public.lectures l
    WHERE l.user_id = p_user_id
    ORDER BY l.created_at DESC
    LIMIT least(greatest(p_limit, 1), 500)
  ) s;
$$;

-- ---------------------------------------------------------------------------
-- 生のメールアドレス(PII開示。呼び出し側が必ずadmin_audit_logに記録すること)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_user_email(p_user_id uuid)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT u.email FROM auth.users u WHERE u.id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- 実行権限: service_role(バックエンド)のみ。
-- ログイン中の一般ユーザー(authenticated)やanonから絶対に呼べないようにする。
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.admin_overview_stats()',
    'public.admin_daily_series(integer)',
    'public.admin_hourly_distribution(integer)',
    'public.admin_pipeline_health(integer)',
    'public.admin_plan_distribution()',
    'public.admin_user_search(text, integer, integer)',
    'public.admin_user_detail(uuid)',
    'public.admin_user_lectures(uuid, integer)',
    'public.admin_user_email(uuid)',
    'public.admin_mask_email(text)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END;
$$;
