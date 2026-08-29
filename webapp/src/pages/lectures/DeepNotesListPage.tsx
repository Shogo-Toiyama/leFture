import React from 'react';
import { Link, useParams } from 'react-router-dom';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useDeepNotes } from '../../hooks/useDeepNotes';

export const DeepNotesListPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const { topics, loading: topicsLoading } = useLectureTopics(lectureId);
  const { notes, loading: notesLoading, error } = useDeepNotes(lectureId);

  const notesByTopic = new Map(notes.map((n) => [n.topic_number, n]));
  const loading = topicsLoading || notesLoading;

  return (
    <div>
      <Link to={`/lectures/${lectureId}`}>← Back to lecture</Link>
      <h1>Deep notes</h1>

      {loading && <p>Loading…</p>}
      {error && <p className="auth-error">{error}</p>}

      <ul className="lecture-list">
        {topics
          .filter((topic) => notesByTopic.has(topic.index))
          .map((topic) => (
            <li key={topic.id}>
              <Link to={`/lectures/${lectureId}/deep-notes/${topic.index}`} className="lecture-list-item">
                <span>{topic.topic_title}</span>
              </Link>
            </li>
          ))}
      </ul>

      {!loading && notes.length === 0 && <p>No deep notes yet.</p>}
    </div>
  );
};
