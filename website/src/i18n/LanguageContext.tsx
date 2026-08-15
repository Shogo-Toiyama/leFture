import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { Locale, Translations, translations } from './translations';

interface LanguageContextType {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: Translations;
  toggleLocale: () => void;
}

const LanguageContext = createContext<LanguageContextType | undefined>(undefined);

const STORAGE_KEY = 'lefture_website_locale';

function getInitialLocale(): Locale {
  if (typeof window === 'undefined') return 'ja';
  const saved = localStorage.getItem(STORAGE_KEY) as Locale | null;
  if (saved === 'ja' || saved === 'en') return saved;
  const browserLang = navigator.language?.toLowerCase() || '';
  if (browserLang.startsWith('ja')) return 'ja';
  return 'en';
}

export const LanguageProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [locale, setLocaleState] = useState<Locale>(getInitialLocale);

  const setLocale = (newLocale: Locale) => {
    setLocaleState(newLocale);
    localStorage.setItem(STORAGE_KEY, newLocale);
    document.documentElement.lang = newLocale;
  };

  const toggleLocale = () => {
    setLocale(locale === 'ja' ? 'en' : 'ja');
  };

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  const value = {
    locale,
    setLocale,
    t: translations[locale],
    toggleLocale,
  };

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
};

export function useTranslation() {
  const context = useContext(LanguageContext);
  if (!context) {
    throw new Error('useTranslation must be used within a LanguageProvider');
  }
  return context;
}
