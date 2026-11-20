import type { Keyword } from '../types/content';
import { stripSidCitations } from './sidCitation';

/**
 * 用語マーク: DeepNotes / ReviewCards の本文中に出てくる講義キーワードを見つけ、
 * 薄くマークしてホバー(タップ)で定義を出すためのマッチャー。
 * user_interface/lib/core/utils/term_glossary.dart と同じ規則で動かすこと。
 *
 * LLMは使わず、キーワード文字列から「本文に出てきそうな表記」をルールで作る:
 *   - 全角英数字→半角、英字は小文字にそろえて比較する
 *   - 「字句スコープ（lexical scoping）」は「字句スコープ」「lexical scoping」に分ける
 *   - 「回線交換とパケット交換」のような複合語は「と・、,/ and or 及び」で分ける
 * 意味は同じでも書き方がまったく違う語(静的スコープ↔字句スコープ)は拾えない。
 *
 * マークは元のテキストを一切変えない(spanで包むだけ)ので、
 * アノテーションの座標系(markdownAnnotations.ts参照)には影響しない。
 */

export interface TermEntry {
  id: string;
  keyword: string;
  definition: string;
  topicNumber: number;
}

interface TermForm {
  form: string;
  entry: TermEntry;
  /** 英数字だけの表記。前後が英数字でないこと(単語境界)を要求する。 */
  ascii: boolean;
}

export interface TermGlossary {
  entries: Map<string, TermEntry>;
  /** 長い表記から順。 */
  forms: TermForm[];
}

/**
 * 比較用に1文字ずつ畳み込む。文字数(UTF-16のコード単位数)を変えないことが重要で、
 * そうすれば畳み込んだ文字列で見つけた位置をそのまま元の文字列に使える。
 */
export function foldForMatch(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    let code = text.charCodeAt(i);
    if (code >= 0xff01 && code <= 0xff5e) code -= 0xfee0; // 全角ASCII→半角
    else if (code === 0x3000) code = 0x20; // 全角スペース
    if (code >= 0x41 && code <= 0x5a) code += 0x20; // A-Z→a-z
    out += String.fromCharCode(code);
  }
  return out;
}

