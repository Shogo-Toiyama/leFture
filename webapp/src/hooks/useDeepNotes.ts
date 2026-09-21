import { useCallback, useEffect, useState } from 'react';
import { listDeepNotes } from '../lib/content';
import type { DeepNote } from '../types/content';
import { useLanguage } from '../i18n/LanguageContext';

export function useDeepNotes(lectureId: string | undefined) {
  const { t } = useLanguage();
  const [notes, setNotes] = useState<DeepNote[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(() => {
    if (!lectureId) return;
    setLoading(true);
    listDeepNotes(lectureId)
      .then(setNotes)
      .catch((err) => setError(err instanceof Error ? err.message : t('failedToLoadDeepNotes')))
      .finally(() => setLoading(false));
  }, [lectureId, t]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { notes, loading, error, refetch, setNotes };
}
