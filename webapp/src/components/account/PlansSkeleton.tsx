import React from 'react';

const PLAN_COUNT = 4;
const FEATURE_ROW_COUNT = 5;

export const PlansSkeleton: React.FC = () => {
  const gridColumns = `minmax(150px, 1.1fr) repeat(${PLAN_COUNT}, minmax(160px, 1fr))`;

  return (
    <div className="plans-content-area" aria-busy="true" aria-live="polite">
      <div className="plans-cards-section">
        <div className="plans-card-row" style={{ ['--plans-grid-columns' as string]: gridColumns }}>
          <div className="plans-row-label-spacer" aria-hidden="true" />
          {Array.from({ length: PLAN_COUNT }).map((_, i) => (
            <article key={i} className="plans-card" style={{ ['--plan-accent' as string]: 'var(--glass-high)', pointerEvents: 'none' }}>
              <div className="plans-card-body">
                <div className="plans-card-info">
                  <span className="skeleton" style={{ width: '70%', height: 20, borderRadius: 6, display: 'block', marginBottom: 8 }} />
                  <span className="skeleton" style={{ width: '40%', height: 24, borderRadius: 6, display: 'block', marginBottom: 8 }} />
                  <span className="skeleton" style={{ width: '85%', height: 12, borderRadius: 6, display: 'block' }} />
                </div>
                <div className="plans-card-action">
                  <span className="skeleton" style={{ width: '100%', height: 36, borderRadius: 10, display: 'block' }} />
                </div>
              </div>
            </article>
          ))}
        </div>
      </div>

      <div className="plans-table-scroll">
        <div className="plans-compare" style={{ gridTemplateColumns: gridColumns }}>
          <div className="plans-compare-cell plans-compare-label">
            <span className="skeleton" style={{ width: 90, height: 13, borderRadius: 6 }} />
          </div>
          {Array.from({ length: PLAN_COUNT }).map((_, i) => (
            <div key={i} className="plans-compare-cell">
              <span className="skeleton" style={{ width: 60, height: 30, borderRadius: 6 }} />
            </div>
          ))}

          {Array.from({ length: FEATURE_ROW_COUNT }).map((_, row) => (
            <React.Fragment key={row}>
              <div className="plans-compare-cell plans-compare-label">
                <span className="skeleton" style={{ width: `${60 + ((row * 13) % 30)}%`, height: 13, borderRadius: 6 }} />
              </div>
              {Array.from({ length: PLAN_COUNT }).map((_, i) => (
                <div key={i} className="plans-compare-cell">
                  <span className="skeleton" style={{ width: 18, height: 18, borderRadius: '50%' }} />
                </div>
              ))}
            </React.Fragment>
          ))}
        </div>
      </div>
    </div>
  );
};
