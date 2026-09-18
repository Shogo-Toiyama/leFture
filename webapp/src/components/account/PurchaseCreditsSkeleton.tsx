import React from 'react';

export const PurchaseCreditsSkeleton: React.FC = () => {
  return (
    <div className="purchase-credits-grid" aria-busy="true" aria-live="polite">
      {Array.from({ length: 6 }).map((_, i) => (
        <div key={i} className="purchase-credit-card" style={{ pointerEvents: 'none' }}>
          <div className="purchase-credit-card-illustration">
            <span className="skeleton" style={{ width: '100%', height: '100%', borderRadius: 14 }} />
          </div>
          <div className="purchase-credit-card-amount" style={{ justifyContent: 'center' }}>
            <span className="skeleton" style={{ width: 70, height: 16, borderRadius: 6 }} />
          </div>
          <span className="purchase-credit-card-btn skeleton" style={{ background: 'none' }} />
        </div>
      ))}
    </div>
  );
};
