import React, { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useProfile } from '../../hooks/useProfile';
import { supabase } from '../../lib/supabase';
import { updateProfileFields, setLanguagePreferences, uploadAvatar } from '../../lib/profile';
import { deleteAccount, hasEmailIdentity } from '../../lib/account';
import { AvatarImage } from '../../components/AvatarImage';
import { Modal } from '../../components/Modal';
import { PageState } from '../../components/PageState';
import type { User } from '@supabase/supabase-js';

export const ProfilePage: React.FC = () => {
  const { profile, loading, refetch, setProfile } = useProfile();
  const navigate = useNavigate();

  const [username, setUsername] = useState('');
  const [bio, setBio] = useState('');
  const [interests, setInterests] = useState('');
  const [futureGoals, setFutureGoals] = useState('');
  const [displayLanguage, setDisplayLanguage] = useState('');
  const [recordingLanguage, setRecordingLanguage] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);

  const [user, setUser] = useState<User | null>(null);
  const [newPassword, setNewPassword] = useState('');
  const [passwordSaved, setPasswordSaved] = useState(false);

  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteConfirmInput, setDeleteConfirmInput] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  useEffect(() => {
    if (!profile) return;
    setUsername(profile.username ?? '');
    setBio(profile.bio ?? '');
    setInterests(profile.interests ?? '');
    setFutureGoals(profile.future_goals ?? '');
    setDisplayLanguage(profile.metadata?.display_language ?? '');
    setRecordingLanguage(profile.metadata?.recording_language ?? '');
  }, [profile]);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user));
  }, []);

  const handleSaveProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const updated = await updateProfileFields({ username, bio, interests, future_goals: futureGoals });
      setProfile(updated);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save profile');
    } finally {
      setSaving(false);
    }
  };

  const handleSaveLanguages = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!profile) return;
    setSaving(true);
    setError(null);
    try {
      const updated = await setLanguagePreferences(profile.metadata, displayLanguage, recordingLanguage);
      setProfile(updated);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save language preferences');
    } finally {
      setSaving(false);
    }
  };

  const handleAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingAvatar(true);
    try {
      await uploadAvatar(file);
      await refetch();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to upload avatar');
    } finally {
      setUploadingAvatar(false);
    }
  };

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    setPasswordSaved(false);
    try {
      const { error: updateError } = await supabase.auth.updateUser({ password: newPassword });
      if (updateError) throw updateError;
      setNewPassword('');
      setPasswordSaved(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to change password');
    } finally {
      setSaving(false);
    }
  };

  const isEmailUser = hasEmailIdentity(user);
  const deleteConfirmMatches = isEmailUser
    ? deleteConfirmInput.length > 0
    : deleteConfirmInput === (profile?.username ?? '');

  const handleDelete = async () => {
    setDeleting(true);
    setDeleteError(null);
    try {
      if (isEmailUser) {
        await deleteAccount(user?.email ?? undefined, deleteConfirmInput);
      } else {
        await deleteAccount();
      }
      navigate('/sign-in', { replace: true });
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Failed to delete account');
    } finally {
      setDeleting(false);
    }
  };

  if (loading) return <PageState kind="loading" />;

  return (
    <div>
      <Link to="/account" className="back-link">
        ← Account
      </Link>
      <h1>Profile &amp; preferences</h1>

      <div className="account-header">
        <AvatarImage avatarUrl={profile?.avatar_url ?? null} size={64} />
        <label className="link-button">
          {uploadingAvatar ? 'Uploading…' : 'Change avatar'}
          <input type="file" accept="image/*" hidden onChange={handleAvatarChange} disabled={uploadingAvatar} />
        </label>
      </div>

      {error && <p className="auth-error">{error}</p>}

      <form className="course-form" onSubmit={handleSaveProfile}>
        <h2>Profile</h2>
        <label>
          Display name
          <input value={username} onChange={(e) => setUsername(e.target.value)} />
        </label>
        <label>
          About you
          <textarea value={bio} onChange={(e) => setBio(e.target.value)} rows={2} />
        </label>
        <label>
          Interests
          <textarea value={interests} onChange={(e) => setInterests(e.target.value)} rows={2} />
        </label>
        <label>
          Future goals
          <textarea value={futureGoals} onChange={(e) => setFutureGoals(e.target.value)} rows={2} />
        </label>
        <button type="submit" disabled={saving}>
          Save profile
        </button>
      </form>

      <form className="course-form" onSubmit={handleSaveLanguages}>
        <h2>Language</h2>
        <div className="course-form-row">
          <label>
            Display language
            <input value={displayLanguage} onChange={(e) => setDisplayLanguage(e.target.value)} />
          </label>
          <label>
            Recording language
            <input value={recordingLanguage} onChange={(e) => setRecordingLanguage(e.target.value)} />
          </label>
        </div>
        <button type="submit" disabled={saving}>
          Save language
        </button>
      </form>

      <form className="course-form" onSubmit={handleChangePassword}>
        <h2>Password</h2>
        <label>
          New password
          <input
            type="password"
            minLength={8}
            required
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
          />
        </label>
        {passwordSaved && <p>Password updated.</p>}
        <button type="submit" disabled={saving}>
          Change password
        </button>
      </form>

      <p className="glass-section-label">Danger zone</p>
      <div className="glass-card" style={{ padding: '1rem' }}>
        <button type="button" className="danger" onClick={() => setDeleteOpen(true)}>
          Delete account
        </button>
      </div>

      <Modal open={deleteOpen} onClose={() => setDeleteOpen(false)} title="Delete account">
        <p>This permanently deletes your account and all its data. This cannot be undone.</p>
        <label>
          {isEmailUser ? 'Enter your password to confirm' : `Type your username ("${profile?.username}") to confirm`}
          <input
            type={isEmailUser ? 'password' : 'text'}
            value={deleteConfirmInput}
            onChange={(e) => setDeleteConfirmInput(e.target.value)}
          />
        </label>
        {deleteError && <p className="auth-error">{deleteError}</p>}
        <button type="button" className="danger" onClick={handleDelete} disabled={!deleteConfirmMatches || deleting}>
          {deleting ? 'Deleting…' : 'Permanently delete my account'}
        </button>
      </Modal>
    </div>
  );
};
