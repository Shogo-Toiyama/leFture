import { useCallback, useEffect, useState } from 'react';
import { listReviewCards } from '../lib/content';
import type { ReviewCard } from '../types/content';
import { useLanguage } from '../i18n/LanguageContext';

export function useReviewCards(lectureId: string | undefined) {
  const { t } = useLanguage();
  const [cards, setCards] = useState<ReviewCard[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(() => {
    if (!lectureId) return;
    setLoading(true);
    listReviewCards(lectureId)
      .then(setCards)
      .catch((err) => setError(err instanceof Error ? err.message : t('failedToLoadReviewCards')))
      .finally(() => setLoading(false));
  }, [lectureId, t]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { cards, loading, error, refetch, setCards };
}
