import React from 'react';

export const LectureViewerSkeleton: React.FC = () => {
  return (
    <div className="lecture-viewer-root lecture-viewer-loading-root">
      {/* 1. Full Viewport Hero Skeleton */}
      <section className="lecture-hero-viewport">
        <div className="lecture-hero-media">
          <div className="hero-slit-container slit-count-4">
            {[0, 1, 2, 3].map((index) => (
              <div key={index} className="hero-slit-item hero-slit-skeleton-item">
                <div className="hero-slit-skeleton-shimmer" style={{ animationDelay: `${index * 0.15}s` }} />
              </div>
            ))}
          </div>
          <div className="hero-top-scrim" />
          <div className="hero-bottom-scrim" />
        </div>

        <div className="lecture-hero-content">
          <div className="lecture-hero-nav">
            <div className="skeleton-hero-back-link skeleton" style={{ width: 140, height: 38, borderRadius: 999 }} />
          </div>

          <div className="lecture-hero-main-info" style={{ width: '100%' }}>
            <div className="skeleton" style={{ width: 180, height: 28, borderRadius: 6, marginBottom: '0.75rem' }} />
            <div className="skeleton" style={{ width: '65%', height: 48, borderRadius: 12, marginBottom: '0.75rem' }} />
            <div className="skeleton" style={{ width: '80%', height: 20, borderRadius: 6, marginBottom: '0.4rem' }} />
            <div className="skeleton" style={{ width: '50%', height: 20, borderRadius: 6 }} />
          </div>
        </div>
      </section>

      {/* 2. Main Body 2-Column Split Skeleton */}
      <div className="lecture-body-container">
        <div className="lecture-split-layout">
          {/* Left Column Stack */}
          <div className="action-nav-stack">
            {[0, 1, 2].map((idx) => (
              <div
                key={idx}
                className="action-nav-card"
                style={{ height: 72, pointerEvents: 'none' }}
              >
                <div className="action-nav-left" style={{ width: '100%' }}>
                  <div className="skeleton" style={{ width: 44, height: 44, borderRadius: 12 }} />
                  <div className="skeleton" style={{ width: '45%', height: 20, borderRadius: 6 }} />
                </div>
              </div>
            ))}
          </div>

          {/* Right Column Fun Fact Skeleton */}
          <div className="lecture-funfacts-column">
            <div className="fun-fact-card" style={{ minHeight: 260, pointerEvents: 'none' }}>
              <div className="skeleton" style={{ width: '40%', height: 24, margin: '0 auto', borderRadius: 6 }} />
              <div className="skeleton" style={{ width: '90%', height: 18, borderRadius: 6, marginTop: '1rem' }} />
              <div className="skeleton" style={{ width: '75%', height: 18, borderRadius: 6 }} />
              <div className="fun-fact-divider" style={{ opacity: 0.3 }} />
              <div className="skeleton" style={{ width: '100%', height: 16, borderRadius: 6 }} />
              <div className="skeleton" style={{ width: '95%', height: 16, borderRadius: 6 }} />
              <div className="skeleton" style={{ width: '60%', height: 16, borderRadius: 6 }} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
