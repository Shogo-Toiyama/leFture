import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import {
  ArrowLeft,
  Bookmark,
  Heart,
  ThumbsDown,
  Megaphone,
  Trash2,
  Inbox,
  RotateCcw,
  BookOpen,
  FileText,
  Tag,
  Sparkles,
  GraduationCap,
  Mic,
  CheckCircle2,
  Circle,
  AlertCircle,
  Loader2,
  Info,
} from 'lucide-react';
import { ConfirmModal } from '../../components/modals/ConfirmModal';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import {
  fetchActivityRecords,
  toggleSaveRecord,
  updateReactionRecord,
  toggleAnnouncementComplete,
  softDeleteAnnouncement,
  restoreTrashRecord,
  deleteTrashRecordPermanently,
  emptyTrashRecords,
  type ActivityRecord,
  type ActivityType,
} from '../../lib/activity';

interface ActivityMeta {
  title: string;
  subtitle: string;
  icon: React.ReactNode;
  iconColor: string;
  iconBg: string;
  filters: { label: string; value: string }[];
}

const getActivityMeta = (type: string, t: (k: TranslationKey) => string): ActivityMeta => {
  const map: Record<string, ActivityMeta> = {
    saved: {
      title: t('activitySavedTitle'),
      subtitle: t('activitySavedSubtitle'),
      icon: <Bookmark size={22} />,
      iconColor: 'var(--star-gold, #fbc02d)',
      iconBg: 'rgba(251, 192, 45, 0.15)',
      filters: [
        { label: t('filterAll'), value: 'all' },
        { label: t('filterReviewCard'), value: 'reviewCard' },
        { label: t('filterDeepNote'), value: 'deepNote' },
        { label: t('filterKeyword'), value: 'keyword' },
      ],
    },
    likes: {
      title: t('activityLikesTitle'),
      subtitle: t('activityLikesSubtitle'),
      icon: <Heart size={22} />,
      iconColor: 'var(--correction-red, #ff5252)',
      iconBg: 'rgba(229, 57, 53, 0.15)',
      filters: [
        { label: t('filterAll'), value: 'all' },
        { label: t('filterReviewCard'), value: 'reviewCard' },
        { label: t('filterDeepNote'), value: 'deepNote' },
        { label: t('filterFunFact'), value: 'funFact' },
      ],
    },
    dislikes: {
      title: t('activityDislikesTitle'),
      subtitle: t('activityDislikesSubtitle'),
      icon: <ThumbsDown size={22} />,
      iconColor: '#2196f3',
      iconBg: 'rgba(33, 150, 243, 0.15)',
      filters: [
        { label: t('filterAll'), value: 'all' },
        { label: t('filterReviewCard'), value: 'reviewCard' },
        { label: t('filterDeepNote'), value: 'deepNote' },
        { label: t('filterFunFact'), value: 'funFact' },
      ],
    },
    announcements: {
      title: t('activityAnnouncementsTitle'),
      subtitle: t('activityAnnouncementsSubtitle'),
      icon: <Megaphone size={22} />,
      iconColor: '#ba68c8',
      iconBg: 'rgba(186, 104, 200, 0.15)',
      filters: [
        { label: t('filterAll'), value: 'all' },
        { label: t('filterActive'), value: 'active' },
        { label: t('filterCompleted'), value: 'completed' },
      ],
    },
    trash: {
      title: t('activityTrashTitle'),
      subtitle: t('activityTrashSubtitle'),
      icon: <Trash2 size={22} />,
      iconColor: 'var(--correction-red, #ff5252)',
      iconBg: 'rgba(229, 57, 53, 0.15)',
      filters: [
        { label: t('filterAll'), value: 'all' },
        { label: t('filterCourse'), value: 'course' },
        { label: t('filterLecture'), value: 'lecture' },
        { label: t('filterAnnouncement'), value: 'announcement' },
      ],
    },
  };

  return map[type] || map.saved;
};

const VALID_TYPES = new Set(['saved', 'likes', 'dislikes', 'announcements', 'trash']);

const ANNOUNCEMENT_TYPES = [
  { value: 'todo', label: 'TODO', color: '#ff9800' },
  { value: 'event', label: 'EVENT', color: '#2196f3' },
  { value: 'info', label: 'INFO', color: '#4caf50' },
  { value: 'hint', label: 'HINT', color: '#ba68c8' },
];

