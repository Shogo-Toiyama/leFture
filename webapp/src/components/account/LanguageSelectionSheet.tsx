import React, { useState } from 'react';
import { AdaptiveSheet } from '../modals/AdaptiveSheet';
import { Check } from 'lucide-react';
import { setLanguagePreferences } from '../../lib/profile';
import { notifyProfileUpdate } from '../../hooks/useProfile';
import { useLanguage } from '../../i18n/LanguageContext';
import type { UserProfile } from '../../types/profile';

export type LanguageSheetMode = 'display' | 'recording';

interface LanguageOption {
  code: string;
  nativeName: string;
  englishName: string;
}

const DISPLAY_LANGUAGES: LanguageOption[] = [
  { code: 'ja', nativeName: '日本語', englishName: 'Japanese' },
  { code: 'en', nativeName: 'English', englishName: 'English' },
];

const RECORDING_LANGUAGES: LanguageOption[] = [
  { code: 'ja', nativeName: '日本語', englishName: 'Japanese' },
  { code: 'en', nativeName: 'English', englishName: 'English' },
  { code: 'zh', nativeName: '中文', englishName: 'Chinese' },
  { code: 'es', nativeName: 'Español', englishName: 'Spanish' },
  { code: 'fr', nativeName: 'Français', englishName: 'French' },
  { code: 'de', nativeName: 'Deutsch', englishName: 'German' },
  { code: 'ko', nativeName: '한국語', englishName: 'Korean' },
];

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
  const { language, setLanguage } = useLanguage();
  const isJa = language === 'ja';
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

  const title =
    mode === 'display'
      ? isJa
        ? '表示言語'
        : 'Display Language'
      : isJa
        ? '録音言語'
        : 'Recording Language';
  const subtitle =
    mode === 'display'
      ? isJa
        ? 'インターフェースとメニューで使用する言語を選択'
        : 'Choose the language used for interface and menus'
      : isJa
        ? '音声書き起こし時のデフォルト言語を選択'
        : 'Choose the default spoken language when transcribing audio';

  const handleSelect = async (code: string) => {
    setSelected(code);
    setSaving(true);
    setError(null);
    try {
      const displayLang = mode === 'display' ? code : profile?.metadata?.display_language || 'ja';
      const recordingLang = mode === 'recording' ? code : profile?.metadata?.recording_language || 'ja';

      const updated = await setLanguagePreferences(profile?.metadata ?? null, displayLang, recordingLang);
      notifyProfileUpdate(updated);
      if (mode === 'display' && (code === 'ja' || code === 'en')) {
        setLanguage(code);
      }
      await onUpdated();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save language');
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
            return (
              <button
                key={opt.code}
                type="button"
                className={`language-option-row ${isSelected ? 'is-selected' : ''}`}
                onClick={() => handleSelect(opt.code)}
                disabled={saving}
              >
                <div className="language-option-text">
                  <span className="language-native-name">{opt.nativeName}</span>
                  <span className="language-english-name">{opt.englishName}</span>
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
