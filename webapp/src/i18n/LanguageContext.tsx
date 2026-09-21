import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import {
  translations,
  LOCALE_MAP,
  SUPPORTED_LANGUAGES,
  DEFAULT_LANGUAGE,
  isLanguage,
  type Language,
  type TranslationKey,
} from './translations';

/**
 * tの型だけを単独で必要とする箇所(Reactコンポーネント外のplain関数にtを
 * 引数として渡す場合など)向けにエクスポートしておく。
 */
export type Translate = (key: TranslationKey, params?: Record<string, string | number | undefined | null>) => string;

interface LanguageContextValue {
  language: Language;
  locale: string;
  setLanguage: (lang: Language) => void;
  t: Translate;
  formatDate: (date: string | number | Date, options?: Intl.DateTimeFormatOptions) => string;
  formatNumber: (value: number, options?: Intl.NumberFormatOptions) => string;
}

const LanguageContext = createContext<LanguageContextValue | undefined>(undefined);

const STORAGE_KEY = 'orbit_app_language';

function detectInitialLanguage(): Language {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (isLanguage(saved)) return saved;

  // navigator.languagesはユーザーの優先順位リスト全体(例: ['fr-CA', 'fr', 'en'])。
  // navigator.language(先頭1件)だけを見ると、優先1位が未対応言語なだけで
  // 2位以降がサポート対象でも無視して既定値に落ちてしまうため、リスト全体を
  // 「xx-YY」「xx」の順に対応言語と突き合わせる。
  const candidates = navigator.languages?.length ? navigator.languages : [navigator.language || ''];
  for (const raw of candidates) {
    const lower = raw.toLowerCase();
    if (isLanguage(lower)) return lower;
    const base = lower.split('-')[0];
    if (isLanguage(base)) return base;
  }
  return DEFAULT_LANGUAGE;
}

export const LanguageProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [language, setLanguageState] = useState<Language>(detectInitialLanguage);

  const setLanguage = useCallback((lang: Language) => {
    setLanguageState(lang);
    localStorage.setItem(STORAGE_KEY, lang);
    document.documentElement.lang = lang;
  }, []);

  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);

  const locale = LOCALE_MAP[language] || LOCALE_MAP[DEFAULT_LANGUAGE];

  // t/formatDate/formatNumberはuseCallbackでlanguage(とそこから導出される
  // locale)にだけ依存させ、レンダーのたびに新しい関数を作らないようにする。
  // これを怠ると、呼び出し側のuseCallback/useEffectの依存配列にtを含めた
  // 瞬間、毎レンダーで依存が変わり続けて無限ループになる
  // (逆に依存配列からtを省くと、言語切替後もエラーメッセージ等が古い言語の
  // ままになるstale closureを埋め込むことになるため、どちらの回避策も
  // 正しい解決にならない。tそのものを安定させるのが唯一の正しい修正)。
  const t = useCallback<Translate>(
    (key, params) => {
      const langDict = translations[language] || translations[DEFAULT_LANGUAGE];
      let text: string = langDict[key] || translations[DEFAULT_LANGUAGE][key] || key;
      if (params) {
        Object.entries(params).forEach(([k, v]) => {
          text = text.replace(new RegExp(`\\{${k}\\}`, 'g'), String(v ?? ''));
        });
      }
      return text;
    },
    [language]
  );

  const formatDate = useCallback(
    (date: string | number | Date, options?: Intl.DateTimeFormatOptions): string => {
      const d = typeof date === 'string' || typeof date === 'number' ? new Date(date) : date;
      return d.toLocaleDateString(locale, options);
    },
    [locale]
  );

  const formatNumber = useCallback(
    (value: number, options?: Intl.NumberFormatOptions): string => new Intl.NumberFormat(locale, options).format(value),
    [locale]
  );

  const value = useMemo(
    () => ({ language, locale, setLanguage, t, formatDate, formatNumber }),
    [language, locale, setLanguage, t, formatDate, formatNumber]
  );

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
};

export function useLanguage(): LanguageContextValue {
  const ctx = useContext(LanguageContext);
  if (!ctx) {
    throw new Error('useLanguage must be used within a LanguageProvider');
  }
  return ctx;
}

export { SUPPORTED_LANGUAGES };
