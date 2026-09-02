import React from 'react';
import { useLanguage } from '../../i18n/LanguageContext';

interface AuthDividerProps {
  label?: string;
}

export const AuthDivider: React.FC<AuthDividerProps> = ({ label }) => {
  const { t } = useLanguage();
  const displayLabel = label ?? t('or');

  return (
    <div className="auth-divider">
      <div className="auth-divider-line" />
      <span className="auth-divider-text">{displayLabel}</span>
      <div className="auth-divider-line" />
    </div>
  );
};
