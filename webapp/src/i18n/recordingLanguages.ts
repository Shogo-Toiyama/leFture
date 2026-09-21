// user_interface/lib/domain/entities/app_language.dart の kRecordingLanguages /
// kAutoDetectLanguageCode と1対1対応させたリスト。Web側でも録音(文字起こし)
// 言語はUI翻訳(SUPPORTED_LANGUAGES)とは無関係な別の一覧として独立させる。

export const AUTO_DETECT_LANGUAGE_CODE = 'auto';

export interface RecordingLanguageOption {
  code: string;
  nativeName: string;
  englishName: string;
}

export const RECORDING_LANGUAGES: RecordingLanguageOption[] = [
  { code: AUTO_DETECT_LANGUAGE_CODE, nativeName: 'Auto-detect', englishName: 'Auto-detect' },
  { code: 'en', nativeName: 'English', englishName: 'English' },
  { code: 'ja', nativeName: '日本語', englishName: 'Japanese' },
  { code: 'fr', nativeName: 'Français', englishName: 'French' },
  { code: 'es', nativeName: 'Español', englishName: 'Spanish' },
  { code: 'de', nativeName: 'Deutsch', englishName: 'German' },
  { code: 'zh', nativeName: '中文', englishName: 'Chinese' },
  { code: 'yue', nativeName: '廣東話', englishName: 'Cantonese' },
  { code: 'ko', nativeName: '한국어', englishName: 'Korean' },
  { code: 'pt', nativeName: 'Português', englishName: 'Portuguese' },
  { code: 'it', nativeName: 'Italiano', englishName: 'Italian' },
  { code: 'ru', nativeName: 'Русский', englishName: 'Russian' },
  { code: 'ar', nativeName: 'العربية', englishName: 'Arabic' },
  { code: 'hi', nativeName: 'हिन्दी', englishName: 'Hindi' },
];

// app_language.dartのlocalizedName()の日本語分岐と同じ対応表。
const JA_LOCALIZED_NAMES: Record<string, string> = {
  en: '英語',
  ja: '日本語',
  fr: 'フランス語',
  es: 'スペイン語',
  de: 'ドイツ語',
  zh: '中国語',
  yue: '広東語',
  ko: '韓国語',
  pt: 'ポルトガル語',
  it: 'イタリア語',
  ru: 'ロシア語',
  ar: 'アラビア語',
  hi: 'ヒンディー語',
};

function findRecordingLanguage(code: string): RecordingLanguageOption | undefined {
  return RECORDING_LANGUAGES.find((l) => l.code === code);
}

/** app_language.dartのgetNativeName()相当。'auto'は表示言語に応じた案内文言にする。 */
export function recordingLanguageNativeName(code: string, displayLanguage: string): string {
  if (code === AUTO_DETECT_LANGUAGE_CODE) {
    return displayLanguage === 'ja' ? '自動判定' : 'Auto-detect';
  }
  return findRecordingLanguage(code)?.nativeName ?? code;
}

/** app_language.dartのlocalizedName()相当。現在の表示言語に翻訳した言語名(補足テキスト)。 */
export function recordingLanguageLocalizedName(code: string, displayLanguage: string): string | null {
  if (code === AUTO_DETECT_LANGUAGE_CODE) {
    return displayLanguage === 'ja'
      ? '複数言語が混ざる講義を録音する場合に選択'
      : 'Use when multiple languages are spoken in class';
  }
  if (displayLanguage === 'ja') return JA_LOCALIZED_NAMES[code] ?? findRecordingLanguage(code)?.englishName ?? code;
  return findRecordingLanguage(code)?.englishName ?? code;
}
