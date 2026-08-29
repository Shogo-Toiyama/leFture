import { useCallback, useEffect, useState } from 'react';
import { listLectures } from '../lib/lectures';
import type { Lecture } from '../types/lecture';

export function useLectures(courseId: string | undefined) {
  const [lectures, setLectures] = useState<Lecture[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (!courseId) return;
    setLoading(true);
    setError(null);
    try {
      setLectures(await listLectures(courseId));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load lectures');
    } finally {
      setLoading(false);
    }
  }, [courseId]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { lectures, loading, error, refetch };
}
