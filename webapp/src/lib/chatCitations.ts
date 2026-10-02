import type { TranslationKey } from '../i18n/translations';
import type { ChatCitation, ChatSourceType } from '../types/chat';

/** 出典の種類ごとの短い名前(チップに出す)。 */
export const CHAT_SOURCE_LABEL_KEYS: Record<ChatSourceType, TranslationKey> = {
  course: 'chatSourceCourse',
  chat_turn: 'chatSourceChat',
  web: 'chatSourceWeb',
  deep_note: 'chatSourceDeepNote',
  review_card: 'chatSourceReviewCard',
  keyword: 'chatSourceKeyword',
  announcement: 'chatSourceAnnouncement',
  transcript_topic: 'chatSourceTranscript',
  topic_summary: 'chatSourceTopic',
  fun_fact: 'chatSourceFunFact',
  lecture_summary: 'chatSourceLectureSummary',
  lecture_moment: 'chatSourceMoment',
};

/** 出典の番号を文字列でそろえる(Mapのキー・リンクの#cite-…に使う)。 */
export function citationRef(citation: ChatCitation): string {
  return String(citation.n);
}

/** Webのページの出典なら、そのURL(http/httpsのものだけ)。 */
export function citationUrl(citation: ChatCitation): string | null {
  if (citation.source_type !== 'web' || !citation.url) return null;
  return /^https?:\/\//i.test(citation.url) ? citation.url : null;
}

/**
 * 出典を押したときに開くアプリ内の画面。講義に紐づかない出典(講義の無いお知らせ等)と
 * Webのページ(citationUrlで外へ開く)はnull。
 * Deep Notesだけはトピック番号(knowledge_chunks.metadata.topic_number)が
 * あるので、そのトピックまで直接開く。
 */
export function citationRoute(citation: ChatCitation): string | null {
  if (citation.source_type === 'web') return null;
  if (citation.source_type === 'course') {
    return citation.course_id ? `/courses/${citation.course_id}` : null;
  }
  if (citation.source_type === 'chat_turn') {
    return citation.thread_id ? `/chat/${citation.thread_id}` : null;
  }
  const lectureId = citation.lecture_id;
  if (!lectureId) return null;
  switch (citation.source_type) {
    case 'deep_note': {
      const topic = citation.metadata?.topic_number;
      return typeof topic === 'number'
        ? `/lectures/${lectureId}/deep-notes/${topic}`
        : `/lectures/${lectureId}/deep-notes`;
    }
    case 'review_card':
      return `/lectures/${lectureId}/review-cards`;
    case 'transcript_topic': {
      const sentenceRange = typeof citation.metadata?.sentence_range === 'string'
        ? citation.metadata.sentence_range
        : null;
      if (sentenceRange) {
        const startSid = sentenceRange.split('-')[0].trim();
        return `/lectures/${lectureId}/transcript?sid=${startSid}#${startSid}`;
      }
      return `/lectures/${lectureId}/transcript`;
    }
    default:
      return `/lectures/${lectureId}`;
  }
}

/**
 * 出典ラベル "CS 161 / Lecture 7 / Deep Note: Heaps" から、チップに出す
 * 短い名前を作る。先頭のコース名は一覧で重複しがちなので、講義名以降を使う。
 */
export function citationShortLabel(citation: ChatCitation): string {
  if (citation.source_type === 'web') {
    const domain = citation.metadata?.domain;
    return typeof domain === 'string' && domain ? domain : citation.label;
  }
  const parts = (citation.label || '').split(' / ').filter(Boolean);
  // parts: [Course, Lecture, Detail(Topic/Section)]
  if (parts.length >= 3) {
    const detail = parts[2].trim();
    // チップの種別バッジですでに表示される "Transcript: " などのプレフィックスを取り除く
    const cleaned = detail.replace(/^(Transcript|Deep Note|Topic Summary|Review Cards?|Announcement):\s*/i, '');
    const range = typeof citation.metadata?.sentence_range === 'string' ? ` (${citation.metadata.sentence_range})` : '';
    return `${cleaned || detail}${range}`;
  }
  if (parts.length === 2) {
    return parts[1].trim();
  }
  return parts.join(' · ');
}

/** 直前が英数字(a[1] のような添字)なら引用ではない。後読みは古いSafariで使えないので手で見る。 */
function isIndexLike(text: string, offset: number): boolean {
  return offset > 0 && /[A-Za-z0-9_]/.test(text[offset - 1]);
}

/**
 * 回答本文の [n] / [Wn] を、Markdown上で押せるリンク [n](#cite-n) に置き換える。
 * バックエンドの normalize_citations と同じ整理もここでする(修正前に保存された回答と、生成中の表示のため):
 * - [W2, W3] / [1, 2] は1つずつに分ける。数字だけのまとまりは、全部が実在する出典番号のときだけ
 *   (区間の [0, 1] を壊さないため)。Wを含むまとまりは引用とみなし、実在しない番号は落とす。
 * - 実在しない番号(refsに無い [n] / [Wn])は消す。
 * コードブロック・インラインコードの中と、英数字の直後の [..](配列の添字 a[1] 等)は触らない。
 */
export function linkifyCitations(markdown: string, refs: ReadonlySet<string>): string {
  if (!markdown) return markdown;
  // ```…``` と `…` を境界にして、コード以外の部分だけ置き換える
  const segments = markdown.split(/(```[\s\S]*?(?:```|$)|`[^`\n]*`)/g);
  return segments
    .map((segment, i) => {
      // splitの奇数番目がコード部分
      if (i % 2 === 1) return segment;
      const grouped = segment.replace(
        /\[\s*(W?\d{1,2}(?:\s*[,、，]\s*W?\d{1,2})+)\s*\](?!\()/g,
        (whole, list: string, offset: number, text: string) => {
          if (isIndexLike(text, offset)) return whole;
          const items = list.split(/[,、，]/).map((x) => x.trim());
          if (!items.some((x) => x.startsWith('W')) && !items.every((x) => refs.has(x))) return whole;
          return items.filter((x) => refs.has(x)).map((x) => `[${x}]`).join('');
        },
      );
      return grouped.replace(/[ \t]?\[(W?\d{1,2})\](?!\()/g, (whole, ref: string, offset: number, text: string) => {
        const bracketAt = whole.startsWith('[') ? offset : offset + 1;
        if (isIndexLike(text, bracketAt)) return whole;
        if (!refs.has(ref)) return '';
        return `${whole.slice(0, bracketAt - offset)}[${ref}](#cite-${ref})`;
      });
    })
    .join('');
}

/** "#cite-3" → "3"、"#cite-W1" → "W1"。引用リンクでなければnull。 */
export function parseCitationHref(href: string | undefined): string | null {
  const match = href?.match(/^#cite-(W?\d{1,2})$/);
  return match ? match[1] : null;
}
