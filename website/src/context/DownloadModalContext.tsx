import React, { createContext, useContext, useState, useCallback, useEffect } from 'react';
import { useTranslation } from '../i18n/LanguageContext';
import { AppleLogo } from '../components/AppleLogo';
import { AndroidLogo } from '../components/AndroidLogo';
import { APP_STORE_URL } from '../lib/links';
import { X, ChevronRight, Sparkles, Clock } from 'lucide-react';
import './download-modal.css';

interface DownloadModalContextValue {
  isOpen: boolean;
  openModal: () => void;
  closeModal: () => void;
}

const DownloadModalContext = createContext<DownloadModalContextValue | null>(null);

export const DownloadModalProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isOpen, setIsOpen] = useState(false);
  const { t } = useTranslation();

  const openModal = useCallback(() => setIsOpen(true), []);
  const closeModal = useCallback(() => setIsOpen(false), []);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        closeModal();
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
  }, [isOpen, closeModal]);

  return (
    <DownloadModalContext.Provider value={{ isOpen, openModal, closeModal }}>
      {children}
      {isOpen && (
        <div
          className="download-modal-overlay"
          onClick={closeModal}
          role="dialog"
          aria-modal="true"
          aria-labelledby="download-modal-title"
        >
          <div
            className="download-modal-card"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Mobile Sheet indicator bar */}
            <div className="download-modal-sheet-bar" aria-hidden="true" />

            {/* Close button */}
            <button
              type="button"
              className="download-modal-close"
              onClick={closeModal}
              aria-label="Close modal"
            >
              <X size={18} />
            </button>

            {/* Header */}
            <div className="download-modal-header">
              <h2 id="download-modal-title" className="download-modal-title">
                {t.downloadModal.title}
              </h2>
              <p className="download-modal-subtitle">
                {t.downloadModal.subtitle}
              </p>
            </div>

            {/* Platform selection */}
            <div className="download-modal-platforms">
              {/* iOS Card */}
              <a
                href={APP_STORE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="platform-card platform-card--ios"
                onClick={closeModal}
              >
                <div className="platform-card-icon platform-card-icon--ios">
                  <AppleLogo size={28} />
                </div>
                <div className="platform-card-content">
                  <div className="platform-card-top">
                    <span className="platform-card-name">
                      {t.downloadModal.iosTitle}
                    </span>
                    <span className="platform-badge platform-badge--active">
                      <Sparkles size={11} />
                      {t.downloadModal.iosBadge}
                    </span>
                  </div>
                  <p className="platform-card-desc">
                    {t.downloadModal.iosDesc}
                  </p>
                </div>
                <div className="platform-card-action">
                  <ChevronRight size={18} />
                </div>
              </a>

              {/* Android Card (Disabled / Closed Beta Coming Soon) */}
              <div
                className="platform-card platform-card--android-disabled"
                role="region"
                aria-label="Android coming soon"
              >
                <div className="platform-card-icon platform-card-icon--android">
                  <AndroidLogo size={28} />
                </div>
                <div className="platform-card-content">
                  <div className="platform-card-top">
                    <span className="platform-card-name">
                      {t.downloadModal.androidTitle}
                    </span>
                    <span className="platform-badge platform-badge--inactive">
                      <Clock size={11} />
                      {t.downloadModal.androidBadge}
                    </span>
                  </div>
                  <p className="platform-card-desc">
                    {t.downloadModal.androidDesc}
                  </p>
                </div>
              </div>
            </div>

            {/* Note */}
            <p className="download-modal-note">
              {t.downloadModal.note}
            </p>
          </div>
        </div>
      )}
    </DownloadModalContext.Provider>
  );
};

export const useDownloadModal = (): DownloadModalContextValue => {
  const context = useContext(DownloadModalContext);
  if (!context) {
    throw new Error('useDownloadModal must be used within DownloadModalProvider');
  }
  return context;
};
