import React from 'react';
import { Link } from 'react-router-dom';
import type { LectureTopic } from '../../types/content';
import type { Course } from '../../types/course';
import { TopicImage } from '../TopicImage';

interface LectureHeroViewProps {
  course: Course | null;
  lectureTitle: string;
  lectureDatetime: string;
  topics: LectureTopic[];
  summary?: string | null;
  onEdit?: () => void;
}

export const LectureHeroView: React.FC<LectureHeroViewProps> = ({
  course,
  lectureTitle,
  lectureDatetime,
  topics,
  summary,
  onEdit,
}) => {
  const heroTopics = topics.filter((t) => t.image_path).slice(0, 6);
  const courseColor = (course?.metadata?.color as string) || '#FFB300';
  const courseTitle = course?.course_title || 'Course';

  const formattedDate = new Date(lectureDatetime).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    weekday: 'short',
  });

  const formattedTime = new Date(lectureDatetime).toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  });

  return (
    <section className="lecture-hero-viewport" style={{ ['--course-accent' as string]: courseColor }}>
      {/* Background TopicArt Collage / Panorama */}
      <div className="lecture-hero-media">
        {heroTopics.length > 0 ? (
          <div className={`hero-slit-container slit-count-${heroTopics.length}`}>
            {heroTopics.map((topic) => (
              <div key={topic.id} className="hero-slit-item">
                <TopicImage imagePath={topic.image_path} alt={topic.topic_title} className="hero-slit-img" />
                <div className="hero-slit-topic-tag">
                  <span>{topic.topic_title}</span>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="hero-cosmos-empty-art">
            <div className="hero-cosmos-orbit-ring" style={{ borderColor: `${courseColor}44` }} />
            <div className="hero-cosmos-orbit-icon" style={{ color: courseColor }}>✦</div>
          </div>
        )}

        {/* Cinematic Gradient Overlays */}
        <div className="hero-top-scrim" />
        <div className="hero-bottom-scrim" />
      </div>

      {/* Foreground Content */}
      <div className="lecture-hero-content">
        {/* Top Nav: ‹ Course Name on Left, Edit Button on Right */}
        <div className="lecture-hero-nav">
          <Link
            to={`/courses/${course?.id ?? ''}`}
            className="lecture-hero-back-link"
            style={{
              ['--course-accent' as string]: courseColor,
            }}
          >
            <span className="hero-back-chevron">‹</span>
            <span className="hero-back-course-name">{courseTitle}</span>
          </Link>

          {onEdit && (
            <button
              type="button"
              className="lecture-hero-edit-btn"
              onClick={onEdit}
              title="Edit lecture"
              aria-label="Edit lecture"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="hero-edit-svg">
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
              </svg>
            </button>
          )}
        </div>

        {/* Bottom Hero Info */}
        <div className="lecture-hero-main-info">
          <div className="lecture-hero-meta">
            <time className="hero-datetime">
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                className="hero-meta-icon"
              >
                <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
                <line x1="16" y1="2" x2="16" y2="6" />
                <line x1="8" y1="2" x2="8" y2="6" />
                <line x1="3" y1="10" x2="21" y2="10" />
              </svg>
              <span>{formattedDate}</span>
              <span className="hero-meta-divider">•</span>
              <span>{formattedTime}</span>
            </time>
          </div>

          <h1 className="lecture-hero-title">{lectureTitle}</h1>

          {summary && <p className="lecture-hero-summary">{summary}</p>}
        </div>
      </div>
    </section>
  );
};
