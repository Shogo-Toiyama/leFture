import { useCallback, useEffect, useState } from 'react';
import { fetchArtifactObjectUrl, fetchSignedAudioUrl } from '../lib/artifacts';
import { useLanguage } from '../i18n/LanguageContext';

interface AudioArtifact {
  url: string | null;
  loading: boolean;
  error: string | null;
  /** 署名付きURLでストリーミングしているならtrue(期限切れ時にrefreshで取り直す)。 */
  streaming: boolean;
  /** 署名付きURLを取り直す(期限切れで再生が止まった時用)。 */
  refresh: () => void;
}

/**
 * R2上の講義音声を<audio>で再生できるURLにする。
 *
 * まず署名付きURLを使う: ブラウザがRangeリクエストで再生位置の周りだけを取るので、
 * 音声(中央値約32MB)を丸ごと待たずにすぐ再生できる。成果物ワーカーは
 * Authorizationヘッダーを要求するが<audio src>はヘッダーを付けられないため、
 * 署名をURLに含めている。
 * 署名付きURLが使えない(Workerの秘密鍵が未設定など)ときは、従来通り一度blobに
 * 落としてから再生する。
 */
export function useAudioArtifact(storagePath: string | null | undefined): AudioArtifact {
  const { t } = useLanguage();
  const [url, setUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(Boolean(storagePath));
  const [error, setError] = useState<string | null>(null);
  const [streaming, setStreaming] = useState(false);
  const [generation, setGeneration] = useState(0);

  const refresh = useCallback(() => setGeneration((g) => g + 1), []);

  useEffect(() => {
    if (!storagePath) {
      setUrl(null);
      setLoading(false);
      setError(null);
      setStreaming(false);
      return;
    }

    let cancelled = false;
    let created: string | null = null;
    setLoading(true);
    setError(null);

    (async () => {
      const signed = await fetchSignedAudioUrl(storagePath);
      if (signed) {
        if (!cancelled) {
          setUrl(signed);
          setStreaming(true);
        }
        return;
      }
      const objectUrl = await fetchArtifactObjectUrl(storagePath);
      if (cancelled) {
        URL.revokeObjectURL(objectUrl);
        return;
      }
      created = objectUrl;
      setUrl(objectUrl);
      setStreaming(false);
    })()
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : t('failedToLoadAudio'));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
      if (created) URL.revokeObjectURL(created);
    };
  }, [storagePath, t, generation]);

  return { url, loading, error, streaming, refresh };
}