const PAREN_PATTERN = /^(.*?)\s*\((.+?)\)\s*$/;
// 「・」はカタカナに挟まれていれば語の一部(マーク・アンド・スイープ)なので切らない。
const SPLIT_PATTERN = /と|(?<![ァ-ヺー])・|・(?![ァ-ヺー])|、|,|\/| and | or |および|及び/;
const ASCII_FORM = /^[a-z0-9][a-z0-9 .+#'-]*$/;
const HIRAGANA_ONLY = /^[぀-ゟ]+$/;
const HIRAGANA_EDGE = /^[぀-ゟ]|[぀-ゟ]$/;
const DIGITS_ONLY = /^[0-9\s.]+$/;
const ALNUM = /[a-z0-9]/;

function isUsableForm(form: string, fromSplit: boolean): boolean {
  if (DIGITS_ONLY.test(form) || HIRAGANA_ONLY.test(form)) return false;
  if (ASCII_FORM.test(form)) return form.length >= 3;
  if (!fromSplit) return form.length >= 2;
  // 複合語を切った断片は一般語になりやすい(「縄文・古墳時代…」→「縄文」、
  // 「問題としての文化」→「しての文化」)ので、3文字以上で、ひらがなで始まり/終わらないものだけ。
  return form.length >= 3 && !HIRAGANA_EDGE.test(form);
}

/** キーワード1つから、本文に当てる表記の候補を作る。 */
export function termFormsFor(keyword: string): string[] {
  const whole = foldForMatch(keyword).trim();
  const bases = new Set<string>([whole]);
  const paren = PAREN_PATTERN.exec(whole);
  if (paren) {
    bases.add(paren[1].trim());
    bases.add(paren[2].trim());
  }

  const forms = new Set<string>();
  for (const base of bases) if (isUsableForm(base, false)) forms.add(base);
  for (const base of bases) {
    for (const raw of base.split(SPLIT_PATTERN)) {
      const piece = raw.trim();
      if (piece !== base && isUsableForm(piece, true)) forms.add(piece);
    }
  }
  return [...forms];
}

export function buildTermGlossary(keywords: Keyword[]): TermGlossary {
  const entries = new Map<string, TermEntry>();
  const forms: TermForm[] = [];
  const claimed = new Set<string>();

  // 同じ表記を2つのキーワードが作った場合は、先に来た(トピック順で早い)方に寄せる。
  const sorted = [...keywords].sort((a, b) => a.topic_number - b.topic_number);
  for (const kw of sorted) {
    const keyword = kw.keyword?.trim();
    const definition = kw.definition ? stripSidCitations(kw.definition).trim() : '';
    if (!keyword || !definition) continue; // 定義がなければポップアップに出すものがない

    const entry: TermEntry = { id: kw.id, keyword, definition, topicNumber: kw.topic_number };
    entries.set(entry.id, entry);
    for (const form of termFormsFor(keyword)) {
      if (claimed.has(form)) continue;
      claimed.add(form);
      forms.push({ form, entry, ascii: ASCII_FORM.test(form) });
    }
  }

  forms.sort((a, b) => b.form.length - a.form.length);
  return { entries, forms };
}

export interface TermMatch {
  start: number;
  end: number;
  entry: TermEntry;
}

/**
 * テキスト1つの中のマッチを返す(重なりなし、位置順)。
 * 重なったら長い表記を優先し、同じ長さなら[topicNumber]のキーワードを優先する。
 * [seen]にあるキーワードは飛ばし、マークしたものを追加する(=範囲内で最初の1回だけ)。
 */
export function findTermMatches(
  text: string,
  glossary: TermGlossary,
  seen: Set<string>,
  topicNumber: number | null
): TermMatch[] {
  if (glossary.forms.length === 0 || !text) return [];
  const folded = foldForMatch(text);

  const candidates: TermMatch[] = [];
  for (const { form, entry, ascii } of glossary.forms) {
    let from = 0;
    while (true) {
      const at = folded.indexOf(form, from);
      if (at < 0) break;
      from = at + 1;
      let end = at + form.length;
      if (ascii) {
        if (at > 0 && ALNUM.test(folded[at - 1])) continue;
        // 複数形(page table → page tables)までは同じ語として含める
        if (folded[end] === 's' && !ALNUM.test(folded[end + 1] ?? '')) end += 1;
        if (end < folded.length && ALNUM.test(folded[end])) continue;
      }
      candidates.push({ start: at, end, entry });
    }
  }

  candidates.sort((a, b) => {
    const byLength = b.end - b.start - (a.end - a.start);
    if (byLength !== 0) return byLength;
    const aHome = a.entry.topicNumber === topicNumber ? 0 : 1;
    const bHome = b.entry.topicNumber === topicNumber ? 0 : 1;
    if (aHome !== bHome) return aHome - bHome;
    return a.start - b.start;
  });

  const taken: TermMatch[] = [];
  for (const c of candidates) {
    if (taken.some((t) => c.start < t.end && t.start < c.end)) continue;
    taken.push(c);
  }
  taken.sort((a, b) => a.start - b.start);

  const result: TermMatch[] = [];
  for (const m of taken) {
    if (seen.has(m.entry.id)) continue;
    seen.add(m.entry.id);
    result.push(m);
  }
  return result;
}

// ---------------------------------------------------------------------------
// rehypeプラグイン
// ---------------------------------------------------------------------------

interface HastText {
  type: 'text';
  value: string;
}

interface HastElement {
  type: 'element';
  tagName: string;
  properties?: Record<string, unknown>;
  children: HastNode[];
}

type HastNode = HastText | HastElement | { type: string; children?: HastNode[] };

const SKIP_TAGS = new Set(['code', 'pre', 'a', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'img', 'svg']);
const SECTION_TAGS = new Set(['h1', 'h2', 'h3', 'h4']);

function isMathElement(node: HastElement): boolean {
  const cls = node.properties?.className;
  const list = Array.isArray(cls) ? cls : typeof cls === 'string' ? cls.split(' ') : [];
  return list.some((c) => typeof c === 'string' && c.includes('math'));
}

/**
 * react-markdownのrehypePluginsに渡す。rehypeAnnotationsより**前**に置くこと
 * (アノテーションの<mark>が用語spanの内側に入り、クリックはアノテーションが優先される)。
 * 見出しごとに「最初の1回だけ」をリセットする。見出し・コード・数式・リンクの中はマークしない。
 */
export function rehypeTermMarks(glossary: TermGlossary | null, topicNumber: number | null) {
  return () => (tree: HastNode) => {
    if (!glossary || glossary.forms.length === 0) return;
    let seen = new Set<string>();

    const walk = (node: HastNode) => {
      const children = (node as { children?: HastNode[] }).children;
      if (!Array.isArray(children)) return;

      const next: HastNode[] = [];
      for (const child of children) {
        if (child.type === 'element') {
          const el = child as HastElement;
          if (SECTION_TAGS.has(el.tagName)) seen = new Set();
          if (!SKIP_TAGS.has(el.tagName) && !isMathElement(el)) walk(el);
          next.push(el);
          continue;
        }
        if (child.type !== 'text') {
          next.push(child);
          continue;
        }

        const text = (child as HastText).value;
        const matches = findTermMatches(text, glossary, seen, topicNumber);
        if (matches.length === 0) {
          next.push(child);
          continue;
        }
        let cursor = 0;
        for (const m of matches) {
          if (m.start > cursor) next.push({ type: 'text', value: text.slice(cursor, m.start) });
          next.push({
            type: 'element',
            tagName: 'span',
            properties: { className: ['term-mark'], dataTermId: m.entry.id },
            children: [{ type: 'text', value: text.slice(m.start, m.end) }],
          });
          cursor = m.end;
        }
        if (cursor < text.length) next.push({ type: 'text', value: text.slice(cursor) });
      }
      (node as { children: HastNode[] }).children = next;
    };

    walk(tree);
  };
}
