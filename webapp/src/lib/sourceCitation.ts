import {
  buildRawToStrippedMap,
  buildStrippedToRawMap,
  parseSidCitations,
  stripSidCitations,
  type SidCitation,
} from './sidCitation';

/**
 * 選択範囲から「出典」を引くための座標変換。
 *
 * 保存されるアノテーションの座標系は、本文から
 *   1. SID引用記法を取り除き
 *   2. Markdown記法を取り除いて全テキストを連結した
 * 平坦なテキスト上のオフセット(annotation_text_utils.dartのFlattenedTextMap)。
 *
 * モバイル版はMarkdownを再パースしてこの対応表を作るが、ウェブでは
 * 描画済みDOMのtextContentがそのまま「平坦化後のテキスト」になっている。
 * 平坦化はMarkdown記法の文字を「削るだけ」で並べ替えも挿入もしないので、
 * 二つの文字列を先頭から突き合わせるだけで対応表が作れる。
 */
export class FlattenedTextMap {
  readonly flattenedText: string;
  private readonly flatToRaw: number[];
  private readonly rawToFlat: number[];

  private constructor(flattenedText: string, flatToRaw: number[], rawToFlat: number[]) {
    this.flattenedText = flattenedText;
    this.flatToRaw = flatToRaw;
    this.rawToFlat = rawToFlat;
  }

  static build(rawMarkdown: string, flattenedText: string): FlattenedTextMap {
    const stripped = stripSidCitations(rawMarkdown);
    const strippedToRaw = buildStrippedToRawMap(rawMarkdown);
    const rawToStripped = buildRawToStrippedMap(rawMarkdown);

    // flattened の各文字が stripped のどこから来たかを貪欲に対応付ける。
    const flatToStripped: number[] = [];
    let si = 0;
    for (let fi = 0; fi < flattenedText.length; fi += 1) {
      while (si < stripped.length && stripped[si] !== flattenedText[fi]) si += 1;
      if (si >= stripped.length) {
        // 対応が取れなくなったら以降は末尾に寄せる(壊れた入力でも落とさない)
        flatToStripped.push(stripped.length);
        continue;
      }
      flatToStripped.push(si);
      si += 1;
    }
    flatToStripped.push(stripped.length);

    const clamp = (value: number, max: number) => Math.min(Math.max(value, 0), max);

    const flatToRaw = flatToStripped.map(
      (s) => strippedToRaw[clamp(s, strippedToRaw.length - 1)]
    );

    // rawIdx → その位置以降で最初に現れる平坦化後の位置。
    const rawToFlat = new Array<number>(rawMarkdown.length + 1).fill(flattenedText.length);
    for (let rawIdx = 0; rawIdx <= rawMarkdown.length; rawIdx += 1) {
      const target = rawToStripped[clamp(rawIdx, rawToStripped.length - 1)];
      rawToFlat[rawIdx] = lowerBound(flatToStripped, target);
    }

    return new FlattenedTextMap(flattenedText, flatToRaw, rawToFlat);
  }

  toRaw(flattenedIdx: number): number {
    const i = Math.min(Math.max(flattenedIdx, 0), this.flatToRaw.length - 1);
    return this.flatToRaw[i];
  }

  toFlattened(rawIdx: number): number {
    const i = Math.min(Math.max(rawIdx, 0), this.rawToFlat.length - 1);
    return this.rawToFlat[i];
  }
}

/** 非減少列 [values] で value 以上になる最初のindex。 */
function lowerBound(values: number[], value: number): number {
  let lo = 0;
  let hi = values.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (values[mid] < value) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

export interface SourceContext {
  /** 出典として採用した引用(複数選択時は選択内の全引用)。 */
  citations: SidCitation[];
  /** 重複を除いた "s000010" 形式のSID。 */
  sidStrings: string[];
}

/**
 * 選択範囲に対応する出典を探す。
 *
 * 引用マーカーは「それが支える文の直後」に置かれるので、原則として
 * 選択範囲の直後にある引用が出典になる(findSourceCitation と同じ考え方)。
 * 複数の文をまたいで選択された場合は、モバイル版のように選択のやり直しを
 * 求めるのではなく、選択に含まれる引用をすべて採用する。
 *
 * @param rawMarkdown 引用記法を含む元のMarkdown
 * @param flattenedText 描画済みDOMのtextContent(= 選択オフセットの座標系)
 */
export function findSourceForSelection(
  rawMarkdown: string,
  flattenedText: string,
  startIdx: number,
  endIdx: number
): SourceContext | null {
  const citations = parseSidCitations(rawMarkdown);
  if (citations.length === 0) return null;

  const map = FlattenedTextMap.build(rawMarkdown, flattenedText);
  const rawStart = map.toRaw(startIdx);
  const rawEnd = map.toRaw(endIdx);

  const inside = citations.filter((c) => c.start >= rawStart && c.end <= rawEnd);
  if (inside.length > 0) return toContext(inside);

  let next: SidCitation | null = null;
  for (const c of citations) {
    if (c.start >= rawEnd && (next === null || c.start < next.start)) next = c;
  }
  if (next) return toContext([next]);

  // 選択が最後の引用より後ろにある場合は、直前の引用を出典として扱う。
  let prev: SidCitation | null = null;
  for (const c of citations) {
    if (c.end <= rawStart && (prev === null || c.end > prev.end)) prev = c;
  }
  return prev ? toContext([prev]) : null;
}

function toContext(citations: SidCitation[]): SourceContext {
  const seen = new Set<string>();
  const sidStrings: string[] = [];
  for (const c of citations) {
    for (const sid of c.sidStrings) {
      if (seen.has(sid)) continue;
      seen.add(sid);
      sidStrings.push(sid);
    }
  }
  return { citations, sidStrings };
}
