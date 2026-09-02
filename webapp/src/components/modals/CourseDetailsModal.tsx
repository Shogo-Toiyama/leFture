import React from 'react';
import type { Course } from '../../types/course';
import { ModalDialog } from './ModalDialog';
import { useLanguage } from '../../i18n/LanguageContext';

export interface CourseDetailsModalProps {
  course: Course;
  onClose: () => void;
}

export const CourseDetailsModal: React.FC<CourseDetailsModalProps> = ({
  course,
  onClose,
}) => {
  const { language } = useLanguage();

  const title = course.course_title;
  const courseCodeLabel = language === 'ja' ? 'コースコード' : 'Course Code';
  const termLabel = language === 'ja' ? '開講期・年度' : 'Term & Year';
  const createdLabel = language === 'ja' ? '作成日' : 'Created';
  const summaryLabel = language === 'ja' ? '概要・説明' : 'Summary';

  const rows: { icon: string; label: string; value: string }[] = [];

  if (course.course_code?.trim()) {
    rows.push({ icon: '#', label: courseCodeLabel, value: course.course_code.trim() });
  }

  // Attributes from populated object or metadata if available
  const termYearParts = [
    (course as unknown as { term?: { attribute_name: string } })?.term?.attribute_name,
    (course as unknown as { year?: { attribute_name: string } })?.year?.attribute_name,
  ].filter(Boolean);

  if (termYearParts.length > 0) {
    rows.push({ icon: '📅', label: termLabel, value: termYearParts.join(' ') });
  }

  if (course.created_at) {
    const formattedDate = new Date(course.created_at).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
    rows.push({ icon: '🕒', label: createdLabel, value: formattedDate });
  }

  return (
    <ModalDialog title={title} onClose={onClose} maxWidth={520}>
      <div className="course-details-flow">
        <div className="course-details-rows">
          {rows.map((row, idx) => (
            <div key={idx} className="course-details-row">
              <span className="details-row-icon">{row.icon}</span>
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
