import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { useLanguage } from '../../i18n/LanguageContext';
import { AuthLayout } from '../../components/auth/AuthLayout';
import { AppErrorBox } from '../../components/auth/AppErrorBox';

export const ForgotPasswordPage: React.FC = () => {
  const { t } = useLanguage();
  const [email, setEmail] = useState('');
  const [error, setError] = useState<any>(null);
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const cleanEmail = email.trim();
    if (!cleanEmail) {
      setError(t('errorEmailEmpty'));
      return;
    }

    setSubmitting(true);
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(cleanEmail, {
      redirectTo: `${window.location.origin}/reset-password`,
    });
    setSubmitting(false);

    if (resetError) {
      setError(resetError);
      return;
    }
    setSubmitted(true);
  };

  if (submitted) {
    return (
      <AuthLayout
        title={t('checkInboxTitle')}
        subtitle={t('checkInboxSubtitle', { email })}
        icon="mail"
        footer={
          <div>
            <span>{t('rememberPasswordPrompt')}</span>
            <Link to="/sign-in">{t('signInLink')}</Link>
          </div>
        }
      >
        <div style={{ textAlign: 'center', padding: '1rem 0' }}>
          <p style={{ color: 'var(--comet)', fontSize: '0.92rem', lineHeight: '1.6' }}>
            {t('checkInboxInstructions')}
          </p>
          <Link to="/sign-in">
            <button type="button" className="auth-submit-btn" style={{ marginTop: '1.5rem' }}>
              {t('backToSignIn')}
            </button>
          </Link>
        </div>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout
      title={t('forgotPasswordTitle')}
      subtitle={t('forgotPasswordSubtitle')}
      icon="lock"
      backTo={{ label: t('backToSignIn'), to: '/sign-in' }}
      footer={
        <div>
          <span>{t('rememberPasswordPrompt')}</span>
          <Link to="/sign-in">{t('signInLink')}</Link>
        </div>
      }
    >
      <form className="auth-form-body" onSubmit={handleSubmit}>
        <AppErrorBox actionName="requesting password reset" rawError={error} />

        <div className="auth-input-group">
          <label className="auth-input-label" htmlFor="forgot-email-input">
            {t('emailLabel')}
          </label>
          <div className="auth-input-wrap">
            <span className="auth-input-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" />
                <polyline points="22,6 12,13 2,6" />
              </svg>
            </span>
            <input
              id="forgot-email-input"
              type="email"
              required
              autoComplete="email"
              placeholder={t('emailPlaceholder')}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="auth-input-control"
            />
          </div>
        </div>

        <button type="submit" disabled={submitting} className="auth-submit-btn">
          {submitting ? t('sendingResetLink') : t('sendResetLinkButton')}
        </button>
      </form>
    </AuthLayout>
  );
};
