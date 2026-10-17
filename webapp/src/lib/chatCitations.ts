import type { TranslationKey } from '../i18n/translations';
import type { ChatCitation, ChatSourceType } from '../types/chat';
import { PROTECTED_SPLIT_RE } from './markdownText';

/** 出典の種類ごとの短い名前(チップに出す)。 */
export const CHAT_SOURCE_LABEL_KEYS: Record<ChatSourceType, TranslationKey> = {
  course: 'chatSourceCourse',
  chat_turn: 'chatSourceChat',
  web: 'chatSourceWeb',
  chat_attachment: 'chatSourceAttachment',
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
  // Webは外のページ(citationUrl)、添付資料は引用箇所のプレビューだけ(資料の一覧から全文を読める)
  if (citation.source_type === 'web' || citation.source_type === 'chat_attachment') return null;
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

// 3 / 3.5 / 3.5-7 / W1.2 の1つ分(括弧の中身)。範囲の後ろ側に出典番号を繰り返す書き方(3.5-3.7)も許す。
const CITE_ITEM_RE = /^\s*(W?\d{1,2})(?:\s*\.\s*(\d{1,3})(?:\s*[-–]\s*(?:W?\d{1,2}\s*\.\s*)?(\d{1,3}))?)?\s*$/;
// ⟦…⟧(今の形) と [...](昔の形・回答役の癖)。英数字の直後の [..](添字 a[1])は isIndexLike で除く
const CITE_RE = /([ \t]?)(?:⟦([^⟦⟧\n]{1,60})⟧|\[([^[\]\n]{1,60})\](?!\())/g;

/**
 * 回答本文の引用を、Markdown上で押せるリンクに置き換える。表示は出典の番号だけ(⟦3.5⟧ も「3」)。
 *   ⟦3⟧    → [3](#cite-3)
 *   ⟦3.5⟧  → [3](#cite-3~5)      ⟦3.5-7⟧ → [3](#cite-3~5-7)
 * 同じ出典が続けて並んだ ⟦3.5⟧⟦3.9⟧ は1つにまとめる → [3](#cite-3~5,9)(「3」「3」と並ばないように)。
 * 本文は先に prepareMath を通しておくこと(数式の中を触らないため)。
 * バックエンドの normalize_citations と同じ整理もここでする(修正前に保存された回答と、生成中の表示のため):
 * - ⟦2.5, W1.3⟧ は1つずつに分ける。実在しない出典の番号は消す。
 * - 昔の形 [3] / [3.5] も読む。こちらは区間・添字と紛れるので、数字だけのまとまりは全部が実在する出典番号の
 *   ときだけ引用とみなし、[0.5] のような出典番号でない数の区切りつき表記は残す。
 * コード・数式の中と、英数字の直後の [..](配列の添字 a[1] 等)は触らない。
 */
export function linkifyCitations(markdown: string, refs: ReadonlySet<string>): string {
  if (!markdown) return markdown;
  const segments = markdown.split(PROTECTED_SPLIT_RE);
  return segments
    .map((segment, i) => {
      // splitの奇数番目がコード・数式
      if (i % 2 === 1) return segment;
      const linked = segment.replace(
        CITE_RE,
        (whole, space: string, double: string | undefined, legacy: string | undefined, offset: number, text: string) => {
          const isLegacy = double === undefined;
          if (isLegacy && isIndexLike(text, offset + space.length)) return whole;
          const items = (isLegacy ? legacy! : double).split(/[,、，]/).map((x) => x.match(CITE_ITEM_RE));
          if (!items.every(Boolean)) return whole; // 引用ではない括弧
          const parsed = items as RegExpMatchArray[];
          if (isLegacy) {
            const dotted = parsed.some((m) => m[2]);
            const hasWeb = parsed.some((m) => m[1].startsWith('W'));
            if (parsed.length > 1 && !dotted && !hasWeb && !parsed.every((m) => refs.has(m[1]))) return whole;
            if (parsed.length === 1 && dotted && !hasWeb && !refs.has(parsed[0][1])) return whole;
          }
          const links = parsed
            .filter((m) => refs.has(m[1]))
            .map((m) => {
              const spec = m[2] ? (m[3] && m[3] !== m[2] ? `${m[2]}-${m[3]}` : m[2]) : '';
              return `[${m[1]}](#cite-${m[1]}${spec ? `~${spec}` : ''})`;
            })
            .join('');
          return links ? space + links : '';
        },
      );
      // 同じ出典が続けて並んだものを1つにまとめる
      let merged = linked;
      for (let prev = ''; prev !== merged; ) {
        prev = merged;
        merged = merged.replace(
          /\[(W?\d{1,2})\]\(#cite-\1(?:~([\d,-]+))?\)\[\1\]\(#cite-\1(?:~([\d,-]+))?\)/g,
          (_w, ref: string, a?: string, b?: string) => {
            const specs = [...new Set([a, b].filter(Boolean).join(',').split(',').filter(Boolean))].join(',');
            return `[${ref}](#cite-${ref}${specs ? `~${specs}` : ''})`;
          },
        );
      }
      return merged;
    })
    .join('');
}

/**
 * "#cite-3" → {ref: "3", specs: []}、"#cite-W1~2" → {ref: "W1", specs: ["2"]}、
 * "#cite-3~5,9-10" → {ref: "3", specs: ["5", "9-10"]}。引用リンクでなければnull。
 * specs は ChatCitation.passages のキー(押された引用の区切り)。
 */
export function parseCitationHref(href: string | undefined): { ref: string; specs: string[] } | null {
  const match = href?.match(/^#cite-(W?\d{1,2})(?:~([\d,-]+))?$/);
  if (!match) return null;
  return { ref: match[1], specs: match[2] ? match[2].split(',').filter(Boolean) : [] };
}

/**
 * 回答のMarkdownをコピー用にする: 出典の印(⟦3⟧・[3]など)だけを取り除き、ほかの本文はそのまま残す。
 * 画面に出る出典番号と同じ判定(linkifyCitations)を通すので、配列の添字 a[1] などは消えない。
 */
export function stripCitationMarkers(markdown: string, refs: ReadonlySet<string>): string {
  return linkifyCitations(markdown, refs).replace(/[ \t]?\[(?:W?\d{1,2})\]\(#cite-[^)]*\)/g, '');
}
