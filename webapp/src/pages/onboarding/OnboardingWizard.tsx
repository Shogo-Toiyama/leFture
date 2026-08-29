import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useProfile } from '../../hooks/useProfile';
import { usePlans } from '../../hooks/usePlans';
import { updateProfileFields, setLanguagePreferences, markOnboardingCompleted } from '../../lib/profile';
import { claimPlan } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';

/**
 * onboarding_page.dartの Intro → Language → Profile → Permissions → Plan → Done のうち、
 * Permissionsはブラウザ側に相当するOS許可がないためWebでは省略する(webapp実装プラン参照)。
 */
type Step = 'intro' | 'language' | 'profile' | 'plan';
const STEPS: Step[] = ['intro', 'language', 'profile', 'plan'];

function defaultLocale(): string {
  return (navigator.language || 'en').split('-')[0];
}

export const OnboardingWizard: React.FC = () => {
  const navigate = useNavigate();
  const { profile, refetch: refetchProfile } = useProfile();
  const { plans, loading: plansLoading } = usePlans();

  const [stepIndex, setStepIndex] = useState(0);
  const [displayLanguage, setDisplayLanguage] = useState(defaultLocale());
  const [recordingLanguage, setRecordingLanguage] = useState(defaultLocale());
  const [bio, setBio] = useState('');
  const [interests, setInterests] = useState('');
  const [futureGoals, setFutureGoals] = useState('');
  const [claimingId, setClaimingId] = useState<string | null>(null);
  const [finishing, setFinishing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!profile) return;
    setDisplayLanguage(profile.metadata?.display_language ?? defaultLocale());
    setRecordingLanguage(profile.metadata?.recording_language ?? defaultLocale());
    setBio(profile.bio ?? '');
    setInterests(profile.interests ?? '');
    setFutureGoals(profile.future_goals ?? '');
  }, [profile]);

  const step = STEPS[stepIndex];

  const finish = async () => {
    if (!profile) return;
    setFinishing(true);
    setError(null);
    try {
      await markOnboardingCompleted(profile.metadata);
      navigate('/', { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to finish onboarding');
      setFinishing(false);
    }
  };

  const goNext = async () => {
    setError(null);
    try {
      if (step === 'language' && profile) {
        await setLanguagePreferences(profile.metadata, displayLanguage, recordingLanguage);
        await refetchProfile();
      }
      if (step === 'profile') {
        await updateProfileFields({ bio, interests, future_goals: futureGoals });
        await refetchProfile();
      }
      if (stepIndex === STEPS.length - 1) {
        await finish();
        return;
      }
      setStepIndex((i) => i + 1);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save');
    }
  };

  const handleClaim = async (planId: string) => {
    setClaimingId(planId);
    setError(null);
    try {
      await claimPlan(planId);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to claim plan');
    } finally {
      setClaimingId(null);
    }
  };

  return (
    <div className="onboarding-page">
      <div className="onboarding-card">
        <p className="onboarding-step-count">
          Step {stepIndex + 1} of {STEPS.length}
        </p>

        {step === 'intro' && (
          <div>
            <h1>Welcome to leFture</h1>
            <p>Upload a lecture recording and we'll turn it into review cards, deep notes, and more.</p>
          </div>
        )}

        {step === 'language' && (
          <div className="course-form">
            <h1>Language</h1>
            <label>
              Display language
              <input value={displayLanguage} onChange={(e) => setDisplayLanguage(e.target.value)} />
            </label>
            <label>
              Recording language
              <input value={recordingLanguage} onChange={(e) => setRecordingLanguage(e.target.value)} />
            </label>
          </div>
        )}

        {step === 'profile' && (
          <div className="course-form">
            <h1>Tell us about yourself</h1>
            <label>
              Interests
              <textarea value={interests} onChange={(e) => setInterests(e.target.value)} rows={2} />
            </label>
            <label>
              Future goals
              <textarea value={futureGoals} onChange={(e) => setFutureGoals(e.target.value)} rows={2} />
            </label>
            <label>
              About you
              <textarea value={bio} onChange={(e) => setBio(e.target.value)} rows={2} />
            </label>
          </div>
        )}

        {step === 'plan' && (
          <div>
            <h1>Choose a plan</h1>
            {plansLoading && <p>Loading…</p>}
            <ul className="course-list">
              {plans.map((plan) => (
                <li key={plan.id} className="course-list-item">
                  <span>
                    {plan.name} — {toDisplayCredits(plan.monthly_credit_amount)} credits/mo
                  </span>
                  <button type="button" onClick={() => handleClaim(plan.id)} disabled={claimingId === plan.id}>
                    {claimingId === plan.id ? 'Claiming…' : 'Choose'}
                  </button>
                </li>
              ))}
            </ul>
            <p>You can skip this and pick a plan later from your account.</p>
          </div>
        )}

        {error && <p className="auth-error">{error}</p>}

        <div className="onboarding-actions">
          {stepIndex > 0 && (
            <button type="button" onClick={() => setStepIndex((i) => i - 1)}>
              Back
            </button>
          )}
          <button type="button" onClick={goNext} disabled={finishing}>
            {stepIndex === STEPS.length - 1 ? (finishing ? 'Finishing…' : 'Finish') : 'Continue'}
          </button>
        </div>
      </div>
    </div>
  );
};
