import React, { Suspense, lazy } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { LanguageProvider } from './i18n/LanguageContext';
import { Layout } from './components/Layout';
import { HomePage } from './pages/HomePage';

// Lazy-load secondary pages so Supabase & form code are only downloaded on demand
const TermsPage = lazy(() =>
  import('./pages/TermsPage').then((m) => ({ default: m.TermsPage }))
);
const PrivacyPage = lazy(() =>
  import('./pages/PrivacyPage').then((m) => ({ default: m.PrivacyPage }))
);
const ContactPage = lazy(() =>
  import('./pages/ContactPage').then((m) => ({ default: m.ContactPage }))
);
const FaqPage = lazy(() =>
  import('./pages/FaqPage').then((m) => ({ default: m.FaqPage }))
);
const GalaxyScreenshotPage = lazy(() =>
  import('./pages/GalaxyScreenshotPage').then((m) => ({ default: m.GalaxyScreenshotPage }))
);

const PageLoader: React.FC = () => (
  <div
    style={{
      minHeight: '60vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: 'var(--text-comet)',
    }}
  >
    <div
      style={{
        width: '24px',
        height: '24px',
        border: '2px solid rgba(255, 179, 0, 0.2)',
        borderTopColor: 'var(--accent)',
        borderRadius: '50%',
        animation: 'spin 0.8s linear infinite',
      }}
    />
    <style>{`
      @keyframes spin {
        to { transform: rotate(360deg); }
      }
    `}</style>
  </div>
);

export const App: React.FC = () => {
  return (
    <LanguageProvider>
      <BrowserRouter>
        <Routes>
          {/* Temporary full-screen Galaxy page for screenshots (no header/footer) */}
          <Route
            path="galaxy"
            element={
              <Suspense fallback={<PageLoader />}>
                <GalaxyScreenshotPage />
              </Suspense>
            }
          />
          <Route path="/" element={<Layout />}>
            <Route index element={<HomePage />} />
            <Route
              path="terms"
              element={
                <Suspense fallback={<PageLoader />}>
                  <TermsPage />
                </Suspense>
              }
            />
            <Route
              path="privacy"
              element={
                <Suspense fallback={<PageLoader />}>
                  <PrivacyPage />
                </Suspense>
              }
            />
            <Route
              path="contact"
              element={
                <Suspense fallback={<PageLoader />}>
                  <ContactPage />
                </Suspense>
              }
            />
            <Route
              path="faq"
              element={
                <Suspense fallback={<PageLoader />}>
                  <FaqPage />
                </Suspense>
              }
            />
            {/* Catch-all to Home */}
            <Route path="*" element={<HomePage />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </LanguageProvider>
  );
};
