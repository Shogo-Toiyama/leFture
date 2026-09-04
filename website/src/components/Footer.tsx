import React from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from '../i18n/LanguageContext';

export const Footer: React.FC = () => {
  const { t } = useTranslation();

  return (
    <footer style={{
      borderTop: '1px solid var(--glass-border)',
      backgroundColor: 'rgba(9, 11, 20, 0.95)',
      padding: '48px 0 32px',
      marginTop: 'auto',
    }}>
      <div className="container">
        <div style={{
          display: 'flex',
          flexWrap: 'wrap',
          justifyContent: 'space-between',
          alignItems: 'center',
          gap: '24px',
          paddingBottom: '32px',
          borderBottom: '1px solid rgba(255, 255, 255, 0.06)'
        }}>
          <div>
            <div style={{
              fontFamily: 'var(--font-heading)',
              fontSize: '1.25rem',
              fontWeight: 700,
              color: 'var(--text-starlight)',
              marginBottom: '4px'
            }}>
              leFture
            </div>
            <p style={{ fontSize: '0.875rem', color: 'var(--text-dim)', maxWidth: '420px' }}>
              {t.footer.tagline}
            </p>
          </div>

          <nav style={{ display: 'flex', flexWrap: 'wrap', gap: '20px', fontSize: '0.875rem' }}>
            <Link to="/faq" style={{ color: 'var(--text-comet)' }}>
              {t.nav.faq}
            </Link>
            <Link to="/terms" style={{ color: 'var(--text-comet)' }}>
              {t.nav.terms}
            </Link>
            <Link to="/privacy" style={{ color: 'var(--text-comet)' }}>
              {t.nav.privacy}
            </Link>
            <Link to="/contact" style={{ color: 'var(--text-comet)' }}>
              {t.nav.contact}
            </Link>
          </nav>
        </div>

        <div style={{
          paddingTop: '24px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexWrap: 'wrap',
          gap: '12px',
          fontSize: '0.8rem',
          color: 'var(--text-dim)'
        }}>
          <div>© {new Date().getFullYear()} leFture. {t.footer.rights}</div>
          <div>{t.footer.audience}</div>
        </div>
      </div>
    </footer>
  );
};
