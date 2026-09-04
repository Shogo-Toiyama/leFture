import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { signInWithGoogleDirect } from '../../lib/googleAuth';
import { useLanguage } from '../../i18n/LanguageContext';
import { AuthLayout } from '../../components/auth/AuthLayout';
import { AppErrorBox } from '../../components/auth/AppErrorBox';
import { SocialSignInButton } from '../../components/auth/SocialSignInButton';
import { PasswordStrengthMeter } from '../../components/auth/PasswordStrengthMeter';

export const SignUpPage: React.FC = () => {
  const navigate = useNavigate();
  const { t } = useLanguage();
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [agreedToTerms, setAgreedToTerms] = useState(false);
  const [isEmailExpanded, setIsEmailExpanded] = useState(false);
  const [error, setError] = useState<any>(null);
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const validateCommonFields = () => {
    setError(null);
    const cleanUsername = username.trim();
    if (!cleanUsername) {
      setError(t('errorUsernameEmpty'));
      return false;
    }
    if (!agreedToTerms) {
      setError(t('errorAgreeTerms'));
      return false;
    }
    return true;
  };

  const handleEmailSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateCommonFields()) return;

    const cleanEmail = email.trim();
    if (!cleanEmail) {
      setError(t('errorEmailEmpty'));
      return;
    }
    if (password.length < 8) {
      setError(t('errorPasswordTooShort'));
      return;
    }
    if (password !== confirmPassword) {
      setError(t('errorPasswordsMismatch'));
      return;
    }

    setSubmitting(true);
    const { error: signUpError } = await supabase.auth.signUp({
      email: cleanEmail,
      password,
      options: {
        data: {
          username: username.trim(),
        },
      },
    });
    setSubmitting(false);

    if (signUpError) {
      setError(signUpError);
      return;
    }
    setSubmitted(true);
  };

  const handleSocialSignUp = async (provider: 'google' | 'apple') => {
    if (!validateCommonFields()) return;

    if (provider === 'google') {
      try {
        setSubmitting(true);
        await signInWithGoogleDirect();
        setSubmitting(false);
        navigate('/onboarding', { replace: true });
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
        redirectTo: `${window.location.origin}/onboarding`,
        queryParams: {
          prompt: 'select_account',
        },
      },
    });
    if (authError) {
      setError(authError);
    }
  };

  if (submitted) {
    return (
      <AuthLayout
        title={t('checkEmailTitle')}
        subtitle={t('checkEmailSubtitle', { email })}
        icon="mail"
        footer={
          <div>
            <span>{t('alreadyConfirmedPrompt')}</span>
            <Link to="/sign-in">{t('signInLink')}</Link>
          </div>
        }
      >
        <div style={{ textAlign: 'center', padding: '1rem 0' }}>
          <p style={{ color: 'var(--comet)', fontSize: '0.92rem', lineHeight: '1.6' }}>
            {t('checkEmailSpamNote')}
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
      title={t('signUpTitle')}
      subtitle={t('signUpSubtitle')}
      icon="rocket"
      footer={
        <div>
          <span>{t('hasAccountPrompt')}</span>
          <Link to="/sign-in">{t('signInLink')}</Link>
        </div>
      }
    >
      <div className="auth-form-body">
        <AppErrorBox actionName="creating account" rawError={error} />

        {/* ユーザーネーム(どのサインアップ方法でも必須) */}
        <div className="auth-input-group">
          <label className="auth-input-label" htmlFor="username-input">
            {t('usernameLabel')}
          </label>
          <div className="auth-input-wrap">
            <span className="auth-input-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                <circle cx="12" cy="7" r="4" />
              </svg>
            </span>
            <input
              id="username-input"
              type="text"
              required
              placeholder={t('usernamePlaceholder')}
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="auth-input-control"
            />
          </div>
        </div>

        {/* 利用規約チェックボックス(どのサインアップ方法でも必須) */}
        <label
          className="auth-checkbox-wrap"
          style={{
            display: 'flex',
            flexDirection: 'row',
            alignItems: 'flex-start',
            gap: '0.75rem',
            marginTop: '0.25rem',
            marginBottom: '0.5rem',
            cursor: 'pointer',
          }}
        >
          <input
            type="checkbox"
            checked={agreedToTerms}
            onChange={(e) => setAgreedToTerms(e.target.checked)}
            style={{
              width: 18,
              height: 18,
              minWidth: 18,
              maxWidth: 18,
              minHeight: 18,
              maxHeight: 18,
              flexShrink: 0,
              marginTop: 3,
            }}
          />
          <span className="auth-checkbox-label">
            {t('agreementPrefix')}
            <a href="https://lefture.com/terms" target="_blank" rel="noopener noreferrer">
              {t('termsAndConditionsLink')}
            </a>
            {t('agreementMiddle')}
            <a href="https://lefture.com/privacy" target="_blank" rel="noopener noreferrer">
              {t('privacyPolicyLink')}
            </a>
            {t('agreementSuffix')}
          </span>
        </label>

        {/* Google / Apple / Email を対等な選択肢として並べる */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
          <SocialSignInButton
            provider="google"
            disabled={submitting}
            onClick={() => handleSocialSignUp('google')}
          />

          <SocialSignInButton
            provider="apple"
            disabled={submitting}
            onClick={() => handleSocialSignUp('apple')}
          />

          <SocialSignInButton
            provider="email"
            disabled={submitting}
            onClick={() => {
              setError(null);
              setIsEmailExpanded(!isEmailExpanded);
            }}
          />
        </div>

        {/* メール登録アコーディオン */}
        {isEmailExpanded && (
          <form
            onSubmit={handleEmailSignUp}
            style={{
              display: 'flex',
              flexDirection: 'column',
              gap: '1rem',
              marginTop: '0.5rem',
              paddingTop: '1rem',
              borderTop: '1px solid var(--glass-border)',
            }}
          >
            <div className="auth-input-group">
              <label className="auth-input-label" htmlFor="signup-email-input">
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
                  id="signup-email-input"
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
              <label className="auth-input-label" htmlFor="signup-password-input">
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
                  id="signup-password-input"
                  type={showPassword ? 'text' : 'password'}
                  required
                  autoComplete="new-password"
                  placeholder="At least 8 characters"
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
              <PasswordStrengthMeter password={password} />
            </div>

            <div className="auth-input-group">
              <label className="auth-input-label" htmlFor="confirm-password-input">
                {t('confirmPasswordLabel')}
              </label>
              <div className="auth-input-wrap">
                <span className="auth-input-icon">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                    <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                  </svg>
                </span>
                <input
                  id="confirm-password-input"
                  type={showConfirmPassword ? 'text' : 'password'}
                  required
                  autoComplete="new-password"
                  placeholder={t('confirmPasswordPlaceholder')}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  className="auth-input-control"
                />
                <button
                  type="button"
                  className="auth-input-toggle"
                  onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                  aria-label={showConfirmPassword ? 'Hide password' : 'Show password'}
                >
                  {showConfirmPassword ? (
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

            <button type="submit" disabled={submitting} className="auth-submit-btn">
              {submitting ? t('creatingAccount') : t('signUpButton')}
            </button>
          </form>
        )}
      </div>
    </AuthLayout>
  );
};
