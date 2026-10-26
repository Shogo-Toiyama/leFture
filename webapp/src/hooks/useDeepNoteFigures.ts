import { useCallback, useEffect, useState } from 'react';
import { listDeepNoteFigures } from '../lib/content';
import type { DeepNoteFigure } from '../types/content';

export function useDeepNoteFigures(lectureId: string | undefined) {
  const [figures, setFigures] = useState<DeepNoteFigure[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(() => {
    if (!lectureId) return;
    setLoading(true);
    listDeepNoteFigures(lectureId)
      .then(setFigures)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load figures'))
      .finally(() => setLoading(false));
  }, [lectureId]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { figures, loading, error, refetch };
}
