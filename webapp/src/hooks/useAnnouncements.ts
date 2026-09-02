import { useEffect, useState } from 'react';
import { listAnnouncements } from '../lib/content';
import type { Announcement } from '../types/content';

export function useAnnouncements(lectureId?: string, courseId?: string) {
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!lectureId && !courseId) return;
    setLoading(true);
    listAnnouncements(lectureId, courseId)
      .then(setAnnouncements)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load announcements'))
      .finally(() => setLoading(false));
  }, [lectureId, courseId]);

  return { announcements, setAnnouncements, loading, error };
}
