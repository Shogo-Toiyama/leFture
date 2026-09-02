import React, { useState, useRef, useEffect } from 'react';
import { useLanguage } from '../../i18n/LanguageContext';

export const LanguageHeaderButton: React.FC = () => {
  const { language, setLanguage } = useLanguage();
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    };
    if (open) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [open]);

  return (
    <div className="language-header-container" ref={menuRef}>
      <button
        type="button"
        className="language-header-btn"
        onClick={() => setOpen(!open)}
        aria-label="Select Language"
        title="Change Language"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          className="language-icon"
        >
          <circle cx="12" cy="12" r="10" />
          <line x1="2" y1="12" x2="22" y2="12" />
          <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
        </svg>
        <span className="language-current-code">{language.toUpperCase()}</span>
      </button>

      {open && (
        <div className="language-dropdown-menu">
          <button
            type="button"
            className={`language-option ${language === 'en' ? 'is-active' : ''}`}
            onClick={() => {
              setLanguage('en');
              setOpen(false);
            }}
          >
            <span>English</span>
            {language === 'en' && <span className="lang-check">✓</span>}
          </button>
          <button
            type="button"
            className={`language-option ${language === 'ja' ? 'is-active' : ''}`}
            onClick={() => {
              setLanguage('ja');
              setOpen(false);
            }}
          >
            <span>日本語</span>
            {language === 'ja' && <span className="lang-check">✓</span>}
          </button>
        </div>
      )}
    </div>
  );
};
