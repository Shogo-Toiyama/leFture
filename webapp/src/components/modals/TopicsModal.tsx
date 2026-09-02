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
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="topic-action-svg">
                      <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
                      <line x1="8" y1="21" x2="16" y2="21" />
                      <line x1="12" y1="17" x2="12" y2="21" />
                    </svg>
                    <span>{reviewCardsLabel}</span>
                  </Link>

                  <Link
                    to={`/lectures/${lectureId}/deep-notes`}
                    className="topic-action-btn"
                    onClick={onClose}
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="topic-action-svg">
                      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                      <polyline points="14 2 14 8 20 8" />
                      <line x1="16" y1="13" x2="8" y2="13" />
                      <line x1="16" y1="17" x2="8" y2="17" />
                    </svg>
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
