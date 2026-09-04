import React from 'react';
import { Outlet, useLocation } from 'react-router-dom';
import { Header } from './Header';
import { Footer } from './Footer';
import { ScrollToTop } from './ScrollToTop';
import { DownloadModalProvider } from '../context/DownloadModalContext';

export const Layout: React.FC = () => {
  const { pathname } = useLocation();
  // The home page opens on a full-bleed hero, so it supplies its own spacing.
  const isHome = pathname === '/';

  return (
    <DownloadModalProvider>
      <div style={{
        minHeight: '100vh',
        display: 'flex',
        flexDirection: 'column',
        position: 'relative'
      }}>
        <Header />
        <main className={`site-main${isHome ? ' site-main--flush' : ''}`}>
          <Outlet />
        </main>
        <Footer />
        <ScrollToTop />
      </div>
    </DownloadModalProvider>
  );
};
