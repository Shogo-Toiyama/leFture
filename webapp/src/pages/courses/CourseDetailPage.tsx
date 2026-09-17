import React, { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ChevronLeft, Pencil, Trash2, Megaphone, Info, Waypoints, ArrowRight } from 'lucide-react';
import { getCourse, softDeleteCourse } from '../../lib/courses';
import { CourseIconGlyph } from '../../lib/courseIcons';
import { useLectures } from '../../hooks/useLectures';
import { useAnnouncements } from '../../hooks/useAnnouncements';
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

export const CourseDetailPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();
  const { language } = useLanguage();

  const [course, setCourse] = useState<Course | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editCourseOpen, setEditCourseOpen] = useState(false);
  const [detailsModalOpen, setDetailsModalOpen] = useState(false);
  const [announcementsModalOpen, setAnnouncementsModalOpen] = useState(false);
  const [editingLecture, setEditingLecture] = useState<Lecture | null>(null);

  const { lectures, loading: lecturesLoading, error: lecturesError, refetch: refetchLectures } = useLectures(courseId);
  const { announcements, setAnnouncements } = useAnnouncements(undefined, courseId);

  const loadCourseData = () => {
    if (!courseId) return;
    getCourse(courseId)
      .then(setCourse)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load course'));
  };

  useEffect(() => {
    loadCourseData();
  }, [courseId]);

  if (error) return <PageState kind="error" message={error} />;
  if (!course) return <PageState kind="loading" />;

  const accent = (course.metadata?.color as string) || '#FFB300';
  const latestAnnouncement = announcements[0] ?? null;

  const backLabel = language === 'ja' ? 'コース一覧' : 'Courses';
  const noAnnouncementsText = language === 'ja' ? 'お知らせはありません' : 'No announcements';
  const topicMapTitle = language === 'ja' ? 'トピックマップ' : 'Topic Map';
  const openTopicMapLabel = language === 'ja' ? 'トピックマップを開く' : 'Open Topic Map';
  const lecturesSectionTitle = language === 'ja' ? '講義' : 'Lectures';
  const uploadButtonLabel = language === 'ja' ? '+ 講義をアップロード' : '+ Upload Recording';
  const noLecturesTitle = language === 'ja' ? '講義がまだありません' : 'No lectures yet';
  const noLecturesDesc = language === 'ja'
    ? '講義音声をアップロードして、AI学習ノートを作成しましょう。'
    : 'Upload a lecture recording to generate AI notes and review materials.';

  const handleDeleteCourse = async () => {
    if (!courseId) return;
    const msg = language === 'ja'
      ? `コース「${course.course_title}」を削除しますか？`
      : `Delete course "${course.course_title}"?`;
    if (!window.confirm(msg)) return;
    await softDeleteCourse(courseId);
    navigate('/courses');
  };

  const handleDeleteLecture = async (lecture: Lecture) => {
    const msg = language === 'ja'
      ? `講義を削除しますか？`
      : `Delete this lecture?`;
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
      {/* Top Background Gradient Scrim */}
      <div className="course-detail-top-gradient" />

      <div className="course-detail-content">
        {/* Navigation: ‹ Courses */}
        <div className="course-detail-nav">
          <Link to="/courses" className="course-back-link">
            <ChevronLeft size={18} className="course-back-chevron" />
            <span>{backLabel}</span>
          </Link>
        </div>

        {/* Row 1: Metadata (Code, Professor, Term/Year) */}
        <div className="course-meta-row">
          <div className="course-meta-left">
            {course.course_code?.trim() && (
              <span className="course-meta-code">{course.course_code.trim()}</span>
            )}
          </div>
        </div>

        {/* Row 2: Title & Edit Button */}
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
            <Pencil size={16} className="course-edit-svg" />
          </button>
          <button
            type="button"
            className="course-edit-circle-btn course-delete-circle-btn"
            onClick={handleDeleteCourse}
            title={language === 'ja' ? 'コースを削除' : 'Delete course'}
          >
            <Trash2 size={16} className="course-edit-svg" />
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
            {announcements.length > 0 && (
              <span className="course-announcement-badge">{announcements.length}</span>
            )}
          </div>

          {/* Details Info Button (DNS/Server Icon) */}
          <button
            type="button"
            className="course-details-icon-btn"
            onClick={() => setDetailsModalOpen(true)}
            title={language === 'ja' ? 'コース詳細情報' : 'Course Details'}
          >
            <Info size={18} className="course-dns-svg" />
          </button>
        </div>

        {/* Row 4: Topic Map Preview Card */}
        <div className="course-topicmap-section">
          <span className="course-section-heading">{topicMapTitle}</span>
          <Link to={`/courses/${courseId}/topic-map`} className="course-topicmap-preview-card">
            <div className="topicmap-bg-cosmos">
              <div className="topicmap-orbit-ring" style={{ borderColor: `${accent}33` }} />
              <Waypoints size={26} className="topicmap-orbit-icon" style={{ color: accent }} />
            </div>
            <div className="topicmap-preview-overlay-btn">
              <span>{openTopicMapLabel}</span>
              <ArrowRight size={16} className="topicmap-arrow" />
            </div>
          </Link>
        </div>

        {/* Row 5: Lectures Section */}
        <div className="course-lectures-section">
          <div className="course-lectures-header">
            <span className="course-section-heading">{lecturesSectionTitle}</span>
            <Link to={`/courses/${courseId}/upload`}>
              <button type="button" className="auth-submit-btn course-upload-btn">
                {uploadButtonLabel}
              </button>
            </Link>
          </div>

          {lecturesLoading && <PageState kind="loading" />}
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

      {/* Details Info Modal */}
      {detailsModalOpen && (
        <CourseDetailsModal
          course={course}
          onClose={() => setDetailsModalOpen(false)}
        />
      )}

      {/* Announcements Modal */}
      {announcementsModalOpen && (
        <AnnouncementsModal
          announcements={announcements}
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
