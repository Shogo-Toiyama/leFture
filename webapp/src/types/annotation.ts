/**
 * review_cards / deep_notes の metadata.annotations 配列の1要素。
 * user_interface/lib/domain/entities/annotation.dart と同一スキーマ。
 *
 * start_idx / end_idx は「Markdown記法とSID引用を取り除いたフラット化テキスト」
 * 上のオフセット。詳しくは lib/markdownAnnotations.ts を参照。
 */
export type AnnotationType = 'highlight' | 'notes';

/** highlight用の contents。marker=背景塗り, line=下線, wave=波線。 */
export interface HighlightContents {
  type: 'marker' | 'line' | 'wave';
  color: string;
}

/** notes の contents はノート本文の文字列そのもの。 */
export type AnnotationContents = HighlightContents | string | null;

export interface Annotation {
  id: string;
  /** ReviewCardのcard_content内のブロックindex。DeepNotesはnull/undefined。 */
  block_idx?: number | null;
  start_idx: number;
  end_idx: number;
  annotation_type: AnnotationType;
  /** 保存時点で選択されていたテキスト(検証・再アンカリング用)。 */
  annotated_words: string;
  contents: AnnotationContents;
}

export const HIGHLIGHT_PRESET_COLORS = [
  '#FFB300', // Star Gold
  '#EF5350', // Red
  '#F06292', // Pink
  '#BA68C8', // Purple
  '#7986CB', // Indigo
  '#64B5F6', // Blue
  '#4DB6AC', // Teal
  '#81C784', // Green
  '#FF9800', // Orange
] as const;

export const NOTE_MARKER_COLOR = '#C5A059';

export function isHighlightContents(contents: AnnotationContents): contents is HighlightContents {
  return typeof contents === 'object' && contents !== null && 'type' in contents;
}

export function noteText(annotation: Annotation): string {
  return typeof annotation.contents === 'string' ? annotation.contents : '';
}

export function createAnnotationId(): string {
  return crypto.randomUUID();
}
