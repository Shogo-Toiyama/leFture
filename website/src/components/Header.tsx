import React from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from '../i18n/LanguageContext';
import { LanguageDropdown } from './LanguageDropdown';
import { AppleLogo } from './AppleLogo';
import { APP_STORE_URL } from '../lib/links';
import './header.css';

export const Header: React.FC = () => {
  const { t, locale } = useTranslation();

  const ctaLine1 = locale === 'ja' ? '近日' : 'Coming';
  const ctaLine2 = locale === 'ja' ? '公開' : 'Soon';

  return (
    <header className="site-header">
      <div className="container site-header-container">
        {/* Logo */}
        <Link to="/" className="header-logo-link" aria-label="leFture Home">
          <img
            src="/img/app-icon.webp"
            alt="leFture"
            width="34"
            height="34"
            loading="eager"
            decoding="async"
            className="header-logo-img"
          />
          <div className="header-logo-title-group">
            <span className="header-logo-text">leFture</span>
            <span className="header-beta-badge">Beta</span>
          </div>
        </Link>

        {/* Header Right Actions (Custom Language Dropdown & App Store CTA Button) */}
        <div className="header-actions">
          <LanguageDropdown />

          <a
            href={APP_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="btn-primary header-cta-btn"
            aria-label={t.nav.downloadApp}
          >
            <AppleLogo size={16} />
            {/* >400px: 1-line horizontal text */}
            <span className="header-cta-text-single">{t.nav.downloadApp}</span>
            {/* <=400px: 2-tier stacked text (Coming / Soon) */}
            <span className="header-cta-text-stacked">
              <span className="header-cta-line1">{ctaLine1}</span>
              <span className="header-cta-line2">{ctaLine2}</span>
            </span>
          </a>
        </div>
      </div>
    </header>
  );
};
