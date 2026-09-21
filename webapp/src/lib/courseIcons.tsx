import React from 'react';
import { Apple } from 'lucide-react';
import type { TranslationKey } from '../i18n/translations';

/**
 * Flutter版 `CourseStyleHelper.dart` と完全同期したカラーパレット
 */
export const COURSE_PRESET_COLORS = [
  '#FFB300', // Star Gold (Primary)
  '#EF5350', // Red
  '#F06292', // Pink
  '#BA68C8', // Purple
  '#7986CB', // Indigo
  '#64B5F6', // Blue
  '#4DB6AC', // Teal
  '#81C784', // Green
  '#FF9800', // Orange
];

export const DEFAULT_COURSE_COLOR = '#FFB300';
export const DEFAULT_COURSE_ICON = 'school';

export interface CourseIconCategory {
  categoryKey: TranslationKey;
  emoji: string;
  iconNames: string[];
}

/**
 * Flutter版 `getCourseIconCategories()` と完全同期した9カテゴリ・全70種のアイコンリスト
 */
export const COURSE_ICON_CATEGORIES: CourseIconCategory[] = [
  {
    categoryKey: 'courseCategorySchool',
    emoji: '🎓',
    iconNames: ['school', 'book', 'menu_book', 'auto_stories', 'quiz', 'edit_note', 'workspace_premium'],
  },
  {
    categoryKey: 'courseCategoryHumanity',
    emoji: '✍️',
    iconNames: [
      'history_edu',
      'translate',
      'abc',
      'chat_bubble',
      'record_voice_over',
      'museum',
      'hourglass_empty',
      'self_improvement',
      'lightbulb',
      'psychology',
      'festival',
      'theater_comedy',
    ],
  },
  {
    categoryKey: 'courseCategorySociety',
    emoji: '⚖️',
    iconNames: ['gavel', 'balance', 'account_balance', 'how_to_vote', 'public', 'flag'],
  },
  {
    categoryKey: 'courseCategoryScience',
    emoji: '🔬',
    iconNames: [
      'functions',
      'calculate',
      'timeline',
      'science',
      'biotech',
      'nights_stay',
      'rocket_launch',
      'wb_sunny',
      'bolt',
    ],
  },
  {
    categoryKey: 'courseCategoryTech',
    emoji: '💻',
    iconNames: ['settings', 'construction', 'memory', 'terminal', 'code', 'architecture', 'domain'],
  },
  {
    categoryKey: 'courseCategoryAgri',
    emoji: '🌾',
    iconNames: ['agriculture', 'grass', 'nature', 'sailing', 'set_meal', 'phishing'],
  },
  {
    categoryKey: 'courseCategoryMedical',
    emoji: '🏥',
    iconNames: [
      'medical_services',
      'local_hospital',
      'vaccines',
      'medication',
      'health_and_safety',
      'monitor_heart',
      'sentiment_satisfied',
    ],
  },
  {
    categoryKey: 'courseCategorySports',
    emoji: '⚽',
    iconNames: ['sports_soccer', 'sports_basketball', 'fitness_center', 'directions_run', 'spa', 'apple'],
  },
  {
    categoryKey: 'courseCategoryArt',
    emoji: '🎨',
    iconNames: ['palette', 'brush', 'movie', 'theaters', 'flight_takeoff', 'luggage', 'attractions'],
  },
];

export const ALL_COURSE_ICON_KEYS = COURSE_ICON_CATEGORIES.flatMap((c) => c.iconNames);
export const COURSE_ICON_KEYS = ALL_COURSE_ICON_KEYS;

export interface CourseIconGlyphProps extends React.HTMLAttributes<HTMLSpanElement> {
  icon?: string | null;
  size?: number;
  color?: string;
}

/** 旧Web版の別名キーからFlutter標準キーへのマッピング */
const LEGACY_ICON_ALIAS_MAP: Record<string, string> = {
  language: 'translate',
  music_note: 'theaters',
};

/**
 * Material Symbols Outlined を使用してFlutter版と同じアイコンを描画するコンポーネント。
 */
export function CourseIconGlyph({
  icon,
  size = 20,
  color,
  className = '',
  style,
  ...rest
}: CourseIconGlyphProps) {
  const rawKey = (icon || '').trim();
  const glyphName = LEGACY_ICON_ALIAS_MAP[rawKey] || rawKey || DEFAULT_COURSE_ICON;

  // Google Material Symbols には商標の関係で「apple」フォントグリフが存在しないため、
  // Lucide の Apple ベクターアイコンを描画する
  if (glyphName === 'apple') {
    return (
      <span
        className={`course-material-glyph ${className}`}
        style={{
          width: `${size}px`,
          height: `${size}px`,
          lineHeight: 1,
          color: color,
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          userSelect: 'none',
          verticalAlign: 'middle',
          ...style,
        }}
        aria-hidden="true"
        {...rest}
      >
        <Apple size={size} strokeWidth={1.8} color="currentColor" />
      </span>
    );
  }

  return (
    <span
      className={`material-symbols-outlined course-material-glyph ${className}`}
      style={{
        fontSize: `${size}px`,
        width: `${size}px`,
        height: `${size}px`,
        lineHeight: 1,
        color: color,
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        userSelect: 'none',
        verticalAlign: 'middle',
        fontVariationSettings: "'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24",
        ...style,
      }}
      aria-hidden="true"
      {...rest}
    >
      {glyphName}
    </span>
  );
}
