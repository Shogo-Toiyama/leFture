import { apiFetch } from './api';

// 権限判定はバックエンドの require_admin だけが行う。ここは叩くだけ。
// 数値は特記ない限りSQL側で表示単位(クレジット/ドル/時間)に丸め済み。

export interface AdminMe {
  user_id: string;
  email: string | null;
  aal: string | null;
}

export interface AdminOverview {
  generated_at: string;
  users: { total: number; new_24h: number; new_7d: number; new_30d: number; confirmed: number; suspended: number };
  active: {
    active_24h: number;
    active_7d: number;
    active_30d: number;
    created_lecture_24h: number;
    created_lecture_7d: number;
    created_lecture_30d: number;
  };
  lectures: { total: number; trashed: number; new_24h: number; new_7d: number; new_30d: number; audio_hours_30d: number };
  jobs: { running: number; completed_24h: number; failed_24h: number; failed_7d: number; total_7d: number };
  credits: { consumed_24h: number; consumed_30d: number; granted_30d: number; outstanding: number };
  cost: { usd_24h: number; usd_30d: number };
  mrr_usd_estimate: number;
  support: { open: number; total: number };
}

export interface AdminSeriesPoint {
  date: string;
  signups: number;
  active_users: number;
  lectures: number;
  jobs_completed: number;
  jobs_failed: number;
  credits_consumed: number;
  cost_usd: number;
}

export interface AdminPlan {
  plan_id: string;
  name: string;
  price_usd: number;
  claim_mode: string;
  billing_interval_months: number | null;
  disabled: boolean;
  active: number;
  inactive: number;
}

export interface AdminHourly {
  window_days: number;
  local: { hour: number; users: number; engagement: number }[];
  utc: { hour: number; users: number; engagement: number }[];
  by_weekday: { weekday: number; users: number }[];
  by_platform: { platform: string; users: number; hours: number }[];
  by_tz_offset: { offset_minutes: number; users: number }[];
}

export interface AdminPipeline {
  window_days: number;
  by_task_type: {
    task_type: string;
    total: number;
    completed: number;
    failed: number;
    running: number;
    failure_rate: number;
    avg_seconds: number;
  }[];
  recent_failures: {
    task_id: string;
    job_id: string;
    lecture_id: string | null;
    job_status: string | null;
    task_type: string;
    updated_at: string;
    error: string;
  }[];
}

export interface AdminUserRow {
  user_id: string;
  email_masked: string | null;
  username: string | null;
  created_at: string;
  last_active_at: string | null;
  last_reauth_at: string | null;
  confirmed: boolean;
  suspended: boolean;
  plan_name: string | null;
  lecture_count: number;
}

export interface AdminUserDetail {
  user_id: string;
  email_masked: string | null;
  created_at: string;
  last_active_at: string | null;
  active_days_30d: number;
  last_reauth_at: string | null;
  confirmed: boolean;
  providers: string[];
  username: string | null;
  suspension: { suspended_at: string; reason: string | null; suspended_by: string | null } | null;
  subscription: {
    plan_id: string;
    plan_name: string | null;
    price_usd: number | null;
    status: string;
    current_period_start: string | null;
    current_period_end: string | null;
    pending_plan_id: string | null;
  } | null;
  credits: { balance: number; granted_total: number; consumed_total: number };
  usage: {
    lectures: number;
    lectures_trashed: number;
    courses: number;
    audio_hours: number;
    cost_usd: number;
    devices: number;
    jobs_failed: number;
  };
}

export interface AdminUserLecture {
  lecture_id: string;
  course_id: string | null;
  created_at: string;
  deleted_at: string | null;
  duration_seconds: number | null;
  credits_used: number;
  recording_language: string | null;
  job_status: string | null;
  job_id: string | null;
  failed_task_id: string | null;
}

// credit_grants / credit_transactions は生テーブルを返すのでμクレジットのまま。
export interface AdminCreditGrant {
  id: string;
  created_at: string;
  amount: number;
  remaining_amount: number;
  source: string;
  plan_id: string | null;
  expires_at: string | null;
  metadata: Record<string, unknown> | null;
}

