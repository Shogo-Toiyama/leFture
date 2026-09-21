import React, { useState } from 'react';
import { AdaptiveSheet } from '../modals/AdaptiveSheet';
import { Modal } from '../Modal';
import { supabase } from '../../lib/supabase';
import { deleteAccount, hasEmailIdentity } from '../../lib/account';
import { useNavigate } from 'react-router-dom';
import { useLanguage } from '../../i18n/LanguageContext';
import type { User } from '@supabase/supabase-js';
import type { UserProfile } from '../../types/profile';

// ── 1. Change Password Sheet ──────────────────────────────────────────
export const ChangePasswordSheet: React.FC<{
  open: boolean;
  onClose: () => void;
}> = ({ open, onClose }) => {
  const { t } = useLanguage();

  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newPassword !== confirmPassword) {
      setError(t('passwordsDoNotMatch'));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const { error: updateError } = await supabase.auth.updateUser({ password: newPassword });
      if (updateError) throw updateError;
      setSuccess(true);
      setTimeout(() => {
        setSuccess(false);
        setNewPassword('');
        setConfirmPassword('');
        onClose();
      }, 1200);
    } catch (err) {
      setError(err instanceof Error ? err.message : t('failedToUpdatePassword'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <AdaptiveSheet
      open={open}
      onClose={onClose}
      title={t('changePasswordTitle')}
      subtitle={t('changePasswordSubtitle')}
    >
      <form className="sheet-form" onSubmit={handleSubmit}>
        {error && <p className="auth-error">{error}</p>}
        {success && <p className="auth-success">{t('passwordUpdatedSuccess')}</p>}

        <div className="sheet-form-field">
          <label className="sheet-field-label">{t('newPasswordLabel')}</label>
          <input
            type="password"
            className="sheet-input"
            required
            minLength={8}
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            placeholder={t('newPasswordPlaceholder')}
          />
        </div>

        <div className="sheet-form-field">
          <label className="sheet-field-label">{t('confirmNewPasswordLabel')}</label>
          <input
            type="password"
            className="sheet-input"
            required
            minLength={8}
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            placeholder={t('confirmNewPasswordPlaceholder')}
          />
        </div>

        <div className="sheet-actions">
          <button type="submit" className="btn btn-primary" disabled={saving || success}>
            {saving ? t('updatingPasswordButton') : t('updatePasswordButton')}
          </button>
        </div>
      </form>
    </AdaptiveSheet>
  );
};

// ── 2. Change Email Sheet ─────────────────────────────────────────────
export const ChangeEmailSheet: React.FC<{
  open: boolean;
  onClose: () => void;
  currentEmail?: string;
}> = ({ open, onClose, currentEmail }) => {
  const { t } = useLanguage();

  const [newEmail, setNewEmail] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const { error: updateError } = await supabase.auth.updateUser({ email: newEmail });
      if (updateError) throw updateError;
      setSent(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : t('failedToChangeEmail'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <AdaptiveSheet
      open={open}
      onClose={onClose}
      title={t('changeEmailTitle')}
      subtitle={t('changeEmailSubtitle')}
    >
      <form className="sheet-form" onSubmit={handleSubmit}>
        {error && <p className="auth-error">{error}</p>}
        {sent ? (
          <div className="sheet-success-box">
            <p style={{ margin: 0, fontWeight: 600 }}>{t('verificationEmailSent')}</p>
            <p className="muted" style={{ fontSize: '0.85rem', marginTop: '0.4rem' }}>
              {t('verificationEmailInstructions', { email: newEmail })}
            </p>
            <button type="button" className="btn btn-ghost" style={{ marginTop: '1rem' }} onClick={onClose}>
              {t('done')}
            </button>
          </div>
        ) : (
          <>
            {currentEmail && (
              <p className="muted" style={{ fontSize: '0.85rem', marginBottom: '1rem' }}>
                {t('currentEmailLabel')}<strong>{currentEmail}</strong>
              </p>
            )}

            <div className="sheet-form-field">
              <label className="sheet-field-label">{t('newEmailLabel')}</label>
              <input
                type="email"
                className="sheet-input"
                required
                value={newEmail}
                onChange={(e) => setNewEmail(e.target.value)}
                placeholder="name@example.com"
              />
            </div>

            <div className="sheet-actions">
              <button type="submit" className="btn btn-primary" disabled={saving}>
                {saving ? t('sendingVerificationButton') : t('sendVerificationButton')}
              </button>
            </div>
          </>
        )}
      </form>
    </AdaptiveSheet>
  );
};

// ── 3. Delete Account Dialog ──────────────────────────────────────────
export const DeleteAccountModal: React.FC<{
  open: boolean;
  onClose: () => void;
  user: User | null;
  profile: UserProfile | null;
}> = ({ open, onClose, user, profile }) => {
  const { t } = useLanguage();
  const navigate = useNavigate();
  const isEmail = hasEmailIdentity(user);
  const [confirmInput, setConfirmInput] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isConfirmed = isEmail
    ? confirmInput.length >= 6
    : confirmInput.trim() === (profile?.username ?? '').trim();

  const handleDelete = async () => {
    setDeleting(true);
    setError(null);
    try {
      if (isEmail) {
        await deleteAccount(user?.email ?? undefined, confirmInput);
      } else {
        await deleteAccount();
      }
      navigate('/account-deleted', { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : t('failedToDeleteAccount'));
    } finally {
      setDeleting(false);
    }
  };

  const defaultUsername = t('explorerDefaultName');

  return (
    <Modal open={open} onClose={onClose} title={t('deleteAccountTitle')}>
      <div style={{ color: 'var(--universe-text, #f2f2f2)' }}>
        <p style={{ marginTop: 0, color: 'var(--comet)' }}>
          {t('deleteAccountWarningMessage')}
        </p>

        <label style={{ display: 'block', margin: '1rem 0 0.5rem', fontSize: '0.85rem', fontWeight: 600 }}>
          {isEmail
            ? t('deleteAccountPasswordPrompt')
            : t('deleteAccountConfirmationUsername', { username: profile?.username || defaultUsername })}
        </label>
        <input
          type={isEmail ? 'password' : 'text'}
          value={confirmInput}
          onChange={(e) => setConfirmInput(e.target.value)}
          placeholder={isEmail ? t('deleteAccountPasswordLabel') : profile?.username || defaultUsername}
          style={{
            width: '100%',
            padding: '0.65rem 0.85rem',
            background: 'var(--glass-high)',
            border: '1px solid var(--glass-border)',
            borderRadius: '8px',
            color: '#fff',
            boxSizing: 'border-box',
          }}
        />

        {error && <p className="auth-error" style={{ marginTop: '0.75rem' }}>{error}</p>}

        <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end', marginTop: '1.25rem' }}>
          <button
            type="button"
            className="btn btn-ghost"
            onClick={onClose}
            disabled={deleting}
            style={{
              background: 'rgba(255, 255, 255, 0.08)',
              color: '#ffffff',
              border: '1px solid rgba(255, 255, 255, 0.2)',
              borderRadius: '8px',
              padding: '0.55rem 1.15rem',
              fontWeight: 600,
            }}
          >
            {t('cancel')}
          </button>
          <button
            type="button"
            className="btn btn-danger"
            style={{
              background: 'var(--correction-red, #ff5252)',
              color: '#ffffff',
              borderColor: 'transparent',
              borderRadius: '8px',
              padding: '0.55rem 1.15rem',
              fontWeight: 600,
            }}
            onClick={handleDelete}
            disabled={!isConfirmed || deleting}
          >
            {deleting ? t('deletingAccountButton') : t('deleteAccountConfirmButton')}
          </button>
        </div>
      </div>
    </Modal>
  );
};
