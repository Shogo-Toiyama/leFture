/**
 * Markdown本文そのものの下ごしらえ(CommonMarkのパース結果に効く、構文レベルの直し)。
 * 出典の引用記号の整形(chatCitations.ts)とは別物なので、こちらは引用に関係ない
 * 画面(出典プレビュー等)でも使い回せるよう分けてある。
 */

// ```…``` と `…` を境界にして、コード以外の部分だけ処理する。
const CODE_SPLIT_RE = /(```[\s\S]*?(?:```|$)|`[^`\n]*`)/g;

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

// CommonMarkが言う「Unicode punctuation character」に近いもの(Unicodeの P・S 分類)。
// 日本語の鉤括弧・丸括弧(「」『』（）〈〉《》【】〔〕)はPs/Pe、句読点(、。！？)はPoに入る。
const LEADING_PUNCT_RUN = /^[\p{P}\p{S}]+/u;
const TRAILING_PUNCT_RUN = /[\p{P}\p{S}]+$/u;
const BOLD_SPAN_RE = /\*\*([^*]+?)\*\*/g;

/**
 * **「太字」** のように、太字(**…**)の内側がそのまま句読点・括弧で始まる/終わるとき、
 * CommonMarkの強調(emphasis)の判定規則により太字として認識されず、**がそのまま
 * 文字として表示されてしまうことがある(日本語は語の境に空白が無いため起きやすい)。
 *
 * 例: ざっくり言うと**「結論」**だよ → **が文字のまま出る
 *     (「の直後は句読点、**の直前はただの文字なので、CommonMarkの「左flanking」の
 *      条件を満たさない。終わり側の**も同様に右flankingの条件を満たさない)
 *
 * 直し方: 内側の先頭・末尾の句読点のかたまりを、常に**の外側へ出す。
 *     ざっくり言うと「**結論**」だよ
 * 「直前・直後の文字によっては元のままでも解釈できる」場合(例: 英語の
 * "I agree **(see note).**")も含めて一律に外へ出す。CommonMarkの左右flanking規則を
 * 厳密になぞって「必要な側だけ」動かす案も試したが、「「結論」、」のように閉じ括弧の
 * 直後がさらに句読点のときに、その閉じ括弧だけ太字の中に取り残される
 * (「**結論」**、→ 「の後の」が太字に巻き込まれる)。常に外へ出す方が、見た目も
 * 一貫して「括弧の中身だけが太字」になり分かりやすい。
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
