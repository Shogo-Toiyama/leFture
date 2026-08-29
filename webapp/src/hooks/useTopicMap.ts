import { useEffect, useState } from 'react';
import { getTopicMap } from '../lib/content';
import type { TopicMapData } from '../types/content';

export function useTopicMap(courseId: string | undefined) {
  const [map, setMap] = useState<TopicMapData | null>(null);
  const [isStale, setIsStale] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!courseId) return;
    setLoading(true);
    getTopicMap(courseId)
      .then((result) => {
        setMap(result?.map ?? null);
        setIsStale(result?.isStale ?? false);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load topic map'))
      .finally(() => setLoading(false));
  }, [courseId]);

  return { map, isStale, loading, error };
}
