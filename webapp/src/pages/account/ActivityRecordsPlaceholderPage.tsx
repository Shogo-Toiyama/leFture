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

const getActivityMeta = (type: string, isJa: boolean): ActivityMeta => {
  const map: Record<string, ActivityMeta> = {
    saved: {
      title: isJa ? '保存済み' : 'Saved',
      subtitle: isJa ? '復習カード · 詳細ノート · キーワード' : 'Review Cards · Deep Notes · Keywords',
      icon: <Bookmark size={22} />,
      iconColor: 'var(--star-gold, #fbc02d)',
      iconBg: 'rgba(251, 192, 45, 0.15)',
      filters: [
        { label: isJa ? 'すべて' : 'All', value: 'all' },
        { label: isJa ? '復習カード' : 'Review Cards', value: 'reviewCard' },
        { label: isJa ? '詳細ノート' : 'Deep Notes', value: 'deepNote' },
        { label: isJa ? 'キーワード' : 'Keywords', value: 'keyword' },
      ],
    },
    likes: {
      title: isJa ? '高評価' : 'Likes',
      subtitle: isJa ? '復習カード · 詳細ノート · 豆知識' : 'Review Cards · Deep Notes · Fun Facts',
      icon: <Heart size={22} />,
      iconColor: 'var(--correction-red, #ff5252)',
      iconBg: 'rgba(229, 57, 53, 0.15)',
      filters: [
        { label: isJa ? 'すべて' : 'All', value: 'all' },
        { label: isJa ? '復習カード' : 'Review Cards', value: 'reviewCard' },
        { label: isJa ? '詳細ノート' : 'Deep Notes', value: 'deepNote' },
        { label: isJa ? '豆知識' : 'Fun Facts', value: 'funFact' },
      ],
    },
    dislikes: {
      title: isJa ? '低評価' : 'Dislikes',
      subtitle: isJa ? '復習カード · 詳細ノート · 豆知識' : 'Review Cards · Deep Notes · Fun Facts',
      icon: <ThumbsDown size={22} />,
      iconColor: '#2196f3',
      iconBg: 'rgba(33, 150, 243, 0.15)',
      filters: [
        { label: isJa ? 'すべて' : 'All', value: 'all' },
        { label: isJa ? '復習カード' : 'Review Cards', value: 'reviewCard' },
        { label: isJa ? '詳細ノート' : 'Deep Notes', value: 'deepNote' },
        { label: isJa ? '豆知識' : 'Fun Facts', value: 'funFact' },
      ],
    },
    announcements: {
      title: isJa ? 'お知らせ' : 'Announcements',
      subtitle: isJa ? '完了した項目を含む' : 'Including completed items',
      icon: <Megaphone size={22} />,
      iconColor: '#ba68c8',
      iconBg: 'rgba(186, 104, 200, 0.15)',
      filters: [
        { label: isJa ? 'すべて' : 'All', value: 'all' },
        { label: isJa ? '未完了' : 'Active', value: 'active' },
        { label: isJa ? '完了済み' : 'Completed', value: 'completed' },
      ],
    },
    trash: {
      title: isJa ? 'ゴミ箱' : 'Trash',
      subtitle: isJa ? 'ゴミ箱の項目は30日後に完全に削除されます' : 'Items in trash will be permanently deleted after 30 days',
      icon: <Trash2 size={22} />,
      iconColor: 'var(--correction-red, #ff5252)',
      iconBg: 'rgba(229, 57, 53, 0.15)',
      filters: [
        { label: isJa ? 'すべて' : 'All', value: 'all' },
        { label: isJa ? 'コース' : 'Courses', value: 'course' },
        { label: isJa ? '講義' : 'Lectures', value: 'lecture' },
        { label: isJa ? 'お知らせ' : 'Announcements', value: 'announcement' },
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
  const { language } = useLanguage();
  const isJa = language === 'ja';
  const { type = 'saved' } = useParams<{ type: string }>();
  const activityType = (VALID_TYPES.has(type) ? type : 'saved') as ActivityType;
  const meta = useMemo(() => getActivityMeta(activityType, isJa), [activityType, isJa]);
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
      const data = await fetchActivityRecords(activityType);
      setRawRecords(data);
      setPendingOverrides({});
      setRemovedRecordIds(new Set());
    } catch (err: unknown) {
      console.error('Failed to load activity records:', err);
      setError(err instanceof Error ? err.message : 'Failed to load records from cloud');
    } finally {
      setLoading(false);
    }
  }, [activityType]);

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

  // Format date helper
  const formatDate = (isoString: string) => {
    try {
      const d = new Date(isoString);
      return d.toLocaleDateString(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      });
    } catch {
      return '';
    }
  };

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
        showToast(isJa ? '保存済みに戻しました' : 'Item saved again');
      } catch (err) {
        console.error(err);
      }
    } else {
      nextOverrides[record.id] = record;
      setPendingOverrides(nextOverrides);
      try {
        await toggleSaveRecord(record, false);
        showToast(isJa ? '保存済みから削除しました' : 'Item removed from saved');
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

    if (isPending) {
      delete nextOverrides[record.id];
      setPendingOverrides(nextOverrides);
      try {
        await updateReactionRecord(record, reaction);
        showToast(isJa ? (reaction === 'like' ? '高評価に戻しました' : '低評価に戻しました') : `Item ${reaction} restored`);
      } catch (err) {
        console.error(err);
      }
    } else {
      nextOverrides[record.id] = record;
      setPendingOverrides(nextOverrides);
      try {
        await updateReactionRecord(record, null);
        showToast(isJa ? (reaction === 'like' ? '高評価を解除しました' : '低評価を解除しました') : `Item un-${reaction}d`);
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
      showToast(isJa ? 'お知らせをゴミ箱に移動しました' : 'Announcement moved to trash');
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
      showToast(isJa ? `「${record.title}」を復元しました` : `Restored "${record.title}"`);
    } catch (err) {
      console.error(err);
      setRemovedRecordIds((prev) => {
        const next = new Set(prev);
        next.delete(record.id);
        return next;
      });
      showToast(isJa ? 'アイテムの復元に失敗しました' : 'Failed to restore item');
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
      showToast(isJa ? `「${item.title}」を完全に削除しました` : `Permanently deleted "${item.title}"`);
    } catch (err) {
      console.error(err);
      showToast(isJa ? 'アイテムの完全削除に失敗しました' : 'Failed to permanently delete item');
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
      showToast(isJa ? 'ゴミ箱を空にしました' : 'Trash emptied successfully');
    } catch (err) {
      console.error(err);
      showToast(isJa ? 'ゴミ箱を空にできませんでした' : 'Failed to empty trash');
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
            {isJa ? '復習カード' : 'Review Card'}
          </span>
        );
      case 'deepNote':
        return (
          <span className="activity-type-badge">
            <FileText size={11} />
            {isJa ? '詳細ノート' : 'Deep Note'}
          </span>
        );
      case 'keyword':
        return (
          <span className="activity-type-badge">
            <Tag size={11} />
            {isJa ? 'キーワード' : 'Keyword'}
          </span>
        );
      case 'funFact':
        return (
          <span className="activity-type-badge">
            <Sparkles size={11} />
            {isJa ? '豆知識' : 'Fun Fact'}
          </span>
        );
      case 'announcement': {
        const badgeClass = `badge-${record.announcementType || 'info'}`;
        return (
          <span className={`activity-type-badge ${badgeClass}`}>
            <Megaphone size={11} />
            {record.announcementType?.toUpperCase() || (isJa ? 'お知らせ' : 'ANNOUNCEMENT')}
          </span>
        );
      }
      case 'course':
        return (
          <span className="activity-type-badge">
            <GraduationCap size={11} />
            {isJa ? 'コース' : 'Course'}
          </span>
        );
      case 'lecture':
        return (
          <span className="activity-type-badge">
            <Mic size={11} />
            {isJa ? '講義' : 'Lecture'}
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
          <span>{isJa ? 'アカウント' : 'Account'}</span>
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
            {isJa ? 'ゴミ箱を空にする' : 'Empty Trash'}
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
          <div>{isJa ? 'ゴミ箱の項目は30日後に完全に削除されます。' : 'Items in trash will be permanently deleted after 30 days.'}</div>
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
            {isJa ? 'すべての種類' : 'All Types'}
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
          {filteredRecords.length} {isJa ? '件のアイテム' : (filteredRecords.length === 1 ? 'item found' : 'items found')}
        </div>
      )}

      {/* ── Content / List Area ─────────────────────────────────── */}
      {loading ? (
        <div className="glass-card activity-empty-box" style={{ marginTop: '1.25rem' }}>
          <Loader2 size={32} className="spin" style={{ color: 'var(--star-gold, #fbc02d)' }} />
          <p className="muted" style={{ marginTop: '1rem', fontSize: '0.9rem' }}>
            {isJa ? 'クラウドから履歴を読み込み中…' : 'Loading records from cloud…'}
          </p>
        </div>
      ) : error ? (
        <div className="glass-card activity-empty-box" style={{ marginTop: '1.25rem' }}>
          <AlertCircle size={36} style={{ color: 'var(--correction-red, #ff5252)' }} />
          <h3 style={{ margin: '0.75rem 0 0.25rem' }}>{isJa ? 'アクティビティの読み込みに失敗しました' : 'Failed to load activity'}</h3>
          <p className="muted" style={{ margin: 0, fontSize: '0.88rem', maxWidth: '360px' }}>
            {error}
          </p>
          <button
            type="button"
            className="btn btn-ghost"
            style={{ marginTop: '1rem' }}
            onClick={loadRecords}
          >
            {isJa ? '再試行' : 'Retry'}
          </button>
        </div>
      ) : filteredRecords.length === 0 ? (
        <div className="glass-card activity-empty-box" style={{ marginTop: '1.25rem' }}>
          <Inbox size={40} className="activity-empty-icon" />
          <h3 style={{ margin: '0.5rem 0 0.25rem' }}>{isJa ? 'アイテムが見つかりません' : 'No items found'}</h3>
          <p
            className="muted"
            style={{ margin: 0, fontSize: '0.88rem', maxWidth: '320px', textAlign: 'center' }}
          >
            {activityType === 'trash'
              ? (isJa ? 'ゴミ箱は空です。削除した講義やコースがここに表示されます。' : 'Your trash is empty. Deleted lectures or courses will appear here.')
              : (isJa ? `"${activeFilter}" に一致するアイテムはありません。` : `You do not have any ${meta.title.toLowerCase()} items matching "${activeFilter}".`)}
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
                      <span>{isJa ? `${formatDate(record.dateTime)} に削除` : `Deleted on ${formatDate(record.dateTime)}`}</span>
                    </div>
                  </div>
                  <div className="activity-card-actions">
                    <button
                      type="button"
                      className="activity-action-btn active-gold"
                      title={isJa ? 'アイテムを復元' : 'Restore Item'}
                      onClick={(e) => handleRestoreItem(record, e)}
                    >
                      <RotateCcw size={18} />
                    </button>
                    <button
                      type="button"
                      className="activity-action-btn active-red"
                      title={isJa ? '完全に削除' : 'Delete Permanently'}
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
                    title={isCompleted ? (isJa ? '未完了に戻す' : 'Mark Active') : (isJa ? '完了にする' : 'Mark Completed')}
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
                        <span style={{ color: '#4caf50', fontWeight: 600 }}>{isJa ? '完了' : 'Completed'}</span>
                      )}
                    </div>
                  </div>
                  <div className="activity-card-actions">
                    <button
                      type="button"
                      className="activity-action-btn"
                      title={isJa ? 'ゴミ箱に移動' : 'Move to trash'}
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
                      title={isJa ? '元に戻す' : 'Undo action'}
                    >
                      <RotateCcw size={13} />
                      {isJa ? '元に戻す' : 'Undo'}
                    </button>
                  ) : isSavedType ? (
                    <button
                      type="button"
                      className="activity-action-btn active-gold"
                      title={isJa ? '保存済みから削除' : 'Remove from Saved'}
                      onClick={(e) => handleToggleSave(record, e)}
                    >
                      <Bookmark size={20} fill="currentColor" />
                    </button>
                  ) : isLikesType ? (
                    <button
                      type="button"
                      className="activity-action-btn active-red"
                      title={isJa ? '高評価を解除' : 'Remove Like'}
                      onClick={(e) => handleToggleReaction(record, e)}
                    >
                      <Heart size={20} fill="currentColor" />
                    </button>
                  ) : isDislikesType ? (
                    <button
                      type="button"
                      className="activity-action-btn active-blue"
                      title={isJa ? '低評価を解除' : 'Remove Dislike'}
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
        title={isJa ? 'ゴミ箱を空にする' : 'Empty Trash'}
        message={isJa ? 'ゴミ箱内のすべてのアイテムがクラウドおよびストレージから完全に削除されます。この操作は取り消せません。' : 'All items in your trash will be permanently deleted from both cloud and storage. This action cannot be undone.'}
        confirmLabel={isJa ? 'ゴミ箱を空にする' : 'Empty Trash'}
        cancelLabel={isJa ? 'キャンセル' : 'Cancel'}
        isDanger={true}
      />

      {/* ── Single Item Permanent Delete Confirmation Modal ────── */}
      <ConfirmModal
        open={Boolean(singleDeleteRecord)}
        onClose={() => setSingleDeleteRecord(null)}
        onConfirm={handleConfirmSingleDelete}
        title={isJa ? `「${singleDeleteRecord?.title || 'アイテム'}」を完全に削除しますか？` : `Permanently delete "${singleDeleteRecord?.title || 'Item'}"?`}
        message={isJa ? 'このアイテムは完全に削除されます。この操作は取り消せません。' : 'This item will be permanently removed. This action cannot be undone.'}
        confirmLabel={isJa ? '完全に削除' : 'Delete'}
        cancelLabel={isJa ? 'キャンセル' : 'Cancel'}
        isDanger={true}
      />
    </div>
  );
};