export const ActivityRecordsPlaceholderPage: React.FC = () => {
  const { t, formatDate } = useLanguage();
  const { type = 'saved' } = useParams<{ type: string }>();
  const activityType = (VALID_TYPES.has(type) ? type : 'saved') as ActivityType;
  const meta = useMemo(() => getActivityMeta(activityType, t), [activityType, t]);
  const navigate = useNavigate();

  const [rawRecords, setRawRecords] = useState<ActivityRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Filters
  const [activeFilter, setActiveFilter] = useState('all');
  const [selectedAnnouncementType, setSelectedAnnouncementType] = useState<string | null>(null);

  // State for toggled/removed items
  const [pendingOverrides, setPendingOverrides] = useState<Record<string, ActivityRecord>>({});
  const [removedRecordIds, setRemovedRecordIds] = useState<Set<string>>(new Set());
  const [deletingRecordIds, setDeletingRecordIds] = useState<Set<string>>(new Set());

  // Modals
  const [emptyTrashModalOpen, setEmptyTrashModalOpen] = useState(false);
  const [singleDeleteRecord, setSingleDeleteRecord] = useState<ActivityRecord | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const showToast = useCallback((msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 3500);
  }, []);

  // Fetch live records from Supabase
  const loadRecords = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchActivityRecords(activityType, t);
      setRawRecords(data);
      setPendingOverrides({});
      setRemovedRecordIds(new Set());
    } catch (err: unknown) {
      console.error('Failed to load activity records:', err);
      setError(err instanceof Error ? err.message : t('loadActivityFailed'));
    } finally {
      setLoading(false);
    }
  }, [activityType, t]);

  useEffect(() => {
    loadRecords();
    setActiveFilter('all');
    setSelectedAnnouncementType(null);
  }, [loadRecords]);

  // Merge live records with pending overrides
  const mergedRecords = useMemo(() => {
    const freshIds = new Set(rawRecords.map((r) => r.id));
    const overlay = Object.values(pendingOverrides).filter((r) => !freshIds.has(r.id));
    const combined = [...rawRecords, ...overlay].filter((r) => !removedRecordIds.has(r.id));
    combined.sort((a, b) => new Date(b.dateTime).getTime() - new Date(a.dateTime).getTime());
    return combined;
  }, [rawRecords, pendingOverrides, removedRecordIds]);

  // Filter records
  const filteredRecords = useMemo(() => {
    return mergedRecords.filter((r) => {
      // Announcements filter logic
      if (activityType === 'announcements') {
        const isCompleted = Boolean(r.completedAt);
        if (activeFilter === 'active' && isCompleted) return false;
        if (activeFilter === 'completed' && !isCompleted) return false;
        if (selectedAnnouncementType && r.announcementType !== selectedAnnouncementType) {
          return false;
        }
        return true;
      }

      // Trash filter logic
      if (activityType === 'trash') {
        if (activeFilter === 'all') return true;
        return r.type === activeFilter;
      }

      // Saved / Likes / Dislikes filter logic
      if (activeFilter === 'all') return true;
      return r.type === activeFilter;
    });
  }, [mergedRecords, activityType, activeFilter, selectedAnnouncementType]);

  // Card click navigation
  const handleCardClick = (r: ActivityRecord) => {
    if (activityType === 'trash') return;

    if (r.type === 'reviewCard' && r.lectureId) {
      navigate(`/lectures/${r.lectureId}/review-cards`);
    } else if (r.type === 'deepNote' && r.lectureId) {
      navigate(`/lectures/${r.lectureId}/deep-notes`);
    } else if (r.type === 'course' && r.courseId) {
      navigate(`/courses/${r.courseId}`);
    } else if (r.lectureId) {
      navigate(`/lectures/${r.lectureId}`);
    }
  };

  // Toggle Save
  const handleToggleSave = async (record: ActivityRecord, e: React.MouseEvent) => {
    e.stopPropagation();
    const isPending = Boolean(pendingOverrides[record.id]);
    const nextOverrides = { ...pendingOverrides };

    if (isPending) {
      delete nextOverrides[record.id];
      setPendingOverrides(nextOverrides);
      try {
        await toggleSaveRecord(record, true);
        showToast(t('toastItemSavedAgain'));
      } catch (err) {
        console.error(err);
      }
    } else {
      nextOverrides[record.id] = record;
      setPendingOverrides(nextOverrides);
      try {
        await toggleSaveRecord(record, false);
        showToast(t('toastItemRemovedFromSaved'));
      } catch (err) {
        console.error(err);
      }
    }
  };

  // Toggle Reaction (Like / Dislike)
  const handleToggleReaction = async (record: ActivityRecord, e: React.MouseEvent) => {
    e.stopPropagation();
    const isPending = Boolean(pendingOverrides[record.id]);
    const nextOverrides = { ...pendingOverrides };
    const reaction = activityType === 'likes' ? 'like' : 'dislike';
    const reactionLabel = reaction === 'like' ? t('reactionLike') : t('reactionDislike');

    if (isPending) {
      delete nextOverrides[record.id];
      setPendingOverrides(nextOverrides);
      try {
        await updateReactionRecord(record, reaction);
        showToast(t('toastItemReactionRestored').replace('{reaction}', reactionLabel));
      } catch (err) {
        console.error(err);
      }
    } else {
      nextOverrides[record.id] = record;
      setPendingOverrides(nextOverrides);
      try {
        await updateReactionRecord(record, null);
        showToast(t('toastItemReactionRemoved').replace('{reaction}', reactionLabel));
      } catch (err) {
        console.error(err);
      }
    }
  };

  // Toggle Announcement completion
  const handleToggleAnnouncement = async (record: ActivityRecord, e: React.MouseEvent) => {
    e.stopPropagation();
    const isCompleted = Boolean(record.completedAt);
    const nextCompletedAt = isCompleted ? null : new Date().toISOString();

    setRawRecords((prev) =>
      prev.map((r) => (r.id === record.id ? { ...r, completedAt: nextCompletedAt } : r))
    );

    try {
      await toggleAnnouncementComplete(record.id, !isCompleted);
    } catch (err) {
      console.error(err);
      // revert on error
      setRawRecords((prev) =>
        prev.map((r) => (r.id === record.id ? { ...r, completedAt: record.completedAt } : r))
      );
    }
  };

  // Soft delete announcement
  const handleDeleteAnnouncement = async (record: ActivityRecord, e: React.MouseEvent) => {
    e.stopPropagation();
    setRemovedRecordIds((prev) => new Set(prev).add(record.id));
    try {
      await softDeleteAnnouncement(record.id);
      showToast(t('toastAnnouncementMovedToTrash'));
    } catch (err) {
      console.error(err);
      setRemovedRecordIds((prev) => {
        const next = new Set(prev);
        next.delete(record.id);
        return next;
      });
    }
  };

  // Restore trash item
  const handleRestoreItem = async (record: ActivityRecord, e: React.MouseEvent) => {
    e.stopPropagation();
    setRemovedRecordIds((prev) => new Set(prev).add(record.id));
    try {
      await restoreTrashRecord(record);
      showToast(t('toastRecordRestored').replace('{title}', record.title));
    } catch (err) {
      console.error(err);
      setRemovedRecordIds((prev) => {
        const next = new Set(prev);
        next.delete(record.id);
        return next;
      });
      showToast(t('toastRecordRestoreFailed'));
    }
  };

  // Confirm single item permanent delete
  const handleConfirmSingleDelete = async () => {
    if (!singleDeleteRecord) return;
    const item = singleDeleteRecord;
    setDeletingRecordIds((prev) => new Set(prev).add(item.id));
    setSingleDeleteRecord(null);

    try {
      await deleteTrashRecordPermanently(item);
      setRemovedRecordIds((prev) => new Set(prev).add(item.id));
      showToast(t('toastRecordPermanentlyDeleted').replace('{title}', item.title));
    } catch (err) {
      console.error(err);
      showToast(t('toastRecordPermanentDeleteFailed'));
    } finally {
      setDeletingRecordIds((prev) => {
        const next = new Set(prev);
        next.delete(item.id);
        return next;
      });
    }
  };

  // Confirm empty trash
  const handleConfirmEmptyTrash = async () => {
    const trashItems = mergedRecords;
    setEmptyTrashModalOpen(false);
    setLoading(true);

    try {
      await emptyTrashRecords(trashItems);
      setRawRecords([]);
      setPendingOverrides({});
      showToast(t('toastTrashEmptied'));
    } catch (err) {
      console.error(err);
      showToast(t('toastTrashEmptyFailed'));
    } finally {
      setLoading(false);
    }
  };

  // Render Type Icon & Badge
  const getTypeBadge = (record: ActivityRecord) => {
    switch (record.type) {
      case 'reviewCard':
        return (
          <span className="activity-type-badge">
            <BookOpen size={11} />
            {t('badgeReviewCard')}
          </span>
        );
      case 'deepNote':
        return (
          <span className="activity-type-badge">
            <FileText size={11} />
            {t('badgeDeepNote')}
          </span>
        );
      case 'keyword':
        return (
          <span className="activity-type-badge">
            <Tag size={11} />
            {t('badgeKeyword')}
          </span>
        );
      case 'funFact':
        return (
          <span className="activity-type-badge">
            <Sparkles size={11} />
            {t('badgeFunFact')}
          </span>
        );
      case 'announcement': {
        const badgeClass = `badge-${record.announcementType || 'info'}`;
        return (
          <span className={`activity-type-badge ${badgeClass}`}>
            <Megaphone size={11} />
            {record.announcementType?.toUpperCase() || t('announcementBadgeDefault')}
          </span>
        );
      }
      case 'course':
        return (
          <span className="activity-type-badge">
            <GraduationCap size={11} />
            {t('badgeCourse')}
          </span>
        );
      case 'lecture':
        return (
          <span className="activity-type-badge">
            <Mic size={11} />
            {t('badgeLecture')}
          </span>
        );
      default:
        return null;
    }
  };

  const getTrashIcon = (record: ActivityRecord) => {
    if (record.type === 'course') return <GraduationCap size={20} />;
    if (record.type === 'lecture') return <Mic size={20} />;
    return <Megaphone size={20} />;
  };

  return (
    <div className="account-page">
      {/* ── Top Header ─────────────────────────────────────────── */}
      <div className="profile-detail-top-nav">
        <Link to="/account" className="back-link" style={{ margin: 0 }}>
          <ArrowLeft size={18} />
          <span>{t('account')}</span>
        </Link>
        {activityType === 'trash' && mergedRecords.length > 0 && (
          <button
            type="button"
            className="btn btn-ghost"
            style={{
              color: 'var(--correction-red, #ff5252)',
              fontSize: '0.85rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.4rem',
            }}
            onClick={() => setEmptyTrashModalOpen(true)}
          >
            <Trash2 size={16} />
            {t('emptyTrashButton')}
          </button>
        )}
      </div>

      {/* ── Hero Banner ─────────────────────────────────────────── */}
      <div className="activity-page-hero">
        <div
          className="activity-page-hero-icon"
          style={{ background: meta.iconBg, color: meta.iconColor }}
        >
          {meta.icon}
        </div>
        <div>
          <h1 style={{ margin: 0, fontSize: '1.75rem', fontWeight: 700 }}>{meta.title}</h1>
          <p className="muted" style={{ margin: '0.2rem 0 0', fontSize: '0.9rem' }}>
            {meta.subtitle}
          </p>
        </div>
      </div>

      {/* ── Trash 30-day retention banner ───────────────────────── */}
      {activityType === 'trash' && (
        <div className="activity-trash-banner">
          <Info size={18} className="activity-trash-banner-icon" />
          <div>{t('trashRetentionBanner')}</div>
        </div>
      )}

      {/* ── Filter Pills ───────────────────────────────────────── */}
      <div className="activity-filter-bar">
        {meta.filters.map((f) => (
          <button
            key={f.value}
            type="button"
            className={`activity-filter-pill ${activeFilter === f.value ? 'is-active' : ''}`}
            onClick={() => setActiveFilter(f.value)}
          >
            {f.label}
          </button>
        ))}
      </div>

      {/* ── Announcement Type Sub-filters ──────────────────────── */}
      {activityType === 'announcements' && (
        <div className="activity-filter-bar" style={{ marginTop: '0.25rem' }}>
          <button
            type="button"
            className={`activity-filter-pill ${selectedAnnouncementType === null ? 'is-active' : ''}`}
            onClick={() => setSelectedAnnouncementType(null)}
          >
            {t('allTypes')}
          </button>
          {ANNOUNCEMENT_TYPES.map((t) => (
            <button
              key={t.value}
              type="button"
              className={`activity-filter-pill ${selectedAnnouncementType === t.value ? 'is-active' : ''}`}
              style={
                selectedAnnouncementType === t.value
                  ? { background: t.color, borderColor: t.color, color: '#fff' }
                  : {}
              }
              onClick={() => setSelectedAnnouncementType(t.value)}
            >
              {t.label}
            </button>
          ))}
        </div>
      )}

      {/* ── Items Found Count ──────────────────────────────────── */}
      {!loading && !error && (
        <div style={{ margin: '0.75rem 0 0.25rem', fontSize: '0.84rem', color: 'var(--comet)' }}>
          {t('itemsFound').replace('{count}', String(filteredRecords.length))}
        </div>
      )}

      {/* ── Content / List Area ─────────────────────────────────── */}
      {loading ? (
        <div className="glass-card activity-empty-box" style={{ marginTop: '1.25rem' }}>
          <Loader2 size={32} className="spin" style={{ color: 'var(--star-gold, #fbc02d)' }} />
          <p className="muted" style={{ marginTop: '1rem', fontSize: '0.9rem' }}>
            {t('loadingRecords')}
          </p>
        </div>
      ) : error ? (
        <div className="glass-card activity-empty-box" style={{ marginTop: '1.25rem' }}>
          <AlertCircle size={36} style={{ color: 'var(--correction-red, #ff5252)' }} />
          <h3 style={{ margin: '0.75rem 0 0.25rem' }}>{t('loadActivityFailed')}</h3>
          <p className="muted" style={{ margin: 0, fontSize: '0.88rem', maxWidth: '360px' }}>
            {error}
          </p>
          <button
            type="button"
            className="btn btn-ghost"
            style={{ marginTop: '1rem' }}
            onClick={loadRecords}
          >
            {t('retry')}
          </button>
        </div>
      ) : filteredRecords.length === 0 ? (
        <div className="glass-card activity-empty-box" style={{ marginTop: '1.25rem' }}>
          <Inbox size={40} className="activity-empty-icon" />
          <h3 style={{ margin: '0.5rem 0 0.25rem' }}>{t('noItemsFound')}</h3>
          <p
            className="muted"
            style={{ margin: 0, fontSize: '0.88rem', maxWidth: '320px', textAlign: 'center' }}
          >
            {activityType === 'trash'
              ? t('trashEmptyNotice')
              : t('noMatchingFilterItems').replace('{filter}', activeFilter)}
          </p>
        </div>
      ) : (
        <div className="activity-list">
          {filteredRecords.map((record) => {
            const isPending = Boolean(pendingOverrides[record.id]);
            const isDeleting = deletingRecordIds.has(record.id);

            // 1. Trash Card
            if (activityType === 'trash') {
              return (
                <div
                  key={record.id}
                  className="activity-card"
                  style={{ opacity: isDeleting ? 0.4 : 1 }}
                >
                  <div className="activity-card-left-icon">{getTrashIcon(record)}</div>
                  <div className="activity-card-body">
                    <div className="activity-card-header">
                      {getTypeBadge(record)}
                      <h3 className="activity-card-title">{record.title}</h3>
                    </div>
                    <div className="activity-card-meta">
                      <span>{t('deletedOnDate').replace('{date}', formatDate(record.dateTime))}</span>
                    </div>
                  </div>
                  <div className="activity-card-actions">
                    <button
                      type="button"
                      className="activity-action-btn active-gold"
                      title={t('restoreItemAction')}
                      onClick={(e) => handleRestoreItem(record, e)}
                    >
                      <RotateCcw size={18} />
                    </button>
                    <button
                      type="button"
                      className="activity-action-btn active-red"
                      title={t('deletePermanentlyAction')}
                      onClick={(e) => {
                        e.stopPropagation();
                        setSingleDeleteRecord(record);
                      }}
                    >
                      <Trash2 size={18} />
                    </button>
                  </div>
                </div>
              );
            }

            // 2. Announcement Card
            if (activityType === 'announcements') {
              const isCompleted = Boolean(record.completedAt);
              return (
                <div
                  key={record.id}
                  className="activity-card activity-card-clickable"
                  onClick={() => handleCardClick(record)}
                >
                  <button
                    type="button"
                    className="activity-action-btn"
                    style={{ padding: 0, color: isCompleted ? '#4caf50' : 'var(--comet)' }}
                    onClick={(e) => handleToggleAnnouncement(record, e)}
                    title={isCompleted ? t('markActive') : t('markCompleted')}
                  >
                    {isCompleted ? <CheckCircle2 size={22} /> : <Circle size={22} />}
                  </button>
                  <div className="activity-card-body">
                    <div className="activity-card-header">
                      {getTypeBadge(record)}
                      <h3
                        className="activity-card-title"
                        style={isCompleted ? { textDecoration: 'line-through', opacity: 0.6 } : {}}
                      >
                        {record.title}
                      </h3>
                    </div>
                    {record.content && (
                      <p
                        className="activity-card-snippet"
                        style={isCompleted ? { opacity: 0.6 } : {}}
                      >
                        {record.content}
                      </p>
                    )}
                    <div className="activity-card-meta">
                      <span>{formatDate(record.dateTime)}</span>
                      {isCompleted && (
                        <span style={{ color: '#4caf50', fontWeight: 600 }}>{t('completedBadge')}</span>
                      )}
                    </div>
                  </div>
                  <div className="activity-card-actions">
                    <button
                      type="button"
                      className="activity-action-btn"
                      title={t('moveToTrashAction')}
                      onClick={(e) => handleDeleteAnnouncement(record, e)}
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                </div>
              );
            }

            // 3. Saved / Likes / Dislikes Cards
            const isSavedType = activityType === 'saved';
            const isLikesType = activityType === 'likes';
            const isDislikesType = activityType === 'dislikes';

            return (
              <div
                key={record.id}
                className="activity-card activity-card-clickable"
                onClick={() => handleCardClick(record)}
              >
                <div className="activity-card-body">
                  <div className="activity-card-header">
                    {getTypeBadge(record)}
                    <h3 className="activity-card-title">{record.title}</h3>
                  </div>
                  {record.content && (
                    <p className="activity-card-snippet">{record.content}</p>
                  )}
                  <div className="activity-card-meta">
                    <span>{formatDate(record.dateTime)}</span>
                  </div>
                </div>

                <div className="activity-card-actions">
                  {isPending ? (
                    <button
                      type="button"
                      className="activity-undo-chip"
                      onClick={(e) =>
                        isSavedType
                           ? handleToggleSave(record, e)
                          : handleToggleReaction(record, e)
                      }
                      title={t('undoAction')}
                    >
                      <RotateCcw size={13} />
                      {t('undoAction')}
                    </button>
                  ) : isSavedType ? (
                    <button
                      type="button"
                      className="activity-action-btn active-gold"
                      title={t('removeFromSavedAction')}
                      onClick={(e) => handleToggleSave(record, e)}
                    >
                      <Bookmark size={20} fill="currentColor" />
                    </button>
                  ) : isLikesType ? (
                    <button
                      type="button"
                      className="activity-action-btn active-red"
                      title={t('removeLikeAction')}
                      onClick={(e) => handleToggleReaction(record, e)}
                    >
                      <Heart size={20} fill="currentColor" />
                    </button>
                  ) : isDislikesType ? (
                    <button
                      type="button"
                      className="activity-action-btn active-blue"
                      title={t('removeDislikeAction')}
                      onClick={(e) => handleToggleReaction(record, e)}
                    >
                      <ThumbsDown size={20} fill="currentColor" />
                    </button>
                  ) : null}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ── Toast notification ─────────────────────────────────── */}
      {toastMessage && (
        <div
          style={{
            position: 'fixed',
            bottom: '24px',
            right: '24px',
            background: 'rgba(18, 20, 34, 0.95)',
            border: '1px solid var(--glass-border)',
            color: '#fff',
            padding: '0.75rem 1.25rem',
            borderRadius: '12px',
            boxShadow: '0 8px 32px rgba(0,0,0,0.5)',
            zIndex: 2000,
            fontSize: '0.88rem',
            fontWeight: 500,
            animation: 'sheet-fade-in 0.2s ease-out',
          }}
        >
          {toastMessage}
        </div>
      )}

      {/* ── Empty Trash Confirmation Modal ─────────────────────── */}
      <ConfirmModal
        open={emptyTrashModalOpen}
        onClose={() => setEmptyTrashModalOpen(false)}
        onConfirm={handleConfirmEmptyTrash}
        title={t('emptyTrashButton')}
        message={t('emptyTrashConfirmMessage')}
        confirmLabel={t('emptyTrashButton')}
        cancelLabel={t('cancel')}
        isDanger={true}
      />

      {/* ── Single Item Permanent Delete Confirmation Modal ────── */}
      <ConfirmModal
        open={Boolean(singleDeleteRecord)}
        onClose={() => setSingleDeleteRecord(null)}
        onConfirm={handleConfirmSingleDelete}
        title={t('singleDeleteConfirmTitle').replace('{title}', singleDeleteRecord?.title || t('itemLabel'))}
        message={t('singleDeleteConfirmMessage')}
        confirmLabel={t('deletePermanentlyAction')}
        cancelLabel={t('cancel')}
        isDanger={true}
      />
    </div>
  );
};
