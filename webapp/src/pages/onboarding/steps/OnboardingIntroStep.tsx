import React, { useEffect, useState } from 'react';
import { Globe, User, Award } from 'lucide-react';
import { useLanguage } from '../../../i18n/LanguageContext';

interface WaypointSpec {
  color: string;
  Icon: React.ComponentType<{ size?: number; color?: string }>;
  title: string;
  desc: string;
  delayMs: number;
}

// 控えめな瞬く星(CSS onlyのアンビエント演出。intro_particle_field.dartの簡略版)。
const STARS = [
  { top: '12%', left: '18%', size: 2.5, delay: 0 },
  { top: '22%', left: '78%', size: 2, delay: 0.6 },
  { top: '48%', left: '8%', size: 1.5, delay: 1.2 },
  { top: '65%', left: '85%', size: 2.5, delay: 0.3 },
  { top: '8%', left: '52%', size: 1.5, delay: 1.6 },
  { top: '80%', left: '30%', size: 2, delay: 0.9 },
];

/**
 * onboarding_intro_step.dart相当。サインアップ直後に表示する導入スライド。
 * 4ウェイポイント(Language/Profile/Permissions/Plan)のFlutter版に対し、
 * Web版はPermissionsが無いため3ウェイポイント(Language/Profile/Plan)の
 * ロードマップにする。
 */
export const OnboardingIntroStep: React.FC<{ onNext: () => void }> = ({ onNext }) => {
  const { t } = useLanguage();
  const [headerVisible, setHeaderVisible] = useState(false);
  const [nodesVisible, setNodesVisible] = useState(false);
  const [ctaVisible, setCtaVisible] = useState(false);

  useEffect(() => {
    const timers = [
      setTimeout(() => setHeaderVisible(true), 80),
      setTimeout(() => setNodesVisible(true), 360),
      setTimeout(() => setCtaVisible(true), 1000),
    ];
    return () => timers.forEach(clearTimeout);
  }, []);

  const steps: WaypointSpec[] = [
    {
      color: 'var(--blue)',
      Icon: Globe,
      title: t('onboardingIntroStepLanguageTitle'),
      desc: t('onboardingIntroStepLanguageDesc'),
      delayMs: 0,
    },
    {
      color: 'var(--green)',
      Icon: User,
      title: t('onboardingIntroStepProfileTitle'),
      desc: t('onboardingIntroStepProfileDesc'),
      delayMs: 220,
    },
    {
      color: 'var(--gold)',
      Icon: Award,
      title: t('onboardingIntroStepPlanTitle'),
      desc: t('onboardingIntroStepPlanDesc'),
      delayMs: 440,
    },
  ];

  return (
    <div className="onb-intro">
      <div className="onb-intro-stars" aria-hidden="true">
        {STARS.map((s, i) => (
          <span
            key={i}
            className="onb-star"
            style={{
              top: s.top,
              left: s.left,
              width: s.size,
              height: s.size,
              animationDelay: `${s.delay}s`,
            }}
          />
        ))}
      </div>

      <div className={`onb-fade-up ${headerVisible ? 'is-visible' : ''}`}>
        <div className="onb-intro-eyebrow-row">
          <span className="onb-intro-eyebrow-rule" />
          <span className="onb-intro-eyebrow">{t('onboardingIntroEyebrow').toUpperCase()}</span>
        </div>
      </div>
      <div className={`onb-fade-up onb-fade-up-delay-1 ${headerVisible ? 'is-visible' : ''}`}>
        <h1 className="onb-intro-title">{t('onboardingIntroTitle')}</h1>
      </div>
      <div className={`onb-fade-up onb-fade-up-delay-2 ${headerVisible ? 'is-visible' : ''}`}>
        <p className="onb-intro-subtitle">{t('onboardingIntroSubtitle')}</p>
      </div>

      <div className="onb-waypoints">
        {steps.map((step, i) => (
          <Waypoint
            key={i}
            spec={step}
            visible={nodesVisible}
            nextColor={i < steps.length - 1 ? steps[i + 1].color : step.color}
            stepNumber={i + 1}
            showConnector={i < steps.length - 1}
          />
        ))}
      </div>

      <div className={`onb-fade-up ${ctaVisible ? 'is-visible' : ''}`}>
        <button type="button" className="onb-cta-btn" onClick={onNext}>
          {t('onboardingGetStartedButton')}
        </button>
        <p className="onb-intro-hint">{t('onboardingIntroHint')}</p>
      </div>
    </div>
  );
};

const Waypoint: React.FC<{
  spec: WaypointSpec;
  visible: boolean;
  nextColor: string;
  stepNumber: number;
  showConnector: boolean;
}> = ({ spec, visible, nextColor, stepNumber, showConnector }) => {
  const [shown, setShown] = useState(false);

  useEffect(() => {
    if (!visible) return;
    const timer = setTimeout(() => setShown(true), spec.delayMs);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  const Icon = spec.Icon;

  return (
    <div className={`onb-waypoint ${shown ? 'is-shown' : ''}`}>
      <div className="onb-waypoint-rail">
        <div className="onb-waypoint-node" style={{ ['--node-color' as string]: spec.color }}>
          <Icon size={18} color="#fff" />
        </div>
        {showConnector && (
          <div
            className="onb-waypoint-connector"
            style={{ ['--from-color' as string]: spec.color, ['--to-color' as string]: nextColor }}
          />
        )}
      </div>
      <div className="onb-waypoint-body">
        <span className="onb-waypoint-step-badge" style={{ ['--node-color' as string]: spec.color }}>
          STEP {stepNumber}
        </span>
        <h3 className="onb-waypoint-title">{spec.title}</h3>
        <p className="onb-waypoint-desc">{spec.desc}</p>
      </div>
    </div>
  );
};
