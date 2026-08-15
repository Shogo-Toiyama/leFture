import { ja } from './locales/ja';
import { en } from './locales/en';
import { Locale, Translations } from './types';

export * from './types';

export const translations: Record<Locale, Translations> = {
  ja,
  en,
};
