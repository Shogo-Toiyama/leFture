import type { Annotation } from './annotation';

export type Reaction = 'like' | 'dislike' | null;

export interface ContentMetadata {
  reaction?: Reaction;
  saved?: boolean;
  sources?: string[];
  annotations?: Annotation[];
  [key: string]: unknown;
}

export type ReviewCardBlockType = 'paragraph' | 'quote' | 'callout' | 'code' | 'list';
export type CalloutAlertType = 'info' | 'warning' | 'error';

export interface ReviewCardBlock {
  type: ReviewCardBlockType;
  text?: string;
  items?: string[];
  alert_type?: CalloutAlertType;
  code_string?: string;
  explanation?: string;
}

export type ReviewCardType = 'hook' | 'core_why' | 'gotcha' | 'next_action';

export const REVIEW_CARD_TYPE_ORDER: ReviewCardType[] = ['hook', 'core_why', 'gotcha', 'next_action'];

export interface ReviewCard {
  id: string;
  lecture_id: string;
  topic_number: number;
  card_content: ReviewCardBlock[];
  card_type: ReviewCardType;
  title: string | null;
  hero_emoji: string | null;
  metadata: ContentMetadata | null;
  deleted_at: string | null;
}

export interface DeepNote {
  id: string;
  lecture_id: string;
  topic_number: number;
  note_contents: string;
  metadata: ContentMetadata | null;
  deleted_at: string | null;
}

export interface FunFact {
  id: string;
  lecture_id: string;
  title: string;
  hook: string;
  body: string;
  metadata: ContentMetadata | null;
  deleted_at: string | null;
}

export type AnnouncementType = 'TODO' | 'EVENT' | 'HINT' | 'INFO' | 'UNKNOWN';

export interface Announcement {
  id: string;
  lecture_id: string;
  type: AnnouncementType;
  title: string | null;
  description: string | null;
  location: string | null;
  related_topic_title: string | null;
  completed_at: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
  deleted_at: string | null;
}

export interface Keyword {
  id: string;
  lecture_id: string;
  topic_number: number;
  keyword: string | null;
  definition: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
  deleted_at: string | null;
}

export type TopicType = 'ACADEMIC' | 'LOGISTICS' | 'OFF_TOPIC';

export interface LectureTopic {
  id: string;
  lecture_id: string;
  index: number;
  topic_title: string;
  topic_type: TopicType;
  summary: string | null;
  start_sid: string | null;
  end_sid: string | null;
  image_path: string | null;
  deleted_at: string | null;
}

export interface TranscriptSentence {
  sid: string;
  text: string;
  /** 秒単位 (バックエンドの生データそのまま) */
  start: number;
  end: number;
  role: string;
}

export function isMainContent(sentence: Pick<TranscriptSentence, 'role'>): boolean {
  const role = (sentence.role ?? 'CONTENT').toUpperCase();
  return role === 'CONTENT' || role === 'LECTURE';
}

export interface TopicMapCluster {
  cluster_id: string;
  name: string;
}

export interface TopicMapNode {
  topic_id: string;
  title: string;
  topic_type: TopicType;
  cluster_id: string;
  source_lecture_id: string;
  topic_index_in_lecture: number;
}

export interface TopicMapEdge {
  source_id: string;
  target_id: string;
  relation_type: string;
}

export interface TopicMapGhostNode {
  ghost_id: string;
  name: string;
  cluster_id: string;
  status: 'active' | 'faded';
  derived_from_topic_id: string | null;
}

export interface TopicMapData {
  clusters: TopicMapCluster[];
  nodes: TopicMapNode[];
  edges: TopicMapEdge[];
  ghost_nodes: TopicMapGhostNode[];
}
