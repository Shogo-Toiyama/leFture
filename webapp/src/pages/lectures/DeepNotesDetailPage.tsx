import React, { useEffect } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useDeepNotes } from '../../hooks/useDeepNotes';
import { updateDeepNoteReaction } from '../../lib/content';
import { readAnnotations } from '../../lib/annotations';
import { stripFigurePlaceholders, stripSidCitations } from '../../lib/sidCitation';
import { AnnotatedMarkdown } from '../../components/annotations/AnnotatedMarkdown';
import { AnnotationLayer } from '../../components/annotations/AnnotationLayer';
import { TopicImage } from '../../components/TopicImage';
import { ReactionBar } from '../../components/ReactionBar';
import { CitationLink } from '../../components/CitationLink';
import { PageState } from '../../components/PageState';

/** deep_notes_detail_page.dart 準拠: 紙面・単一列、前後トピックへのナビ。 */
export const DeepNotesDetailPage: React.FC = () => {
  const { lectureId, topicIndex } = useParams<{ lectureId: string; topicIndex: string }>();
  const navigate = useNavigate();
  const { topics } = useLectureTopics(lectureId);
  const { notes, loading, error, setNotes } = useDeepNotes(lectureId);

  const entries = topics
    .map((topic) => ({ topic, note: notes.find((n) => n.topic_number === topic.index) }))
    .filter((e) => e.note !== undefined);

  const topicNumber = Number(topicIndex);
  const currentPos = entries.findIndex((e) => e.topic.index === topicNumber);
  const current = currentPos >= 0 ? entries[currentPos] : undefined;
  const prevEntry = currentPos > 0 ? entries[currentPos - 1] : undefined;
  const nextEntry = currentPos >= 0 && currentPos < entries.length - 1 ? entries[currentPos + 1] : undefined;

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === 'TEXTAREA' || target.tagName === 'INPUT')) return;
      if (event.key === 'ArrowRight' && nextEntry) navigate(`/lectures/${lectureId}/deep-notes/${nextEntry.topic.index}`);
      if (event.key === 'ArrowLeft' && prevEntry) navigate(`/lectures/${lectureId}/deep-notes/${prevEntry.topic.index}`);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [nextEntry, prevEntry, lectureId, navigate]);

  if (loading) return <PageState kind="loading" />;
  if (error) return <PageState kind="error" message={error} />;
  if (!current?.note) return <PageState kind="empty" title="Deep note not found" />;

  const { topic, note } = current;
  const cleaned = stripSidCitations(stripFigurePlaceholders(note.note_contents));

  const handleReaction = async (reaction: 'like' | 'dislike') => {
    const next = note.metadata?.reaction === reaction ? null : reaction;
    setNotes((prev) => prev.map((n) => (n.id === note.id ? { ...n, metadata: { ...n.metadata, reaction: next } } : n)));
    await updateDeepNoteReaction(note.id, note.metadata, reaction);
  };

  return (
    <div className="deep-note-page">
      <Link to={`/lectures/${lectureId}/deep-notes`} className="back-link" style={{ padding: '0 16px' }}>
        ← Deep notes
      </Link>

      <div style={{ padding: '0 0' }}>
        {topic.image_path && (
          <div className="deep-note-hero">
            <TopicImage imagePath={topic.image_path} alt={topic.topic_title} />
          </div>
        )}

        <AnnotationLayer
          key={note.id}
          table="deep_notes"
          rowId={note.id}
          metadata={note.metadata}
          onMetadataChange={(metadata) => setNotes((prev) => prev.map((n) => (n.id === note.id ? { ...n, metadata } : n)))}
          lectureId={lectureId!}
        >
          <div className="deep-note-body">
            <h1>{topic.topic_title}</h1>
            {topic.summary && <p className="deep-note-summary">{topic.summary}</p>}
            <AnnotatedMarkdown
              markdown={cleaned}
              rawMarkdown={note.note_contents}
              annotations={readAnnotations(note.metadata)}
              blockIdx={null}
            />
          </div>

          <div style={{ marginTop: '1.25rem' }}>
            <CitationLink lectureId={lectureId!} rawText={note.note_contents} />
            <div style={{ marginTop: '0.5rem' }}>
              <ReactionBar reaction={note.metadata?.reaction ?? null} onChange={handleReaction} />
            </div>
          </div>
        </AnnotationLayer>

        <nav className="deep-note-nav">
          <button
            type="button"
            onClick={() => prevEntry && navigate(`/lectures/${lectureId}/deep-notes/${prevEntry.topic.index}`)}
            disabled={!prevEntry}
          >
            <span className="deep-note-nav-label">Previous</span>
            {prevEntry?.topic.topic_title ?? '—'}
          </button>
          <button
            type="button"
            onClick={() => nextEntry && navigate(`/lectures/${lectureId}/deep-notes/${nextEntry.topic.index}`)}
            disabled={!nextEntry}
          >
            <span className="deep-note-nav-label">Next</span>
            {nextEntry?.topic.topic_title ?? '—'}
          </button>
        </nav>
      </div>
    </div>
  );
};
