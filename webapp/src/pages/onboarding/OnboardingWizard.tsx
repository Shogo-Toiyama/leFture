import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useProfile } from '../../hooks/useProfile';
import { markOnboardingCompleted } from '../../lib/profile';
import { LanguageHeaderButton } from '../../components/auth/LanguageHeaderButton';
import { OnboardingTopBar } from './OnboardingTopBar';
import { OnboardingIntroStep } from './steps/OnboardingIntroStep';
import { OnboardingLanguageStep } from './steps/OnboardingLanguageStep';
import { OnboardingProfileStep } from './steps/OnboardingProfileStep';
import { OnboardingPlanStep } from './steps/OnboardingPlanStep';
import { OnboardingDoneStep } from './steps/OnboardingDoneStep';

type Step = 'intro' | 'language' | 'profile' | 'plan' | 'done';
const STEPS: Step[] = ['intro', 'language', 'profile', 'plan', 'done'];

// onboarding_page.dart準拠。Webはネイティブ権限が無いためPermissionsステップを
// 省き、Intro → Language → Profile → Plan → Done の5画面構成にする。
// 各ステップの上のグラデーション演出色もFlutter版のAppColorsと同じ値
// (cosmicBlue/growthGreen/starGold)。
const STEP_GRADIENT: Partial<Record<Step, string>> = {
  language: '66, 165, 245', // --blue
  profile: '76, 175, 80', // --green
};

export const OnboardingWizard: React.FC = () => {
  const navigate = useNavigate();
  const { profile } = useProfile();
  const [step, setStep] = useState<Step>('intro');

  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [step]);

  // onboarding_page.dart同様、Doneステップに到達した瞬間に完了扱いにする
  // (最後のボタンを押さずタブを閉じても、次回オンボーディングに戻されないため)。
  useEffect(() => {
    if (step === 'done') {
      markOnboardingCompleted(profile?.metadata ?? null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step]);

  const finish = () => {
    navigate('/', { replace: true });
  };

  const goTo = (s: Step) => setStep(s);
  const stepIndex = STEPS.indexOf(step);
  const back = () => {
    if (stepIndex > 0) goTo(STEPS[stepIndex - 1]);
  };
  const next = () => {
    if (stepIndex < STEPS.length - 1) goTo(STEPS[stepIndex + 1]);
  };

  const indicatorIndex = { language: 0, profile: 1, plan: 2 }[step as 'language' | 'profile' | 'plan'];
  const showTopBar = step === 'language' || step === 'profile' || step === 'plan';
  const isFullBleed = step === 'plan';
  const gradientColor = STEP_GRADIENT[step];

  return (
    <div className="onb-page">
      <div
        className="onb-bg-gradient"
        style={{
          background: gradientColor
            ? `linear-gradient(to bottom, rgba(${gradientColor}, 0.32), rgba(${gradientColor}, 0.1) 18%, transparent 35%)`
            : 'transparent',
        }}
        aria-hidden="true"
      />

      {step === 'intro' && (
        <div className="onb-intro-lang-btn">
          <LanguageHeaderButton />
        </div>
      )}

      {showTopBar && (
        <div className="onb-top-bar-wrap">
          <OnboardingTopBar onBack={back} currentStepIndex={indicatorIndex} />
        </div>
      )}

      <div className={isFullBleed ? 'plans-page-inner' : 'onb-content-narrow'} key={step}>
        {step === 'intro' && <OnboardingIntroStep onNext={next} />}
        {step === 'language' && <OnboardingLanguageStep onNext={next} />}
        {step === 'profile' && <OnboardingProfileStep onNext={next} />}
        {step === 'plan' && <OnboardingPlanStep onNext={next} />}
        {step === 'done' && <OnboardingDoneStep onFinish={finish} />}
      </div>
    </div>
  );
};
