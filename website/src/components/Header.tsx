import React from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from '../i18n/LanguageContext';
import { useDownloadModal } from '../context/DownloadModalContext';
import { LanguageDropdown } from './LanguageDropdown';
import { Smartphone } from 'lucide-react';
import './header.css';

export const Header: React.FC = () => {
  const { t, locale } = useTranslation();
  const { openModal } = useDownloadModal();

  const ctaLine1 = locale === 'ja' ? 'アプリ' : 'Try';
  const ctaLine2 = locale === 'ja' ? '試す' : 'App';

  return (
    <header className="site-header">
      <div className="container site-header-container">
        {/* Logo */}
        <Link to="/" className="header-logo-link" aria-label="leFture Home">
          <img
            src="/img/app-icon.webp?v=2"
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

        {/* Header Right Actions (Custom Language Dropdown & Download App CTA Button) */}
        <div className="header-actions">
          <LanguageDropdown />

          <button
            type="button"
            onClick={openModal}
            className="btn-primary header-cta-btn"
            aria-label={t.nav.downloadApp}
          >
            <Smartphone size={15} />
            {/* >400px: 1-line horizontal text */}
            <span className="header-cta-text-single">{t.nav.downloadApp}</span>
            {/* <=400px: 2-tier stacked text */}
            <span className="header-cta-text-stacked">
              <span className="header-cta-line1">{ctaLine1}</span>
              <span className="header-cta-line2">{ctaLine2}</span>
            </span>
          </button>
        </div>
      </div>
    </header>
  );
};
