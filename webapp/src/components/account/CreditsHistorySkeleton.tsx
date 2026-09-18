import React from 'react';

export const CreditsHistorySkeleton: React.FC = () => (
  <ul className="credits-history-list" aria-busy="true" aria-live="polite">
    {Array.from({ length: 5 }).map((_, i) => (
      <li key={i}>
        <div className="credits-history-row" style={{ pointerEvents: 'none' }}>
          <span className="credits-history-icon skeleton" style={{ background: 'none' }} />
          <span className="credits-history-text">
            <span className="skeleton" style={{ width: 70, height: 13, borderRadius: 6 }} />
            <span className="skeleton" style={{ width: 90, height: 11, borderRadius: 6, marginTop: 4 }} />
          </span>
          <span className="skeleton" style={{ width: 60, height: 14, borderRadius: 6 }} />
        </div>
      </li>
    ))}
  </ul>
);
