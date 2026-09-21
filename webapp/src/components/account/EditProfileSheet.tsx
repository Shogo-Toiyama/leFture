import React, { useState, useEffect } from 'react';
import { AdaptiveSheet } from '../modals/AdaptiveSheet';
import { ConfirmModal } from '../modals/ConfirmModal';
import { updateProfileFields } from '../../lib/profile';
import { useLanguage } from '../../i18n/LanguageContext';
import type { UserProfile } from '../../types/profile';

interface EditProfileSheetProps {
  open: boolean;
  onClose: () => void;
  profile: UserProfile | null;
  onUpdated: () => Promise<void>;
}

export const EditProfileSheet: React.FC<EditProfileSheetProps> = ({
  open,
  onClose,
  profile,
  onUpdated,
}) => {
  const { t } = useLanguage();

  const initialBio = profile?.bio ?? '';
  const initialInterests = profile?.interests ?? '';
  const initialGoals = profile?.future_goals ?? '';

  const [bio, setBio] = useState(initialBio);
  const [interests, setInterests] = useState(initialInterests);
  const [futureGoals, setFutureGoals] = useState(initialGoals);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showDiscardConfirm, setShowDiscardConfirm] = useState(false);

  useEffect(() => {
    if (open && profile) {
      setBio(profile.bio ?? '');
      setInterests(profile.interests ?? '');
      setFutureGoals(profile.future_goals ?? '');
      setShowDiscardConfirm(false);
      setError(null);
    }
  }, [profile, open]);

  const isDirty =
    bio !== initialBio ||
    interests !== initialInterests ||
    futureGoals !== initialGoals;

  const handleRequestClose = () => {
    if (isDirty) {
      setShowDiscardConfirm(true);
    } else {
      onClose();
    }
  };

  const handleForceDiscard = () => {
    setShowDiscardConfirm(false);
    setBio(initialBio);
    setInterests(initialInterests);
    setFutureGoals(initialGoals);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isDirty) return;
    setSaving(true);
    setError(null);
    try {
      await updateProfileFields({
        bio,
        interests,
        future_goals: futureGoals,
      });
      await onUpdated();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : t('failedToUpdateProfile'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <AdaptiveSheet
        open={open}
        onClose={handleRequestClose}
        title={t('editProfileTitle')}
        subtitle={t('editProfileSubtitle')}
      >
        <form className="edit-profile-sheet-form" onSubmit={handleSubmit}>
          {error && <p className="auth-error">{error}</p>}

          <div className="sheet-form-field">
            <label htmlFor="sheet-bio" className="sheet-field-label">
              {t('aboutYou')}
            </label>
            <p className="sheet-field-hint">
              {t('aboutYouSubtitle')}
            </p>
            <textarea
              id="sheet-bio"
              className="sheet-textarea"
              rows={3}
              placeholder={t('aboutYouPlaceholder')}
              value={bio}
              onChange={(e) => setBio(e.target.value)}
            />
          </div>

          <div className="sheet-form-field">
            <label htmlFor="sheet-interests" className="sheet-field-label">
              {t('interests')}
            </label>
            <p className="sheet-field-hint">
              {t('interestsSubtitle')}
            </p>
            <textarea
              id="sheet-interests"
              className="sheet-textarea"
              rows={3}
              placeholder={t('interestsPlaceholder')}
              value={interests}
              onChange={(e) => setInterests(e.target.value)}
            />
          </div>

          <div className="sheet-form-field">
            <label htmlFor="sheet-goals" className="sheet-field-label">
              {t('futureGoals')}
            </label>
            <p className="sheet-field-hint">
              {t('futureGoalsSubtitle')}
            </p>
            <textarea
              id="sheet-goals"
              className="sheet-textarea"
              rows={3}
              placeholder={t('futureGoalsPlaceholder')}
              value={futureGoals}
              onChange={(e) => setFutureGoals(e.target.value)}
            />
          </div>

          <div className="sheet-actions" style={{ marginTop: '1.5rem' }}>
            <button
              type="submit"
              className="btn btn-primary"
              disabled={!isDirty || saving}
              title={!isDirty ? t('noChangesYet') : undefined}
            >
              {saving ? t('saving') : t('saveChanges')}
            </button>
          </div>
        </form>
      </AdaptiveSheet>

      <ConfirmModal
        open={showDiscardConfirm}
        onClose={() => setShowDiscardConfirm(false)}
        onConfirm={handleForceDiscard}
        title={t('discardChangesTitle')}
        message={t('discardChangesMessage')}
        confirmLabel={t('discardChangesButton')}
        cancelLabel={t('keepEditingButton')}
        isDanger={true}
      />
    </>
  );
};
