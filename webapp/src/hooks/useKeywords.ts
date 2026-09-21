import { useEffect, useState } from 'react';
import { listKeywords } from '../lib/content';
import type { Keyword } from '../types/content';
import { useLanguage } from '../i18n/LanguageContext';

export function useKeywords(lectureId: string | undefined) {
  const { t } = useLanguage();
  const [keywords, setKeywords] = useState<Keyword[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!lectureId) return;
    setLoading(true);
    listKeywords(lectureId)
      .then(setKeywords)
      .catch((err) => setError(err instanceof Error ? err.message : t('failedToLoadKeywords')))
      .finally(() => setLoading(false));
  }, [lectureId, t]);

  return { keywords, setKeywords, loading, error };
}
