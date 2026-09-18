import React from 'react';
import { User, Bookmark, Rocket, Shield } from 'lucide-react';
import { GlassRowSkeleton } from './GlassRowSkeleton';

const Divider = () => <div className="glass-divider" />;

export const AccountPageSkeleton: React.FC = () => {
  return (
    <div className="account-page" aria-busy="true" aria-live="polite">
      <div className="account-top-header">
        <div className="account-user-row">
          <span className="account-avatar-wrapper" style={{ pointerEvents: 'none' }}>
            <span className="skeleton" style={{ width: 72, height: 72, borderRadius: '50%', display: 'block' }} />
          </span>
          <div className="account-name-block">
            <span className="skeleton" style={{ width: 140, height: 26, borderRadius: 8, display: 'inline-block' }} />
          </div>
        </div>

        <div className="credit-card-interactive" style={{ pointerEvents: 'none' }}>
          <div className="credit-card-top-row">
            <div className="credit-card-title-group">
              <span className="credit-card-icon-pill skeleton" style={{ background: 'none' }} />
              <span className="skeleton" style={{ width: 100, height: 14, borderRadius: 6 }} />
            </div>
            <span className="skeleton" style={{ width: 50, height: 14, borderRadius: 6 }} />
          </div>
          <div className="credit-dual-track">
            <div className="credit-bar-loading" />
          </div>
        </div>
      </div>

      <p className="glass-section-label">
        <User size={15} className="section-label-icon" color="var(--star-gold, #fbc02d)" />
        <span>Profile</span>
      </p>
      <div className="glass-card">
        {[0, 1, 2].map((i) => (
          <React.Fragment key={i}>
            <span className="account-preview-tile" style={{ pointerEvents: 'none' }}>
              <div className="account-preview-tile-body" style={{ width: '100%' }}>
                <span className="skeleton" style={{ width: 90, height: 13, borderRadius: 6, display: 'inline-block', marginBottom: 6 }} />
                <span className="skeleton" style={{ width: '80%', height: 13, borderRadius: 6, display: 'block' }} />
              </div>
            </span>
            {i < 2 && <Divider />}
          </React.Fragment>
        ))}
      </div>

      <p className="glass-section-label">
        <Bookmark size={15} className="section-label-icon" color="var(--star-gold, #fbc02d)" />
        <span>Activity</span>
      </p>
      <div className="glass-card">
        {Array.from({ length: 5 }).map((_, i) => (
          <React.Fragment key={i}>
            <GlassRowSkeleton />
            {i < 4 && <Divider />}
          </React.Fragment>
        ))}
      </div>

      <p className="glass-section-label">
        <Rocket size={15} className="section-label-icon" color="var(--star-gold, #fbc02d)" />
        <span>Application</span>
      </p>
      <div className="glass-card">
        {Array.from({ length: 3 }).map((_, i) => (
          <React.Fragment key={i}>
            <GlassRowSkeleton />
            {i < 2 && <Divider />}
          </React.Fragment>
        ))}
      </div>

      <p className="glass-section-label">
        <Shield size={15} className="section-label-icon" color="var(--comet, #8e99a6)" />
        <span>Settings</span>
      </p>
      <div className="glass-card">
        <GlassRowSkeleton withSub={false} />
        <Divider />
        <GlassRowSkeleton withSub={false} />
      </div>
      <div className="glass-card" style={{ marginTop: '0.85rem' }}>
        {Array.from({ length: 3 }).map((_, i) => (
          <React.Fragment key={i}>
            <GlassRowSkeleton withSub={false} />
            {i < 2 && <Divider />}
          </React.Fragment>
        ))}
      </div>
    </div>
  );
};
