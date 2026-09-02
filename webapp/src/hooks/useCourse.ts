import { useEffect, useState } from 'react';
import { getCourse } from '../lib/courses';
import type { Course } from '../types/course';

export function useCourse(courseId?: string) {
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
          setError(err instanceof Error ? err.message : 'Failed to load course');
          setLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [courseId]);

  return { course, loading, error };
}
