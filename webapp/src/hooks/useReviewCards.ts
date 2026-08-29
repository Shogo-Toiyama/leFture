import { useCallback, useEffect, useState } from 'react';
import { listReviewCards } from '../lib/content';
import type { ReviewCard } from '../types/content';

export function useReviewCards(lectureId: string | undefined) {
  const [cards, setCards] = useState<ReviewCard[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(() => {
    if (!lectureId) return;
    setLoading(true);
    listReviewCards(lectureId)
      .then(setCards)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load review cards'))
      .finally(() => setLoading(false));
  }, [lectureId]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { cards, loading, error, refetch, setCards };
}
