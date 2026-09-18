import { supabase } from './supabase';
import { apiFetch } from './api';
import { stripFunFactCitations } from './content';

export type ActivityType = 'saved' | 'likes' | 'dislikes' | 'announcements' | 'trash';

export type ActivityRecordType =
  | 'reviewCard'
  | 'deepNote'
  | 'keyword'
  | 'funFact'
  | 'announcement'
  | 'lecture'
  | 'course';

export interface ActivityRecord {
  id: string;
  type: ActivityRecordType;
  title: string;
  content: string;
  dateTime: string;
  lectureId?: string;
  courseId?: string;
  topicIndex?: number;
  metadata?: Record<string, unknown> | null;
  completedAt?: string | null;
  announcementType?: 'todo' | 'event' | 'info' | 'hint' | string;
}

/**
 * Clean plain-text preview generator (strips citations, markdown markers, extra whitespace)
 */
export function plainTextPreview(text: string | null | undefined, maxLength = 140): string {
  if (!text) return '';
  const cleaned = stripFunFactCitations(text)
    .replace(/[#*`_~>[\]()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (cleaned.length <= maxLength) return cleaned;
  return cleaned.slice(0, maxLength) + '…';
}

/**
 * Fetch all activity items from Supabase for the given activity type
 */
export async function fetchActivityRecords(type: ActivityType): Promise<ActivityRecord[]> {
  const { data: userData } = await supabase.auth.getUser();
  const uid = userData?.user?.id;
  if (!uid) return [];

  // Pre-fetch lectures to map lectureId -> courseId and title
  const { data: lecturesData } = await supabase
    .from('lectures')
    .select('id, course_id, title, title_generated')
    .eq('user_id', uid);

  const lectureCourseMap: Record<string, string> = {};
  if (lecturesData) {
    for (const lec of lecturesData) {
      if (lec.course_id) {
        lectureCourseMap[lec.id] = lec.course_id;
      }
    }
  }

  const list: ActivityRecord[] = [];

  switch (type) {
    case 'saved': {
      // 1. Review cards
      const { data: cards } = await supabase
        .from('review_cards')
        .select('*')
        .eq('user_id', uid)
        .is('deleted_at', null);

      if (cards) {
        for (const c of cards) {
          const meta = (c.metadata as Record<string, unknown> | null) ?? null;
          if (meta?.saved === true || meta?.saved === 'true') {
            let snippet = '';
            if (Array.isArray(c.card_content) && c.card_content.length > 0) {
              const first = c.card_content[0];
              if (first && typeof first === 'object') {
                snippet = first.text || (Array.isArray(first.items) ? first.items.join(', ') : '');
              }
            } else if (typeof c.card_content === 'string') {
              snippet = c.card_content;
            }
            list.push({
              id: c.id,
              type: 'reviewCard',
              title: c.title || 'Review Card',
              content: plainTextPreview(snippet),
              dateTime: c.updated_at || c.created_at || new Date().toISOString(),
              lectureId: c.lecture_id,
              courseId: lectureCourseMap[c.lecture_id],
              metadata: meta,
            });
          }
        }
      }

      // 2. Deep notes & lecture topics for titles
      const { data: notes } = await supabase
        .from('deep_notes')
        .select('*')
        .eq('user_id', uid)
        .is('deleted_at', null);

      const { data: topics } = await supabase
        .from('lecture_topics')
        .select('lecture_id, index, topic_title')
        .eq('user_id', uid)
        .is('deleted_at', null);

      if (notes) {
        for (const n of notes) {
          const meta = (n.metadata as Record<string, unknown> | null) ?? null;
          if (meta?.saved === true || meta?.saved === 'true') {
            const topic = topics?.find(
              (t) => t.lecture_id === n.lecture_id && t.index === n.topic_number
            );
            const title =
              topic?.topic_title?.trim() || `Deep Note (Topic ${n.topic_number ?? 1})`;
            list.push({
              id: n.id,
              type: 'deepNote',
              title,
              content: plainTextPreview(n.note_contents),
              dateTime: n.updated_at || n.created_at || new Date().toISOString(),
              lectureId: n.lecture_id,
              courseId: lectureCourseMap[n.lecture_id],
              topicIndex: n.topic_number,
              metadata: meta,
            });
          }
        }
      }

      // 3. Keywords
      const { data: keywords } = await supabase
        .from('keywords')
        .select('*')
        .eq('user_id', uid)
        .is('deleted_at', null);

      if (keywords) {
        for (const k of keywords) {
          const meta = (k.metadata as Record<string, unknown> | null) ?? null;
          if (meta?.saved === true || meta?.saved === 'true') {
            list.push({
              id: k.id,
              type: 'keyword',
              title: k.keyword?.trim() || 'Keyword',
              content: plainTextPreview(k.definition),
              dateTime: k.updated_at || k.created_at || new Date().toISOString(),
              lectureId: k.lecture_id,
              courseId: lectureCourseMap[k.lecture_id],
              metadata: meta,
            });
          }
        }
      }
      break;
    }

    case 'likes':
    case 'dislikes': {
      const targetReaction = type === 'likes' ? 'like' : 'dislike';

      // 1. Review cards
      const { data: cards } = await supabase
        .from('review_cards')
        .select('*')
        .eq('user_id', uid)
        .is('deleted_at', null);

      if (cards) {
        for (const c of cards) {
          const meta = (c.metadata as Record<string, unknown> | null) ?? null;
          if (meta?.reaction === targetReaction) {
            let snippet = '';
            if (Array.isArray(c.card_content) && c.card_content.length > 0) {
              const first = c.card_content[0];
              if (first && typeof first === 'object') {
                snippet = first.text || (Array.isArray(first.items) ? first.items.join(', ') : '');
              }
            } else if (typeof c.card_content === 'string') {
              snippet = c.card_content;
            }
            list.push({
              id: c.id,
              type: 'reviewCard',
              title: c.title || 'Review Card',
              content: plainTextPreview(snippet),
              dateTime: c.updated_at || c.created_at || new Date().toISOString(),
              lectureId: c.lecture_id,
              courseId: lectureCourseMap[c.lecture_id],
              metadata: meta,
            });
          }
        }
      }

      // 2. Deep notes
      const { data: notes } = await supabase
        .from('deep_notes')
        .select('*')
        .eq('user_id', uid)
        .is('deleted_at', null);

      const { data: topics } = await supabase
        .from('lecture_topics')
        .select('lecture_id, index, topic_title')
        .eq('user_id', uid)
        .is('deleted_at', null);

      if (notes) {
        for (const n of notes) {
          const meta = (n.metadata as Record<string, unknown> | null) ?? null;
          if (meta?.reaction === targetReaction) {
            const topic = topics?.find(
              (t) => t.lecture_id === n.lecture_id && t.index === n.topic_number
            );
            const title =
              topic?.topic_title?.trim() || `Deep Note (Topic ${n.topic_number ?? 1})`;
            list.push({
              id: n.id,
              type: 'deepNote',
              title,
              content: plainTextPreview(n.note_contents),
              dateTime: n.updated_at || n.created_at || new Date().toISOString(),
              lectureId: n.lecture_id,
              courseId: lectureCourseMap[n.lecture_id],
              topicIndex: n.topic_number,
              metadata: meta,
            });
          }
        }
      }

      // 3. Fun facts
      const { data: facts } = await supabase
        .from('fun_facts')
        .select('*')
        .eq('user_id', uid)
        .is('deleted_at', null);

      if (facts) {
        for (const f of facts) {
          const meta = (f.metadata as Record<string, unknown> | null) ?? null;
          const reaction = (f as { reaction?: string }).reaction || meta?.reaction;
          if (reaction === targetReaction) {
            list.push({
              id: f.id,
              type: 'funFact',
              title: f.title || 'Fun Fact',
              content: plainTextPreview(f.hook || f.body),
              dateTime: f.updated_at || f.created_at || new Date().toISOString(),
              lectureId: f.lecture_id,
              courseId: lectureCourseMap[f.lecture_id],
              metadata: meta,
            });
          }
        }
      }
      break;
    }

    case 'announcements': {
      const { data: anns } = await supabase
        .from('announcements')
        .select('*')
        .eq('user_id', uid)
        .is('deleted_at', null)
        .order('created_at', { ascending: false });

      if (anns) {
        for (const a of anns) {
          list.push({
            id: a.id,
            type: 'announcement',
            title: a.title || 'Announcement',
            content: plainTextPreview(a.description || ''),
            dateTime: a.created_at || new Date().toISOString(),
            lectureId: a.lecture_id,
            courseId: lectureCourseMap[a.lecture_id],
            completedAt: a.completed_at,
            announcementType: a.type || 'info',
            metadata: (a.metadata as Record<string, unknown> | null) ?? null,
          });
        }
      }
      break;
    }

    case 'trash': {
      // 1. Deleted Courses
      const { data: courses } = await supabase
        .from('courses')
        .select('*')
        .eq('user_id', uid)
        .not('deleted_at', 'is', null)
        .order('deleted_at', { ascending: false });

      if (courses) {
        for (const c of courses) {
          list.push({
            id: c.id,
            type: 'course',
            title: c.title || c.course_code || 'Untitled Course',
            content: c.course_code || 'Course',
            dateTime: c.deleted_at || c.updated_at || new Date().toISOString(),
            courseId: c.id,
          });
        }
      }

      // 2. Deleted Lectures
      const { data: lectures } = await supabase
        .from('lectures')
        .select('*')
        .eq('user_id', uid)
        .not('deleted_at', 'is', null)
        .order('deleted_at', { ascending: false });

      if (lectures) {
        for (const l of lectures) {
          const displayTitle = l.title?.trim() || l.title_generated?.trim() || 'Untitled Lecture';
          list.push({
            id: l.id,
            type: 'lecture',
            title: displayTitle,
            content: 'Lecture',
            dateTime: l.deleted_at || l.updated_at || new Date().toISOString(),
            lectureId: l.id,
            courseId: l.course_id,
          });
        }
      }

      // 3. Deleted Announcements
      const { data: anns } = await supabase
        .from('announcements')
        .select('*')
        .eq('user_id', uid)
        .not('deleted_at', 'is', null)
        .order('deleted_at', { ascending: false });

      if (anns) {
        for (const a of anns) {
          list.push({
            id: a.id,
            type: 'announcement',
            title: a.title || 'Announcement',
            content: plainTextPreview(a.description || 'Announcement'),
            dateTime: a.deleted_at || a.updated_at || new Date().toISOString(),
            lectureId: a.lecture_id,
            courseId: lectureCourseMap[a.lecture_id],
          });
        }
      }
      break;
    }
  }

  // Sort descending by dateTime
  list.sort((a, b) => new Date(b.dateTime).getTime() - new Date(a.dateTime).getTime());
  return list;
}

/**
 * Toggle saved status for a record
 */
export async function toggleSaveRecord(record: ActivityRecord, save: boolean): Promise<void> {
  const nextMeta = { ...(record.metadata ?? {}), saved: save };
  const now = new Date().toISOString();

  if (record.type === 'reviewCard') {
    const { error } = await supabase
      .from('review_cards')
      .update({ metadata: nextMeta, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  } else if (record.type === 'deepNote') {
    const { error } = await supabase
      .from('deep_notes')
      .update({ metadata: nextMeta, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  } else if (record.type === 'keyword') {
    const { error } = await supabase
      .from('keywords')
      .update({ metadata: nextMeta, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  }
}

/**
 * Update reaction (like/dislike/null) for a record
 */
export async function updateReactionRecord(
  record: ActivityRecord,
  reaction: 'like' | 'dislike' | null
): Promise<void> {
  const nextMeta = { ...(record.metadata ?? {}), reaction };
  const now = new Date().toISOString();

  if (record.type === 'reviewCard') {
    const { error } = await supabase
      .from('review_cards')
      .update({ metadata: nextMeta, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  } else if (record.type === 'deepNote') {
    const { error } = await supabase
      .from('deep_notes')
      .update({ metadata: nextMeta, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  } else if (record.type === 'funFact') {
    const { error } = await supabase
      .from('fun_facts')
      .update({ metadata: nextMeta, reaction, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  }
}

/**
 * Toggle announcement completion status
 */
export async function toggleAnnouncementComplete(id: string, isCompleted: boolean): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase
    .from('announcements')
    .update({
      completed_at: isCompleted ? now : null,
      updated_at: now,
    })
    .eq('id', id);
  if (error) throw error;
}

/**
 * Soft-delete an announcement
 */
export async function softDeleteAnnouncement(id: string): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase
    .from('announcements')
    .update({
      deleted_at: now,
      updated_at: now,
    })
    .eq('id', id);
  if (error) throw error;
}

/**
 * Restore an item from trash (sets deleted_at = null)
 */
export async function restoreTrashRecord(record: ActivityRecord): Promise<void> {
  const now = new Date().toISOString();

  if (record.type === 'course') {
    const { error } = await supabase
      .from('courses')
      .update({ deleted_at: null, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  } else if (record.type === 'lecture') {
    const { error } = await supabase
      .from('lectures')
      .update({ deleted_at: null, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  } else if (record.type === 'announcement') {
    const { error } = await supabase
      .from('announcements')
      .update({ deleted_at: null, updated_at: now })
      .eq('id', record.id);
    if (error) throw error;
  }
}

/**
 * Delete a trash item permanently
 */
export async function deleteTrashRecordPermanently(record: ActivityRecord): Promise<void> {
  if (record.type === 'course') {
    try {
      await apiFetch(`/courses/${record.id}/hard-delete`, { method: 'POST' });
    } catch (e: unknown) {
      // 404 is treated as already deleted
      if ((e as { status?: number }).status !== 404) throw e;
    }
  } else if (record.type === 'lecture') {
    try {
      await apiFetch(`/lectures/${record.id}/hard-delete`, { method: 'POST' });
    } catch (e: unknown) {
      if ((e as { status?: number }).status !== 404) throw e;
    }
  } else if (record.type === 'announcement') {
    const { error } = await supabase.from('announcements').delete().eq('id', record.id);
    if (error) throw error;
  }
}

/**
 * Empty all items from trash
 */
export async function emptyTrashRecords(records: ActivityRecord[]): Promise<void> {
  // Call backend /trash/empty
  try {
    await apiFetch('/trash/empty', { method: 'POST' });
  } catch (backendError) {
    // If backend /trash/empty fails or for any announcements remaining, clean up
    console.warn('Backend empty trash failed or partially succeeded, cleaning announcements', backendError);
  }

  // Also ensure announcements in trash are permanently deleted
  const annIds = records.filter((r) => r.type === 'announcement').map((r) => r.id);
  if (annIds.length > 0) {
    await supabase.from('announcements').delete().in('id', annIds);
  }
}
