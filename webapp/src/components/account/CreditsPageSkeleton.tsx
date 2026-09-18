import React from 'react';
import { CreditsHistorySkeleton } from './CreditsHistorySkeleton';

export const CreditsPageSkeleton: React.FC = () => {
  return (
    <div className="account-page credits-page" aria-busy="true" aria-live="polite">
      <div className="credits-page-head">
        <span className="back-link" style={{ opacity: 0.5, pointerEvents: 'none' }}>← Account</span>
      </div>
      <h1>
        <span className="skeleton" style={{ width: 110, height: 28, borderRadius: 8, display: 'inline-block' }} />
      </h1>

      <section className="glass-card credits-card">
        <div className="credits-card-head">
          <span className="skeleton" style={{ width: 120, height: 15, borderRadius: 6 }} />
          <span className="skeleton" style={{ width: 70, height: 20, borderRadius: 6 }} />
        </div>
        <div className="credits-dual-track">
          <div className="credit-bar-loading" />
        </div>
        <div className="credits-card-foot">
          <span className="skeleton" style={{ width: 100, height: 12, borderRadius: 6 }} />
          <span className="skeleton" style={{ width: 90, height: 12, borderRadius: 6 }} />
        </div>
      </section>

      <section className="glass-card credits-card credits-card-skeleton" style={{ position: 'relative' }}>
        <span
          className="skeleton"
          style={{ position: 'absolute', inset: 0, borderRadius: 'inherit' }}
        />
      </section>

      <section className="glass-card credits-card">
        <div className="credits-card-head">
          <span className="skeleton" style={{ width: 100, height: 15, borderRadius: 6 }} />
          <span className="skeleton" style={{ width: 90, height: 12, borderRadius: 6 }} />
        </div>
        <CreditsHistorySkeleton />
      </section>
    </div>
  );
};
