/**
 * SID引用記法 (⟦s000010-s000012⟧) のパース/修復/除去。
 * user_interface/lib/core/utils/sid_citation.dart の移植。
 *
 * バックエンドのLLMが生成する本文には、トランスクリプトの文への引用が
 * この記法で埋め込まれる。LLM出力なので揺れがある前提でパースする:
 *   - 閉じカッコの欠落
 *   - 大文字の S / 0埋めされていない数字
 *   - 全角やUnicodeのカンマ・ハイフン
 *   - 類似の角カッコ (〚〛 [[ ]])
 *
 * 注意: [stripSidCitations] の結果はアノテーションの座標系そのものなので、
 * モバイル版と一字一句同じ文字列を返さなければならない。
 * 「引用の直前の空白だけを削る」以外の整形(全体のtrimや連続空白の圧縮)は
 * 絶対に足さないこと。
 */

const OPEN_BRACKETS = ['⟦', '〚', '[['];
const CLOSE_BRACKETS = ['⟧', '〛', ']]'];
const DASH_CHARS = '-‐‑‒–—―−－~〜～';
const COMMA_CHARS = ',，、;；';

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const OPEN_PATTERN = new RegExp(OPEN_BRACKETS.map(escapeRegExp).join('|'));
const CLOSE_PATTERN = new RegExp(CLOSE_BRACKETS.map(escapeRegExp).join('|'));
const VALID_BODY_CHAR = new RegExp(`[sS0-9 \\t${DASH_CHARS}${COMMA_CHARS}]`);
const SID_PATTERN = /[sS]\s*0*(\d{1,6})/;

export function formatSid(n: number): string {
  return `s${n.toString().padStart(6, '0')}`;
}

/** "s000010" のようなSIDから連番部分だけを取り出す。 */
function sidToNumber(sid: string | null | undefined): number | null {
  if (!sid) return null;
  const match = /[sS]\s*0*(\d{1,6})/.exec(sid);
  return match ? Number(match[1]) : null;
}

/**
 * start_sid〜end_sid(両端含む)を個々のSID文字列へ展開する。
 * announcements.start_sid/end_sidのように、範囲の両端しか持たないデータを
 * TranscriptView の highlightSids (Set<string>) に渡すための変換。
 */
export function expandSidRange(
  startSid: string | null | undefined,
  endSid: string | null | undefined
): string[] {
  const from = sidToNumber(startSid);
  const to = sidToNumber(endSid ?? startSid);
  if (from === null || to === null) return [];
  const [lo, hi] = from <= to ? [from, to] : [to, from];
  const sids: string[] = [];
  for (let i = lo; i <= hi; i += 1) sids.push(formatSid(i));
  return sids;
}

/** "s000010-s000012, s000020" のような中身をSID番号に展開する。 */
function parseSidBody(body: string): number[] {
  const sids: number[] = [];
  const parts = body.split(new RegExp(`[${COMMA_CHARS}]`));

  for (const rawPart of parts) {
    const trimmed = rawPart.trim();
    if (!trimmed) continue;

    const rangeSplit = trimmed.split(new RegExp(`[${DASH_CHARS}]`));
    if (rangeSplit.length >= 2) {
      const fromMatch = SID_PATTERN.exec(rangeSplit[0]);
      const toMatch = SID_PATTERN.exec(rangeSplit[rangeSplit.length - 1]);
      if (fromMatch && toMatch) {
        let from = Number(fromMatch[1]);
        let to = Number(toMatch[1]);
        if (from > to) [from, to] = [to, from];
        // 異常に広い範囲はLLMの暴走とみなして端点だけ採用する
        if (to - from > 5000) {
          sids.push(from, to);
        } else {
          for (let i = from; i <= to; i += 1) sids.push(i);
        }
        continue;
      }
    }

    const single = SID_PATTERN.exec(trimmed);
    if (single) sids.push(Number(single[1]));
  }

  return sids;
}

export interface SidCitation {
  /** マッチした生の文字列 (例: "⟦s000010-s000012⟧") */
  raw: string;
  /** 元テキスト内での開始オフセット */
  start: number;
  /** 元テキスト内での終了オフセット (exclusive) */
  end: number;
  /** 範囲を展開したSID番号 */
  sids: number[];
  /** "s000010" 形式 */
  sidStrings: string[];
}

/**
 * テキスト中の全SID引用を検出する。
 * 閉じカッコが無い場合は、引用として妥当な文字が続く範囲までを引用とみなす。
 */
