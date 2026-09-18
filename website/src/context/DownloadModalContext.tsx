import React, { createContext, useContext, useState, useCallback, useEffect } from 'react';
import { useTranslation } from '../i18n/LanguageContext';
import { AppleLogo } from '../components/AppleLogo';
import { AndroidLogo } from '../components/AndroidLogo';
import { APP_STORE_URL } from '../lib/links';
import { X, ChevronRight, ArrowLeft, CheckCircle2, Loader2, AlertCircle } from 'lucide-react';
import './download-modal.css';

interface DownloadModalContextValue {
  isOpen: boolean;
  openModal: () => void;
  closeModal: () => void;
}

const DownloadModalContext = createContext<DownloadModalContextValue | null>(null);

type ModalViewState = 'select' | 'android_form' | 'success';

export const DownloadModalProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [viewState, setViewState] = useState<ModalViewState>('select');
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const { t, locale } = useTranslation();

  const resetForm = useCallback(() => {
    setViewState('select');
    setEmail('');
    setName('');
    setIsSubmitting(false);
    setErrorMsg(null);
  }, []);

  const openModal = useCallback(() => {
    resetForm();
    setIsOpen(true);
  }, [resetForm]);

  const closeModal = useCallback(() => {
    setIsOpen(false);
    resetForm();
  }, [resetForm]);

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

  const handleSubmitSignup = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmedEmail = email.trim();
    if (!trimmedEmail || !trimmedEmail.includes('@')) {
      setErrorMsg(t.downloadModal.form.errorEmail);
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const res = await fetch('/api/closed-test-signup', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email: trimmedEmail,
          name: name.trim(),
          lang: locale,
        }),
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error || t.downloadModal.form.errorGeneric);
      }

      setViewState('success');
    } catch (err: any) {
      setErrorMsg(err.message || t.downloadModal.form.errorGeneric);
    } finally {
      setIsSubmitting(false);
    }
  };

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

            {/* Back button (when in form state) */}
            {viewState === 'android_form' && (
              <button
                type="button"
                className="download-modal-back"
                onClick={() => {
                  setErrorMsg(null);
                  setViewState('select');
                }}
                aria-label={t.downloadModal.form.back}
              >
                <ArrowLeft size={16} />
                <span>{t.downloadModal.form.back}</span>
              </button>
            )}

            {/* Close button */}
            <button
              type="button"
              className="download-modal-close"
              onClick={closeModal}
              aria-label="Close modal"
            >
              <X size={18} />
            </button>

            {/* State 1: Select Platform */}
            {viewState === 'select' && (
              <>
                <div className="download-modal-header">
                  <h2 id="download-modal-title" className="download-modal-title">
                    {t.downloadModal.title}
                  </h2>
                  <p className="download-modal-subtitle">
                    {t.downloadModal.subtitle}
                  </p>
                </div>

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
                      </div>
                      <p className="platform-card-desc">
                        {t.downloadModal.iosDesc}
                      </p>
                    </div>
                    <div className="platform-card-action">
                      <ChevronRight size={18} />
                    </div>
                  </a>

                  {/* Android Card (Active: click opens signup form) */}
                  <button
                    type="button"
                    className="platform-card platform-card--android"
                    onClick={() => setViewState('android_form')}
                  >
                    <div className="platform-card-icon platform-card-icon--android">
                      <AndroidLogo size={28} />
                    </div>
                    <div className="platform-card-content">
                      <div className="platform-card-top">
                        <span className="platform-card-name">
                          {t.downloadModal.androidTitle}
                        </span>
                      </div>
                      <p className="platform-card-desc">
                        {t.downloadModal.androidDesc}
                      </p>
                    </div>
                    <div className="platform-card-action">
                      <ChevronRight size={18} />
                    </div>
                  </button>
                </div>

                <p className="download-modal-note">
                  {t.downloadModal.note}
                </p>
              </>
            )}

            {/* State 2: Android Closed Beta Signup Form */}
            {viewState === 'android_form' && (
              <div className="download-modal-form-wrap">
                <div className="download-modal-header download-modal-header--form">
                  <h2 id="download-modal-title" className="download-modal-title">
                    {t.downloadModal.form.title}
                  </h2>
                  <p className="download-modal-subtitle">
                    {t.downloadModal.form.subtitle}
                  </p>
                </div>

                <form onSubmit={handleSubmitSignup} className="download-modal-form">
                  {errorMsg && (
                    <div className="download-form-alert download-form-alert--error" role="alert">
                      <AlertCircle size={16} />
                      <span>{errorMsg}</span>
                    </div>
                  )}

                  <div className="download-form-group">
                    <label htmlFor="beta-email" className="download-form-label">
                      {t.downloadModal.form.emailLabel} <span className="download-form-required">*</span>
                    </label>
                    <input
                      id="beta-email"
                      type="email"
                      required
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder={t.downloadModal.form.emailPlaceholder}
                      className="download-form-input"
                      autoFocus
                    />
                    <span className="download-form-hint">
                      {t.downloadModal.form.emailHint}
                    </span>
                  </div>

                  <div className="download-form-group">
                    <label htmlFor="beta-name" className="download-form-label">
                      {t.downloadModal.form.nameLabel}
                    </label>
                    <input
                      id="beta-name"
                      type="text"
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      placeholder={t.downloadModal.form.namePlaceholder}
                      className="download-form-input"
                    />
                  </div>

                  <button
                    type="submit"
                    disabled={isSubmitting}
                    className="download-form-submit"
                  >
                    {isSubmitting ? (
                      <>
                        <Loader2 size={16} className="download-form-spinner" />
                        <span>{t.downloadModal.form.submitting}</span>
                      </>
                    ) : (
                      <span>{t.downloadModal.form.submitButton}</span>
                    )}
                  </button>
                </form>
              </div>
            )}

            {/* State 3: Success Confirmation */}
            {viewState === 'success' && (
              <div className="download-modal-success-wrap">
                <div className="download-modal-success-icon">
                  <CheckCircle2 size={48} />
                </div>
                <h2 className="download-modal-title">
                  {t.downloadModal.form.successTitle}
                </h2>
                <p className="download-modal-subtitle download-modal-success-text">
                  {t.downloadModal.form.successMessage}
                </p>
                <div className="download-modal-success-box">
                  <span className="download-modal-success-email">{email}</span>
                </div>
                <button
                  type="button"
                  className="download-form-submit download-form-submit--done"
                  onClick={closeModal}
                >
                  {t.downloadModal.form.closeButton}
                </button>
              </div>
            )}
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
