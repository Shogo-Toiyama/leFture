import { useCallback, useEffect, useState } from 'react';
import { listDeepNotes } from '../lib/content';
import type { DeepNote } from '../types/content';

export function useDeepNotes(lectureId: string | undefined) {
  const [notes, setNotes] = useState<DeepNote[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(() => {
    if (!lectureId) return;
    setLoading(true);
    listDeepNotes(lectureId)
      .then(setNotes)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load deep notes'))
      .finally(() => setLoading(false));
  }, [lectureId]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { notes, loading, error, refetch, setNotes };
}
