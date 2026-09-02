import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useProfile } from '../../hooks/useProfile';
import { usePlans } from '../../hooks/usePlans';
import { updateProfileFields, setLanguagePreferences, markOnboardingCompleted } from '../../lib/profile';
import { claimPlan } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { AppErrorBox } from '../../components/auth/AppErrorBox';

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
  const [error, setError] = useState<any>(null);

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
      setError(err);
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
      setError(err);
    }
  };

  const handleClaim = async (planId: string) => {
    setClaimingId(planId);
    setError(null);
    try {
      await claimPlan(planId);
    } catch (err) {
      setError(err);
    } finally {
      setClaimingId(null);
    }
  };

  return (
    <div className="auth-cosmos-page">
      <div className="auth-cosmos-glow" />

      <div className="auth-cosmos-container" style={{ maxWidth: 500 }}>
        <div className="auth-glass-card">
          <div className="onboarding-steps">
            {STEPS.map((s, i) => (
              <span
                key={s}
                className={`onboarding-step-dot ${i <= stepIndex ? 'is-done' : ''}`}
              />
            ))}
          </div>

          <AppErrorBox rawError={error} />

          {step === 'intro' && (
            <div style={{ textAlign: 'center', padding: '1rem 0' }}>
              <div className="auth-glow-icon-wrap">
                <div className="auth-glow-icon">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z" />
                  </svg>
                </div>
              </div>
              <h1 className="auth-cosmos-title">Welcome to Orbit</h1>
              <p className="auth-cosmos-subtitle" style={{ maxWidth: 360, margin: '0.5rem auto 1.5rem' }}>
                Your smart lecture companion. Turn recordings into review cards, deep notes, and an interconnected universe of knowledge.
              </p>
            </div>
          )}

          {step === 'language' && (
            <div className="auth-form-body">
              <h2 className="auth-cosmos-title" style={{ fontSize: '1.4rem' }}>Language Settings</h2>
              <p className="auth-cosmos-subtitle" style={{ marginBottom: '1rem' }}>
                Choose your preferred interface and recording language.
              </p>
              <div className="auth-input-group">
                <label className="auth-input-label">Display Language</label>
                <div className="auth-input-wrap">
                  <input
                    value={displayLanguage}
                    onChange={(e) => setDisplayLanguage(e.target.value)}
                    className="auth-input-control"
                    style={{ paddingLeft: '1rem' }}
                    placeholder="en, ja, etc."
                  />
                </div>
              </div>
              <div className="auth-input-group">
                <label className="auth-input-label">Recording Language</label>
                <div className="auth-input-wrap">
                  <input
                    value={recordingLanguage}
                    onChange={(e) => setRecordingLanguage(e.target.value)}
                    className="auth-input-control"
                    style={{ paddingLeft: '1rem' }}
                    placeholder="en, ja, etc."
                  />
                </div>
              </div>
            </div>
          )}

          {step === 'profile' && (
            <div className="auth-form-body">
              <h2 className="auth-cosmos-title" style={{ fontSize: '1.4rem' }}>Tell Us About Yourself</h2>
              <p className="auth-cosmos-subtitle" style={{ marginBottom: '1rem' }}>
                Personalize your study experience.
              </p>
              <div className="auth-input-group">
                <label className="auth-input-label">Interests & Majors</label>
                <div className="auth-input-wrap">
                  <input
                    value={interests}
                    onChange={(e) => setInterests(e.target.value)}
                    className="auth-input-control"
                    style={{ paddingLeft: '1rem' }}
                    placeholder="e.g. Computer Science, Economics"
                  />
                </div>
              </div>
              <div className="auth-input-group">
                <label className="auth-input-label">Future Goals</label>
                <div className="auth-input-wrap">
                  <input
                    value={futureGoals}
                    onChange={(e) => setFutureGoals(e.target.value)}
                    className="auth-input-control"
                    style={{ paddingLeft: '1rem' }}
                    placeholder="e.g. Pass exams, Research AI"
                  />
                </div>
              </div>
              <div className="auth-input-group">
                <label className="auth-input-label">Short Bio</label>
                <div className="auth-input-wrap">
                  <textarea
                    value={bio}
                    onChange={(e) => setBio(e.target.value)}
                    className="auth-input-control"
                    style={{ padding: '0.75rem 1rem', height: 72, resize: 'none' }}
                    placeholder="A few words about you…"
                  />
                </div>
              </div>
            </div>
          )}

          {step === 'plan' && (
            <div className="auth-form-body">
              <h2 className="auth-cosmos-title" style={{ fontSize: '1.4rem' }}>Choose a Plan</h2>
              <p className="auth-cosmos-subtitle" style={{ marginBottom: '1rem' }}>
                Select a starting credit package. You can change this anytime.
              </p>
              {plansLoading && <p style={{ color: 'var(--comet)' }}>Loading plans…</p>}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                {plans.map((plan) => (
                  <div
                    key={plan.id}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: '1rem',
                      borderRadius: 14,
                      background: 'rgba(255, 255, 255, 0.05)',
                      border: '1px solid var(--glass-border)',
                    }}
                  >
                    <div>
                      <div style={{ fontWeight: 600, color: 'var(--starlight)' }}>{plan.name}</div>
                      <div style={{ fontSize: '0.85rem', color: 'var(--comet)' }}>
                        {toDisplayCredits(plan.monthly_credit_amount)} credits/mo
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={() => handleClaim(plan.id)}
                      disabled={claimingId === plan.id}
                      style={{
                        padding: '0.5rem 1rem',
                        borderRadius: 10,
                        background: 'var(--gold)',
                        color: '#fff',
                        border: 'none',
                        fontWeight: 600,
                        cursor: 'pointer',
                      }}
                    >
                      {claimingId === plan.id ? 'Claiming…' : 'Choose'}
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="onboarding-actions">
            {stepIndex > 0 && (
              <button
                type="button"
                onClick={() => setStepIndex((i) => i - 1)}
                className="social-signin-btn"
                style={{ width: 'auto', padding: '0 1.25rem', height: 44 }}
              >
                Back
              </button>
            )}
            <button
              type="button"
              onClick={goNext}
              disabled={finishing}
              className="auth-submit-btn"
              style={{ width: 'auto', minWidth: 120, height: 44, margin: 0 }}
            >
              {stepIndex === STEPS.length - 1 ? (finishing ? 'Finishing…' : 'Finish') : 'Continue'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
