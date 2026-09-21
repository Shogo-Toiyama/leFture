import { useEffect, useState } from 'react';
import { getLecture } from '../lib/lectures';
import { fetchTranscriptArtifact, ArtifactFetchError } from '../lib/artifacts';
import type { TranscriptSentence } from '../types/content';
import { useLanguage } from '../i18n/LanguageContext';

export function useTranscript(lectureId: string | undefined) {
  const { t } = useLanguage();
  const [sentences, setSentences] = useState<TranscriptSentence[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!lectureId) return;
    let cancelled = false;
    setLoading(true);
    setError(null);

    (async () => {
      try {
        const lecture = await getLecture(lectureId);
        const data = await fetchTranscriptArtifact<TranscriptSentence[]>(lecture.user_id, lectureId);
        if (!cancelled) setSentences(data);
      } catch (err) {
        if (cancelled) return;
        if (err instanceof ArtifactFetchError) {
          setError(t('transcriptNotAvailable'));
        } else {
          setError(err instanceof Error ? err.message : t('failedToLoadTranscript'));
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [lectureId, t]);

  return { sentences, loading, error };
}
