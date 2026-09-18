import React, { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ChevronLeft, Pencil, Megaphone, Info, Maximize2, Plus } from 'lucide-react';
import { getCourse } from '../../lib/courses';
import { CourseIconGlyph } from '../../lib/courseIcons';
import { useLectures } from '../../hooks/useLectures';
import { useAnnouncements } from '../../hooks/useAnnouncements';
import { useCourseAttributes } from '../../hooks/useCourseAttributes';
import { useTopicMap } from '../../hooks/useTopicMap';
import { computeTopicMapLayout } from '../../lib/topicMap/layout';
import { TopicMapCanvas } from '../../components/courses/topicMap/TopicMapCanvas';
import { useLanguage } from '../../i18n/LanguageContext';
import { softDeleteLecture } from '../../lib/lectures';
import type { Course } from '../../types/course';
import type { Lecture } from '../../types/lecture';
import { CourseEditModal } from '../../components/modals/CourseEditModal';
import { CourseDetailsModal } from '../../components/modals/CourseDetailsModal';
import { AnnouncementsModal } from '../../components/modals/AnnouncementsModal';
import { LectureEditModal } from '../../components/modals/LectureEditModal';
import { LectureTile } from '../../components/LectureTile';
import { PageState } from '../../components/PageState';
import { CourseDetailSkeleton } from '../../components/courses/CourseDetailSkeleton';
import { CourseLecturesSectionSkeleton } from '../../components/courses/CourseLecturesSectionSkeleton';
import { useUploadModal } from '../../context/UploadModalContext';

