import React, { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AuthLayout } from '../../components/auth/AuthLayout';
import { AppErrorBox } from '../../components/auth/AppErrorBox';
import { useAuth } from '../../auth/AuthProvider';
import { useProfile } from '../../hooks/useProfile';
import { useLanguage } from '../../i18n/LanguageContext';
import { supabase } from '../../lib/supabase';
import { deleteAccount, hasEmailIdentity, waitUntilBackendReady } from '../../lib/account';

export const DeleteAccountPage: React.FC = () => {
  const { user } = useAuth();
  const { profile, loading: profileLoading } = useProfile();
  const { t } = useLanguage();
  const navigate = useNavigate();

  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [usernameInput, setUsernameInput] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<any>(null);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);

  // Flutter版と同様、画面表示時にバックグラウンドでCloud Runのウォームアップを開始
  const warmupPromiseRef = useRef<Promise<boolean> | null>(null);
  useEffect(() => {
    warmupPromiseRef.current = waitUntilBackendReady(45000);
  }, []);

  const isEmailUser = hasEmailIdentity(user);
  const currentUsername = profile?.username ?? '';

  // 入力値バリデーション (Flutter版 my_account_page.dart:1435-1439 準拠)
  const isInputValid = isEmailUser
    ? password.trim().length > 0
    : currentUsername.length > 0 && usernameInput.trim() === currentUsername;

  const handleDelete = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!isInputValid || isSubmitting) return;

    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      // 1. バックエンド起動待機
      setStatusMessage(t('deleteAccountWakingBackendStatus'));
      const isServerReady = warmupPromiseRef.current ? await warmupPromiseRef.current : await waitUntilBackendReady(45000);
      if (!isServerReady) {
        setIsSubmitting(false);
        setStatusMessage(null);
        setErrorMessage(t('deleteAccountSlowBackendError'));
        return;
      }

      // 2. アカウント削除処理
      setStatusMessage(t('deleteAccountDeletingStatus'));
      if (isEmailUser) {
        await deleteAccount(user?.email ?? undefined, password);
      } else {
        await deleteAccount();
      }

      // 3. 削除完了画面へ遷移
      navigate('/account-deleted', { replace: true });
    } catch (err: any) {
      setIsSubmitting(false);
      setStatusMessage(null);
      setErrorMessage(err);
    }
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    navigate('/sign-in', { replace: true });
  };

  return (
    <AuthLayout
      title={t('deleteAccountTitle')}
      subtitle={t('deleteAccountSubtitle')}
      icon="trash"
      glowVariant="danger"
      footer={
        <div style={{ textAlign: 'center' }}>
          <button
            type="button"
            className="link-button"
            onClick={handleSignOut}
            disabled={isSubmitting}
            style={{ color: 'var(--text-comet)', fontSize: '0.875rem' }}
          >
            {t('backToSignIn')}
          </button>
        </div>
      }
    >
      <form onSubmit={handleDelete} style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
        {/* Error box */}
        <AppErrorBox actionName="deleting your account" rawError={errorMessage} />

        {/* Status indicator (Waking up / Deleting) */}
        {statusMessage && (
          <div
            style={{
              padding: '0.75rem 1rem',
              borderRadius: '10px',
              background: 'rgba(229, 57, 53, 0.1)',
              border: '1px solid rgba(229, 57, 53, 0.35)',
              color: '#ff8b85',
              fontSize: '0.875rem',
              textAlign: 'center',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px',
            }}
          >
            <div
              style={{
                width: '14px',
                height: '14px',
                border: '2px solid rgba(229, 57, 53, 0.25)',
                borderTopColor: '#ff8b85',
                borderRadius: '50%',
                animation: 'spin 0.8s linear infinite',
              }}
            />
            <span>{statusMessage}</span>
          </div>
        )}

        {/* User identification info */}
        <div
          style={{
            padding: '0.875rem 1rem',
            background: 'rgba(255, 255, 255, 0.04)',
            borderRadius: '12px',
            border: '1px solid var(--glass-border)',
            fontSize: '0.875rem',
            color: 'var(--text-starlight)',
          }}
        >
          <span style={{ color: 'var(--text-comet)', display: 'block', fontSize: '0.75rem', marginBottom: '4px' }}>
            {t('emailLabel')} / ID
          </span>
          <strong>{user?.email ?? user?.id ?? '—'}</strong>
          {currentUsername && (
            <div style={{ marginTop: '4px', fontSize: '0.8125rem', color: 'var(--text-comet)' }}>
              {t('usernameLabel')}: <span style={{ color: 'var(--text-starlight)' }}>{currentUsername}</span>
            </div>
          )}
        </div>

        {/* Warning message (Flutter deleteAccountDialogWarningMessage) */}
        <div
          style={{
            padding: '1rem',
            background: 'rgba(229, 57, 53, 0.08)',
            border: '1px solid rgba(229, 57, 53, 0.3)',
            borderRadius: '12px',
            fontSize: '0.875rem',
            lineHeight: '1.5',
            color: 'var(--text-starlight)',
          }}
        >
          <div style={{ fontWeight: 600, color: '#ff8b85', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '6px' }}>
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
              <line x1="12" y1="9" x2="12" y2="13" />
              <line x1="12" y1="17" x2="12.01" y2="17" />
            </svg>
            Permanent Action
          </div>
          <p style={{ margin: 0, color: 'var(--text-comet)' }}>
            {t('deleteAccountWarningMessage')}
          </p>
        </div>

        {/* Identity-based Confirmation Input */}
        {isEmailUser ? (
          <div className="auth-input-group" style={{ marginBottom: 0 }}>
            <label className="auth-input-label" htmlFor="delete-account-password">
              {t('deleteAccountPasswordPrompt')}
            </label>
            <div className="auth-input-wrap">
              <span className="auth-input-icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                  <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                </svg>
              </span>
              <input
                id="delete-account-password"
                type={showPassword ? 'text' : 'password'}
                required
                autoComplete="current-password"
                placeholder={t('deleteAccountPasswordPlaceholder')}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={isSubmitting}
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
        ) : (
          <div className="auth-input-group" style={{ marginBottom: 0 }}>
            <label className="auth-input-label" htmlFor="delete-account-username">
              {profileLoading ? t('loading') : t('deleteAccountUsernamePrompt', { username: currentUsername })}
            </label>
            <div className="auth-input-wrap">
              <span className="auth-input-icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                  <circle cx="12" cy="7" r="4" />
                </svg>
              </span>
              <input
                id="delete-account-username"
                type="text"
                required
                autoComplete="off"
                placeholder={t('deleteAccountUsernamePlaceholder')}
                value={usernameInput}
                onChange={(e) => setUsernameInput(e.target.value)}
                disabled={isSubmitting || profileLoading}
                className="auth-input-control"
              />
            </div>
          </div>
        )}

        {/* Confirmation Submit Button */}
        <button
          type="submit"
          disabled={!isInputValid || isSubmitting}
          className="danger block"
          style={{
            padding: '0.875rem 1.25rem',
            borderRadius: '12px',
            fontWeight: 600,
            cursor: !isInputValid || isSubmitting ? 'not-allowed' : 'pointer',
            marginTop: '0.5rem',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '8px',
          }}
        >
          {isSubmitting ? (
            <>
              <div
                style={{
                  width: '16px',
                  height: '16px',
                  border: '2px solid rgba(255, 255, 255, 0.3)',
                  borderTopColor: '#ffffff',
                  borderRadius: '50%',
                  animation: 'spin 0.8s linear infinite',
                }}
              />
              <span>{t('deleteAccountDeletingStatus')}</span>
            </>
          ) : (
            t('deleteAccountConfirmButton')
          )}
        </button>
      </form>
    </AuthLayout>
  );
};
