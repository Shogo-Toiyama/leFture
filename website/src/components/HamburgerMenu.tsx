import React, { useState, useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
import { Link, useLocation } from 'react-router-dom';
import { useTranslation } from '../i18n/LanguageContext';
import { useDownloadModal } from '../context/DownloadModalContext';
import {
  Menu,
  X,
  HelpCircle,
  FileText,
  Shield,
  Mail,
  Home,
  ChevronRight,
  Smartphone,
} from 'lucide-react';
import './hamburger-menu.css';

export const HamburgerMenu: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const location = useLocation();
  const { t } = useTranslation();
  const { openModal } = useDownloadModal();

  const closeMenu = useCallback(() => {
    setIsOpen(false);
  }, []);

  const toggleMenu = useCallback(() => {
    setIsOpen((prev) => !prev);
  }, []);

  // Close menu on route changes
  useEffect(() => {
    closeMenu();
  }, [location.pathname, closeMenu]);

  // Lock body scroll and listen for Escape key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        closeMenu();
      }
    };

    if (isOpen) {
      document.body.style.overflow = 'hidden';
      window.addEventListener('keydown', handleKeyDown);
    } else {
      document.body.style.overflow = '';
    }

    return () => {
      document.body.style.overflow = '';
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [isOpen, closeMenu]);

  const navItems = [
    {
      to: '/',
      label: t.nav.home,
      icon: Home,
    },
    {
      to: '/faq',
      label: t.nav.faq,
      icon: HelpCircle,
    },
    {
      to: '/terms',
      label: t.nav.terms,
      icon: FileText,
    },
    {
      to: '/privacy',
      label: t.nav.privacy,
      icon: Shield,
    },
    {
      to: '/contact',
      label: t.nav.contact,
      icon: Mail,
    },
  ];

  const drawerContent = (
    <>
      {/* Backdrop covering entire screen */}
      <div
        className={`nav-drawer-backdrop${isOpen ? ' is-open' : ''}`}
        onClick={closeMenu}
        aria-hidden="true"
      />

      {/* Slide-over Drawer / Fullscreen Panel */}
      <aside
        id="site-navigation-drawer"
        className={`nav-drawer-panel${isOpen ? ' is-open' : ''}`}
        role="dialog"
        aria-modal="true"
        aria-label="Navigation Menu"
      >
        {/* Drawer Header */}
        <div className="nav-drawer-header">
          <Link to="/" className="nav-drawer-brand" onClick={closeMenu}>
            <img
              src="/img/app-icon.webp?v=2"
              alt="leFture"
              width="32"
              height="32"
              className="nav-drawer-brand-img"
            />
            <span className="nav-drawer-brand-text">leFture</span>
          </Link>
          <button
            type="button"
            className="nav-drawer-close-btn"
            onClick={closeMenu}
            aria-label="Close menu"
          >
            <X size={20} />
          </button>
        </div>

        {/* Navigation Items */}
        <nav className="nav-drawer-content" aria-label="Main menu">
          <div className="nav-drawer-section-label">Menu</div>
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = location.pathname === item.to;
            return (
              <Link
                key={item.to}
                to={item.to}
                className={`nav-drawer-link${isActive ? ' is-active' : ''}`}
                onClick={closeMenu}
              >
                <div className="nav-drawer-link-left">
                  <span className="nav-drawer-link-icon">
                    <Icon size={18} />
                  </span>
                  <span className="nav-drawer-link-text">{item.label}</span>
                </div>
                <ChevronRight size={18} className="nav-drawer-link-arrow" />
              </Link>
            );
          })}
        </nav>

        {/* Drawer Footer CTA */}
        <div className="nav-drawer-footer">
          <button
            type="button"
            className="btn-primary nav-drawer-cta-btn"
            onClick={() => {
              closeMenu();
              openModal();
            }}
          >
            <Smartphone size={16} />
            <span>{t.nav.downloadApp}</span>
          </button>
          <div className="nav-drawer-copyright">
            © {new Date().getFullYear()} leFture
          </div>
        </div>
      </aside>
    </>
  );

  return (
    <>
      {/* Hamburger Trigger Button */}
      <button
        type="button"
        className={`hamburger-toggle-btn${isOpen ? ' is-active' : ''}`}
        onClick={toggleMenu}
        aria-label="Navigation Menu"
        aria-expanded={isOpen}
        aria-controls="site-navigation-drawer"
      >
        <Menu size={20} />
      </button>

      {/* Render drawer into document.body via Portal to escape header clipping & backdrop-filter context */}
      {typeof document !== 'undefined' ? createPortal(drawerContent, document.body) : null}
    </>
  );
};
