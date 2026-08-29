import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { getLecture } from '../lib/lectures';
import type { Lecture, ProcessingJob, ProcessingTask } from '../types/lecture';
import { DEAD_JOB_STATUSES } from '../types/lecture';

const POLL_INTERVAL_MS = 5000;

/**
 * 講義本体 + 直近のprocessing_job + そのタスク一覧を取得する。
 * Supabase Realtimeを第一の更新経路にしつつ、購読が効かない/切断された場合の
 * フォールバックとして常に低頻度ポーリングも並行して行う(webapp実装プラン参照)。
 */
export function useProcessingStatus(lectureId: string | undefined) {
  const [lecture, setLecture] = useState<Lecture | null>(null);
  const [job, setJob] = useState<ProcessingJob | null>(null);
  const [tasks, setTasks] = useState<ProcessingTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const jobIdRef = useRef<string | null>(null);

  const refetch = useCallback(async () => {
    if (!lectureId) return;
    try {
      const lectureRow = await getLecture(lectureId);
      setLecture(lectureRow);

      const { data: jobRows, error: jobError } = await supabase
        .from('processing_jobs')
        .select('*')
        .eq('lecture_id', lectureId)
        .order('created_at', { ascending: false })
        .limit(1);
      if (jobError) throw jobError;
      const latestJob = (jobRows?.[0] as ProcessingJob | undefined) ?? null;
      setJob(latestJob);
      jobIdRef.current = latestJob?.id ?? null;

      if (latestJob) {
        const { data: taskRows, error: tasksError } = await supabase
          .from('processing_tasks')
          .select('*')
          .eq('job_id', latestJob.id);
        if (tasksError) throw tasksError;
        setTasks((taskRows as ProcessingTask[]) ?? []);
      } else {
        setTasks([]);
      }
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load processing status');
    } finally {
      setLoading(false);
    }
  }, [lectureId]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  // Realtime: このlectureのジョブ/タスク行が変化したら即座に再取得する。
  useEffect(() => {
    if (!lectureId) return;
    const channel = supabase
      .channel(`processing-status:${lectureId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'processing_jobs', filter: `lecture_id=eq.${lectureId}` },
        () => refetch()
      )
      .on('postgres_changes', { event: '*', schema: 'public', table: 'processing_tasks' }, (payload) => {
        const row = (payload.new ?? payload.old) as { job_id?: string } | null;
        if (row?.job_id && row.job_id === jobIdRef.current) refetch();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [lectureId, refetch]);

  // ポーリング・フォールバック: ジョブが未終端の間は常に併走させる。
  useEffect(() => {
    const isTerminal = job ? job.status === 'COMPLETED' || DEAD_JOB_STATUSES.includes(job.status) : false;
    if (!lectureId || isTerminal) return;
    const interval = setInterval(refetch, POLL_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [lectureId, job, refetch]);

  return { lecture, job, tasks, loading, error, refetch };
}
