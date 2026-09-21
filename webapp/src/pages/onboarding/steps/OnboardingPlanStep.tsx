import React from 'react';
import { useLanguage } from '../../../i18n/LanguageContext';
import { PlansContent } from '../../account/PlansContent';
import { OnboardingStepHeader } from '../OnboardingStepHeader';

/**
 * onboarding_plan_step.dart相当。アカウント設定と全く同じ`PlansContent`
 * (カード列+比較表+課金モーダル一式)をそのまま埋め込み、ヘッダーだけ他の
 * オンボーディングステップと統一した`OnboardingStepHeader`に差し替える。
 * Freeに限らずどのプランでも選べる(Flutter版のPlanSelectionView同様)。
 */
export const OnboardingPlanStep: React.FC<{ onNext: () => void }> = ({ onNext }) => {
  const { t } = useLanguage();

  return (
    <PlansContent
      header={
        <div className="onb-plan-header">
          <OnboardingStepHeader
            eyebrow={t('onboardingPlanEyebrow')}
            title={t('onboardingPlanTitle')}
            subtitle={t('onboardingPlanSubtitle')}
            eyebrowColor="var(--gold)"
          />
        </div>
      }
      onPlanActivated={onNext}
    />
  );
};
