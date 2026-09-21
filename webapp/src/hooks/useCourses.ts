import { useCallback, useEffect, useState } from 'react';
import { listCourses } from '../lib/courses';
import type { Course } from '../types/course';
import { useLanguage } from '../i18n/LanguageContext';

export function useCourses() {
  const { t } = useLanguage();
  const [courses, setCourses] = useState<Course[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setCourses(await listCourses());
    } catch (err) {
      setError(err instanceof Error ? err.message : t('failedToLoadCourses'));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { courses, loading, error, refetch };
}
