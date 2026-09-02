import React, { useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { signInWithGoogleDirect } from '../../lib/googleAuth';
import { useLanguage } from '../../i18n/LanguageContext';
import { AuthLayout } from '../../components/auth/AuthLayout';
import { AppErrorBox } from '../../components/auth/AppErrorBox';
import { AuthDivider } from '../../components/auth/AuthDivider';
import { SocialSignInButton } from '../../components/auth/SocialSignInButton';

export const SignInPage: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { t } = useLanguage();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<any>(null);
  const [submitting, setSubmitting] = useState(false);

  const from = (location.state as { from?: Location })?.from?.pathname ?? '/';

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const cleanEmail = email.trim();
    if (!cleanEmail) {
      setError(t('errorEmailEmpty'));
      return;
    }
    if (!password) {
      setError(t('errorPasswordEmpty'));
      return;
    }

    setSubmitting(true);
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: cleanEmail,
      password,
    });
    setSubmitting(false);

    if (signInError) {
      setError(signInError);
      return;
    }
    navigate(from, { replace: true });
  };

  const handleSocialSignIn = async (provider: 'google' | 'apple') => {
    setError(null);
    if (provider === 'google') {
      try {
        setSubmitting(true);
        await signInWithGoogleDirect();
        setSubmitting(false);
        navigate(from, { replace: true });
      } catch (err: any) {
        setSubmitting(false);
        if (err?.message && !err.message.includes('popup_closed_by_user')) {
          setError(err);
        }
      }
      return;
    }

    const { error: authError } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: `${window.location.origin}/`,
        queryParams: {
          prompt: 'select_account',
        },
      },
    });
    if (authError) {
      setError(authError);
    }
  };

  return (
    <AuthLayout
      title={t('signInTitle')}
      subtitle={t('signInSubtitle')}
      icon="book"
      footer={
        <div>
          <span>{t('noAccountPrompt')}</span>
          <Link to="/sign-up">{t('createAccountLink')}</Link>
        </div>
      }
    >
      <form className="auth-form-body" onSubmit={handleSubmit}>
        <AppErrorBox actionName="signing in" rawError={error} />

        <div className="auth-input-group">
          <label className="auth-input-label" htmlFor="email-input">
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
              id="email-input"
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

        <div className="auth-input-group">
          <label className="auth-input-label" htmlFor="password-input">
            {t('passwordLabel')}
          </label>
          <div className="auth-input-wrap">
            <span className="auth-input-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
            </span>
            <input
              id="password-input"
              type={showPassword ? 'text' : 'password'}
              required
              autoComplete="current-password"
              placeholder={t('passwordPlaceholder')}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="auth-input-control"
            />
            <button
              type="button"
              className="auth-input-toggle"
              onClick={() => setShowPassword(!showPassword)}
              aria-label={showPassword ? 'Hide password' : 'Show password'}
            >
              {showPassword ? (
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
                  <line x1="1" y1="1" x2="23" y2="23" />
                </svg>
              ) : (
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                  <circle cx="12" cy="12" r="3" />
                </svg>
              )}
            </button>
          </div>
        </div>

        <div className="auth-row-actions">
          <Link to="/forgot-password" className="auth-text-link">
            {t('forgotPasswordLink')}
          </Link>
        </div>

        <button type="submit" disabled={submitting} className="auth-submit-btn">
          {submitting ? t('signingIn') : t('signInButton')}
        </button>

        <AuthDivider />

        <SocialSignInButton
          provider="google"
          disabled={submitting}
          onClick={() => handleSocialSignIn('google')}
        />

        <SocialSignInButton
          provider="apple"
          disabled={submitting}
          onClick={() => handleSocialSignIn('apple')}
        />
      </form>
    </AuthLayout>
  );
};
