import { useEffect, useState } from 'react';
import { listKeywords } from '../lib/content';
import type { Keyword } from '../types/content';

export function useKeywords(lectureId: string | undefined) {
  const [keywords, setKeywords] = useState<Keyword[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!lectureId) return;
    setLoading(true);
    listKeywords(lectureId)
      .then(setKeywords)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load keywords'))
      .finally(() => setLoading(false));
  }, [lectureId]);

  return { keywords, setKeywords, loading, error };
}
