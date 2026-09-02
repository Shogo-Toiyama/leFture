import React, { useState } from 'react';
import type { Course } from '../../types/course';
import { createCourse, updateCourse } from '../../lib/courses';
import { ModalDialog } from './ModalDialog';
import { useLanguage } from '../../i18n/LanguageContext';

const PRESET_COLORS = [
  '#FFB300', // Gold (Default)
  '#FF7043', // Orange
  '#EF5350', // Red
  '#EC407A', // Pink
  '#AB47BC', // Purple
  '#5C6BC0', // Indigo
  '#42A5F5', // Blue
  '#26A69A', // Teal
  '#66BB6A', // Green
  '#8D6E63', // Brown
];

const PRESET_ICONS = [
  'school',
  'book',
  'science',
  'code',
  'calculate',
  'psychology',
  'history_edu',
  'language',
  'palette',
  'music_note',
  'public',
  'biotech',
];

export interface CourseEditModalProps {
  existingCourse?: Course | null;
  onClose: () => void;
  onCourseSaved?: (course: Course) => void;
}

export const CourseEditModal: React.FC<CourseEditModalProps> = ({
  existingCourse,
  onClose,
  onCourseSaved,
}) => {
  const { language } = useLanguage();
  const isEditing = Boolean(existingCourse);

  const [title, setTitle] = useState(existingCourse?.course_title ?? '');
  const [code, setCode] = useState(existingCourse?.course_code ?? '');
  const [summary, setSummary] = useState(existingCourse?.summary ?? '');
  const [color, setColor] = useState(
    (existingCourse?.metadata?.color as string) || '#FFB300'
  );
  const [icon, setIcon] = useState(
    (existingCourse?.metadata?.icon as string) || 'school'
  );
  const [showMore, setShowMore] = useState(
    Boolean(existingCourse?.course_code || existingCourse?.summary)
  );

  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const modalTitle = isEditing
    ? (language === 'ja' ? 'コースを編集' : 'Edit Course')
    : (language === 'ja' ? 'コースを作成' : 'Create Course');
  const titleLabel = language === 'ja' ? 'コース名' : 'Course Title';
  const colorLabel = language === 'ja' ? 'カラー' : 'Color';
  const iconLabel = language === 'ja' ? 'アイコン' : 'Icon';
  const moreInfoLabel = language === 'ja' ? '詳細情報（任意）' : 'More Information (Optional)';
  const codeLabel = language === 'ja' ? 'コースコード' : 'Course Code';
  const summaryLabel = language === 'ja' ? '概要・説明' : 'Summary';
  const saveLabel = isEditing
    ? (language === 'ja' ? '保存' : 'Save')
    : (language === 'ja' ? '作成' : 'Create');
  const cancelLabel = language === 'ja' ? 'キャンセル' : 'Cancel';

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) {
      setErrorMsg(language === 'ja' ? 'コース名を入力してください' : 'Please enter a course title');
      return;
    }

    setSaving(true);
    setErrorMsg(null);

    try {
      const input = {
        courseTitle: title.trim(),
        courseCode: code.trim(),
        summary: summary.trim(),
        year: '',
        term: '',
        professor: '',
        school: '',
        subject: '',
        metadata: {
          ...(existingCourse?.metadata ?? {}),
          color,
          icon,
        },
      };

      const result = isEditing && existingCourse
        ? await updateCourse(existingCourse.id, input)
        : await createCourse(input);

      onCourseSaved?.(result);
      onClose();
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to save course');
    } finally {
      setSaving(false);
    }
  };

  return (
    <ModalDialog title={modalTitle} onClose={onClose} maxWidth={560}>
      <form onSubmit={handleSave} className="course-edit-form">
        {errorMsg && (
          <div className="app-error-box" style={{ marginBottom: '1rem' }}>
            <span>{errorMsg}</span>
          </div>
        )}

        {/* 1. Title */}
        <div className="edit-form-field">
          <label className="edit-form-label">{titleLabel} *</label>
          <input
            type="text"
            className="auth-input edit-title-input"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={language === 'ja' ? '例: Computer Systems' : 'e.g. Computer Systems'}
            required
            autoFocus
          />
        </div>

        {/* 2. Color Selection */}
        <div className="edit-form-field">
          <label className="edit-form-label">{colorLabel}</label>
          <div className="course-color-picker-row">
            {PRESET_COLORS.map((c) => (
              <button
                key={c}
                type="button"
                className={`course-color-dot ${color === c ? 'is-selected' : ''}`}
                style={{ backgroundColor: c }}
                onClick={() => setColor(c)}
                aria-label={`Select color ${c}`}
              />
            ))}
          </div>
        </div>

        {/* 3. Icon Selection */}
        <div className="edit-form-field">
          <label className="edit-form-label">{iconLabel}</label>
          <div className="course-icon-picker-grid">
            {PRESET_ICONS.map((ic) => (
              <button
                key={ic}
                type="button"
                className={`course-icon-btn ${icon === ic ? 'is-selected' : ''}`}
                style={{
                  color: icon === ic ? color : 'var(--comet)',
                  borderColor: icon === ic ? color : 'transparent',
                }}
                onClick={() => setIcon(ic)}
              >
                <span className="course-icon-symbol">✦</span>
                <span className="course-icon-name">{ic}</span>
              </button>
            ))}
          </div>
        </div>

        {/* 4. More Information Accordion */}
        <div className="course-more-info-accordion">
          <button
            type="button"
            className="course-accordion-toggle"
            onClick={() => setShowMore((prev) => !prev)}
          >
            <span>{moreInfoLabel}</span>
            <span className="accordion-chevron">{showMore ? '▲' : '▼'}</span>
          </button>

          {showMore && (
            <div className="course-accordion-body">
              <div className="edit-form-field">
                <label className="edit-form-label">{codeLabel}</label>
                <input
                  type="text"
                  className="auth-input"
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  placeholder={language === 'ja' ? '例: CS101' : 'e.g. CS101'}
                />
              </div>

              <div className="edit-form-field">
                <label className="edit-form-label">{summaryLabel}</label>
                <textarea
                  className="auth-input"
                  value={summary}
                  onChange={(e) => setSummary(e.target.value)}
                  placeholder={language === 'ja' ? '講義の目的やシラバスなど' : 'Course description or syllabus'}
                  rows={2}
                />
              </div>
            </div>
          )}
        </div>

        {/* Form Actions */}
        <div className="edit-form-actions">
          <button
            type="button"
            className="keyword-btn-cancel"
            onClick={onClose}
            disabled={saving}
          >
            {cancelLabel}
          </button>
          <button
            type="submit"
            className="auth-submit-btn edit-btn-submit"
            disabled={saving || !title.trim()}
          >
            {saving
              ? (language === 'ja' ? '保存中…' : 'Saving…')
              : saveLabel}
          </button>
        </div>
      </form>
    </ModalDialog>
  );
};
