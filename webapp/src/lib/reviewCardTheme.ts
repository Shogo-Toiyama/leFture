import type { ReviewCardBlock } from '../types/content';
import { stripSidCitations } from './sidCitation';

/** review_cards_viewer_page.dart の reviewCardTypeColor と同じ配色。 */
export function reviewCardTypeColor(cardType: string | null | undefined): string {
  switch ((cardType ?? '').toLowerCase()) {
    case 'core_why':
      return '#42A5F5';
    case 'gotcha':
      return '#FF9A3D';
    case 'next_action':
      return '#B98BFF';
    case 'hook':
    default:
      return '#FFB300';
  }
}

/** #RRGGBB / #AARRGGBB を r,g,b に分解する。解釈できなければ null。 */
function parseHex(hex: string): [number, number, number] | null {
  const raw = hex.trim().replace('#', '');
  const body = raw.length === 8 ? raw.slice(2) : raw;
  if (!/^[0-9a-fA-F]{6}$/.test(body)) return null;
  return [
    parseInt(body.slice(0, 2), 16),
    parseInt(body.slice(2, 4), 16),
    parseInt(body.slice(4, 6), 16),
  ];
}

/**
 * コースカラーが明るすぎるとクリーム紙の上で文字/罫線として読めないため、
 * HSLのlightnessが0.65を超える色は0.5まで落とす。
 * course_style_helper.dart 側の textThemeColor と同じ考え方。
 */
export function readableAccent(hex: string | null | undefined, fallback = '#FFB300'): string {
  const rgb = parseHex(hex ?? '') ?? parseHex(fallback);
  if (!rgb) return fallback;
  const [r, g, b] = rgb.map((v) => v / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (l <= 0.65) return `#${rgb.map((v) => v.toString(16).padStart(2, '0')).join('')}`;

  const d = max - min;
  const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  let h = 0;
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
  }
  return hslToHex(h, s, 0.5);
}

function hslToHex(h: number, s: number, l: number): string {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  const seg = Math.floor(h / 60) % 6;
  const table: [number, number, number][] = [
    [c, x, 0],
    [x, c, 0],
    [0, c, x],
    [0, x, c],
    [x, 0, c],
    [c, 0, x],
  ];
  const [r, g, b] = table[seg];
  return `#${[r, g, b]
    .map((v) => Math.round((v + m) * 255).toString(16).padStart(2, '0'))
    .join('')}`;
}

/** タイル用の短いプレビュー文字列。text_preview.dart の plainTextPreview 相当。 */
export function plainTextPreview(blocks: ReviewCardBlock[], maxLength = 90): string {
  const first = blocks.find((b) => (b.text ?? '').trim().length > 0 || (b.items ?? []).length > 0);
  if (!first) return '';
  const source = (first.text ?? '') || (first.items ?? []).join(' ');
  const flat = stripSidCitations(source)
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[*_`>#-]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return flat.length > maxLength ? `${flat.slice(0, maxLength).trimEnd()}…` : flat;
}
