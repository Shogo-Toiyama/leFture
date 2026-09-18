import { supabase } from './supabase';
import type {
  Announcement,
  ContentMetadata,
  DeepNote,
  FunFact,
  Keyword,
  LectureTopic,
  Reaction,
  ReviewCard,
  TopicMapData,
} from '../types/content';

/**
 * Fun Factの本文・Hookに含まれるWeb文献引用記法 (⟦1⟧, ⟦1, 2⟧, 〚1〛, [[1]] 等) を除去する。
 * Flutter版 stripFunFactCitations 準拠。
 */
export function stripFunFactCitations(source: string | null | undefined): string {
  if (!source) return '';
  return source
    .replace(/(?:⟦|〚|\[\[)\s*\d+[\d\s,，\-–—−]*\s*(?:⟧|〛|\]\])/g, '')
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
}

export async function listLectureTopics(lectureId: string): Promise<LectureTopic[]> {
  const { data, error } = await supabase
    .from('lecture_topics')
    .select('*')
    .eq('lecture_id', lectureId)
    .is('deleted_at', null)
    .order('index', { ascending: true });
  if (error) throw error;
  return data as LectureTopic[];
}

/** 最初のトピック(index = 1)のimage_pathを取得。lecture_topic_repository_supabase.dart準拠。 */
export async function getFirstTopicImagePath(lectureId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('lecture_topics')
    .select('image_path')
    .eq('lecture_id', lectureId)
    .eq('index', 1)
    .is('deleted_at', null)
    .maybeSingle();
  if (error) throw error;
  return (data?.image_path as string | null) ?? null;
}

export async function listReviewCards(lectureId: string): Promise<ReviewCard[]> {
  const { data, error } = await supabase
    .from('review_cards')
    .select('*')
    .eq('lecture_id', lectureId)
    .is('deleted_at', null);
  if (error) throw error;
  return data as ReviewCard[];
}

export async function listDeepNotes(lectureId: string): Promise<DeepNote[]> {
  const { data, error } = await supabase
    .from('deep_notes')
    .select('*')
    .eq('lecture_id', lectureId)
    .is('deleted_at', null);
  if (error) throw error;
  return data as DeepNote[];
}

export async function listFunFacts(lectureId: string): Promise<FunFact[]> {
  const { data, error } = await supabase
    .from('fun_facts')
    .select('*')
    .eq('lecture_id', lectureId)
    .is('deleted_at', null);
  if (error) throw error;
  return data as FunFact[];
}

export async function listAnnouncements(
  lectureId?: string,
  courseId?: string
): Promise<Announcement[]> {
  if (lectureId) {
    const { data, error } = await supabase
      .from('announcements')
      .select('*')
      .eq('lecture_id', lectureId)
      .is('deleted_at', null)
      .order('created_at', { ascending: false });

    if (error) throw error;
    return (data as Announcement[]) || [];
  }

  if (courseId) {
    // Announcements are associated with lectures via lecture_id.
    // Fetch all active lectures for this course first.
    const { data: lectures, error: lecErr } = await supabase
      .from('lectures')
      .select('id')
      .eq('course_id', courseId)
      .is('deleted_at', null);

    if (lecErr) throw lecErr;
    if (!lectures || lectures.length === 0) {
      return [];
    }

    const lectureIds = lectures.map((l: { id: string }) => l.id);
    const { data, error } = await supabase
      .from('announcements')
      .select('*')
      .in('lecture_id', lectureIds)
      .is('deleted_at', null)
      .order('created_at', { ascending: false });

    if (error) throw error;
    return (data as Announcement[]) || [];
  }

  return [];
}

export async function listKeywords(lectureId: string): Promise<Keyword[]> {
  const { data, error } = await supabase
    .from('keywords')
    .select('*')
    .eq('lecture_id', lectureId)
    .is('deleted_at', null)
    .order('topic_number', { ascending: true });
  if (error) throw error;
  return data as Keyword[];
}

export async function getTopicMap(courseId: string): Promise<{ map: TopicMapData; isStale: boolean } | null> {
  const { data, error } = await supabase
    .from('topic_maps')
    .select('map, is_stale')
    .eq('course_id', courseId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return { map: data.map as TopicMapData, isStale: Boolean(data.is_stale) };
}

async function updateReaction(
  table: 'review_cards' | 'deep_notes' | 'fun_facts',
  id: string,
  currentMetadata: ContentMetadata | null,
  reaction: Reaction
): Promise<void> {
  const nextReaction = currentMetadata?.reaction === reaction ? null : reaction;
  const { error } = await supabase
    .from(table)
    .update({ metadata: { ...currentMetadata, reaction: nextReaction } })
    .eq('id', id);
  if (error) throw error;
}

export const updateReviewCardReaction = (id: string, currentMetadata: ContentMetadata | null, reaction: Reaction) =>
  updateReaction('review_cards', id, currentMetadata, reaction);

export const updateDeepNoteReaction = (id: string, currentMetadata: ContentMetadata | null, reaction: Reaction) =>
  updateReaction('deep_notes', id, currentMetadata, reaction);

export const updateFunFactReaction = (id: string, currentMetadata: ContentMetadata | null, reaction: Reaction) =>
  updateReaction('fun_facts', id, currentMetadata, reaction);

export async function updateKeyword(
  id: string,
  updates: {
    keyword?: string;
    definition?: string;
    isSaved?: boolean;
    existingMetadata?: Record<string, unknown> | null;
  }
): Promise<void> {
  const payload: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };
  if (updates.keyword !== undefined) payload.keyword = updates.keyword;
  if (updates.definition !== undefined) payload.definition = updates.definition;
  if (updates.isSaved !== undefined) {
    payload.metadata = {
      ...(updates.existingMetadata ?? {}),
      saved: updates.isSaved,
    };
  }

  const { error } = await supabase.from('keywords').update(payload).eq('id', id);
  if (error) throw error;
}

export async function toggleAnnouncementCompleted(id: string, isCompleted: boolean): Promise<void> {
  const payload = {
    completed_at: isCompleted ? new Date().toISOString() : null,
    updated_at: new Date().toISOString(),
  };
  const { error } = await supabase.from('announcements').update(payload).eq('id', id);
  if (error) throw error;
}
