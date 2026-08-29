import React from 'react';
import ReactMarkdown from 'react-markdown';
import { Link, useParams } from 'react-router-dom';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useDeepNotes } from '../../hooks/useDeepNotes';
import { updateDeepNoteReaction } from '../../lib/content';
import { stripFigurePlaceholders, stripSidCitations } from '../../lib/sidCitation';
import { CitationLink } from '../../components/CitationLink';
import { ReactionButtons } from '../../components/ReactionButtons';

export const DeepNotesDetailPage: React.FC = () => {
  const { lectureId, topicIndex } = useParams<{ lectureId: string; topicIndex: string }>();
  const { topics } = useLectureTopics(lectureId);
  const { notes, loading, error, setNotes } = useDeepNotes(lectureId);

  const topicNumber = Number(topicIndex);
  const topic = topics.find((t) => t.index === topicNumber);
  const note = notes.find((n) => n.topic_number === topicNumber);

  if (loading) return <p>Loading…</p>;
  if (error) return <p className="auth-error">{error}</p>;
  if (!note) return <p>Deep note not found.</p>;

  const cleaned = stripSidCitations(stripFigurePlaceholders(note.note_contents));

  const handleReaction = async (reaction: 'like' | 'dislike') => {
    await updateDeepNoteReaction(note.id, note.metadata, reaction);
    setNotes((prev) =>
      prev.map((n) =>
        n.id === note.id
          ? { ...n, metadata: { ...n.metadata, reaction: n.metadata?.reaction === reaction ? null : reaction } }
          : n
      )
    );
  };

  return (
    <div>
      <Link to={`/lectures/${lectureId}/deep-notes`}>← Deep notes</Link>
      <h1>{topic?.topic_title ?? 'Deep note'}</h1>

      <div className="deep-note-body">
        <ReactMarkdown>{cleaned}</ReactMarkdown>
      </div>

      <CitationLink lectureId={lectureId!} rawText={note.note_contents} />
      <ReactionButtons reaction={note.metadata?.reaction ?? null} onChange={handleReaction} />
    </div>
  );
};
