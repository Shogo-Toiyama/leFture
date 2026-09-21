import React, { useState } from 'react';
import { Languages, Mic, ChevronRight } from 'lucide-react';
import { useLanguage } from '../../../i18n/LanguageContext';
import { useProfile } from '../../../hooks/useProfile';
import { LanguageSelectionSheet, type LanguageSheetMode } from '../../../components/account/LanguageSelectionSheet';
import { recordingLanguageNativeName } from '../../../i18n/recordingLanguages';
import { OnboardingStepHeader } from '../OnboardingStepHeader';
import { LanguageStepIllustration } from '../OnboardingIllustrations';

/**
 * onboarding_language_step.dart相当。表示言語/録音言語の2枚のカードは
 * account settingsと全く同じ`LanguageSelectionSheet`を開く — 選択肢や
 * 見た目が両画面で常に一致するようにするため。
 */
export const OnboardingLanguageStep: React.FC<{ onNext: () => void }> = ({ onNext }) => {
  const { t, language } = useLanguage();
  const { profile, refetch } = useProfile();
  const [sheetMode, setSheetMode] = useState<LanguageSheetMode | null>(null);

  const displayCode = profile?.metadata?.display_language || 'ja';
  const recordingCode = profile?.metadata?.recording_language || 'ja';

  return (
    <div className="onb-step-body">
      <OnboardingStepHeader
        eyebrow={t('onboardingLanguageEyebrow')}
        title={t('onboardingLanguageTitle')}
        subtitle={t('onboardingLanguageSubtitle')}
        eyebrowColor="var(--blue)"
      />

      <div className="onb-illustration">
        <LanguageStepIllustration />
      </div>

      <button type="button" className="onb-language-row" onClick={() => setSheetMode('display')}>
        <span className="onb-language-row-icon">
          <Languages size={20} />
        </span>
        <span className="onb-language-row-text">
          <span className="onb-language-row-title">{t('displayLanguage')}</span>
          <span className="onb-language-row-desc">{t('displayLanguageSubtitle')}</span>
        </span>
        <span className="onb-language-row-value">
          {recordingLanguageNativeName(displayCode, language)}
          <ChevronRight size={18} />
        </span>
      </button>

      <button type="button" className="onb-language-row" onClick={() => setSheetMode('recording')}>
        <span className="onb-language-row-icon">
          <Mic size={20} />
        </span>
        <span className="onb-language-row-text">
          <span className="onb-language-row-title">{t('recordingLanguageLabel')}</span>
          <span className="onb-language-row-desc">{t('recordingLanguageSubtitle')}</span>
        </span>
        <span className="onb-language-row-value">
          {recordingLanguageNativeName(recordingCode, language)}
          <ChevronRight size={18} />
        </span>
      </button>

      <p className="onb-footer-note">{t('onboardingLanguageFooterNote')}</p>

      <div className="onb-step-spacer" />

      <button type="button" className="onb-cta-btn" onClick={onNext}>
        {t('continue')}
      </button>

      {sheetMode && (
        <LanguageSelectionSheet
          open={Boolean(sheetMode)}
          onClose={() => setSheetMode(null)}
          mode={sheetMode}
          profile={profile}
          onUpdated={refetch}
        />
      )}
    </div>
  );
};
