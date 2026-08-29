import { useEffect, useState } from 'react';
import { listLectureTopics } from '../lib/content';
import type { LectureTopic } from '../types/content';

export function useLectureTopics(lectureId: string | undefined) {
  const [topics, setTopics] = useState<LectureTopic[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!lectureId) return;
    setLoading(true);
    listLectureTopics(lectureId)
      .then(setTopics)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load topics'))
      .finally(() => setLoading(false));
  }, [lectureId]);

  return { topics, loading, error };
}
