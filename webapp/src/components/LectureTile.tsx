import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { MoreVertical, Pencil, Trash2, Clock } from 'lucide-react';
import type { Lecture } from '../types/lecture';
import { lectureDisplayTitle } from '../types/lecture';
import { TopicImage } from './TopicImage';
import { useFirstTopicImagePath } from '../hooks/useFirstTopicImagePath';
import { useLanguage } from '../i18n/LanguageContext';

export interface LectureTileProps {
  lecture: Lecture;
  to?: string;
  courseCode?: string | null;
  courseColor?: string | null;
  onEdit?: () => void;
  onDelete?: () => void;
}

export const LectureTile: React.FC<LectureTileProps> = ({
  lecture,
  to,
  courseCode,
  courseColor,
  onEdit,
  onDelete,
}) => {
  const { language } = useLanguage();
  const [menuOpen, setMenuOpen] = useState(false);

  const firstTopicImagePath = useFirstTopicImagePath(lecture.id);
  const targetUrl = to || `/lectures/${lecture.id}`;
  const accent = courseColor || '#FFB300';
  const title = lectureDisplayTitle(lecture);

  const formattedDate = new Date(lecture.lecture_datetime).toLocaleDateString(
    language === 'ja' ? 'ja-JP' : 'en-US',
    {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    }
  );

  // 枠外クリック or Escapeキーでメニューを閉じる
  useEffect(() => {
    if (!menuOpen) return;
    const handleClose = () => setMenuOpen(false);
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMenuOpen(false);
    };
    window.addEventListener('click', handleClose);
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('click', handleClose);
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [menuOpen]);

  return (
    <div
      className={`lecture-tile-wrapper ${menuOpen ? 'is-menu-open' : ''}`}
      style={{ ['--course-accent' as string]: accent }}
    >
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
            <Clock size={13} className="tile-time-svg" />
            <span className="lecture-tile-date">{formattedDate}</span>
            {courseCode && <span className="lecture-tile-code">{courseCode}</span>}
          </div>
        </div>
      </Link>

      {/* Right: 3-dots Menu Button (CourseTileと共通のドロップダウン仕様) */}
      {(onEdit || onDelete) && (
        <div
          className="course-card-menu-wrap lecture-tile-menu-wrap"
          onClick={(e) => e.stopPropagation()}
        >
          <button
            type="button"
            className={`course-card-menu-btn ${menuOpen ? 'is-active' : ''}`}
            onClick={(e) => {
              e.stopPropagation();
              e.preventDefault();
              setMenuOpen((prev) => !prev);
            }}
            aria-label="Lecture options"
            aria-expanded={menuOpen}
          >
            <MoreVertical size={18} />
          </button>

          {menuOpen && (
            <div className="course-card-dropdown lecture-tile-dropdown">
              {onEdit && (
                <button
                  type="button"
                  className="course-dropdown-item"
                  onClick={(e) => {
                    e.stopPropagation();
                    e.preventDefault();
                    setMenuOpen(false);
                    onEdit();
                  }}
                >
                  <Pencil size={15} />
                  <span>{language === 'ja' ? '編集' : 'Edit'}</span>
                </button>
              )}
              {onDelete && (
                <button
                  type="button"
                  className="course-dropdown-item is-delete"
                  onClick={(e) => {
                    e.stopPropagation();
                    e.preventDefault();
                    setMenuOpen(false);
                    onDelete();
                  }}
                >
                  <Trash2 size={15} />
                  <span>{language === 'ja' ? '削除' : 'Delete'}</span>
                </button>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
};
