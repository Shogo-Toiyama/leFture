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
  created_at: string;
  updated_at: string;
}

export function lectureDisplayTitle(lecture: Pick<Lecture, 'title' | 'title_generated'>): string {
  if (lecture.title && lecture.title.trim().length > 0) return lecture.title;
  if (lecture.title_generated && lecture.title_generated.trim().length > 0) return lecture.title_generated;
  return 'Untitled lecture';
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
