export type CourseAttributeType = 'year' | 'term' | 'professor' | 'school' | 'subject';

export interface CourseAttribute {
  id: string;
  attribute_type: CourseAttributeType;
  attribute_name: string;
}

export interface CourseMetadata {
  color?: string;
  icon?: string;
  [key: string]: unknown;
}

export interface Course {
  id: string;
  user_id: string;
  course_title: string;
  course_code: string | null;
  summary: string | null;
  year_id: string | null;
  term_id: string | null;
  professor: string | null;
  school_id: string | null;
  subject_id: string | null;
  metadata: CourseMetadata | null;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
}
