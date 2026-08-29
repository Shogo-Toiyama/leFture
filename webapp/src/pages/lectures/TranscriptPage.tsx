import React, { useEffect, useRef } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { useTranscript } from '../../hooks/useTranscript';
import { isMainContent } from '../../types/content';

function formatTimestamp(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export const TranscriptPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const [searchParams] = useSearchParams();
  const { sentences, loading, error } = useTranscript(lectureId);
  const highlightRef = useRef<HTMLDivElement>(null);

  const highlightSids = new Set((searchParams.get('sids') ?? '').split(',').filter(Boolean));

  useEffect(() => {
    if (highlightSids.size > 0 && highlightRef.current) {
      highlightRef.current.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sentences]);

  return (
    <div>
      <Link to={`/lectures/${lectureId}`}>← Back to lecture</Link>
      <h1>Transcript</h1>

      {loading && <p>Loading…</p>}
      {error && <p className="auth-error">{error}</p>}

      <div className="transcript-body">
        {sentences?.map((sentence, i) => {
          const isHighlighted = highlightSids.has(sentence.sid);
          const firstHighlighted = isHighlighted && !sentences.slice(0, i).some((s) => highlightSids.has(s.sid));
          return (
            <div
              key={sentence.sid}
              ref={firstHighlighted ? highlightRef : undefined}
              className={[
                'transcript-sentence',
                isMainContent(sentence) ? '' : 'transcript-sentence-offtopic',
                isHighlighted ? 'transcript-sentence-highlighted' : '',
              ]
                .filter(Boolean)
                .join(' ')}
            >
              <span className="transcript-timestamp">{formatTimestamp(sentence.start)}</span>
              <span>{sentence.text}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
};
