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
  const { language } = useLanguage();
  const isJa = language === 'ja';

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
      setError(err instanceof Error ? err.message : 'Failed to update profile');
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <AdaptiveSheet
        open={open}
        onClose={handleRequestClose}
        title={isJa ? 'プロフィールを編集' : 'Edit Profile'}
        subtitle={isJa ? 'プロフィール情報と学習の目標を設定' : 'Personalize your profile details and learning goals'}
      >
        <form className="edit-profile-sheet-form" onSubmit={handleSubmit}>
          {error && <p className="auth-error">{error}</p>}

          <div className="sheet-form-field">
            <label htmlFor="sheet-bio" className="sheet-field-label">
              {isJa ? '自己紹介' : 'About you'}
            </label>
            <p className="sheet-field-hint">
              {isJa ? 'あなた自身や学んでいることについての簡単な紹介' : 'A brief description of yourself and what you study'}
            </p>
            <textarea
              id="sheet-bio"
              className="sheet-textarea"
              rows={3}
              placeholder={isJa ? '例: AIや宇宙物理学に興味がある情報科学専攻の学生' : 'e.g. Computer Science student interested in AI and astronomy'}
              value={bio}
              onChange={(e) => setBio(e.target.value)}
            />
          </div>

          <div className="sheet-form-field">
            <label htmlFor="sheet-interests" className="sheet-field-label">
              {isJa ? '興味・関心' : 'Interests'}
            </label>
            <p className="sheet-field-hint">
              {isJa ? '興味のあるテーマや研究分野など' : 'Topics, subjects, and hobbies you enjoy'}
            </p>
            <textarea
              id="sheet-interests"
              className="sheet-textarea"
              rows={3}
              placeholder={isJa ? '例: 宇宙天文学、機械学習、UIデザイン' : 'e.g. Astrophysics, Machine Learning, UI Design'}
              value={interests}
              onChange={(e) => setInterests(e.target.value)}
            />
          </div>

          <div className="sheet-form-field">
            <label htmlFor="sheet-goals" className="sheet-field-label">
              {isJa ? '将来の夢・目標' : 'Future goals'}
            </label>
            <p className="sheet-field-hint">
              {isJa ? '学習を通じて達成したい目標や将来像' : 'What you aim to achieve with your learning'}
            </p>
            <textarea
              id="sheet-goals"
              className="sheet-textarea"
              rows={3}
              placeholder={isJa ? '例: 系外惑星の研究に携わる、AIスタートアップを立ち上げる' : 'e.g. Conduct research in exoplanets, launch an AI startup'}
              value={futureGoals}
              onChange={(e) => setFutureGoals(e.target.value)}
            />
          </div>

          <div className="sheet-actions" style={{ marginTop: '1.5rem' }}>
            <button
              type="submit"
              className="btn btn-primary"
              disabled={!isDirty || saving}
              title={!isDirty ? (isJa ? '変更はありません' : 'No changes made yet') : undefined}
            >
              {saving ? (isJa ? '保存中…' : 'Saving…') : (isJa ? '変更を保存' : 'Save Changes')}
            </button>
          </div>
        </form>
      </AdaptiveSheet>

      <ConfirmModal
        open={showDiscardConfirm}
        onClose={() => setShowDiscardConfirm(false)}
        onConfirm={handleForceDiscard}
        title={isJa ? '変更を破棄しますか？' : 'Discard unsaved changes?'}
        message={isJa ? '保存されていない変更があります。破棄して閉じますか？' : 'You have unsaved changes in your profile. Are you sure you want to discard your edits and close?'}
        confirmLabel={isJa ? '破棄する' : 'Discard Changes'}
        cancelLabel={isJa ? '編集を続ける' : 'Keep Editing'}
        isDanger={true}
      />
    </>
  );
};
