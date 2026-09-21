import { useEffect, useState } from 'react';
import { getCourse } from '../lib/courses';
import type { Course } from '../types/course';
import { useLanguage } from '../i18n/LanguageContext';

export function useCourse(courseId?: string) {
  const { t } = useLanguage();
  const [course, setCourse] = useState<Course | null>(null);
  const [loading, setLoading] = useState(Boolean(courseId));
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!courseId) {
      setCourse(null);
      setLoading(false);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    getCourse(courseId)
      .then((data) => {
        if (!cancelled) {
          setCourse(data);
          setLoading(false);
        }
      })
      .catch((err) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : t('failedToLoadCourse'));
          setLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [courseId, t]);

  return { course, loading, error };
}
