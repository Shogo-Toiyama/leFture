import { supabase } from './supabase';
import type { Course, CourseAttribute, CourseAttributeType, CourseMetadata } from '../types/course';

export async function listCourses(): Promise<Course[]> {
  const { data, error } = await supabase
    .from('courses')
    .select('*')
    .is('deleted_at', null)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data as Course[];
}

export async function getCourse(courseId: string): Promise<Course> {
  const { data, error } = await supabase.from('courses').select('*').eq('id', courseId).single();
  if (error) throw error;
  return data as Course;
}

export async function listAttributes(attributeType: CourseAttributeType): Promise<CourseAttribute[]> {
  const { data, error } = await supabase
    .from('course_attributes')
    .select('id, attribute_type, attribute_name')
    .eq('attribute_type', attributeType)
    .is('deleted_at', null)
    .order('attribute_name', { ascending: true });
  if (error) throw error;
  return data as CourseAttribute[];
}

/** Flutter同等のget-or-createパターン (course_attribute_repository_supabase.dart:52-81)。 */
async function resolveAttribute(
  attributeType: CourseAttributeType,
  rawName: string
): Promise<string | null> {
  const attributeName = rawName.trim();
  if (!attributeName) return null;

  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) throw new Error('Not signed in');

  const { data: existing, error: selectError } = await supabase
    .from('course_attributes')
    .select('id')
    .eq('user_id', userId)
    .eq('attribute_type', attributeType)
    .eq('attribute_name', attributeName)
    .maybeSingle();
  if (selectError) throw selectError;
  if (existing) return existing.id as string;

  const { data: inserted, error: insertError } = await supabase
    .from('course_attributes')
    .insert({ user_id: userId, attribute_type: attributeType, attribute_name: attributeName })
    .select('id')
    .single();
  if (insertError) throw insertError;
  return inserted.id as string;
}

export interface CourseFormInput {
  courseTitle: string;
  courseCode: string;
  summary: string;
  year: string;
  term: string;
  professor: string;
  school: string;
  subject: string;
  metadata: CourseMetadata;
}

export async function createCourse(input: CourseFormInput): Promise<Course> {
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) throw new Error('Not signed in');

  const [yearId, termId, professorId, schoolId, subjectId] = await Promise.all([
    resolveAttribute('year', input.year),
    resolveAttribute('term', input.term),
    resolveAttribute('professor', input.professor),
    resolveAttribute('school', input.school),
    resolveAttribute('subject', input.subject),
  ]);

  const { data, error } = await supabase
    .from('courses')
    .insert({
      user_id: userId,
      course_title: input.courseTitle.trim(),
      course_code: input.courseCode.trim() || null,
      summary: input.summary.trim() || null,
      year_id: yearId,
      term_id: termId,
      professor: professorId,
      school_id: schoolId,
      subject_id: subjectId,
      metadata: input.metadata,
    })
    .select('*')
    .single();
  if (error) throw error;
  return data as Course;
}

export async function updateCourse(courseId: string, input: CourseFormInput): Promise<Course> {
  const [yearId, termId, professorId, schoolId, subjectId] = await Promise.all([
    resolveAttribute('year', input.year),
    resolveAttribute('term', input.term),
    resolveAttribute('professor', input.professor),
    resolveAttribute('school', input.school),
    resolveAttribute('subject', input.subject),
  ]);

  const { data, error } = await supabase
    .from('courses')
    .update({
      course_title: input.courseTitle.trim(),
      course_code: input.courseCode.trim() || null,
      summary: input.summary.trim() || null,
      year_id: yearId,
      term_id: termId,
      professor: professorId,
      school_id: schoolId,
      subject_id: subjectId,
      metadata: input.metadata,
      updated_at: new Date().toISOString(),
    })
    .eq('id', courseId)
    .select('*')
    .single();
  if (error) throw error;
  return data as Course;
}

export async function softDeleteCourse(courseId: string): Promise<void> {
  const { error } = await supabase
    .from('courses')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', courseId);
  if (error) throw error;
}
