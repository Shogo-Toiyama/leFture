-- Adminダッシュボードの復旧操作に必要なIDを、既存の集計関数に足す。
--
--   admin_pipeline_health.recent_failures に lecture_id
--     → 失敗一覧から POST /admin/lectures/{id}/cancel-jobs を呼ぶため
--   admin_user_lectures に failed_task_id
--     → ユーザーの講義一覧から POST /admin/tasks/{id}/retry を呼ぶため
--
-- どちらもIDを足すだけで、講義の中身(タイトル・要約等)は相変わらず返さない。
-- CREATE OR REPLACE は既存の権限(service_roleのみEXECUTE)をそのまま保持する。

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
    -- error_messageはまれにLLMの応答断片を含みうるため300文字で切る
    -- (講義本文の閲覧手段にはしないこと)。
    'recent_failures', (
      SELECT coalesce(json_agg(x ORDER BY x->>'updated_at' DESC), '[]'::json) FROM (
        SELECT json_build_object(
          'task_id',    t.id,
          'job_id',     t.job_id,
          'lecture_id', j.lecture_id,
          'job_status', j.status,
          'task_type',  t.task_type,
          'updated_at', t.updated_at,
          'error',      left(coalesce(t.error_message, ''), 300)
        ) AS x
        FROM window_tasks t
        LEFT JOIN public.processing_jobs j ON j.id = t.job_id
        WHERE t.status IN ('FAILED','ERROR')
        ORDER BY t.updated_at DESC
        LIMIT 50
      ) f
    )
  );
$$;

-- ★ title / title_generated / summary は意図的に返していない(20260930010000参照)。
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
      'job_status',   lj.status,
      'job_id',       lj.id,
      'failed_task_id', (
        SELECT t.id FROM public.processing_tasks t
        WHERE t.job_id = lj.id AND t.status IN ('FAILED','ERROR')
        ORDER BY t.updated_at DESC LIMIT 1
      )
    ) AS x
    FROM public.lectures l
    LEFT JOIN LATERAL (
      SELECT j.id, j.status FROM public.processing_jobs j
      WHERE j.lecture_id = l.id ORDER BY j.created_at DESC LIMIT 1
    ) lj ON true
    WHERE l.user_id = p_user_id
    ORDER BY l.created_at DESC
    LIMIT least(greatest(p_limit, 1), 500)
  ) s;
$$;
