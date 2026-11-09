import React, { Suspense, useEffect } from 'react';
import { Outlet } from 'react-router-dom';
import { useProfile } from '../hooks/useProfile';
import { useLanguage } from '../i18n/LanguageContext';
import { isLanguage } from '../i18n/translations';
import { PageState } from './PageState';
import { AppTopbar } from './AppTopbar';

export const Layout: React.FC = () => {
  const { profile } = useProfile();
  const { language, setLanguage } = useLanguage();

  useEffect(() => {
    const profLang = profile?.metadata?.display_language;
    if (isLanguage(profLang) && profLang !== language) {
      setLanguage(profLang);
    }
  }, [profile?.metadata?.display_language, language, setLanguage]);

  return (
    <div className="app-shell">
      <AppTopbar />

      <main className="app-main">
        <Suspense fallback={<PageState kind="loading" />}>
          <Outlet />
        </Suspense>
      </main>
    </div>
  );
};
