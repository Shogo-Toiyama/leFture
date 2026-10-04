import { apiFetch } from './api';

/**
 * 自分像プロフィール(docs/chatbot_context_and_retrieval_roadmap.md 9章)のAPI。
 * 読み出しも書き込みもバックエンドを通す(根拠のつながりや観察メモは本人向けのRLSを置いておらず、
 * バックエンドで組み立てて返すため)。表紙(いまのわたし)の編集だけは従来どおり
 * lib/profile.ts の updateProfileFields で本人のJWTから直接書く(DBのトリガが書き手を「本人」にする)。
 */

export type CoverField = 'bio' | 'interests' | 'future_goals';
export const COVER_FIELDS: CoverField[] = ['bio', 'interests', 'future_goals'];

export interface CoverValue {
  text: string | null;
  written_by: 'ai' | 'user' | null;
}

export interface CoverProposal {
  id: string;
  field: CoverField;
  proposed_text: string;
  created_at: string;
}

export interface ProfileCategory {
  id: string;
  name: string;
  description: string;
  kind: 'trait' | 'record';
  parent_id: string | null;
}

export interface ProfileItem {
  id: string;
  category_id: string | null;
  kind: 'trait' | 'record';
  content: string;
  origin: 'ai' | 'user';
  status: 'active' | 'pending_confirm';
  sensitive: string;
  first_seen_at: string | null;
  last_seen_at: string | null;
  occurred_at: string | null;
  is_new: boolean;
  /** 作られた日か、最後に書き直された日の新しいほう */
  changed_at: string;
  evidence_threads: number;
}

export interface RecentItem {
  item_id: string;
  /** 別々の会話から来た話題(2つ以上のときだけ入る) */
  topics: string[];
  quote: string | null;
}

export interface SelfPortrait {
  cover: Record<CoverField, CoverValue>;
  proposals: CoverProposal[];
  categories: ProfileCategory[];
  items: ProfileItem[];
  recent: RecentItem[];
}

export interface ItemEvidence {
  observation_id: string;
  thread_id: string;
  thread_title: string;
  note: string;
  quote: string | null;
  observed_at: string;
}

export interface ItemDetail {
  item: { id: string; content: string; origin: 'ai' | 'user'; status: string; kind: string; created_at: string };
  evidence: ItemEvidence[];
  versions: { content: string; origin: string; replaced_at: string }[];
}

export interface AiMemo {
  id: string;
  kind: 'answer_style' | 'situation';
  content: string;
  expires_at: string | null;
  created_at: string;
}

export interface ObservationGroup {
  thread_id: string;
  thread_title: string;
  last_observed_at: string;
  observations: { id: string; note: string; observed_at: string }[];
}

export interface AiMemory {
  memos: AiMemo[];
  observation_groups: ObservationGroup[];
  observation_count: number;
}

const post = <T = unknown>(path: string, body?: unknown) =>
  apiFetch<T>(path, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) });

export const selfPortraitApi = {
  get: () => apiFetch<SelfPortrait>('/profile/self-portrait'),
  item: (id: string) => apiFetch<ItemDetail>(`/profile/items/${id}`),
  reject: (id: string, reason?: string) => post(`/profile/items/${id}/reject`, { reason: reason || null }),
  edit: (id: string, content: string) =>
    apiFetch(`/profile/items/${id}`, { method: 'PATCH', body: JSON.stringify({ content }) }),
  discard: (id: string) => post<{ success: boolean; blocked_area: string | null }>(`/profile/items/${id}/discard`),
  keep: (id: string) => post(`/profile/items/${id}/keep`),
  markSeen: (ids: string[]) => post('/profile/items/seen', { item_ids: ids }),
  decideProposal: (id: string, accept: boolean) =>
    post(`/profile/cover-proposals/${id}/${accept ? 'accept' : 'reject'}`),
  aiMemory: () => apiFetch<AiMemory>('/profile/ai-memory'),
  deleteMemo: (id: string) => apiFetch(`/profile/memos/${id}`, { method: 'DELETE' }),
  deleteObservation: (id: string) => apiFetch(`/profile/observations/${id}`, { method: 'DELETE' }),
  forgetAiNotes: () => post('/profile/ai-notes/forget'),
};

/** "2026-10-02" や ISO の日時を、表示用の「10/02」形式にする(年は今年なら省く)。 */
export function shortDate(value: string | null | undefined, locale: string): string {
  if (!value) return '';
  const d = new Date(value.length === 10 ? `${value}T00:00:00` : value);
  if (Number.isNaN(d.getTime())) return '';
  const sameYear = d.getFullYear() === new Date().getFullYear();
  return d.toLocaleDateString(locale, sameYear ? { month: 'numeric', day: 'numeric' } : { year: 'numeric', month: 'numeric', day: 'numeric' });
}
