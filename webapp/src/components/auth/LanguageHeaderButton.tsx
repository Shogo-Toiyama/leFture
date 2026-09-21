import React, { useState, useRef, useEffect } from 'react';
import { useLanguage } from '../../i18n/LanguageContext';

const LANGUAGE_OPTIONS = [
  { code: 'en' as const, label: 'English' },
  { code: 'ja' as const, label: '日本語' },
];

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
          {LANGUAGE_OPTIONS.map((opt) => (
            <button
              key={opt.code}
              type="button"
              className={`language-option ${language === opt.code ? 'is-active' : ''}`}
              onClick={() => {
                setLanguage(opt.code);
                setOpen(false);
              }}
            >
              <span>{opt.label}</span>
              {language === opt.code && <span className="lang-check">✓</span>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
};
