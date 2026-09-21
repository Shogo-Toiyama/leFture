import React, { useState, useMemo, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { MoreVertical, Pencil, Trash2 } from 'lucide-react';
import type { Announcement, AnnouncementType } from '../../types/content';
import type { Lecture } from '../../types/lecture';
import { toggleAnnouncementCompleted, deleteAnnouncement } from '../../lib/content';
import { expandSidRange } from '../../lib/sidCitation';
import { ModalDialog } from './ModalDialog';
import { TranscriptSheet } from '../transcript/TranscriptSheet';
import { AnnouncementEditModal } from './AnnouncementEditModal';
import { ConfirmModal } from './ConfirmModal';
import { useLanguage } from '../../i18n/LanguageContext';

export interface AnnouncementsModalProps {
  announcements: Announcement[];
  lectures?: Lecture[];
  onClose: () => void;
  onAnnouncementToggled?: (updated: Announcement) => void;
  onAnnouncementUpdated?: (updated: Announcement) => void;
  onAnnouncementDeleted?: (id: string) => void;
  /**
   * trueにすると、カードのクリックは(該当sidがあれば)講義への遷移ではなく
   * トランスクリプトの該当範囲をこのモーダルに被せて表示する動作になる。
   * LectureViewerPage(=今まさにその講義を見ている画面)からの利用専用。
   * HomePage/CourseDetailPageでは渡さず、素直に講義ページへ遷移させる。
   */
  enableTranscriptView?: boolean;
}

export function getAnnouncementTypeConfig(type: string) {
  switch (type.toUpperCase()) {
    case 'TODO':
      return { icon: 'task_alt', color: '#4ade80', bg: 'rgba(74, 222, 128, 0.14)', label: 'TODO' };
    case 'EVENT':
      return { icon: 'event', color: '#60a5fa', bg: 'rgba(96, 165, 250, 0.14)', label: 'EVENT' };
    case 'INFO':
      return { icon: 'info', color: '#d8b4fe', bg: 'rgba(216, 180, 254, 0.14)', label: 'INFO' };
    case 'HINT':
      return { icon: 'lightbulb', color: '#fbbf24', bg: 'rgba(251, 191, 36, 0.14)', label: 'HINT' };
    default:
      return { icon: 'star', color: '#FFB300', bg: 'rgba(255, 179, 0, 0.14)', label: type.toUpperCase() };
  }
}

function formatAnnouncementDate(iso: string | null | undefined, locale: string): string {
  if (!iso) return '';
  try {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleDateString(locale, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return '';
  }
}

export const AnnouncementsModal: React.FC<AnnouncementsModalProps> = ({
  announcements,
  lectures,
  onClose,
  onAnnouncementToggled,
  onAnnouncementUpdated,
  onAnnouncementDeleted,
  enableTranscriptView,
}) => {
  const { t, locale } = useLanguage();
  const navigate = useNavigate();
  const title = t('announcementsTitle');

  const [localAnnouncements, setLocalAnnouncements] = useState<Announcement[]>(announcements);
  useEffect(() => {
    setLocalAnnouncements(announcements);
  }, [announcements]);

  const [activeMenuId, setActiveMenuId] = useState<string | null>(null);
  const [editingAnnouncement, setEditingAnnouncement] = useState<Announcement | null>(null);
  const [deletingAnnouncement, setDeletingAnnouncement] = useState<Announcement | null>(null);

  // Close dropdown on outside click
  useEffect(() => {
    if (!activeMenuId) return;
    const handleOutsideClick = (e: MouseEvent) => {
      const target = e.target as HTMLElement | null;
      if (!target?.closest('.announcement-menu-wrap')) {
        setActiveMenuId(null);
      }
    };
    document.addEventListener('click', handleOutsideClick);
    return () => document.removeEventListener('click', handleOutsideClick);
  }, [activeMenuId]);

  // 1. Status Filter: 'active' | 'completed' | 'all' (Flutter: statusFilter)
  const [filter, setFilter] = useState<'active' | 'completed' | 'all'>('active');
  // 2. Type Filter: null | 'TODO' | 'EVENT' | 'INFO' | 'HINT' (Flutter: selectedType)
  const [selectedType, setSelectedType] = useState<AnnouncementType | null>(null);
  // トランスクリプト表示中の対象。モーダルは閉じずに、この状態がある間だけ
  // ModalDialogのsidePanelとして左側にTranscriptSheetを被せる。
  const [transcriptTarget, setTranscriptTarget] = useState<{ lectureId: string; sids: string[] } | null>(
    null
  );

  const activeCount = useMemo(() => localAnnouncements.filter((a) => !a.completed_at).length, [localAnnouncements]);
  const completedCount = useMemo(() => localAnnouncements.filter((a) => Boolean(a.completed_at)).length, [localAnnouncements]);
  const lectureTitleMap = useMemo(() => new Map(lectures?.map((l) => [l.id, l.title]) ?? []), [lectures]);

  const filtered = localAnnouncements.filter((a) => {
    if (filter === 'active' && a.completed_at) return false;
    if (filter === 'completed' && !a.completed_at) return false;
    if (selectedType && a.type.toUpperCase() !== selectedType.toUpperCase()) return false;
    return true;
  });

  /** タップ時の遷移: レクチャーページ由来ならトランスクリプトの該当範囲、
   *  それ以外(Home/CourseDetail)なら講義ページそのものへ。
   *  Flutter版と同様、完了済みの項目はタップ遷移を無効化する。 */
  const handleCardActivate = (item: Announcement) => {
    if (item.completed_at) return;
    if (enableTranscriptView) {
      if (item.start_sid && item.end_sid) {
        setTranscriptTarget({ lectureId: item.lecture_id, sids: expandSidRange(item.start_sid, item.end_sid) });
      }
      return;
    }
    if (item.lecture_id) navigate(`/lectures/${item.lecture_id}`);
  };

  const handleToggleDone = async (item: Announcement) => {
    const isCompleted = Boolean(item.completed_at);
    const nextCompleted = !isCompleted;
    try {
      await toggleAnnouncementCompleted(item.id, nextCompleted);
      const updated: Announcement = {
        ...item,
        completed_at: nextCompleted ? new Date().toISOString() : null,
      };
      setLocalAnnouncements((prev) => prev.map((a) => (a.id === updated.id ? updated : a)));
      onAnnouncementToggled?.(updated);
    } catch (err) {
      console.error('Failed to toggle announcement completion:', err);
    }
  };

  const handleAnnouncementUpdated = (updated: Announcement) => {
    setLocalAnnouncements((prev) => prev.map((a) => (a.id === updated.id ? updated : a)));
    onAnnouncementUpdated?.(updated);
    setEditingAnnouncement(null);
  };

  const handleConfirmDelete = async () => {
    if (!deletingAnnouncement) return;
    const id = deletingAnnouncement.id;
    try {
      await deleteAnnouncement(id);
      setLocalAnnouncements((prev) => prev.filter((a) => a.id !== id));
      onAnnouncementDeleted?.(id);
      setDeletingAnnouncement(null);
    } catch (err) {
      console.error('Failed to delete announcement:', err);
    }
  };

  return (
    <>
      <ModalDialog
        title={title}
        count={localAnnouncements.length}
        onClose={onClose}
      maxWidth={720}
      sidePanel={
        transcriptTarget ? (
          <TranscriptSheet
            lectureId={transcriptTarget.lectureId}
            sids={transcriptTarget.sids}
            onClose={() => setTranscriptTarget(null)}
          />
        ) : undefined
      }
    >
      {/* ── 1. Status Filter (Flutter _SegmentItem Segment Bar) ── */}
      <div className="announcements-segment-bar">
        <button
          type="button"
          className={`announcements-segment-tab ${filter === 'active' ? 'is-selected' : ''}`}
          onClick={() => setFilter('active')}
        >
          {t('announcementsActive', { count: activeCount })}
        </button>
        <button
          type="button"
          className={`announcements-segment-tab ${filter === 'completed' ? 'is-selected' : ''}`}
          onClick={() => setFilter('completed')}
        >
          {t('announcementsCompleted', { count: completedCount })}
        </button>
        <button
          type="button"
          className={`announcements-segment-tab ${filter === 'all' ? 'is-selected' : ''}`}
          onClick={() => setFilter('all')}
        >
          {t('announcementsAll', { count: announcements.length })}
        </button>
      </div>

      {/* ── 2. Type Filter Chips (Flutter _TypeChip Row) ── */}
      <div className="announcements-type-chips-row">
        <button
          type="button"
          className={`announcement-type-chip ${selectedType === null ? 'is-selected' : ''}`}
          onClick={() => setSelectedType(null)}
          style={{ '--chip-color': '#FFB300' } as React.CSSProperties}
        >
          <span className="material-symbols-outlined type-chip-icon">apps</span>
          <span>{t('announcementsAllTab')}</span>
        </button>

        {(['TODO', 'EVENT', 'INFO', 'HINT'] as const).map((tType) => {
          const cfg = getAnnouncementTypeConfig(tType);
          const isSelected = selectedType === tType;
          return (
            <button
              key={tType}
              type="button"
              className={`announcement-type-chip ${isSelected ? 'is-selected' : ''}`}
              onClick={() => setSelectedType(isSelected ? null : tType)}
              style={{ '--chip-color': cfg.color } as React.CSSProperties}
            >
              <span className="material-symbols-outlined type-chip-icon">{cfg.icon}</span>
              <span>{cfg.label}</span>
            </button>
          );
        })}
      </div>

      {/* ── 3. Announcement List ── */}
      {filtered.length === 0 ? (
        <div className="modal-empty-state">
          <p>{t('announcementsEmpty')}</p>
        </div>
      ) : (
        <div className="modal-item-list">
          {filtered.map((item) => {
            const isCompleted = Boolean(item.completed_at);
            const typeConfig = getAnnouncementTypeConfig(item.type);
            const lectureTitle = item.lecture_id ? lectureTitleMap.get(item.lecture_id) : null;
            const formattedDate = formatAnnouncementDate(item.created_at, locale);
            const hasTranscript = Boolean(item.start_sid && item.end_sid);
            const isActivatable =
              !isCompleted && (enableTranscriptView ? hasTranscript : Boolean(item.lecture_id));

            return (
              <div
                key={item.id}
                className={`flutter-announcement-card ${isCompleted ? 'is-completed' : ''} ${
                  isActivatable ? 'is-activatable' : ''
                }`}
                role={isActivatable ? 'button' : undefined}
                tabIndex={isActivatable ? 0 : undefined}
                onClick={isActivatable ? () => handleCardActivate(item) : undefined}
                onKeyDown={
                  isActivatable
                    ? (e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault();
                          handleCardActivate(item);
                        }
                      }
                    : undefined
                }
              >
                {/* Left: Type Icon (Colored Badge) */}
                <div
                  className="announcement-leading-icon"
                  style={{
                    color: typeConfig.color,
                    backgroundColor: typeConfig.bg,
                    border: `1px solid ${typeConfig.color}44`,
                    opacity: isCompleted ? 0.65 : 1,
                  }}
                >
                  <span className="material-symbols-outlined">
                    {typeConfig.icon}
                  </span>
                </div>

                {/* Middle: Content */}
                <div className="announcement-content-area">
                  {(lectureTitle || item.related_topic_title) && (
                    <div className="announcement-header-tags">
                      {lectureTitle && (
                        <span className="announcement-lecture-tag" title={lectureTitle}>
                          {lectureTitle}
                        </span>
                      )}
                      {item.related_topic_title && (
                        <span className="announcement-topic-tag">{item.related_topic_title}</span>
                      )}
                    </div>
                  )}

                  <h3 className={`announcement-tile-title ${isCompleted ? 'is-line-through' : ''}`}>
                    {item.title || t('announcementDefaultTitle')}
                  </h3>

                  {item.description && (
                    <p className={`announcement-tile-desc ${isCompleted ? 'is-line-through' : ''}`}>
                      {item.description}
                    </p>
                  )}

                  {/* Meta / Timestamp row */}
                  <div className="announcement-meta-subrow">
                    {item.location && (
                      <span className="announcement-location-info">
                        <span className="material-symbols-outlined location-mini-icon">location_on</span>
                        <span>{item.location}</span>
                      </span>
                    )}
                    {formattedDate && (
                      <span className="announcement-date-info">{formattedDate}</span>
                    )}
                  </div>

                  {enableTranscriptView && hasTranscript && !isCompleted && (
                    <button
                      type="button"
                      className="announcement-transcript-btn"
                      onClick={(e) => {
                        e.stopPropagation();
                        handleCardActivate(item);
                      }}
                    >
                      <span className="material-symbols-outlined">receipt_long</span>
                      <span>{t('announcementsViewInTranscript')}</span>
                    </button>
                  )}
                </div>

                {/* Right: Square Checkmark Button & 3-dots Menu */}
                <div className="announcement-action-area">
                  <button
                    type="button"
                    className={`announcement-square-check ${isCompleted ? 'is-completed' : ''}`}
                    onClick={(e) => {
                      e.stopPropagation();
                      handleToggleDone(item);
                    }}
                    title={
                      isCompleted
                        ? t('announcementsMarkActive')
                        : t('announcementsMarkCompleted')
                    }
                    aria-label={isCompleted ? 'Mark uncompleted' : 'Mark completed'}
                  >
                    <svg
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      className="square-check-svg"
                    >
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  </button>

                  {/* Three-dots Menu */}
                  <div
                    className="course-card-menu-wrap announcement-menu-wrap"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <button
                      type="button"
                      className={`course-card-menu-btn announcement-menu-btn ${activeMenuId === item.id ? 'is-active' : ''}`}
                      onClick={(e) => {
                        e.stopPropagation();
                        e.preventDefault();
                        setActiveMenuId((prev) => (prev === item.id ? null : item.id));
                      }}
                      aria-label="Announcement options"
                      aria-expanded={activeMenuId === item.id}
                    >
                      <MoreVertical size={16} />
                    </button>

                    {activeMenuId === item.id && (
                      <div className="course-card-dropdown announcement-dropdown">
                        <button
                          type="button"
                          className="course-dropdown-item"
                          onClick={(e) => {
                            e.stopPropagation();
                            e.preventDefault();
                            setActiveMenuId(null);
                            handleToggleDone(item);
                          }}
                        >
                          <span className="material-symbols-outlined" style={{ fontSize: 16 }}>
                            {isCompleted ? 'undo' : 'check_circle'}
                          </span>
                          <span>{isCompleted ? t('announcementsMarkActive') : t('announcementsMarkCompleted')}</span>
                        </button>

                        <button
                          type="button"
                          className="course-dropdown-item"
                          onClick={(e) => {
                            e.stopPropagation();
                            e.preventDefault();
                            setActiveMenuId(null);
                            setEditingAnnouncement(item);
                          }}
                        >
                          <Pencil size={14} />
                          <span>{t('edit')}</span>
                        </button>

                        <button
                          type="button"
                          className="course-dropdown-item is-delete"
                          onClick={(e) => {
                            e.stopPropagation();
                            e.preventDefault();
                            setActiveMenuId(null);
                            setDeletingAnnouncement(item);
                          }}
                        >
                          <Trash2 size={14} />
                          <span>{t('delete')}</span>
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </ModalDialog>

    {editingAnnouncement && (
      <AnnouncementEditModal
        announcement={editingAnnouncement}
        onClose={() => setEditingAnnouncement(null)}
        onAnnouncementUpdated={handleAnnouncementUpdated}
      />
    )}

    {deletingAnnouncement && (
      <ConfirmModal
        open={Boolean(deletingAnnouncement)}
        onClose={() => setDeletingAnnouncement(null)}
        onConfirm={handleConfirmDelete}
        title={t('announcementDeleteTitle')}
        message={t('announcementDeleteMessage').replace(
          '{title}',
          deletingAnnouncement.title?.trim() || t('announcementDefaultTitle')
        )}
        confirmLabel={t('delete')}
        cancelLabel={t('cancel')}
        isDanger
      />
    )}
  </>
);
};
