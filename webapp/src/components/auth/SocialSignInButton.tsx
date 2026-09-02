import React from 'react';
import { useLanguage } from '../../i18n/LanguageContext';

export type SocialProvider = 'google' | 'apple' | 'email';

interface SocialSignInButtonProps {
  provider: SocialProvider;
  onClick: () => void;
  disabled?: boolean;
}

export const SocialSignInButton: React.FC<SocialSignInButtonProps> = ({
  provider,
  onClick,
  disabled = false,
}) => {
  const { t } = useLanguage();

  const getLabel = () => {
    switch (provider) {
      case 'google':
        return t('continueWithGoogle');
      case 'apple':
        return t('continueWithApple');
      case 'email':
        return t('continueWithEmail');
    }
  };

  const renderIcon = () => {
    switch (provider) {
      case 'google':
        return (
          <svg className="social-icon" viewBox="0 0 48 48">
            <path
              fill="#4285F4"
              d="M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z"
            />
            <path
              fill="#34A853"
              d="M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z"
            />
            <path
              fill="#FBBC05"
              d="M11.69 28.18c-.44-1.32-.69-2.73-.69-4.18s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z"
            />
            <path
              fill="#EA4335"
              d="M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z"
            />
          </svg>
        );
      case 'apple':
        return (
          <svg className="social-icon apple-icon" viewBox="0 0 24 24" fill="currentColor">
            <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.37c.61-.75 1.04-1.8 0.92-2.87-.93.04-2.02.63-2.66 1.38-.56.65-1.06 1.7-0.93 2.73 1.05.08 2.07-.49 2.67-1.24z" />
          </svg>
        );
      case 'email':
        return (
          <svg className="social-icon email-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" />
            <polyline points="22,6 12,13 2,6" />
          </svg>
        );
    }
  };

  return (
    <button
      type="button"
      className={`social-signin-btn ${provider}`}
      onClick={onClick}
      disabled={disabled}
    >
      {renderIcon()}
      <span className="social-signin-label">{getLabel()}</span>
    </button>
  );
};
