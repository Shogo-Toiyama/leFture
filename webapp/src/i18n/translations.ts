import { en } from './locales/en';
import { ja } from './locales/ja';

/**
 * サポート言語の唯一の定義箇所。ここに1件足す(辞書ファイル追加+このオブジェクトへの
 * 登録)だけで、Language型・翻訳辞書・表示名一覧・言語判定(isLanguage)・
 * ロケール(Intl用)が全て自動的に追従する。
 *
 * 以前はLanguageContext.detectInitialLanguage/Layout.tsx/LanguageSelectionSheet.tsx
 * の3箇所以上に「'ja' || 'en'」の判定が個別にハードコードされており、新しい言語の
 * 辞書を追加しても、それらの判定漏れにより実際にはUIが英語のまま切り替わらない
 * (=保存はされるが表示に反映されない)というバグを生みやすい構造だった。
 */
export const LANGUAGE_META = {
  en: { dictionary: en, locale: 'en-US', nativeName: 'English', englishName: 'English' },
  ja: { dictionary: ja, locale: 'ja-JP', nativeName: '日本語', englishName: 'Japanese' },
} as const;

export type Language = keyof typeof LANGUAGE_META;

export const SUPPORTED_LANGUAGES = Object.keys(LANGUAGE_META) as Language[];

export const DEFAULT_LANGUAGE: Language = 'en';

export function isLanguage(value: string | null | undefined): value is Language {
  return !!value && (SUPPORTED_LANGUAGES as string[]).includes(value);
}

export const translations: Record<Language, Record<keyof typeof en, string>> = Object.fromEntries(
  SUPPORTED_LANGUAGES.map((lang) => [lang, LANGUAGE_META[lang].dictionary])
) as Record<Language, Record<keyof typeof en, string>>;

export const LOCALE_MAP: Record<Language, string> = Object.fromEntries(
  SUPPORTED_LANGUAGES.map((lang) => [lang, LANGUAGE_META[lang].locale])
) as Record<Language, string>;

export type TranslationKey = keyof typeof en;
