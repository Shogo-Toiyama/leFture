import React from 'react';
import { Tag, User, Landmark, Bookmark, Calendar, Clock, type LucideIcon } from 'lucide-react';
import type { Course } from '../../types/course';
import { ModalDialog } from './ModalDialog';
import { useLanguage } from '../../i18n/LanguageContext';
import { useCourseAttributes } from '../../hooks/useCourseAttributes';

export interface CourseDetailsModalProps {
  course: Course;
  resolvedAttributes?: {
    yearName?: string;
    termName?: string;
    professorName?: string;
    schoolName?: string;
    subjectName?: string;
  };
  onClose: () => void;
}

/**
 * Flutter版 `course_details_sheet.dart` と完全同期したコース詳細モーダル。
 * 項目順: コード / 教授 / 学校 / 科目 / 学期・年度 / 作成日 / 概要
 */
export const CourseDetailsModal: React.FC<CourseDetailsModalProps> = ({
  course,
  resolvedAttributes,
  onClose,
}) => {
  const { language } = useLanguage();

  const existingYears = useCourseAttributes('year');
  const existingTerms = useCourseAttributes('term');
  const existingProfessors = useCourseAttributes('professor');
  const existingSchools = useCourseAttributes('school');
  const existingSubjects = useCourseAttributes('subject');

  const yearName =
    resolvedAttributes?.yearName ??
    (course.year_id ? existingYears.find((y) => y.id === course.year_id)?.attribute_name : undefined);

  const termName =
    resolvedAttributes?.termName ??
    (course.term_id ? existingTerms.find((t) => t.id === course.term_id)?.attribute_name : undefined);

  const professorName =
    resolvedAttributes?.professorName ??
    (course.professor
      ? existingProfessors.find((p) => p.id === course.professor)?.attribute_name || course.professor
      : undefined);

  const schoolName =
    resolvedAttributes?.schoolName ??
    (course.school_id ? existingSchools.find((s) => s.id === course.school_id)?.attribute_name : undefined);

  const subjectName =
    resolvedAttributes?.subjectName ??
    (course.subject_id ? existingSubjects.find((s) => s.id === course.subject_id)?.attribute_name : undefined);

  const title = course.course_title;
  const codeLabel = language === 'ja' ? 'コード' : 'Course Code';
  const professorLabel = language === 'ja' ? '教授' : 'Professor';
  const schoolLabel = language === 'ja' ? '学校' : 'School';
  const subjectLabel = language === 'ja' ? '科目' : 'Subject';
  const termLabel = language === 'ja' ? '学期・年度' : 'Term & Year';
  const createdLabel = language === 'ja' ? '作成日' : 'Created';
  const summaryLabel = language === 'ja' ? '概要' : 'Summary';

  const rows: { icon: LucideIcon; label: string; value: string }[] = [];

  // 1. コード (Icons.tag)
  if (course.course_code?.trim()) {
    rows.push({ icon: Tag, label: codeLabel, value: course.course_code.trim() });
  }

  // 2. 教授 (Icons.person_outline)
  if (professorName?.trim()) {
    rows.push({ icon: User, label: professorLabel, value: professorName.trim() });
  }

  // 3. 学校 (Icons.account_balance_outlined)
  if (schoolName?.trim()) {
    rows.push({ icon: Landmark, label: schoolLabel, value: schoolName.trim() });
  }

  // 4. 科目 (Icons.category_outlined)
  if (subjectName?.trim()) {
    rows.push({ icon: Bookmark, label: subjectLabel, value: subjectName.trim() });
  }

  // 5. 学期・年度 (Icons.calendar_today_outlined)
  const termYearParts = [termName?.trim(), yearName?.trim()].filter(Boolean);
  if (termYearParts.length > 0) {
    rows.push({ icon: Calendar, label: termLabel, value: termYearParts.join(' ') });
  }

  // 6. 作成日 (Icons.schedule)
  if (course.created_at) {
    const formattedDate = new Date(course.created_at).toLocaleDateString(
      language === 'ja' ? 'ja-JP' : 'en-US',
      {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      }
    );
    rows.push({ icon: Clock, label: createdLabel, value: formattedDate });
  }

  return (
    <ModalDialog title={title} onClose={onClose} maxWidth={520}>
      <div className="course-details-flow">
        <div className="course-details-rows">
          {rows.map((row, idx) => (
            <div key={idx} className="course-details-row">
              <row.icon size={18} className="details-row-icon" />
              <span className="details-row-label">{row.label}</span>
              <span className="details-row-value">{row.value}</span>
            </div>
          ))}
        </div>

        {course.summary?.trim() && (
          <div className="course-details-summary-section">
            <span className="details-summary-label">{summaryLabel}</span>
            <p className="details-summary-text">{course.summary.trim()}</p>
          </div>
        )}
      </div>
    </ModalDialog>
  );
};