export const CourseDetailPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();
  const { language } = useLanguage();
  const { openUploadModal } = useUploadModal();

  const [course, setCourse] = useState<Course | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editCourseOpen, setEditCourseOpen] = useState(false);
  const [detailsModalOpen, setDetailsModalOpen] = useState(false);
  const [announcementsModalOpen, setAnnouncementsModalOpen] = useState(false);
  const [editingLecture, setEditingLecture] = useState<Lecture | null>(null);

  const { lectures, loading: lecturesLoading, error: lecturesError, refetch: refetchLectures } = useLectures(courseId);
  const { announcements, setAnnouncements } = useAnnouncements(undefined, courseId);
  const { map: topicMapData } = useTopicMap(courseId);

  // 属性マスターデータ (Flutter同等の属性解決用)
  const years = useCourseAttributes('year');
  const terms = useCourseAttributes('term');
  const professors = useCourseAttributes('professor');
  const schools = useCourseAttributes('school');
  const subjects = useCourseAttributes('subject');

  const loadCourseData = () => {
    if (!courseId) return;
    getCourse(courseId)
      .then(setCourse)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load course'));
  };

  useEffect(() => {
    loadCourseData();
  }, [courseId]);

  // 属性名解決
  const yearName = useMemo(() => {
    if (!course?.year_id) return '';
    return years.find((y) => y.id === course.year_id)?.attribute_name || '';
  }, [course?.year_id, years]);

  const termName = useMemo(() => {
    if (!course?.term_id) return '';
    return terms.find((t) => t.id === course.term_id)?.attribute_name || '';
  }, [course?.term_id, terms]);

  const profName = useMemo(() => {
    if (!course?.professor) return '';
    return professors.find((p) => p.id === course.professor)?.attribute_name || course.professor;
  }, [course?.professor, professors]);

  const schoolName = useMemo(() => {
    if (!course?.school_id) return '';
    return schools.find((s) => s.id === course.school_id)?.attribute_name || '';
  }, [course?.school_id, schools]);

  const subjectName = useMemo(() => {
    if (!course?.subject_id) return '';
    return subjects.find((s) => s.id === course.subject_id)?.attribute_name || '';
  }, [course?.subject_id, subjects]);

  // Flutter版と同じ学期・年度ラベル (例: "Spring 2026")
  const termYearParts = [termName, yearName].filter(Boolean);
  const termYearLabel = termYearParts.join(' ');

  // 本物のトピックマップと同一のフォースレイアウト計算
  const lectureNumBySourceLectureId = useMemo(() => {
    const map = new Map<string, number>();
    const sorted = [...(lectures || [])].sort((a, b) =>
      a.created_at.localeCompare(b.created_at)
    );
    sorted.forEach((lecture, i) => map.set(lecture.id, i + 1));
    return map;
  }, [lectures]);

  const topicMapLayout = useMemo(() => {
    if (!topicMapData || topicMapData.nodes.length === 0) return null;
    return computeTopicMapLayout(topicMapData, lectureNumBySourceLectureId);
  }, [topicMapData, lectureNumBySourceLectureId]);

  if (error) return <PageState kind="error" message={error} />;
  if (!course) return <CourseDetailSkeleton />;

  const accent = (course.metadata?.color as string) || '#FFB300';
  const activeAnnouncements = announcements.filter((a) => !a.completed_at);
  const latestAnnouncement = activeAnnouncements[0] ?? null;

  const backLabel = language === 'ja' ? 'コース一覧' : 'Courses';
  const noAnnouncementsText = language === 'ja' ? 'お知らせはありません' : 'No announcements';
  const topicMapTitle = language === 'ja' ? 'トピックマップ' : 'Topic Map';
  const lecturesSectionTitle = language === 'ja' ? '講義' : 'Lectures';
  const newLectureLabel = language === 'ja' ? '新規講義' : 'New Lecture';
  const noLecturesTitle = language === 'ja' ? '講義がまだありません' : 'No lectures yet';
  const noLecturesDesc = language === 'ja'
    ? '講義音声をアップロードして、AI学習ノートを作成しましょう。'
    : 'Upload a lecture recording to generate AI notes and review materials.';

  const handleDeleteLecture = async (lecture: Lecture) => {
    const msg = language === 'ja'
      ? '講義を削除しますか？'
      : 'Delete this lecture?';
    if (!window.confirm(msg)) return;
    try {
      await softDeleteLecture(lecture.id);
      await refetchLectures();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to delete lecture');
    }
  };

  return (
    <div
      className="course-detail-root"
      style={{
        ['--course-accent' as string]: accent,
      }}
    >
      {/* Top Background Gradient: Header Dark -> Course Color -> Background Void */}
      <div className="course-detail-top-gradient" />

      {/* Top-Right Giant Watermark Icon (2x Large) */}
      <div className="course-detail-watermark-wrap" aria-hidden="true">
        <div
          className="course-detail-watermark-icon"
          style={{ color: accent }}
        >
          <CourseIconGlyph
            icon={course.metadata?.icon as string}
            size={700}
            className="course-detail-watermark-glyph"
          />
        </div>
      </div>

      <div className="course-detail-content">
        {/* Navigation: ‹ Courses (左端) & Year/Term (右端プレーンテキスト) */}
        <div className="course-detail-nav">
          <Link to="/courses" className="course-back-link">
            <ChevronLeft size={18} className="course-back-chevron" />
            <span>{backLabel}</span>
          </Link>
          {termYearLabel && (
            <span className="course-nav-term-year">{termYearLabel}</span>
          )}
        </div>

        {/* Row 1: Metadata (Code & Professor) */}
        {(course.course_code?.trim() || profName?.trim()) && (
          <div className="course-meta-row">
            <div className="course-meta-left">
              {course.course_code?.trim() && (
                <span className="course-meta-code">{course.course_code.trim()}</span>
              )}
              {profName?.trim() && (
                <span className="course-meta-professor">{profName.trim()}</span>
              )}
            </div>
          </div>
        )}

        {/* Row 2: Title & Edit Button (大きくはっきりしたペンシルアイコン) */}
        <div className="course-title-row">
          <div
            className="course-title-icon-box"
            style={{
              backgroundColor: `${accent}22`,
              borderColor: `${accent}55`,
              color: accent,
            }}
          >
            <CourseIconGlyph icon={course.metadata?.icon as string} size={22} className="course-icon-symbol" />
          </div>
          <h1 className="course-main-title">{course.course_title}</h1>
          <button
            type="button"
            className="course-edit-circle-btn"
            onClick={() => setEditCourseOpen(true)}
            title={language === 'ja' ? 'コースを編集' : 'Edit course'}
          >
            <Pencil size={22} strokeWidth={2.2} className="course-edit-svg" />
          </button>
        </div>

        {/* Row 3: Announcement Card & Details Info Button */}
        <div className="course-action-cards-row">
          {/* Announcement Card */}
          <div
            className="course-announcement-card"
            onClick={() => setAnnouncementsModalOpen(true)}
            role="button"
            tabIndex={0}
          >
            <div className="course-announcement-icon-wrap" style={{ color: 'var(--gold)' }}>
              <Megaphone size={18} className="announcement-card-svg" />
            </div>
            <span className="course-announcement-text">
              {latestAnnouncement?.title?.trim() || latestAnnouncement?.description?.trim() || noAnnouncementsText}
            </span>
            {activeAnnouncements.length > 0 && (
              <span className="course-announcement-badge">{activeAnnouncements.length}</span>
            )}
          </div>

          {/* Details Info Button (Course Details Sheet) */}
          <button
            type="button"
            className="course-details-icon-btn"
            onClick={() => setDetailsModalOpen(true)}
            title={language === 'ja' ? 'コース詳細情報' : 'Course Details'}
          >
            <Info size={18} className="course-dns-svg" />
          </button>
        </div>

        {/* Row 4: Topic Map (実際のTopicMapCanvasと統一) */}
        <div className="course-topicmap-section">
          <span className="course-section-heading">{topicMapTitle}</span>
          <div
            className="course-topicmap-preview-card"
            onClick={() => navigate(`/courses/${courseId}/topic-map`)}
            role="button"
            tabIndex={0}
            title={topicMapTitle}
          >
            {topicMapLayout && topicMapData && topicMapData.nodes.length > 0 ? (
              <TopicMapCanvas
                data={topicMapData}
                simulation={topicMapLayout.simulation}
                canvasSize={topicMapLayout.canvasSize}
                clusterIdByNodeId={topicMapLayout.clusterIdByNodeId}
                lectureNumByNodeId={topicMapLayout.lectureNumByNodeId}
                selection={null}
                onSelectNode={() => {}}
                onSelectCluster={() => {}}
                onClearSelection={() => {}}
              />
            ) : (
              // Flutter版 _TopicMapPainter と同一の宇宙軌道・星座グラフ
              <svg
                viewBox="0 0 600 220"
                className="course-topicmap-svg"
                preserveAspectRatio="xMidYMid meet"
              >
                <defs>
                  <radialGradient id="orbitGlow" cx="50%" cy="50%" r="50%">
                    <stop offset="0%" stopColor={accent} stopOpacity="0.25" />
                    <stop offset="100%" stopColor={accent} stopOpacity="0" />
                  </radialGradient>
                </defs>

                <circle cx="300" cy="110" r="140" fill="url(#orbitGlow)" />

                {/* 十字グリッド線 */}
                <line x1="0" y1="110" x2="600" y2="110" stroke="rgba(255, 255, 255, 0.05)" strokeWidth="1" />
                <line x1="300" y1="0" x2="300" y2="220" stroke="rgba(255, 255, 255, 0.05)" strokeWidth="1" />

                {/* 同心円軌道 (Flutter: r=40, r=80, r=120) */}
                <circle cx="300" cy="110" r="45" fill="none" stroke="rgba(255, 255, 255, 0.08)" strokeWidth="1" strokeDasharray="3 3" />
                <circle cx="300" cy="110" r="85" fill="none" stroke="rgba(255, 255, 255, 0.06)" strokeWidth="1" />
                <circle cx="300" cy="110" r="125" fill="none" stroke="rgba(255, 255, 255, 0.04)" strokeWidth="1" strokeDasharray="6 4" />

                {/* 星座リンク線 */}
                <line x1="300" y1="110" x2="240" y2="90" stroke={accent} strokeOpacity="0.4" strokeWidth="2" />
                <line x1="300" y1="110" x2="330" y2="50" stroke={accent} strokeOpacity="0.4" strokeWidth="2" />
                <line x1="300" y1="110" x2="370" y2="140" stroke={accent} strokeOpacity="0.4" strokeWidth="2" />
                <line x1="300" y1="110" x2="270" y2="170" stroke={accent} strokeOpacity="0.4" strokeWidth="2" />
                <line x1="240" y1="90" x2="330" y2="50" stroke={accent} strokeOpacity="0.25" strokeWidth="1.5" strokeDasharray="4 4" />
                <line x1="370" y1="140" x2="270" y2="170" stroke={accent} strokeOpacity="0.25" strokeWidth="1.5" strokeDasharray="4 4" />

                {/* スターノード */}
                <circle cx="300" cy="110" r="8" fill={accent} filter="drop-shadow(0 0 8px currentColor)" />
                <circle cx="300" cy="110" r="3.5" fill="#ffffff" />

                <circle cx="240" cy="90" r="5.5" fill={accent} fillOpacity="0.9" />
                <circle cx="240" cy="90" r="2" fill="#ffffff" />

                <circle cx="330" cy="50" r="6" fill={accent} fillOpacity="0.9" />
                <circle cx="330" cy="50" r="2.5" fill="#ffffff" />

                <circle cx="370" cy="140" r="5" fill={accent} fillOpacity="0.9" />
                <circle cx="370" cy="140" r="2" fill="#ffffff" />

                <circle cx="270" cy="170" r="4.5" fill={accent} fillOpacity="0.9" />
                <circle cx="270" cy="170" r="2" fill="#ffffff" />
              </svg>
            )}

            {/* 右上の拡大アイコン */}
            <div className="topicmap-expand-badge" aria-label="Expand Topic Map">
              <Maximize2 size={15} />
            </div>
          </div>
        </div>

        {/* Row 5: Lectures Section */}
        <div className="course-lectures-section">
          <div className="course-lectures-header">
            <span className="course-section-heading">{lecturesSectionTitle}</span>
          </div>

          {lecturesLoading && <CourseLecturesSectionSkeleton />}
          {lecturesError && <PageState kind="error" message={lecturesError} />}

          {!lecturesLoading && lectures.length === 0 && (
            <div className="course-lectures-empty">
              <p className="lectures-empty-title">{noLecturesTitle}</p>
              <p className="lectures-empty-desc">{noLecturesDesc}</p>
            </div>
          )}

          <div className="course-lectures-list">
            {lectures.map((lecture) => (
              <LectureTile
                key={lecture.id}
                lecture={lecture}
                courseCode={course.course_code}
                courseColor={accent}
                onEdit={() => setEditingLecture(lecture)}
                onDelete={() => handleDeleteLecture(lecture)}
              />
            ))}
          </div>
        </div>
      </div>

      {/* Floating Action Button (Flutter同等の右下固定ボタン: ＋アイコン + 'New Lecture' / '新規講義') */}
      <button
        type="button"
        className="courses-fab"
        onClick={() => openUploadModal(courseId)}
        aria-label={newLectureLabel}
      >
        <Plus size={19} strokeWidth={2.6} />
        <span>{newLectureLabel}</span>
      </button>

      {/* Edit Course Modal */}
      {editCourseOpen && (
        <CourseEditModal
          existingCourse={course}
          onClose={() => setEditCourseOpen(false)}
          onCourseSaved={async () => {
            loadCourseData();
            setEditCourseOpen(false);
          }}
        />
      )}

      {/* Details Info Modal (Flutter course_details_sheet と完全同期) */}
      {detailsModalOpen && (
        <CourseDetailsModal
          course={course}
          resolvedAttributes={{
            yearName,
            termName,
            professorName: profName,
            schoolName,
            subjectName,
          }}
          onClose={() => setDetailsModalOpen(false)}
        />
      )}

      {/* Announcements Modal */}
      {announcementsModalOpen && (
        <AnnouncementsModal
          announcements={announcements}
          lectures={lectures}
          onClose={() => setAnnouncementsModalOpen(false)}
          onAnnouncementToggled={(updated) => {
            setAnnouncements((prev) => prev.map((a) => (a.id === updated.id ? updated : a)));
          }}
        />
      )}

      {/* Lecture Edit Modal */}
      {editingLecture && (
        <LectureEditModal
          lecture={editingLecture}
          onClose={() => setEditingLecture(null)}
          onLectureUpdated={async () => {
            await refetchLectures();
            setEditingLecture(null);
          }}
        />
      )}
    </div>
  );
};
