import React, { useEffect, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { useLanguage } from '../../../i18n/LanguageContext';
import { useProfile } from '../../../hooks/useProfile';
import { updateProfileFields } from '../../../lib/profile';
import { OnboardingStepHeader } from '../OnboardingStepHeader';
import { ProfileStepIllustration } from '../OnboardingIllustrations';

/**
 * onboarding_profile_step.dart相当。単一スクロール画面でBio(必須)→Interests→
 * Future Dreamsの順に入力する(3ステップウィザードだった旧版を統合したもの)。
 */
export const OnboardingProfileStep: React.FC<{ onNext: () => void }> = ({ onNext }) => {
  const { t } = useLanguage();
  const { profile, refetch } = useProfile();

  const [bio, setBio] = useState('');
  const [interests, setInterests] = useState('');
  const [futureGoals, setFutureGoals] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!profile) return;
    setBio(profile.bio ?? '');
    setInterests(profile.interests ?? '');
    setFutureGoals(profile.future_goals ?? '');
  }, [profile]);

  const canAdvance = bio.trim().length > 0;

  const submit = async () => {
    if (submitting || !canAdvance) return;
    setSubmitting(true);
    try {
      await updateProfileFields({
        bio: bio.trim(),
        interests: interests.trim(),
        future_goals: futureGoals.trim(),
      });
      await refetch();
      onNext();
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="onb-step-body">
      <OnboardingStepHeader
        eyebrow={t('onboardingProfileEyebrow')}
        title={t('onboardingProfileTitle')}
        subtitle={t('onboardingProfileSubtitle')}
        eyebrowColor="var(--green)"
      />

      <div className="onb-illustration">
        <ProfileStepIllustration />
      </div>

      <ProfileField
        title={t('onboardingProfileBioTitle')}
        subtitle={t('onboardingProfileBioSubtitle')}
        hint={t('onboardingProfileBioHint')}
        value={bio}
        onChange={setBio}
        rows={4}
        required
        requiredNote={t('onboardingProfileBioRequiredNote')}
      />
      <ProfileField
        title={t('onboardingProfileInterestsTitle')}
        subtitle={t('onboardingProfileInterestsSubtitle')}
        hint={t('onboardingProfileInterestsHint')}
        value={interests}
        onChange={setInterests}
        rows={3}
      />
      <ProfileField
        title={t('onboardingProfileDreamsTitle')}
        subtitle={t('onboardingProfileDreamsSubtitle')}
        hint={t('onboardingProfileDreamsHint')}
        value={futureGoals}
        onChange={setFutureGoals}
        rows={3}
      />

      <div className="onb-step-spacer" />

      <button type="button" className="onb-cta-btn" onClick={submit} disabled={!canAdvance || submitting}>
        {submitting ? <Loader2 size={18} className="animate-spin" /> : t('continue')}
      </button>
    </div>
  );
};

const ProfileField: React.FC<{
  title: string;
  subtitle: string;
  hint: string;
  value: string;
  onChange: (v: string) => void;
  rows: number;
  required?: boolean;
  requiredNote?: string;
}> = ({ title, subtitle, hint, value, onChange, rows, required, requiredNote }) => {
  const { t } = useLanguage();
  return (
    <div className="onb-profile-field">
      <div className="onb-profile-field-head">
        <span className="onb-profile-field-title">{title}</span>
        {required && <span className="onb-profile-field-required">{t('requiredBadge')}</span>}
      </div>
      <p className="onb-profile-field-subtitle">{subtitle}</p>
      <textarea
        className="onb-textarea"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={hint}
        rows={rows}
      />
      {required && requiredNote && <p className="onb-profile-field-required-note">{requiredNote}</p>}
    </div>
  );
};
