import React from 'react';
import { Link } from 'react-router-dom';
import type { Lecture } from '../types/lecture';
import { lectureDisplayTitle } from '../types/lecture';
import { TopicImage } from './TopicImage';

export interface LectureTileProps {
  lecture: Lecture;
  to?: string;
  courseCode?: string | null;
  courseColor?: string | null;
  firstTopicImagePath?: string | null;
  onEdit?: () => void;
  onDelete?: () => void;
}

export const LectureTile: React.FC<LectureTileProps> = ({
  lecture,
  to,
  courseCode,
  courseColor,
  firstTopicImagePath,
  onEdit,
  onDelete,
}) => {
  const targetUrl = to || `/lectures/${lecture.id}`;
  const accent = courseColor || '#FFB300';
  const title = lectureDisplayTitle(lecture);

  const formattedDate = new Date(lecture.lecture_datetime).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });

  return (
    <div className="lecture-tile-wrapper" style={{ ['--course-accent' as string]: accent }}>
      <Link to={targetUrl} className="lecture-tile-card">
        {/* Left: Thumbnail Image or Icon */}
        <div className="lecture-tile-thumb-box">
          {firstTopicImagePath ? (
            <TopicImage
              imagePath={firstTopicImagePath}
              alt={title}
              className="lecture-tile-thumb-img"
            />
          ) : (
            <div className="lecture-tile-fallback-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="tile-svg">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <polyline points="14 2 14 8 20 8" />
              </svg>
            </div>
          )}
        </div>

        {/* Center: Title & Metadata */}
        <div className="lecture-tile-info">
          <div className="lecture-tile-title-row">
            <span className="lecture-tile-title">{title}</span>
          </div>

          <div className="lecture-tile-meta-row">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="tile-time-svg">
              <circle cx="12" cy="12" r="10" />
              <polyline points="12 6 12 12 16 14" />
            </svg>
            <span className="lecture-tile-date">{formattedDate}</span>
            {courseCode && <span className="lecture-tile-code">{courseCode}</span>}
          </div>
        </div>

        {/* Right: Chevron */}
        <div className="lecture-tile-chevron">›</div>
      </Link>

      {/* Edit & Delete Action Buttons (Hover / Action Menu) */}
      {(onEdit || onDelete) && (
        <div className="lecture-tile-actions">
          {onEdit && (
            <button
              type="button"
              className="tile-action-btn"
              onClick={(e) => {
                e.stopPropagation();
                onEdit();
              }}
              title="Edit lecture"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="tile-btn-svg">
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
              </svg>
            </button>
          )}
          {onDelete && (
            <button
              type="button"
              className="tile-action-btn tile-action-delete"
              onClick={(e) => {
                e.stopPropagation();
                onDelete();
              }}
              title="Delete lecture"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="tile-btn-svg">
                <polyline points="3 6 5 6 21 6" />
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
              </svg>
            </button>
          )}
        </div>
      )}
    </div>
  );
};
