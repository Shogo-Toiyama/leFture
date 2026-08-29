import { useCallback, useEffect, useState } from 'react';
import { listFunFacts } from '../lib/content';
import type { FunFact } from '../types/content';

export function useFunFacts(lectureId: string | undefined) {
  const [funFacts, setFunFacts] = useState<FunFact[]>([]);
  const [loading, setLoading] = useState(true);

  const refetch = useCallback(() => {
    if (!lectureId) return;
    setLoading(true);
    listFunFacts(lectureId)
      .then(setFunFacts)
      .finally(() => setLoading(false));
  }, [lectureId]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { funFacts, loading, refetch, setFunFacts };
}
