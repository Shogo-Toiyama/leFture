import React from 'react';

export const GlassRowSkeleton: React.FC<{ withSub?: boolean }> = ({ withSub = true }) => (
  <span className="glass-row" style={{ pointerEvents: 'none' }}>
    <span className="glass-row-icon skeleton" style={{ background: 'none' }} />
    <span className="glass-row-text">
      <span className="skeleton" style={{ width: '45%', height: 14, borderRadius: 6 }} />
      {withSub && <span className="skeleton" style={{ width: '70%', height: 12, borderRadius: 6, marginTop: 4 }} />}
    </span>
  </span>
);
