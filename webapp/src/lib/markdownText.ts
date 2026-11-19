import type {} from 'remark-parse';
import type { Plugin } from 'unified';

/**
 * Markdown本文そのものの下ごしらえ(CommonMarkのパース結果に効く、構文レベルの直し)。
 * 出典の引用記号の整形(chatCitations.ts)とは別物なので、こちらは引用に関係ない
 * 画面(出典プレビュー等)でも使い回せるよう分けてある。
 */

// ```…``` と `…` を境界にして、コード以外の部分だけ処理する。
const CODE_SPLIT_RE = /(```[\s\S]*?(?:```|$)|`[^`\n]*`)/g;

const EMPHASIS_BRACKETS = '()（）[]［］「」『』【】〈〉《》〔〕';

/** Let emphasis touch brackets in CJK prose while retaining the full emphasized text. */
export const remarkBracketEmphasis: Plugin = function () {
  const extensions = this.data('micromarkExtensions') ?? [];
  // The parser still handles escapes, code, math, and matching delimiters.
  extensions.push({
    attentionMarkers: { null: Array.from(EMPHASIS_BRACKETS, (char) => char.charCodeAt(0)) },
  });
  this.data('micromarkExtensions', extensions);
};

/**
 * 整形処理が触ってはいけない部分(コード・数式・エスケープされた\$)を境界にして分けるための正規表現。
 * splitすると奇数番目がその部分になる。数式は prepareMath を通した後の形
 * ($$…$$ / $…$。値段の $ は \$ にエスケープ済み)を前提にしている。
 */
export const PROTECTED_SPLIT_RE = /(```[\s\S]*?(?:```|$)|`[^`\n]*`|\\\$|\$\$[\s\S]*?\$\$|\$[^$\n]+?\$)/g;

/**
 * 回答役のLaTeXを、remark-mathが読める形にそろえる(コードの中は触らない)。
 * - \(…\) → $…$、\[…\] → $$…$$(Geminiがよく使う書き方。remark-mathは$しか読まない)
 * - 数式ではない $(値段の「$5 と $10」など)を \$ にエスケープする。判定はPandocと同じ:
 *   開きの $ の直後が空白でなく、閉じの $ の直前が空白でなく、閉じの直後が数字でないときだけ数式。
 *   条件を満たさない $ は文字のまま($5 と $10 → \$5 と \$10)。
 * 生成中に閉じがまだ届いていない $x は、届くまでは文字のまま表示される。
 */
export function prepareMath(markdown: string): string {
  if (!markdown) return markdown;
  return markdown
    .split(CODE_SPLIT_RE)
    .map((segment, i) => (i % 2 === 1 ? segment : prepareMathSegment(segment)))
    .join('');
}

function prepareMathSegment(source: string): string {
  // 別行の数式は $$ を前後の行に置いた形にする(remark-mathは、$$ と式が同じ行だと行内の数式として描く)。
  // 1行だけで書かれた $$…$$ も同じ形にそろえる
  const text = source
    .replace(/\\\[([\s\S]+?)\\\]/g, (_w, body: string) => `\n$$\n${body.trim()}\n$$\n`)
    .replace(/^[ \t]*\$\$([^\n$]+?)\$\$[ \t]*$/gm, (_w, body: string) => `$$\n${body.trim()}\n$$`)
    .replace(/\\\(([^\n]+?)\\\)/g, (_w, body: string) => `$${body.trim()}$`);
  let out = '';
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (ch === '\\' && text[i + 1] === '$') {
      out += '\\$';
      i += 2;
      continue;
    }
    if (ch !== '$') {
      out += ch;
      i += 1;
      continue;
    }
    if (text[i + 1] === '$') {
      // 別行の数式 $$…$$。閉じが無ければ文字のまま
      const close = text.indexOf('$$', i + 2);
      if (close > i + 2) {
        out += text.slice(i, close + 2);
        i = close + 2;
      } else {
        out += '\\$\\$';
        i += 2;
      }
      continue;
    }
    // 行内の数式 $…$: 開きの直後が空白でなければ、同じ行の次の $ が閉じとして正しいかを見る
    if (i + 1 < text.length && !/\s/.test(text[i + 1])) {
      let j = i + 1;
      while (j < text.length && text[j] !== '\n' && text[j] !== '$') j += 1;
      if (j < text.length && text[j] === '$' && !/\s/.test(text[j - 1]) && !/\d/.test(text[j + 1] ?? '') && text[j + 1] !== '$') {
        out += text.slice(i, j + 1);
        i = j + 1;
        continue;
      }
    }
    out += '\\$';
    i += 1;
  }
  return out;
}

const escapedBrackets = EMPHASIS_BRACKETS.replace(/[\[\]]/g, '\\$&');
const NON_BRACKET_PUNCT = String.raw`(?:(?![${escapedBrackets}])[\p{P}\p{S}])`;
const LEADING_PUNCT_RUN = new RegExp(`^${NON_BRACKET_PUNCT}+`, 'u');
const TRAILING_PUNCT_RUN = new RegExp(`${NON_BRACKET_PUNCT}+$`, 'u');
const BOLD_SPAN_RE = /\*\*([^*]+?)\*\*/g;

/**
 * Move punctuation such as a final full stop out of bold in chat prose.
 * Leave brackets inside the span so remarkBracketEmphasis can render them in bold.
 */
export function fixBoldPunctuationSpacing(markdown: string): string {
  if (!markdown) return markdown;
  // コードと数式はそのまま(**$x$ の式**の $ を太字の外へ出すと数式が壊れるため)
  const segments = markdown.split(PROTECTED_SPLIT_RE);
  return segments
    .map((segment, i) => {
      if (i % 2 === 1) return segment; // コード・数式はそのまま
      return segment.replace(BOLD_SPAN_RE, (whole, content: string) => {
        const leadMatch = content.match(LEADING_PUNCT_RUN);
        const trailMatch = content.match(TRAILING_PUNCT_RUN);
        if (!leadMatch && !trailMatch) return whole;

        const leadLen = leadMatch ? leadMatch[0].length : 0;
        const trailLen = trailMatch ? trailMatch[0].length : 0;
        if (leadLen + trailLen >= content.length) return whole; // ほぼ句読点だけの中身は触らない

        const prefix = leadMatch ? content.slice(0, leadLen) : '';
        const suffix = trailMatch ? content.slice(content.length - trailLen) : '';
        const core = content.slice(leadLen, content.length - trailLen);
        return `${prefix}**${core}**${suffix}`;
      });
    })
    .join('');
}

/**
 * 出典の区切り(Markdownの1ブロックや1文)を、ハイライトのある平文として見せるための整形。
 * 区切りはブロックの途中で切れていることがあり(**の片方だけ等)、Markdownとして描くと崩れるので、
 * 見出し・箇条書き・引用の記号と、強調・コードの記号を外す。改行は残す(CSSのpre-lineで見せる)。
 */
export function markdownToPlainText(markdown: string): string {
  if (!markdown) return markdown;
  return markdown
    .replace(/^[ \t]*#{1,6}[ \t]+/gm, '')
    .replace(/^[ \t]*>[ \t]?/gm, '')
    .replace(/^[ \t]*(?:[-*+]|\d+\.)[ \t]+/gm, '• ')
    .replace(/\*\*|__|`/g, '')
    .replace(/\[([^\]\n]+)\]\((?:[^)\s]+)\)/g, '$1')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
