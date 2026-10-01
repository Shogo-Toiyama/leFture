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
    case 'transcript_topic':
      return `/lectures/${lectureId}/transcript`;
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
  if (parts.length >= 3) return parts.slice(1).join(' · ');
  return parts.join(' · ');
}

/**
 * 回答本文の [n] / [Wn] を、Markdown上で押せるリンク [n](#cite-n) に置き換える。
 * 存在する出典番号(refs)だけを対象にし、コードブロック・インライン
 * コードの中(配列の添字 a[1] 等)は触らない。
 */
export function linkifyCitations(markdown: string, refs: ReadonlySet<string>): string {
  if (!markdown || refs.size === 0) return markdown;
  // ```…``` と `…` を境界にして、コード以外の部分だけ置き換える
  const segments = markdown.split(/(```[\s\S]*?(?:```|$)|`[^`\n]*`)/g);
  return segments
    .map((segment, i) => {
      // splitの奇数番目がコード部分
      if (i % 2 === 1) return segment;
      return segment.replace(/\[(W?\d{1,2})\](?!\()/g, (whole, ref: string) =>
        refs.has(ref) ? `[${ref}](#cite-${ref})` : whole,
      );
    })
    .join('');
}

/** "#cite-3" → "3"、"#cite-W1" → "W1"。引用リンクでなければnull。 */
export function parseCitationHref(href: string | undefined): string | null {
  const match = href?.match(/^#cite-(W?\d{1,2})$/);
  return match ? match[1] : null;
}
