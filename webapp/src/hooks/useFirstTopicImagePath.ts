import { useEffect, useState } from 'react';
import { getFirstTopicImagePath } from '../lib/content';

/** レクチャーの最初のトピック(index=1)のimage_pathを取得する。firstTopicImagePathProvider(Flutter)相当。 */
export function useFirstTopicImagePath(lectureId: string | null | undefined): string | null {
  const [path, setPath] = useState<string | null>(null);

  useEffect(() => {
    if (!lectureId) {
      setPath(null);
      return;
    }
    let cancelled = false;

    getFirstTopicImagePath(lectureId)
      .then((result) => {
        if (!cancelled) setPath(result);
      })
      .catch(() => {
        if (!cancelled) setPath(null);
      });

    return () => {
      cancelled = true;
    };
  }, [lectureId]);

  return path;
}
