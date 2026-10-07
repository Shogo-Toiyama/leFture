import { CHAT_MENTION_RE, chatMentionToken } from '../types/chat';

/**
 * 本文の中で資料を指す(メンション)ための文字列処理。画面(ChatComposer)から切り離した純粋な関数。
 *
 * 入力欄はtextareaのまま(日本語の変換と相性が良い)で、資料は「@名前」の文字として入れる。
 * 送るときに「@名前」を印 ⟦att:<id>⟧ に置き換える(バックエンドのchat_attachments.MENTION_RE)。
 * 保存された本文の印は、送ったメッセージの中でチップとして見せる。
 */

/** 入力欄に入れる名前の長さの上限(長い題名は省く)。 */
const LABEL_MAX_CHARS = 40;

export type MentionTarget =
  | { kind: 'existing'; attachmentId: string; mode: 'full' | 'mention' }
  | { kind: 'draft'; localId: string };

export interface ComposerMention {
  /** 入力欄の中の文字("@" から始まる) */
  label: string;
  target: MentionTarget;
}

/** 入力欄に入れる「@名前」。同じ名前が既にあれば (2) などを付けて区別する。 */
export function makeLabel(title: string, taken: Iterable<string>): string {
  const clean = title.replace(/\s+/g, ' ').trim() || 'material';
  const base = `@${clean.length > LABEL_MAX_CHARS ? `${clean.slice(0, LABEL_MAX_CHARS - 1)}…` : clean}`;
  const used = new Set(taken);
  if (!used.has(base)) return base;
  for (let n = 2; ; n++) {
    const next = `${base} (${n})`;
    if (!used.has(next)) return next;
  }
}

/**
 * カーソルの直前が「@入力中の言葉」なら、その開始位置と言葉(@の後ろ)を返す(資料の候補を出す)。
 * @は行頭か空白の直後のときだけ(メールアドレスなどでは出さない)。既に入れた「@名前」の中では出さない。
 */
export function findMentionQuery(
  value: string,
  caret: number,
  labels: string[]
): { start: number; query: string } | null {
  const before = value.slice(0, caret);
  const at = before.lastIndexOf('@');
  if (at < 0) return null;
  const query = before.slice(at + 1);
  if (query.length > 30 || /[\s]/.test(query)) return null;
  if (at > 0 && !/\s/.test(before[at - 1])) return null;
  // 既に入れた「@名前」の@なら出さない
  if (labels.some((label) => value.startsWith(label, at))) return null;
  return { start: at, query };
}

/** カーソルの直前にある「@名前」(Backspaceで丸ごと消すため)。無ければnull。 */
export function labelBeforeCaret(value: string, caret: number, labels: string[]): string | null {
  // 長い名前から調べる("@A (2)" と "@A" の両方があるとき)
  for (const label of [...labels].sort((a, b) => b.length - a.length)) {
    if (caret >= label.length && value.slice(caret - label.length, caret) === label) return label;
  }
  return null;
}

/** 入力欄の文字の中で、名前がある範囲(色を付けるため)。重ならないように長い名前を優先する。 */
export function mentionRanges(value: string, mentions: ComposerMention[]): Array<{ start: number; end: number; mention: ComposerMention }> {
  const ranges: Array<{ start: number; end: number; mention: ComposerMention }> = [];
  const taken = new Array<boolean>(value.length).fill(false);
  for (const mention of [...mentions].sort((a, b) => b.label.length - a.label.length)) {
    let from = 0;
    for (;;) {
      const i = value.indexOf(mention.label, from);
      if (i < 0) break;
      const end = i + mention.label.length;
      if (!taken.slice(i, end).some(Boolean)) {
        ranges.push({ start: i, end, mention });
        taken.fill(true, i, end);
      }
      from = end;
    }
  }
  return ranges.sort((a, b) => a.start - b.start);
}

/** 送る本文: 「@名前」を印に置き換える。tokenIdForがnullを返すもの(まだ準備中など)は名前のまま残す。 */
export function toMessageContent(
  value: string,
  mentions: ComposerMention[],
  tokenIdFor: (mention: ComposerMention) => string | null
): string {
  let out = '';
  let pos = 0;
  for (const { start, end, mention } of mentionRanges(value, mentions)) {
    const id = tokenIdFor(mention);
    out += value.slice(pos, start) + (id ? chatMentionToken(id) : value.slice(start, end));
    pos = end;
  }
  return out + value.slice(pos);
}

/** 入力欄に残っている(送るときに使う)メンション。 */
export function presentMentions(value: string, mentions: ComposerMention[]): ComposerMention[] {
  const present = new Set(mentionRanges(value, mentions).map((r) => r.mention));
  return mentions.filter((m) => present.has(m));
}

export type MessagePart = { type: 'text'; text: string } | { type: 'mention'; id: string };

/** 保存された本文を、文字と資料の印に分ける(送ったメッセージの中でチップにするため)。 */
export function splitMessageText(content: string): MessagePart[] {
  const parts: MessagePart[] = [];
  let pos = 0;
  for (const m of content.matchAll(new RegExp(CHAT_MENTION_RE.source, 'g'))) {
    const i = m.index ?? 0;
    if (i > pos) parts.push({ type: 'text', text: content.slice(pos, i) });
    parts.push({ type: 'mention', id: m[1] });
    pos = i + m[0].length;
  }
  if (pos < content.length) parts.push({ type: 'text', text: content.slice(pos) });
  return parts;
}

/** 本文が指している資料のid。 */
export function messageMentionIds(content: string): string[] {
  return splitMessageText(content).flatMap((p) => (p.type === 'mention' ? [p.id] : []));
}
