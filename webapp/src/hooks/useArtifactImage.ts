import { useEffect, useState } from 'react';
import { fetchArtifactObjectUrl } from '../lib/artifacts';

/** R2上のトピック画像などをobject URLとして取得する。解放はアンマウント時に行う。 */
export function useArtifactImage(storagePath: string | null | undefined): string | null {
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    if (!storagePath) {
      setUrl(null);
      return;
    }
    let cancelled = false;
    let created: string | null = null;

    fetchArtifactObjectUrl(storagePath)
      .then((objectUrl) => {
        if (cancelled) {
          URL.revokeObjectURL(objectUrl);
          return;
        }
        created = objectUrl;
        setUrl(objectUrl);
      })
      .catch(() => {
        if (!cancelled) setUrl(null);
      });

    return () => {
      cancelled = true;
      if (created) URL.revokeObjectURL(created);
    };
  }, [storagePath]);

  return url;
}
