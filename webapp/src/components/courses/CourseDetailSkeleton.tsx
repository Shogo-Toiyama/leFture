import React from 'react';
import { ChevronLeft } from 'lucide-react';
import { CourseLecturesSectionSkeleton } from './CourseLecturesSectionSkeleton';

export const CourseDetailSkeleton: React.FC = () => {
  return (
    <div className="course-detail-root" aria-busy="true" aria-live="polite">
      <div className="course-detail-content">
        <div className="course-detail-nav">
          <span className="course-back-link" style={{ pointerEvents: 'none', opacity: 0.5 }}>
            <ChevronLeft size={18} className="course-back-chevron" />
            <span className="skeleton" style={{ width: 60, height: 14, borderRadius: 6 }} />
          </span>
        </div>

        <div className="course-title-row">
          <span className="skeleton" style={{ width: 48, height: 48, borderRadius: 14, flexShrink: 0 }} />
          <span className="skeleton" style={{ width: '45%', height: 32, borderRadius: 8 }} />
        </div>

        <div className="course-action-cards-row">
          <span
            className="course-announcement-card"
            style={{ pointerEvents: 'none', display: 'flex', alignItems: 'center' }}
          >
            <span className="skeleton" style={{ width: '70%', height: 16, borderRadius: 6 }} />
          </span>
          <span className="course-details-icon-btn skeleton" style={{ pointerEvents: 'none' }} />
        </div>

        <div className="course-topicmap-section">
          <span className="skeleton" style={{ width: 110, height: 16, borderRadius: 6, marginBottom: '0.5rem', display: 'inline-block' }} />
          <div className="course-topicmap-preview-card" style={{ pointerEvents: 'none' }}>
            <span className="skeleton" style={{ width: '100%', height: '100%', position: 'absolute', inset: 0, borderRadius: 'inherit' }} />
          </div>
        </div>

        <div className="course-lectures-section">
          <div className="course-lectures-header">
            <span className="skeleton" style={{ width: 70, height: 16, borderRadius: 6 }} />
          </div>
          <CourseLecturesSectionSkeleton />
        </div>
      </div>
    </div>
  );
};
