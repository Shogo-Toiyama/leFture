export interface Lecture {
  id: string;
  user_id: string;
  course_id: string;
  title: string | null;
  title_generated: string | null;
  lecture_datetime: string;
  sort_order: number;
  summary: string | null;
  audio_path: string | null;
  metadata: Record<string, unknown> | null;
  deleted_at: string | null;
  recording_language: string | null;
  display_language: string | null;
  credits_used?: number | null;
  created_at: string;
  updated_at: string;
}

export function lectureDisplayTitle(lecture: Pick<Lecture, 'title' | 'title_generated'>): string {
  if (lecture.title && lecture.title.trim().length > 0) return lecture.title;
  if (lecture.title_generated && lecture.title_generated.trim().length > 0) return lecture.title_generated;
  return 'Untitled lecture';
}

/**
 * Returns display credit amount (e.g., 100), or null if not recorded.
 * If stored in micro-credits (1 credit = 1,000,000 micro-credits), converts to integer credits.
 */
export function lectureCreditsUsedDisplay(
  lecture: { credits_used?: number | null; metadata?: Record<string, unknown> | null } | null | undefined
): number | null {
  if (!lecture) return null;
  const raw = lecture.credits_used ?? (typeof lecture.metadata?.credits_used === 'number' ? lecture.metadata.credits_used : null);
  if (raw == null || isNaN(raw) || raw <= 0) return null;
  if (raw >= 10000) {
    return Math.floor(raw / 1000000);
  }
  return Math.floor(raw);
}

export type ProcessingJobStatus =
  | 'PENDING'
  | 'QUEUED'
  | 'WAITING'
  | 'RUNNING'
  | 'COMPLETED'
  | 'FAILED'
  | 'ERROR'
  | 'CANCELLED';

export const DEAD_JOB_STATUSES: ProcessingJobStatus[] = ['FAILED', 'ERROR', 'CANCELLED'];

export interface ProcessingJob {
  id: string;
  lecture_id: string;
  expected_chunks: number;
  status: ProcessingJobStatus;
  created_at: string;
  updated_at: string;
}

export interface ProcessingTask {
  id: string;
  job_id: string;
  task_type: string;
  status: ProcessingJobStatus;
  error_message: string | null;
  created_at: string;
  updated_at: string;
}
