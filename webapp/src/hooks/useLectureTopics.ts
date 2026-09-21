import { useEffect, useState } from 'react';
import { listLectureTopics } from '../lib/content';
import type { LectureTopic } from '../types/content';
import { useLanguage } from '../i18n/LanguageContext';

export function useLectureTopics(lectureId: string | undefined) {
  const { t } = useLanguage();
  const [topics, setTopics] = useState<LectureTopic[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!lectureId) return;
    setLoading(true);
    listLectureTopics(lectureId)
      .then(setTopics)
      .catch((err) => setError(err instanceof Error ? err.message : t('failedToLoadTopics')))
      .finally(() => setLoading(false));
  }, [lectureId, t]);

  return { topics, loading, error };
}
