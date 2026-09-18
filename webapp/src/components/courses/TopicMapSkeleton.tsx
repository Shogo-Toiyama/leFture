import React from 'react';

export const TopicMapSkeleton: React.FC = () => {
  return (
    <div className="tm-page tm-skeleton-page" aria-busy="true" aria-live="polite">
      <header className="tm-header">
        <div className="tm-header-bar">
          <div className="tm-header-left">
            <span className="skeleton" style={{ width: 140, height: 32, borderRadius: 999, display: 'inline-block' }} />
          </div>

          <div className="tm-header-center">
            <span className="skeleton" style={{ width: 96, height: 20, borderRadius: 6, display: 'inline-block' }} />
            <span className="skeleton" style={{ width: 130, height: 12, borderRadius: 4, marginTop: 4, display: 'inline-block' }} />
          </div>

          <div className="tm-header-right">
            <div className="tm-app-bar-actions">
              <span className="skeleton" style={{ width: 34, height: 34, borderRadius: '50%', display: 'inline-block' }} />
              <span className="skeleton" style={{ width: 34, height: 34, borderRadius: '50%', display: 'inline-block' }} />
            </div>
          </div>
        </div>

        <div className="tm-header-chips">
          <div className="tm-lecture-chips">
            {[68, 68, 68, 68].map((w, i) => (
              <span key={i} className="skeleton" style={{ width: w, height: 28, borderRadius: 999, flex: '0 0 auto' }} />
            ))}
          </div>
        </div>
      </header>

      <div className="tm-canvas-shell tm-skeleton-canvas">
        <div className="tm-skeleton-nodes" aria-hidden="true">
          <div className="tm-skeleton-orbit orbit-1" />
          <div className="tm-skeleton-orbit orbit-2" />
          <span className="skeleton tm-skeleton-node node-center" />
          <span className="skeleton tm-skeleton-node node-1" />
          <span className="skeleton tm-skeleton-node node-2" />
          <span className="skeleton tm-skeleton-node node-3" />
          <span className="skeleton tm-skeleton-node node-4" />
        </div>
      </div>
    </div>
  );
};
