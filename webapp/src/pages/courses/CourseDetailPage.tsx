import React, { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getCourse, softDeleteCourse } from '../../lib/courses';
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
            <span className="course-back-chevron">‹</span>
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
            <span className="course-icon-symbol">✦</span>
          </div>
          <h1 className="course-main-title">{course.course_title}</h1>
          <button
            type="button"
            className="course-edit-circle-btn"
            onClick={() => setEditCourseOpen(true)}
            title={language === 'ja' ? 'コースを編集' : 'Edit course'}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="course-edit-svg">
              <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
              <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
            </svg>
          </button>
          <button
            type="button"
            className="course-edit-circle-btn course-delete-circle-btn"
            onClick={handleDeleteCourse}
            title={language === 'ja' ? 'コースを削除' : 'Delete course'}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="course-edit-svg">
              <polyline points="3 6 5 6 21 6" />
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
            </svg>
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
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="announcement-card-svg">
                <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
                <path d="M13.73 21a2 2 0 0 1-3.46 0" />
              </svg>
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
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="course-dns-svg">
              <rect x="2" y="2" width="20" height="8" rx="2" ry="2" />
              <rect x="2" y="14" width="20" height="8" rx="2" ry="2" />
              <line x1="6" y1="6" x2="6.01" y2="6" />
              <line x1="6" y1="18" x2="6.01" y2="18" />
            </svg>
          </button>
        </div>

        {/* Row 4: Topic Map Preview Card */}
        <div className="course-topicmap-section">
          <span className="course-section-heading">{topicMapTitle}</span>
          <Link to={`/courses/${courseId}/topic-map`} className="course-topicmap-preview-card">
            <div className="topicmap-bg-cosmos">
              <div className="topicmap-orbit-ring" style={{ borderColor: `${accent}33` }} />
              <div className="topicmap-orbit-icon" style={{ color: accent }}>✦</div>
            </div>
            <div className="topicmap-preview-overlay-btn">
              <span>{openTopicMapLabel}</span>
              <span className="topicmap-arrow">→</span>
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
