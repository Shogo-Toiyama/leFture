import React from 'react';
import { User, Sparkles, Flag, ArrowLeft } from 'lucide-react';

const ITEMS = [
  { icon: User, label: 'ABOUT YOU' },
  { icon: Sparkles, label: 'INTERESTS' },
  { icon: Flag, label: 'FUTURE DREAMS' },
];

export const ProfileSkeleton: React.FC = () => {
  return (
    <div className="account-page" aria-busy="true" aria-live="polite">
      <div className="profile-detail-top-nav">
        <span className="back-link" style={{ margin: 0, opacity: 0.5, pointerEvents: 'none' }}>
          <ArrowLeft size={18} />
          <span>Account</span>
        </span>
        <span className="profile-detail-edit-action" style={{ opacity: 0.5, pointerEvents: 'none' }} />
      </div>

      <div className="profile-detail-title-row">
        <h1 style={{ margin: '0.5rem 0 0.25rem', fontSize: '1.8rem' }}>
          <span className="skeleton" style={{ width: 110, height: 28, borderRadius: 8, display: 'inline-block' }} />
        </h1>
        <span className="skeleton" style={{ width: '65%', height: 14, borderRadius: 6, display: 'inline-block' }} />
      </div>

      <div className="glass-card" style={{ marginTop: '1.5rem' }}>
        {ITEMS.map(({ icon: Icon, label }, i) => (
          <React.Fragment key={label}>
            <div className="profile-detail-item">
              <div className="profile-detail-label">
                <Icon size={15} className="profile-detail-icon" />
                <span>{label}</span>
              </div>
              <p className="profile-detail-content">
                <span className="skeleton" style={{ width: '90%', height: 14, borderRadius: 6, display: 'inline-block', marginBottom: 6 }} />
                <span className="skeleton" style={{ width: '55%', height: 14, borderRadius: 6, display: 'inline-block' }} />
              </p>
            </div>
            {i < ITEMS.length - 1 && <div className="glass-divider" />}
          </React.Fragment>
        ))}
      </div>
    </div>
  );
};
