import React from 'react';
import { Link } from 'react-router-dom';
import type { LectureTopic } from '../../types/content';
import { TopicImage } from '../TopicImage';
import { ModalDialog } from './ModalDialog';
import { useLanguage } from '../../i18n/LanguageContext';

export interface TopicsModalProps {
  lectureId: string;
  courseId?: string | null;
  topics: LectureTopic[];
  onClose: () => void;
}

export const TopicsModal: React.FC<TopicsModalProps> = ({
  lectureId,
  topics,
  onClose,
}) => {
  const { language } = useLanguage();
  const title = language === 'ja' ? 'トピック' : 'Topics';
  const reviewCardsLabel = language === 'ja' ? '復習カード' : 'Review Cards';
  const deepNotesLabel = language === 'ja' ? '詳細ノート' : 'Deep Notes';
  const emptyStateText = language === 'ja' ? '利用可能なトピックがまだありません' : 'No topics available yet';

  return (
    <ModalDialog title={title} count={topics.length} onClose={onClose} maxWidth={720}>
      {topics.length === 0 ? (
        <div className="modal-empty-state">
          <p>{emptyStateText}</p>
        </div>
      ) : (
        <div className="topics-vertical-list">
          {topics.map((topic) => {
            const hasSummary = Boolean(topic.summary?.trim());

            return (
              <div key={topic.id} className="topic-vertical-tile">
                <div className="topic-tile-upper">
                  {/* Left: Thumbnail image */}
                  <div className="topic-tile-thumbnail">
                    <TopicImage imagePath={topic.image_path} alt={topic.topic_title} />
                  </div>

                  {/* Right: Content Info */}
                  <div className="topic-tile-info">
                    <div className="topic-badge-row">
                      <span className="topic-number-gold-pill">TOPIC {topic.index}</span>
                    </div>
                    <h3 className="topic-tile-title">{topic.topic_title}</h3>
                    {hasSummary && <p className="topic-tile-summary">{topic.summary}</p>}
                  </div>
                </div>

                <div className="topic-tile-divider" />

                {/* Bottom: Action Buttons (Review Cards & Deep Notes) */}
                <div className="topic-tile-actions">
                  <Link
                    to={`/lectures/${lectureId}/review-cards`}
                    className="topic-action-btn"
                    onClick={onClose}
                  >
                    <span className="material-symbols-outlined topic-action-glyph topic-action-glyph-review">style</span>
                    <span>{reviewCardsLabel}</span>
                  </Link>

                  <Link
                    to={`/lectures/${lectureId}/deep-notes/${topic.index}`}
                    className="topic-action-btn"
                    onClick={onClose}
                  >
                    <span className="material-symbols-outlined topic-action-glyph topic-action-glyph-notes">description</span>
                    <span>{deepNotesLabel}</span>
                  </Link>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </ModalDialog>
  );
};