export function parseSidCitations(text: string): SidCitation[] {
  const results: SidCitation[] = [];
  let searchStart = 0;

  while (searchStart < text.length) {
    const openMatch = OPEN_PATTERN.exec(text.slice(searchStart));
    if (!openMatch) break;

    const openStart = searchStart + openMatch.index;
    const bodyStart = openStart + openMatch[0].length;

    const rest = text.slice(bodyStart);
    const closeMatch = CLOSE_PATTERN.exec(rest);
    const nextOpenMatch = OPEN_PATTERN.exec(rest);

    let bodyEnd: number;
    let citationEnd: number;
    if (closeMatch && (!nextOpenMatch || closeMatch.index < nextOpenMatch.index)) {
      bodyEnd = bodyStart + closeMatch.index;
      citationEnd = bodyStart + closeMatch.index + closeMatch[0].length;
    } else {
      // 閉じカッコが無いケースの修復
      let cursor = bodyStart;
      while (cursor < text.length && VALID_BODY_CHAR.test(text[cursor])) cursor += 1;
      bodyEnd = cursor;
      citationEnd = cursor;
    }

    const sids = parseSidBody(text.slice(bodyStart, bodyEnd));
    // SIDが取れないカッコは引用ではない(数式など)のでスキップする
    if (sids.length > 0) {
      results.push({
        raw: text.slice(openStart, citationEnd),
        start: openStart,
        end: citationEnd,
        sids,
        sidStrings: sids.map(formatSid),
      });
    }

    searchStart = citationEnd > openStart ? citationEnd : openStart + 1;
  }

  return results;
}

/** 引用の直前に残る空白だけを削り、引用記法を取り除いた表示用テキストを返す。 */
export function stripSidCitations(text: string): string {
  const citations = parseSidCitations(text);
  if (citations.length === 0) return text;

  let out = '';
  let cursor = 0;
  for (const c of citations) {
    out += text.slice(cursor, c.start).replace(/[ \t]+$/, '');
    cursor = c.end;
  }
  return out + text.slice(cursor);
}

/** 除去後テキストのindex → 元テキストのindex。長さは除去後の長さ+1。 */
export function buildStrippedToRawMap(rawText: string): number[] {
  const citations = parseSidCitations(rawText);
  if (citations.length === 0) {
    return Array.from({ length: rawText.length + 1 }, (_, i) => i);
  }

  const map: number[] = [];
  let cursor = 0;
  for (const c of citations) {
    const chunk = rawText.slice(cursor, c.start);
    const trimmedLen = chunk.replace(/[ \t]+$/, '').length;
    for (let i = 0; i < trimmedLen; i += 1) map.push(cursor + i);
    cursor = c.end;
  }
  const remaining = rawText.length - cursor;
  for (let i = 0; i < remaining; i += 1) map.push(cursor + i);
  map.push(rawText.length);
  return map;
}

/** 元テキストのindex → 除去後テキストのindex。長さは元テキストの長さ+1。 */
export function buildRawToStrippedMap(rawText: string): number[] {
  const citations = parseSidCitations(rawText);
  const map = new Array<number>(rawText.length + 1).fill(0);
  if (citations.length === 0) {
    for (let i = 0; i <= rawText.length; i += 1) map[i] = i;
    return map;
  }

  let strippedLen = 0;
  let cursor = 0;
  for (const c of citations) {
    const chunk = rawText.slice(cursor, c.start);
    const trimmedLen = chunk.replace(/[ \t]+$/, '').length;

    for (let i = 0; i < trimmedLen; i += 1) map[cursor + i] = strippedLen + i;

    // 削られた空白と引用本体は、その直後の位置に潰す
    const collapsed = strippedLen + trimmedLen;
    for (let i = trimmedLen; i < chunk.length; i += 1) map[cursor + i] = collapsed;
    for (let i = c.start; i < c.end; i += 1) map[i] = collapsed;

    strippedLen += trimmedLen;
    cursor = c.end;
  }

  const remaining = rawText.length - cursor;
  for (let i = 0; i < remaining; i += 1) map[cursor + i] = strippedLen + i;
  map[rawText.length] = strippedLen + remaining;
  return map;
}

/**
 * deep_notesの本文に埋め込まれる
 * `<!-- FIGURE: type="..." title="..." description="..." -->`
 * プレースホルダーを除去する。画像としては描画しない(モバイル版と同じ扱い)。
 */
export function stripFigurePlaceholders(text: string): string {
  return text.replace(/<!--\s*FIGURE:[^>]*-->/g, '').trim();
}
