import React, { useState, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import type { Announcement, AnnouncementType } from '../../types/content';
import type { Lecture } from '../../types/lecture';
import { toggleAnnouncementCompleted } from '../../lib/content';
import { expandSidRange } from '../../lib/sidCitation';
import { ModalDialog } from './ModalDialog';
import { TranscriptSheet } from '../transcript/TranscriptSheet';
import { useLanguage } from '../../i18n/LanguageContext';

export interface AnnouncementsModalProps {
  announcements: Announcement[];
  lectures?: Lecture[];
  onClose: () => void;
  onAnnouncementToggled?: (updated: Announcement) => void;
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

function formatAnnouncementDate(iso: string | null | undefined, lang: string): string {
  if (!iso) return '';
  try {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleDateString(lang === 'ja' ? 'ja-JP' : 'en-US', {
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
  enableTranscriptView,
}) => {
  const { language } = useLanguage();
  const navigate = useNavigate();
  const title = language === 'ja' ? 'お知らせ' : 'Announcements';

  // 1. Status Filter: 'active' | 'completed' | 'all' (Flutter: statusFilter)
  const [filter, setFilter] = useState<'active' | 'completed' | 'all'>('active');
  // 2. Type Filter: null | 'TODO' | 'EVENT' | 'INFO' | 'HINT' (Flutter: selectedType)
  const [selectedType, setSelectedType] = useState<AnnouncementType | null>(null);
  // トランスクリプト表示中の対象。モーダルは閉じずに、この状態がある間だけ
  // ModalDialogのsidePanelとして左側にTranscriptSheetを被せる。
  const [transcriptTarget, setTranscriptTarget] = useState<{ lectureId: string; sids: string[] } | null>(
    null
  );

  const activeCount = useMemo(() => announcements.filter((a) => !a.completed_at).length, [announcements]);
  const completedCount = useMemo(() => announcements.filter((a) => Boolean(a.completed_at)).length, [announcements]);
  const lectureTitleMap = useMemo(() => new Map(lectures?.map((l) => [l.id, l.title]) ?? []), [lectures]);

  const filtered = announcements.filter((a) => {
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
      onAnnouncementToggled?.(updated);
    } catch (err) {
      console.error('Failed to toggle announcement completion:', err);
    }
  };

  return (
    <ModalDialog
      title={title}
      count={announcements.length}
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
          {language === 'ja' ? `未完了 (${activeCount})` : `Active (${activeCount})`}
        </button>
        <button
          type="button"
          className={`announcements-segment-tab ${filter === 'completed' ? 'is-selected' : ''}`}
          onClick={() => setFilter('completed')}
        >
          {language === 'ja' ? `完了済み (${completedCount})` : `Completed (${completedCount})`}
        </button>
        <button
          type="button"
          className={`announcements-segment-tab ${filter === 'all' ? 'is-selected' : ''}`}
          onClick={() => setFilter('all')}
        >
          {language === 'ja' ? `すべて (${announcements.length})` : `All (${announcements.length})`}
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
          <span>{language === 'ja' ? 'すべて' : 'All'}</span>
        </button>

        {(['TODO', 'EVENT', 'INFO', 'HINT'] as const).map((t) => {
          const cfg = getAnnouncementTypeConfig(t);
          const isSelected = selectedType === t;
          return (
            <button
              key={t}
              type="button"
              className={`announcement-type-chip ${isSelected ? 'is-selected' : ''}`}
              onClick={() => setSelectedType(isSelected ? null : t)}
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
          <p>{language === 'ja' ? '該当するお知らせはありません' : 'No announcements in this view'}</p>
        </div>
      ) : (
        <div className="modal-item-list">
          {filtered.map((item) => {
            const isCompleted = Boolean(item.completed_at);
            const typeConfig = getAnnouncementTypeConfig(item.type);
            const lectureTitle = item.lecture_id ? lectureTitleMap.get(item.lecture_id) : null;
            const formattedDate = formatAnnouncementDate(item.created_at, language);
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
                    {item.title || (language === 'ja' ? 'お知らせ' : 'Announcement')}
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
                      <span>{language === 'ja' ? 'トランスクリプトで確認' : 'View in transcript'}</span>
                    </button>
                  )}
                </div>

                {/* Right: Square Checkmark Button (Done / Undo) */}
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
                        ? language === 'ja'
                          ? 'クリックして未完了に戻す'
                          : 'Click to mark as active'
                        : language === 'ja'
                        ? 'クリックして完了にする'
                        : 'Click to mark as completed'
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
                </div>
              </div>
            );
          })}
        </div>
      )}
    </ModalDialog>
  );
};
