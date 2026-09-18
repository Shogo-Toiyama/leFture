import { useEffect, useState } from 'react';
import { fetchArtifactObjectUrl } from '../lib/artifacts';

interface AudioArtifact {
  url: string | null;
  loading: boolean;
  error: string | null;
}

/**
 * R2上の講義音声をobject URLとして取得する。
 * 成果物ワーカーはAuthorizationヘッダーを要求するので<audio src>から直接は
 * 引けない。Flutter版がファイルを落としてから再生するのと同じく、ここでも
 * 一度blobに落としてから再生する。
 */
export function useAudioArtifact(storagePath: string | null | undefined): AudioArtifact {
  const [url, setUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(Boolean(storagePath));
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!storagePath) {
      setUrl(null);
      setLoading(false);
      setError(null);
      return;
    }

    let cancelled = false;
    let created: string | null = null;
    setLoading(true);
    setError(null);

    fetchArtifactObjectUrl(storagePath)
      .then((objectUrl) => {
        if (cancelled) {
          URL.revokeObjectURL(objectUrl);
          return;
        }
        created = objectUrl;
        setUrl(objectUrl);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load audio');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
      if (created) URL.revokeObjectURL(created);
    };
  }, [storagePath]);

  return { url, loading, error };
}
