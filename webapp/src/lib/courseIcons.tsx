import React from 'react';
import {
  GraduationCap,
  Book,
  FlaskConical,
  Code,
  Calculator,
  Brain,
  Landmark,
  Languages,
  Palette,
  Music,
  Globe,
  Dna,
  type LucideProps,
} from 'lucide-react';

/**
 * course.metadata.icon(文字列キー)→lucide-reactアイコンの対応表。
 * Flutter版のcourse_style_helper.dartのiconMapと同じキー名(school/book/science等)を
 * webapp側のプリセット(CourseEditModal.tsxのPRESET_ICONS)に合わせて対応させている
 * (Flutterは70種以上のフルライブラリを持つが、webappは現状12種のプリセットのみ)。
 */
const COURSE_ICON_MAP: Record<string, React.ComponentType<LucideProps>> = {
  school: GraduationCap,
  book: Book,
  science: FlaskConical,
  code: Code,
  calculate: Calculator,
  psychology: Brain,
  history_edu: Landmark,
  language: Languages,
  palette: Palette,
  music_note: Music,
  public: Globe,
  biotech: Dna,
};

const DEFAULT_ICON = GraduationCap;

/** 未知のiconキー・未設定の場合はcourse_style_helper.dartのデフォルト(school)にフォールバックする。 */
export function CourseIconGlyph({
  icon,
  ...props
}: { icon?: string | null } & LucideProps) {
  const Glyph = (icon && COURSE_ICON_MAP[icon]) || DEFAULT_ICON;
  return <Glyph {...props} />;
}

export const COURSE_ICON_KEYS = Object.keys(COURSE_ICON_MAP);
