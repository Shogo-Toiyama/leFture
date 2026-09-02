import { supabase } from './supabase';
import type { Lecture } from '../types/lecture';

export async function listLectures(courseId: string): Promise<Lecture[]> {
  const { data, error } = await supabase
    .from('lectures')
    .select('*')
    .eq('course_id', courseId)
    .is('deleted_at', null)
    .order('lecture_datetime', { ascending: false });
  if (error) throw error;
  return data as Lecture[];
}

export async function getLecture(lectureId: string): Promise<Lecture> {
  const { data, error } = await supabase.from('lectures').select('*').eq('id', lectureId).single();
  if (error) throw error;
  return data as Lecture;
}

export interface DraftLectureInput {
  courseId: string;
  title: string;
  lectureDatetime: string;
  recordingLanguage: string;
  displayLanguage: string;
}

/**
 * recording_controller.dart:788-872 の uploadAudioFile が作るドラフト行のWeb版。
 * モバイルはローカルDrift経由だが、Webはオフライン要件がないのでSupabaseへ直接insertする。
 */
export async function createDraftLecture(input: DraftLectureInput): Promise<Lecture> {
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) throw new Error('Not signed in');

  const { data, error } = await supabase
    .from('lectures')
    .insert({
      user_id: userId,
      course_id: input.courseId,
      title: input.title.trim() || null,
      lecture_datetime: input.lectureDatetime,
      sort_order: 0,
      recording_language: input.recordingLanguage,
      display_language: input.displayLanguage,
    })
    .select('*')
    .single();
  if (error) throw error;
  return data as Lecture;
}

export async function updateLecture(
  lectureId: string,
  updates: {
    title?: string | null;
    course_id?: string | null;
    lecture_datetime?: string;
  }
): Promise<Lecture> {
  const payload: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };
  if (updates.title !== undefined) payload.title = updates.title;
  if (updates.course_id !== undefined) payload.course_id = updates.course_id;
  if (updates.lecture_datetime !== undefined) payload.lecture_datetime = updates.lecture_datetime;

  const { data, error } = await supabase
    .from('lectures')
    .update(payload)
    .eq('id', lectureId)
    .select('*')
    .single();
  if (error) throw error;
  return data as Lecture;
}

export async function softDeleteLecture(lectureId: string): Promise<void> {
  const { error } = await supabase
    .from('lectures')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', lectureId);
  if (error) throw error;
}
