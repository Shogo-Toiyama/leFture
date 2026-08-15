import React, { useState, useRef, useEffect } from 'react';
import { Globe, ChevronDown, Check } from 'lucide-react';
import { useTranslation } from '../i18n/LanguageContext';
import { SUPPORTED_LANGUAGES, Locale } from '../i18n/translations';

export const LanguageDropdown: React.FC = () => {
  const { locale, setLocale } = useTranslation();
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const currentLang = SUPPORTED_LANGUAGES.find((l) => l.code === locale) || SUPPORTED_LANGUAGES[0];

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  return (
    <div ref={containerRef} style={{ position: 'relative', display: 'inline-block' }}>
      {/* Trigger Button */}
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: '8px',
          background: isOpen ? 'var(--glass-bg-high)' : 'var(--glass-bg-mid)',
          border: `1px solid ${isOpen ? 'var(--color-star-gold)' : 'var(--glass-border)'}`,
          borderRadius: '9999px',
          padding: '6px 14px',
          color: 'var(--text-starlight)',
          fontSize: '0.85rem',
          fontWeight: 600,
          cursor: 'pointer',
          whiteSpace: 'nowrap',
          transition: 'all 0.2s cubic-bezier(0.16, 1, 0.3, 1)',
          backdropFilter: 'blur(12px)',
          WebkitBackdropFilter: 'blur(12px)',
          boxShadow: isOpen ? '0 0 16px rgba(255, 179, 0, 0.2)' : 'none',
        }}
        aria-haspopup="listbox"
        aria-expanded={isOpen}
      >
        <Globe size={15} color="var(--color-star-gold)" style={{ flexShrink: 0 }} />
        <span className="lang-label">{currentLang.label}</span>
        <ChevronDown
          size={14}
          color="var(--text-dim)"
          style={{
            transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)',
            transition: 'transform 0.2s ease',
          }}
        />
      </button>

      {/* Dropdown Menu */}
      {isOpen && (
        <div
          role="listbox"
          style={{
            position: 'absolute',
            top: 'calc(100% + 8px)',
            right: 0,
            minWidth: '150px',
            background: 'rgba(21, 25, 40, 0.95)',
            backdropFilter: 'blur(20px)',
            WebkitBackdropFilter: 'blur(20px)',
            border: '1px solid rgba(255, 255, 255, 0.15)',
            borderRadius: '14px',
            padding: '6px',
            boxShadow: '0 12px 36px rgba(0, 0, 0, 0.5), 0 0 0 1px rgba(255, 179, 0, 0.1)',
            zIndex: 100,
            animation: 'fadeIn 0.18s cubic-bezier(0.16, 1, 0.3, 1) forwards',
          }}
        >
          {SUPPORTED_LANGUAGES.map((lang) => {
            const isSelected = lang.code === locale;
            return (
              <button
                key={lang.code}
                type="button"
                role="option"
                aria-selected={isSelected}
                onClick={() => {
                  setLocale(lang.code as Locale);
                  setIsOpen(false);
                }}
                style={{
                  width: '100%',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: '8px',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  background: isSelected ? 'rgba(255, 179, 0, 0.12)' : 'transparent',
                  color: isSelected ? 'var(--color-star-gold)' : 'var(--text-starlight)',
                  fontSize: '0.85rem',
                  fontWeight: isSelected ? 600 : 400,
                  cursor: 'pointer',
                  border: 'none',
                  textAlign: 'left',
                  transition: 'background 0.15s ease',
                }}
                onMouseEnter={(e) => {
                  if (!isSelected) e.currentTarget.style.background = 'rgba(255, 255, 255, 0.06)';
                }}
                onMouseLeave={(e) => {
                  if (!isSelected) e.currentTarget.style.background = 'transparent';
                }}
              >
                <span>{lang.label}</span>
                {isSelected && <Check size={14} color="var(--color-star-gold)" />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};
