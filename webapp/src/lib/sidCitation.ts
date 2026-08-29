/**
 * ⟦s000010-s000012⟧ 形式のSID引用記法のパース/除去。
 * user_interface/lib/core/utils/sid_citation.dart のTS移植(簡略版)。
 * 揺れ表記(閉じ括弧欠落など)の救済は行わず、正規フォーマットのみ対応する。
 */

const OPEN_BRACKETS = ['⟦', '〚', '[['];
const CLOSE_BRACKETS = ['⟧', '〛', ']]'];
const DASH_CHARS = '-‐‑‒–—―−－~〜～';
const COMMA_CHARS = ',，、;；';

const CITATION_PATTERN = new RegExp(
  `(?:${OPEN_BRACKETS.map(escapeRegExp).join('|')})([^${CLOSE_BRACKETS.join('')}]*)(?:${CLOSE_BRACKETS.map(escapeRegExp).join('|')})`,
  'g'
);

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function formatSid(n: number): string {
  return `s${n.toString().padStart(6, '0')}`;
}

function parseSidBody(body: string): number[] {
  const sids: number[] = [];
  const sidPattern = /[sS]\s*0*(\d{1,6})/;
  const parts = body.split(new RegExp(`[${COMMA_CHARS}]`));

  for (const rawPart of parts) {
    const trimmed = rawPart.trim();
    if (!trimmed) continue;

    const rangeSplit = trimmed.split(new RegExp(`[${DASH_CHARS}]`));
    if (rangeSplit.length >= 2) {
      const fromMatch = rangeSplit[0].match(sidPattern);
      const toMatch = rangeSplit[rangeSplit.length - 1].match(sidPattern);
      if (fromMatch && toMatch) {
        let from = parseInt(fromMatch[1], 10);
        let to = parseInt(toMatch[1], 10);
        if (from > to) [from, to] = [to, from];
        if (to - from > 5000) {
          sids.push(from, to);
        } else {
          for (let i = from; i <= to; i++) sids.push(i);
        }
        continue;
      }
    }

    const single = trimmed.match(sidPattern);
    if (single) sids.push(parseInt(single[1], 10));
  }

  return sids;
}

export interface SidCitation {
  raw: string;
  sids: number[];
  sidStrings: string[];
}

export function parseSidCitations(text: string): SidCitation[] {
  const citations: SidCitation[] = [];
  for (const match of text.matchAll(CITATION_PATTERN)) {
    const sids = parseSidBody(match[1] ?? '');
    if (sids.length === 0) continue;
    citations.push({ raw: match[0], sids, sidStrings: sids.map(formatSid) });
  }
  return citations;
}

export function stripSidCitations(text: string): string {
  return text.replace(CITATION_PATTERN, '').replace(/[ \t]{2,}/g, ' ').trim();
}

/**
 * deep_notesの本文に埋め込まれる `<!-- FIGURE: type="..." title="..." description="..." -->`
 * プレースホルダーを除去する。画像としては描画しない(mobile版と同じ扱い)。
 * annotation_text_utils.dart:33-48 のTS移植。
 */
export function stripFigurePlaceholders(text: string): string {
  return text.replace(/<!--\s*FIGURE:[^>]*-->/g, '').trim();
}
