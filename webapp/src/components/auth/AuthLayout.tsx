import React from 'react';
import { Link } from 'react-router-dom';
import { LanguageHeaderButton } from './LanguageHeaderButton';

interface AuthLayoutProps {
  title: string;
  subtitle?: string;
  icon?: 'book' | 'lock' | 'mail' | 'user' | 'sparkles' | 'rocket' | 'trash';
  glowVariant?: 'gold' | 'danger';
  children: React.ReactNode;
  footer?: React.ReactNode;
  backTo?: {
    label: string;
    to: string;
  };
}

export const AuthLayout: React.FC<AuthLayoutProps> = ({
  title,
  subtitle,
  icon = 'book',
  glowVariant = 'gold',
  children,
  footer,
  backTo,
}) => {
  const renderIcon = () => {
    switch (icon) {
      case 'trash':
        return (
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="3 6 5 6 21 6" />
            <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
            <line x1="10" y1="11" x2="10" y2="17" />
            <line x1="14" y1="11" x2="14" y2="17" />
          </svg>
        );
      case 'rocket':
        return (
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z" />
            <path d="M12 15l-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z" />
            <path d="M9 12H4s.55-3.03 2-4.5c1.62-1.63 5-2 5-2" />
            <path d="M15 12v5s3.03-.55 4.5-2c1.63-1.62 2-5 2-5" />
          </svg>
        );
      case 'lock':
        return (
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        );
      case 'mail':
        return (
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" />
            <polyline points="22,6 12,13 2,6" />
          </svg>
        );
      case 'user':
        return (
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
            <circle cx="12" cy="7" r="4" />
          </svg>
        );
      case 'sparkles':
        return (
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />
          </svg>
        );
      case 'book':
      default:
        return (
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z" />
            <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z" />
          </svg>
        );
    }
  };

  return (
    <div className="auth-cosmos-page">
      {/* Top right language button */}
      <div className="auth-top-actions">
        <LanguageHeaderButton />
      </div>

      {backTo && (
        <div className="auth-top-nav">
          <Link to={backTo.to} className="auth-back-link">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <line x1="19" y1="12" x2="5" y2="12" />
              <polyline points="12 19 5 12 12 5" />
            </svg>
            <span>{backTo.label}</span>
          </Link>
        </div>
      )}

      <div className="auth-cosmos-container">
        <div className="auth-cosmos-header">
          <div className="auth-glow-icon-wrap">
            <div className={`auth-glow-icon ${glowVariant === 'danger' ? 'danger' : ''}`}>{renderIcon()}</div>
          </div>
          <h1 className="auth-cosmos-title">{title}</h1>
          {subtitle && <p className="auth-cosmos-subtitle">{subtitle}</p>}
        </div>

        <div className="auth-glass-card">{children}</div>

        {footer && <div className="auth-cosmos-footer">{footer}</div>}
      </div>
    </div>
  );
};
