import React from 'react';

const CARD_COUNT = 6;

export const CourseListSkeleton: React.FC = () => {
  return (
    <div className="courses-tree-flow" aria-busy="true" aria-live="polite">
      <div className="courses-year-section">
        <div className="courses-year-header-row">
          <div className="courses-folder-toggle-btn courses-year-folder-btn" style={{ pointerEvents: 'none' }}>
            <span className="skeleton" style={{ width: 18, height: 18, borderRadius: 4 }} />
            <span className="skeleton" style={{ width: 90, height: 18, borderRadius: 6 }} />
          </div>
        </div>

        <div className="courses-year-body">
          <div className="courses-term-section">
            <div className="courses-term-header-row">
              <div className="courses-folder-toggle-btn courses-term-folder-btn" style={{ pointerEvents: 'none' }}>
                <span className="skeleton" style={{ width: 16, height: 16, borderRadius: 4 }} />
                <span className="skeleton" style={{ width: 70, height: 16, borderRadius: 6 }} />
              </div>
            </div>

            <div className="courses-card-grid-4x3">
              {Array.from({ length: CARD_COUNT }).map((_, i) => (
                <div
                  key={i}
                  className="course-card-4x3"
                  style={{ pointerEvents: 'none', background: 'var(--glass-low)' }}
                >
                  <div className="course-card-info">
                    <span className="skeleton" style={{ width: 64, height: 20, borderRadius: 999, marginBottom: '0.5rem' }} />
                    <span className="skeleton" style={{ width: '80%', height: 22, borderRadius: 6 }} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
