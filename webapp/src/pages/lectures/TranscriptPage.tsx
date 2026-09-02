import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { useTranscript } from '../../hooks/useTranscript';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { isMainContent } from '../../types/content';
import { PageState } from '../../components/PageState';

function formatTimestamp(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = h > 0 ? String(m).padStart(2, '0') : String(m);
  return `${h > 0 ? `${h}:` : ''}${mm}:${String(s).padStart(2, '0')}`;
}

export const TranscriptPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const [searchParams] = useSearchParams();
  const { sentences, loading, error } = useTranscript(lectureId);
  const { topics } = useLectureTopics(lectureId);
  const highlightRef = useRef<HTMLDivElement>(null);

  const [query, setQuery] = useState('');
  const [mainOnly, setMainOnly] = useState(false);

  const highlightSids = useMemo(
    () => new Set((searchParams.get('sids') ?? '').split(',').filter(Boolean)),
    [searchParams]
  );

  const visible = useMemo(() => {
    if (!sentences) return [];
    const needle = query.trim().toLowerCase();
    return sentences.filter((sentence) => {
      if (mainOnly && !isMainContent(sentence)) return false;
      if (needle && !sentence.text.toLowerCase().includes(needle)) return false;
      return true;
    });
  }, [sentences, query, mainOnly]);

  useEffect(() => {
    if (highlightSids.size > 0 && highlightRef.current) {
      highlightRef.current.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }, [visible, highlightSids]);

  const chapters = useMemo(() => topics.filter((t) => t.start_sid), [topics]);

  const scrollToSid = (sid: string) => {
    document.getElementById(`sid-${sid}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  };

  if (loading) return <PageState kind="loading" />;
  if (error) {
    return (
      <PageState
        kind="empty"
        title="Transcript not available"
        message={error}
        action={<Link to={`/lectures/${lectureId}`}>Back to lecture</Link>}
      />
    );
  }

  let firstHighlightSeen = false;

  return (
    <div className="transcript-page">
      <Link to={`/lectures/${lectureId}`} className="back-link">
        ← Lecture
      </Link>
      <h1>Transcript</h1>

      {chapters.length > 0 && (
        <div className="transcript-chapters">
          {chapters.map((topic) => (
            <button key={topic.id} type="button" className="pill-chip" onClick={() => scrollToSid(topic.start_sid!)}>
              {topic.topic_title}
            </button>
          ))}
        </div>
      )}

      <div className="transcript-toolbar">
        <input
          type="search"
          className="transcript-search"
          placeholder="Search transcript…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <label className="toggle">
          <input type="checkbox" checked={mainOnly} onChange={(e) => setMainOnly(e.target.checked)} />
          Lecture content only
        </label>
      </div>

      <div className="transcript">
        {visible.map((sentence) => {
          const isHighlighted = highlightSids.has(sentence.sid);
          const attachRef = isHighlighted && !firstHighlightSeen;
          if (attachRef) firstHighlightSeen = true;
          return (
            <div
              key={sentence.sid}
              id={`sid-${sentence.sid}`}
              ref={attachRef ? highlightRef : undefined}
              className={[
                'transcript-sentence',
                isMainContent(sentence) ? '' : 'transcript-sentence-aside',
                isHighlighted ? 'transcript-sentence-highlighted' : '',
              ]
                .filter(Boolean)
                .join(' ')}
            >
              <span className="transcript-timestamp">{formatTimestamp(sentence.start)}</span>
              <span className="transcript-text">{sentence.text}</span>
            </div>
          );
        })}
        {visible.length === 0 && <p className="transcript-empty">No lines match your search.</p>}
      </div>
    </div>
  );
};
