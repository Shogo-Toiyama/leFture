import React from 'react';
import { ChevronLeft, Globe as GlobeIcon, User as UserIcon, Award as AwardIcon } from 'lucide-react';
import { LanguageHeaderButton } from '../../components/auth/LanguageHeaderButton';

interface StepSpec {
  color: string;
  Icon: React.ComponentType<{ size?: number; color?: string }>;
}

// Permissionsステップが無いWeb版では3ノード(Language/Profile/Plan)。
// 色はonboarding_horizontal_step_indicator.dart準拠(cosmicBlue/growthGreen/starGold)。
const STEPS: StepSpec[] = [
  { color: 'var(--blue)', Icon: GlobeIcon },
  { color: 'var(--green)', Icon: UserIcon },
  { color: 'var(--gold)', Icon: AwardIcon },
];

/** onboarding_horizontal_step_indicator.dart相当。currentStepIndex: 0=Language,1=Profile,2=Plan。 */
const OnboardingStepIndicator: React.FC<{ currentStepIndex: number }> = ({ currentStepIndex }) => (
  <div className="onb-indicator">
    {STEPS.map((step, i) => {
      const isActive = i === currentStepIndex;
      const isCompleted = i < currentStepIndex;
      const isLit = isActive || isCompleted;
      const Icon = step.Icon;
      return (
        <React.Fragment key={i}>
          <div
            className={`onb-indicator-node ${isActive ? 'is-active' : ''} ${isLit ? 'is-lit' : ''}`}
            style={{ ['--node-color' as string]: step.color }}
          >
            <Icon size={isActive ? 15 : 13} color={isLit ? '#fff' : 'rgba(255,255,255,0.35)'} />
          </div>
          {i < STEPS.length - 1 && (
            <div
              className={`onb-indicator-connector ${i < currentStepIndex ? 'is-passed' : ''}`}
              style={{
                ['--from-color' as string]: STEPS[i].color,
                ['--to-color' as string]: STEPS[i + 1].color,
              }}
            />
          )}
        </React.Fragment>
      );
    })}
  </div>
);

/** onboarding_top_bar.dart相当。戻るボタン + 3ステップインジケーター + 言語切替。 */
export const OnboardingTopBar: React.FC<{ onBack: () => void; currentStepIndex: number }> = ({
  onBack,
  currentStepIndex,
}) => (
  <div className="onb-top-bar">
    <button type="button" className="onb-back-btn" onClick={onBack} aria-label="Back">
      <ChevronLeft size={28} strokeWidth={2.5} />
    </button>
    <div className="onb-top-bar-indicator">
      <OnboardingStepIndicator currentStepIndex={currentStepIndex} />
    </div>
    <LanguageHeaderButton />
  </div>
);
