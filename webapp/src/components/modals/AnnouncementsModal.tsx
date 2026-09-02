import React, { useState } from 'react';
import type { Announcement } from '../../types/content';
import { toggleAnnouncementCompleted } from '../../lib/content';
import { ModalDialog } from './ModalDialog';
import { useLanguage } from '../../i18n/LanguageContext';

export interface AnnouncementsModalProps {
  announcements: Announcement[];
  onClose: () => void;
  onAnnouncementToggled?: (updated: Announcement) => void;
}

export const AnnouncementsModal: React.FC<AnnouncementsModalProps> = ({
  announcements,
  onClose,
  onAnnouncementToggled,
}) => {
  const { language } = useLanguage();
  const title = language === 'ja' ? 'お知らせ' : 'Announcements';

  // Filter tabs: 'active' | 'completed' | 'all'
  const [filter, setFilter] = useState<'active' | 'completed' | 'all'>('active');

  const filtered = announcements.filter((a) => {
    if (filter === 'active') return !a.completed_at;
    if (filter === 'completed') return Boolean(a.completed_at);
    return true;
  });

  const handleToggleDone = async (item: Announcement) => {
    const isCompleted = Boolean(item.completed_at);
    const nextCompleted = !isCompleted;
    try {
      await toggleAnnouncementCompleted(item.id, nextCompleted);
      const updated: Announcement = {
        ...item,
        completed_at: nextCompleted ? new Date().toISOString() : null,
      };
      onAnnouncementToggled?.(updated);
    } catch (err) {
      console.error('Failed to toggle announcement completion:', err);
    }
  };

  return (
    <ModalDialog title={title} count={announcements.length} onClose={onClose} maxWidth={680}>
      {/* Filter Tabs */}
      <div className="announcements-filter-tabs">
        <button
          type="button"
          className={`announcement-tab-btn ${filter === 'active' ? 'is-active' : ''}`}
          onClick={() => setFilter('active')}
        >
          {language === 'ja' ? '未完了' : 'Active'}
        </button>
        <button
          type="button"
          className={`announcement-tab-btn ${filter === 'completed' ? 'is-active' : ''}`}
          onClick={() => setFilter('completed')}
        >
          {language === 'ja' ? '完了済み' : 'Completed'}
        </button>
        <button
          type="button"
          className={`announcement-tab-btn ${filter === 'all' ? 'is-active' : ''}`}
          onClick={() => setFilter('all')}
        >
          {language === 'ja' ? 'すべて' : 'All'}
        </button>
      </div>

      {filtered.length === 0 ? (
        <div className="modal-empty-state">
          <p>{language === 'ja' ? '該当するお知らせはありません' : 'No announcements in this view'}</p>
        </div>
      ) : (
        <div className="modal-item-list">
          {filtered.map((item) => {
            const isCompleted = Boolean(item.completed_at);

            return (
              <div
                key={item.id}
                className={`announcement-item-card ${isCompleted ? 'is-completed' : ''}`}
              >
                <div className="announcement-card-top-row">
                  <div className="announcement-meta-left">
                    <span className={`announcement-type-pill type-${item.type.toLowerCase()}`}>
                      {item.type}
                    </span>
                    {item.related_topic_title && (
                      <span className="announcement-topic-tag">{item.related_topic_title}</span>
                    )}
                  </div>

                  {/* Completion Toggle Button */}
                  <button
                    type="button"
                    className={`announcement-complete-btn ${isCompleted ? 'is-done' : ''}`}
                    onClick={() => handleToggleDone(item)}
                    title={isCompleted ? 'Mark as active' : 'Mark as completed'}
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" className="complete-check-svg">
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  </button>
                </div>

                <h3 className={`announcement-item-title ${isCompleted ? 'line-through-title' : ''}`}>
                  {item.title || 'Untitled Announcement'}
                </h3>

                {item.description && (
                  <p className="announcement-item-desc">{item.description}</p>
                )}

                {item.location && (
                  <div className="announcement-extra-info">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="extra-info-icon">
                      <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
                      <circle cx="12" cy="10" r="3" />
                    </svg>
                    <span>{item.location}</span>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </ModalDialog>
  );
};
