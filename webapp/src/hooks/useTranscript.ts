import { useEffect, useState } from 'react';
import { getLecture } from '../lib/lectures';
import { fetchTranscriptArtifact, ArtifactFetchError } from '../lib/artifacts';
import type { TranscriptSentence } from '../types/content';

export function useTranscript(lectureId: string | undefined) {
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
          setError('Transcript is not available yet.');
        } else {
          setError(err instanceof Error ? err.message : 'Failed to load transcript');
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [lectureId]);

  return { sentences, loading, error };
}
