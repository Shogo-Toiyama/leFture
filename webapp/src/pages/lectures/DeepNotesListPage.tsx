import React from 'react';
import { Link, useParams } from 'react-router-dom';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useDeepNotes } from '../../hooks/useDeepNotes';
import { PageState } from '../../components/PageState';

/** deep_notes_list_page.dart 準拠: ナンバリング付きグラスカードの縦リスト。 */
export const DeepNotesListPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const { topics, loading: topicsLoading } = useLectureTopics(lectureId);
  const { notes, loading: notesLoading, error } = useDeepNotes(lectureId);

  const entries = topics
    .map((topic) => ({ topic, note: notes.find((n) => n.topic_number === topic.index) }))
    .filter((e) => e.note !== undefined);

  const loading = topicsLoading || notesLoading;

  return (
    <div>
      <Link to={`/lectures/${lectureId}`} className="back-link">
        ← Lecture
      </Link>
      <h1>Deep notes</h1>

      {loading && <PageState kind="loading" />}
      {error && <PageState kind="error" message={error} />}
      {!loading && entries.length === 0 && <PageState kind="empty" title="No deep notes yet" />}

      <ul className="deep-note-list">
        {entries.map(({ topic, note }, i) => (
          <li key={topic.id}>
            <Link to={`/lectures/${lectureId}/deep-notes/${topic.index}`} className="deep-note-list-item">
              <span className="deep-note-badge">{i + 1}</span>
              <span className="deep-note-list-text">
                <strong>{topic.topic_title}</strong>
                {(topic.summary || note?.note_contents) && <span>{topic.summary ?? note?.note_contents}</span>}
              </span>
              <span className="glass-row-chevron">›</span>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
};
