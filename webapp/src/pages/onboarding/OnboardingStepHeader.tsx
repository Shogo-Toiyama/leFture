import React from 'react';

/**
 * user_interface/.../onboarding_step_header.dart 相当。
 * eyebrow + title (+ optional subtitle) をステップ共通のトンマナで並べる。
 */
export const OnboardingStepHeader: React.FC<{
  eyebrow: string;
  title: string;
  subtitle?: string;
  eyebrowColor: string;
}> = ({ eyebrow, title, subtitle, eyebrowColor }) => (
  <div className="onb-step-header">
    <span className="onb-step-eyebrow" style={{ color: eyebrowColor }}>
      {eyebrow}
    </span>
    <h2 className="onb-step-title">{title}</h2>
    {subtitle && <p className="onb-step-subtitle">{subtitle}</p>}
  </div>
);
