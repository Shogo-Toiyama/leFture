import React from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from '../i18n/LanguageContext';
import { LanguageDropdown } from './LanguageDropdown';
import { AppleLogo } from './AppleLogo';
import { APP_STORE_URL } from '../lib/links';

export const Header: React.FC = () => {
  const { t } = useTranslation();

  return (
    <header style={{
      position: 'sticky',
      top: 0,
      zIndex: 50,
      width: '100%',
      backdropFilter: 'blur(16px)',
      WebkitBackdropFilter: 'blur(16px)',
      backgroundColor: 'rgba(13, 16, 29, 0.85)',
      borderBottom: '1px solid var(--glass-border)'
    }}>
      <div className="container" style={{
        height: 'var(--header-height)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: '16px'
      }}>
        {/* Logo */}
        <Link to="/" style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <img
            src="/img/app-icon.webp"
            alt="leFture"
            width="34"
            height="34"
            loading="eager"
            decoding="async"
            style={{
              width: '34px',
              height: '34px',
              borderRadius: '9px',
              objectFit: 'cover',
              boxShadow: '0 2px 10px rgba(0, 0, 0, 0.4), 0 0 0 1px rgba(255, 255, 255, 0.1)',
              display: 'block'
            }}
          />
          <span style={{
            fontFamily: 'var(--font-heading)',
            fontSize: '1.35rem',
            fontWeight: 700,
            letterSpacing: '-0.02em',
            color: 'var(--text-starlight)'
          }}>
            leFture
          </span>
          <span style={{
            fontFamily: 'var(--font-heading)',
            fontSize: '0.68rem',
            fontWeight: 700,
            letterSpacing: '0.08em',
            textTransform: 'uppercase',
            padding: '2px 7px',
            borderRadius: '6px',
            backgroundColor: 'rgba(255, 179, 0, 0.12)',
            color: 'var(--accent)',
            border: '1px solid rgba(255, 179, 0, 0.3)',
            marginLeft: '2px',
          }}>
            Beta
          </span>
        </Link>

        {/* Header Right Actions (Custom Language Dropdown & App Store Button) */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <LanguageDropdown />

          <a
            href={APP_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="btn-primary"
            style={{
              padding: '8px 18px',
              fontSize: '0.85rem',
              minHeight: '38px',
            }}
          >
            <AppleLogo size={16} />
            <span>{t.nav.downloadApp}</span>
          </a>
        </div>
      </div>
    </header>
  );
};
