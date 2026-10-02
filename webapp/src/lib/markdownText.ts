/**
 * Markdown本文そのものの下ごしらえ(CommonMarkのパース結果に効く、構文レベルの直し)。
 * 出典の引用記号の整形(chatCitations.ts)とは別物なので、こちらは引用に関係ない
 * 画面(出典プレビュー等)でも使い回せるよう分けてある。
 */

// ```…``` と `…` を境界にして、コード以外の部分だけ処理する(他の整形処理と同じ切り方)。
const CODE_SPLIT_RE = /(```[\s\S]*?(?:```|$)|`[^`\n]*`)/g;

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
  const segments = markdown.split(CODE_SPLIT_RE);
  return segments
    .map((segment, i) => {
      if (i % 2 === 1) return segment; // コード部分はそのまま
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
