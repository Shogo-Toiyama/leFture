import React, { useMemo } from 'react';
import { AppColors } from '../../theme/colors';
import { useLanguage } from '../../i18n/LanguageContext';
import { type TranslationKey } from '../../i18n/translations';

export type PasswordStrength = 'empty' | 'weak' | 'fair' | 'good' | 'strong';

export interface PasswordRequirement {
  id: 'minLength' | 'upperLower' | 'digit' | 'symbol';
  labelKey: TranslationKey;
  isMet: boolean;
}

export interface PasswordStrengthResult {
  strength: PasswordStrength;
  requirements: PasswordRequirement[];
  filledSegments: number;
  labelKey: TranslationKey | null;
  color: string;
}

export function evaluatePasswordStrength(password: string): PasswordStrengthResult {
  const hasMinLength = password.length >= 8;
  const hasLongLength = password.length >= 12;
  const hasUpperAndLower = /[A-Z]/.test(password) && /[a-z]/.test(password);
  const hasDigit = /[0-9]/.test(password);
  const hasSymbol = /[!@#$%^&*(),.?":{}|<>_\-[\]/\\+=~`]/.test(password);

  const requirements: PasswordRequirement[] = [
    { id: 'minLength', labelKey: 'reqMinLength', isMet: hasMinLength },
    { id: 'upperLower', labelKey: 'reqUpperLower', isMet: hasUpperAndLower },
    { id: 'digit', labelKey: 'reqDigit', isMet: hasDigit },
    { id: 'symbol', labelKey: 'reqSymbol', isMet: hasSymbol },
  ];

  if (!password) {
    return {
      strength: 'empty',
      requirements,
      filledSegments: 0,
      labelKey: null,
      color: AppColors.universe.glassBorder,
    };
  }

  let score = 0;
  if (hasMinLength) score++;
  if (hasLongLength) score++;
  if (hasUpperAndLower) score++;
  if (hasDigit) score++;
  if (hasSymbol) score++;
  if (!hasMinLength) score = Math.min(score, 1);

  let strength: PasswordStrength = 'weak';
  let filledSegments = 1;
  let labelKey: TranslationKey = 'strengthWeak';
  let color: string = AppColors.correctionRed;

  if (score >= 5) {
    strength = 'strong';
    filledSegments = 4;
    labelKey = 'strengthStrong';
    color = AppColors.growthGreen;
  } else if (score >= 3) {
    strength = 'good';
    filledSegments = 3;
    labelKey = 'strengthGood';
    color = AppColors.starGold;
  } else if (score === 2) {
    strength = 'fair';
    filledSegments = 2;
    labelKey = 'strengthFair';
    color = AppColors.alertAmber;
  }

  return {
    strength,
    requirements,
    filledSegments,
    labelKey,
    color,
  };
}

interface PasswordStrengthMeterProps {
  password: string;
}

export const PasswordStrengthMeter: React.FC<PasswordStrengthMeterProps> = ({ password }) => {
  const { t } = useLanguage();
  const result = useMemo(() => evaluatePasswordStrength(password), [password]);

  if (result.strength === 'empty') {
    return null;
  }

  return (
    <div className="password-strength-meter">
      <div className="strength-bar-row">
        <div className="strength-segments">
          {[0, 1, 2, 3].map((index) => (
            <div
              key={index}
              className="strength-segment"
              style={{
                backgroundColor:
                  index < result.filledSegments
                    ? result.color
                    : AppColors.universe.glassBorder,
              }}
            />
          ))}
        </div>
        {result.labelKey && (
          <span className="strength-label" style={{ color: result.color }}>
            {t(result.labelKey)}
          </span>
        )}
      </div>

      <div className="strength-reqs">
        {result.requirements.map((req) => (
          <div
            key={req.id}
            className={`strength-req-item ${req.isMet ? 'is-met' : ''}`}
          >
            <span className="req-icon">
              {req.isMet ? (
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
              ) : (
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <circle cx="12" cy="12" r="9" />
                </svg>
              )}
            </span>
            <span className="req-text">{t(req.labelKey)}</span>
          </div>
        ))}
      </div>
    </div>
  );
};