export interface AdminCreditTransaction {
  id: string;
  created_at: string;
  delta: number;
  balance_after: number | null;
  reason: string | null;
  related_job_id: string | null;
  related_grant_id: string | null;
  metadata: Record<string, unknown> | null;
}

export type TicketStatus = 'open' | 'in_progress' | 'resolved' | 'closed';

export interface AdminTicket {
  id: string;
  ticket_code: string;
  user_id: string | null;
  user_email_masked: string | null;
  category: string;
  message: string;
  status: TicketStatus;
  created_at: string;
  updated_at: string;
}

export interface AdminAuditEntry {
  id: number;
  created_at: string;
  admin_user_id: string;
  admin_email: string | null;
  action: string;
  target_type: string | null;
  target_id: string | null;
  params: Record<string, unknown>;
  result: string;
  error_message: string | null;
  ip: string | null;
  user_agent: string | null;
}

function qs(params: Record<string, string | number | null | undefined>): string {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== null && v !== undefined && v !== '') sp.set(k, String(v));
  }
  const s = sp.toString();
  return s ? `?${s}` : '';
}

const post = <T>(path: string, body?: unknown) =>
  apiFetch<T>(path, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) });

export const adminApi = {
  me: () => apiFetch<AdminMe>('/admin/me'),

  overview: () => apiFetch<AdminOverview>('/admin/overview'),
  series: (days: number) => apiFetch<AdminSeriesPoint[]>(`/admin/series${qs({ days })}`),
  plans: () => apiFetch<AdminPlan[]>('/admin/plans'),
  hourly: (days: number) => apiFetch<AdminHourly>(`/admin/hourly${qs({ days })}`),
  pipeline: (days: number) => apiFetch<AdminPipeline>(`/admin/pipeline${qs({ days })}`),

  users: (q: string, limit: number, offset: number) =>
    apiFetch<AdminUserRow[]>(`/admin/users${qs({ q, limit, offset })}`),
  userDetail: (id: string) => apiFetch<AdminUserDetail>(`/admin/users/${id}`),
  userLectures: (id: string) => apiFetch<AdminUserLecture[]>(`/admin/users/${id}/lectures`),
  userCredits: (id: string) =>
    apiFetch<{ grants: AdminCreditGrant[]; transactions: AdminCreditTransaction[] }>(`/admin/users/${id}/credits`),
  revealUserEmail: (id: string) => post<{ user_id: string; email: string }>(`/admin/users/${id}/reveal-email`),

  grantCredits: (id: string, credits: number, reason: string, expiresInDays: number | null) =>
    post<{ success: boolean; grant_id: string | null }>(`/admin/users/${id}/credits/grant`, {
      credits,
      reason,
      expires_in_days: expiresInDays,
    }),
  suspend: (id: string, reason: string) => post(`/admin/users/${id}/suspend`, { reason }),
  unsuspend: (id: string) => post(`/admin/users/${id}/unsuspend`),
  deleteUser: (id: string, confirmUserId: string, reason: string) =>
    post(`/admin/users/${id}/delete`, { confirm_user_id: confirmUserId, reason }),

  cancelLectureJobs: (lectureId: string) =>
    post<{ success: boolean; cancelled_jobs: number }>(`/admin/lectures/${lectureId}/cancel-jobs`),
  retryTask: (taskId: string) => post(`/admin/tasks/${taskId}/retry`),

  tickets: (status: TicketStatus | null) => apiFetch<AdminTicket[]>(`/admin/support/tickets${qs({ status })}`),
  revealTicketEmail: (id: string) =>
    post<{ id: string; user_id: string | null; user_email: string }>(`/admin/support/tickets/${id}/reveal-email`),
  setTicketStatus: (id: string, status: TicketStatus) => post(`/admin/support/tickets/${id}/status`, { status }),

  auditLog: (params: { action?: string; target_id?: string; limit: number; offset: number }) =>
    apiFetch<AdminAuditEntry[]>(`/admin/audit-log${qs(params)}`),
};
