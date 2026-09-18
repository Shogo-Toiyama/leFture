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
  const { language } = useLanguage();
  const isJa = language === 'ja';

  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newPassword !== confirmPassword) {
      setError(isJa ? 'パスワードが一致しません' : 'Passwords do not match');
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
      setError(err instanceof Error ? err.message : (isJa ? 'パスワードの更新に失敗しました' : 'Failed to update password'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <AdaptiveSheet
      open={open}
      onClose={onClose}
      title={isJa ? 'パスワードを変更' : 'Change Password'}
      subtitle={isJa ? '新しいパスワードを入力してください' : 'Enter a secure new password for your account'}
    >
      <form className="sheet-form" onSubmit={handleSubmit}>
        {error && <p className="auth-error">{error}</p>}
        {success && <p className="auth-success">{isJa ? 'パスワードを更新しました！' : 'Password updated successfully!'}</p>}

        <div className="sheet-form-field">
          <label className="sheet-field-label">{isJa ? '新しいパスワード' : 'New Password'}</label>
          <input
            type="password"
            className="sheet-input"
            required
            minLength={8}
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            placeholder={isJa ? '8文字以上' : 'At least 8 characters'}
          />
        </div>

        <div className="sheet-form-field">
          <label className="sheet-field-label">{isJa ? 'パスワード（確認）' : 'Confirm New Password'}</label>
          <input
            type="password"
            className="sheet-input"
            required
            minLength={8}
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            placeholder={isJa ? 'もう一度入力してください' : 'Re-enter new password'}
          />
        </div>

        <div className="sheet-actions">
          <button type="submit" className="btn btn-primary" disabled={saving || success}>
            {saving ? (isJa ? '更新中…' : 'Updating…') : (isJa ? 'パスワードを更新' : 'Update Password')}
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
  const { language } = useLanguage();
  const isJa = language === 'ja';

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
      setError(err instanceof Error ? err.message : (isJa ? 'メールアドレスの変更に失敗しました' : 'Failed to change email'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <AdaptiveSheet
      open={open}
      onClose={onClose}
      title={isJa ? 'メールアドレスを変更' : 'Change Email'}
      subtitle={isJa ? 'アカウントの主要メールアドレスを更新します' : 'Update your primary account email address'}
    >
      <form className="sheet-form" onSubmit={handleSubmit}>
        {error && <p className="auth-error">{error}</p>}
        {sent ? (
          <div className="sheet-success-box">
            <p style={{ margin: 0, fontWeight: 600 }}>{isJa ? '確認メールを送信しました！' : 'Verification email sent!'}</p>
            <p className="muted" style={{ fontSize: '0.85rem', marginTop: '0.4rem' }}>
              {isJa ? (
                <><strong>{newEmail}</strong> に届いたリンクをクリックして変更を完了してください。</>
              ) : (
                <>Please check your inbox at <strong>{newEmail}</strong> to confirm the change.</>
              )}
            </p>
            <button type="button" className="btn btn-ghost" style={{ marginTop: '1rem' }} onClick={onClose}>
              {isJa ? '閉じる' : 'Done'}
            </button>
          </div>
        ) : (
          <>
            {currentEmail && (
              <p className="muted" style={{ fontSize: '0.85rem', marginBottom: '1rem' }}>
                {isJa ? '現在のメールアドレス: ' : 'Current email: '}<strong>{currentEmail}</strong>
              </p>
            )}

            <div className="sheet-form-field">
              <label className="sheet-field-label">{isJa ? '新しいメールアドレス' : 'New Email Address'}</label>
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
                {saving ? (isJa ? '送信中…' : 'Sending…') : (isJa ? '確認メールを送信' : 'Send Verification')}
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
  const { language } = useLanguage();
  const isJa = language === 'ja';
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
      setError(err instanceof Error ? err.message : (isJa ? 'アカウントの削除に失敗しました' : 'Failed to delete account'));
    } finally {
      setDeleting(false);
    }
  };

  return (
    <Modal open={open} onClose={onClose} title={isJa ? 'アカウントを削除' : 'Delete Account'}>
      <div style={{ color: 'var(--universe-text, #f2f2f2)' }}>
        <p style={{ marginTop: 0, color: 'var(--comet)' }}>
          {isJa ? (
            <>アカウントおよびすべてのコース・講義・関連データがローカルとクラウドの両方から完全に削除されます。<strong style={{ color: '#ff8b85' }}>この操作は取り消せません。</strong></>
          ) : (
            <>This permanently deletes your account, all courses, lectures, and associated data from both local and cloud storage. <strong style={{ color: '#ff8b85' }}>This action cannot be undone.</strong></>
          )}
        </p>

        <label style={{ display: 'block', margin: '1rem 0 0.5rem', fontSize: '0.85rem', fontWeight: 600 }}>
          {isEmail
            ? (isJa ? '確認のためパスワードを入力してください:' : 'Enter your password to confirm:')
            : (isJa ? `確認のためユーザー名 ("${profile?.username || '探検者'}") を入力してください:` : `Type your username ("${profile?.username || 'Explorer'}") to confirm:`)}
        </label>
        <input
          type={isEmail ? 'password' : 'text'}
          value={confirmInput}
          onChange={(e) => setConfirmInput(e.target.value)}
          placeholder={isEmail ? (isJa ? 'パスワード' : 'Password') : profile?.username || (isJa ? '探検者' : 'Explorer')}
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
            {isJa ? 'キャンセル' : 'Cancel'}
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
            {deleting ? (isJa ? '削除中…' : 'Deleting…') : (isJa ? 'アカウントを削除' : 'Delete Account')}
          </button>
        </div>
      </div>
    </Modal>
  );
};
