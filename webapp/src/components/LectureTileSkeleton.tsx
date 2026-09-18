import React from 'react';

export const LectureTileSkeleton: React.FC = () => {
  return (
    <div className="lecture-tile-wrapper" aria-hidden="true">
      <div className="lecture-tile-card" style={{ pointerEvents: 'none' }}>
        <div className="lecture-tile-thumb-box">
          <span className="skeleton" style={{ width: '100%', height: '100%', borderRadius: 12 }} />
        </div>
        <div className="lecture-tile-info">
          <div className="lecture-tile-title-row">
            <span className="skeleton" style={{ width: '55%', height: 17, borderRadius: 6 }} />
          </div>
          <div className="lecture-tile-meta-row">
            <span className="skeleton" style={{ width: 80, height: 13, borderRadius: 6 }} />
          </div>
        </div>
      </div>
    </div>
  );
};
