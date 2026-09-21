import React, { useState } from 'react';
import { AdaptiveSheet } from '../modals/AdaptiveSheet';
import { Check } from 'lucide-react';
import { setLanguagePreferences } from '../../lib/profile';
import { notifyProfileUpdate } from '../../hooks/useProfile';
import { useLanguage } from '../../i18n/LanguageContext';
import { LANGUAGE_META, SUPPORTED_LANGUAGES, isLanguage } from '../../i18n/translations';
import {
  RECORDING_LANGUAGES,
  recordingLanguageLocalizedName,
  recordingLanguageNativeName,
} from '../../i18n/recordingLanguages';
import type { UserProfile } from '../../types/profile';

export type LanguageSheetMode = 'display' | 'recording';

interface LanguageOption {
  code: string;
  nativeName: string;
  englishName: string;
}

// 表示言語(UI翻訳)の選択肢は、翻訳辞書が実際に存在する言語からそのまま
// 導出する。個別にハードコードすると、辞書に新言語を足してもここに
// 反映し忘れる(=selectしても表示が変わらない)バグが起きるため。
const DISPLAY_LANGUAGES: LanguageOption[] = SUPPORTED_LANGUAGES.map((code) => ({
  code,
  nativeName: LANGUAGE_META[code].nativeName,
  englishName: LANGUAGE_META[code].englishName,
}));

interface LanguageSelectionSheetProps {
  open: boolean;
  onClose: () => void;
  mode: LanguageSheetMode;
  profile: UserProfile | null;
  onUpdated: () => Promise<void>;
}

export const LanguageSelectionSheet: React.FC<LanguageSelectionSheetProps> = ({
  open,
  onClose,
  mode,
  profile,
  onUpdated,
}) => {
  const { t, language, setLanguage } = useLanguage();
  const options = mode === 'display' ? DISPLAY_LANGUAGES : RECORDING_LANGUAGES;

  const currentVal =
    mode === 'display'
      ? profile?.metadata?.display_language || 'ja'
      : profile?.metadata?.recording_language || 'ja';

  const [selected, setSelected] = useState(currentVal);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  React.useEffect(() => {
    if (open) {
      setSelected(currentVal);
    }
  }, [open, currentVal]);

  const title = mode === 'display' ? t('displayLanguage') : t('recordingLanguageLabel');
  const subtitle = mode === 'display' ? t('displayLanguageSubtitle') : t('recordingLanguageSubtitle');

  const handleSelect = async (code: string) => {
    setSelected(code);
    setSaving(true);
    setError(null);
    try {
      const displayLang = mode === 'display' ? code : profile?.metadata?.display_language || 'ja';
      const recordingLang = mode === 'recording' ? code : profile?.metadata?.recording_language || 'ja';

      const updated = await setLanguagePreferences(profile?.metadata ?? null, displayLang, recordingLang);
      notifyProfileUpdate(updated);
      if (mode === 'display' && isLanguage(code)) {
        setLanguage(code);
      }
      await onUpdated();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : t('failedToSaveLanguage'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <AdaptiveSheet open={open} onClose={onClose} title={title} subtitle={subtitle}>
      <div className="language-sheet-content">
        {error && <p className="auth-error">{error}</p>}

        <div className="language-options-list">
          {options.map((opt) => {
            const isSelected = selected === opt.code;
            const mainLabel = recordingLanguageNativeName(opt.code, language);
            const subLabel = recordingLanguageLocalizedName(opt.code, language);
            return (
              <button
                key={opt.code}
                type="button"
                className={`language-option-row ${isSelected ? 'is-selected' : ''}`}
                onClick={() => handleSelect(opt.code)}
                disabled={saving}
              >
                <div className="language-option-text">
                  <span className="language-native-name">{mainLabel}</span>
                  {subLabel && <span className="language-english-name">{subLabel}</span>}
                </div>
                {isSelected && <Check size={18} className="language-option-check" />}
              </button>
            );
          })}
        </div>
      </div>
    </AdaptiveSheet>
  );
};
