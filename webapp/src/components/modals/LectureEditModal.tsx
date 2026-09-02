import React, { useState } from 'react';
import type { Lecture } from '../../types/lecture';
import { useCourses } from '../../hooks/useCourses';
import { updateLecture } from '../../lib/lectures';
import { ModalDialog } from './ModalDialog';
import { CoursePickerModal } from './CoursePickerModal';
import { useLanguage } from '../../i18n/LanguageContext';

export interface LectureEditModalProps {
  lecture: Lecture;
  onClose: () => void;
  onLectureUpdated?: (updated: Lecture) => void;
}

export const LectureEditModal: React.FC<LectureEditModalProps> = ({
  lecture,
  onClose,
  onLectureUpdated,
}) => {
  const { language } = useLanguage();
  const { courses } = useCourses();

  // Format date for <input type="datetime-local"> (YYYY-MM-DDTHH:mm)
  const formatDatetimeLocal = (iso: string) => {
    try {
      const d = new Date(iso);
      const offset = d.getTimezoneOffset() * 60000;
      const local = new Date(d.getTime() - offset);
      return local.toISOString().slice(0, 16);
    } catch {
      return '';
    }
  };

  const [title, setTitle] = useState(lecture.title ?? '');
  const [courseId, setCourseId] = useState<string | null>(lecture.course_id ?? null);
  const [lectureDatetime, setLectureDatetime] = useState<string>(
    formatDatetimeLocal(lecture.lecture_datetime)
  );
  const [showCoursePicker, setShowCoursePicker] = useState(false);
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const selectedCourse = courses.find((c) => c.id === courseId);
  const selectedCourseColor = (selectedCourse?.metadata?.color as string) || '#FFB300';

  const modalTitle = language === 'ja' ? '講義を編集' : 'Edit Lecture';
  const courseLabel = language === 'ja' ? 'コース' : 'Course';
  const noCourseLabel = language === 'ja' ? 'コース未設定' : 'No Course (Unassigned)';
  const datetimeLabel = language === 'ja' ? '講義日時' : 'Lecture Date & Time';
  const titleLabel = language === 'ja' ? 'タイトル' : 'Title';
  const defaultSuffix = lecture.title_generated
    ? (language === 'ja' ? `${lecture.title_generated}（デフォルト）` : `${lecture.title_generated} (Default)`)
    : (language === 'ja' ? '無題の講義' : 'Untitled Lecture');
  const saveLabel = language === 'ja' ? '保存' : 'Save';
  const savingLabel = language === 'ja' ? '保存中…' : 'Saving…';
  const cancelLabel = language === 'ja' ? 'キャンセル' : 'Cancel';

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setErrorMsg(null);

    try {
      const isoDatetime = lectureDatetime ? new Date(lectureDatetime).toISOString() : lecture.lecture_datetime;
      const updated = await updateLecture(lecture.id, {
        title: title.trim() ? title.trim() : null,
        course_id: courseId,
        lecture_datetime: isoDatetime,
      });

      onLectureUpdated?.(updated);
      onClose();
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to update lecture');
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <ModalDialog title={modalTitle} onClose={onClose} maxWidth={580}>
        <form onSubmit={handleSave} className="lecture-edit-form">
          {errorMsg && (
            <div className="app-error-box" style={{ marginBottom: '1rem' }}>
              <span>{errorMsg}</span>
            </div>
          )}

          {/* 1. Course Selection Pill Box (Opens CoursePickerModal) */}
          <div className="edit-form-field">
            <label className="edit-form-label">{courseLabel}</label>
            <div
              className="edit-course-selector-box"
              onClick={() => setShowCoursePicker(true)}
              role="button"
              tabIndex={0}
            >
              {selectedCourse ? (
                <div className="selected-course-info">
                  <div
                    className="selected-course-dot"
                    style={{ backgroundColor: selectedCourseColor }}
                  />
                  <span className="selected-course-name">{selectedCourse.course_title}</span>
                </div>
              ) : (
                <span className="unassigned-course-text">{noCourseLabel}</span>
              )}
              <span className="selector-chevron">›</span>
            </div>
          </div>

          {/* 2. Lecture Date & Time */}
          <div className="edit-form-field">
            <label className="edit-form-label">{datetimeLabel}</label>
            <input
              type="datetime-local"
              className="auth-input edit-datetime-input"
              value={lectureDatetime}
              onChange={(e) => setLectureDatetime(e.target.value)}
              required
            />
          </div>

          {/* 3. Title */}
          <div className="edit-form-field">
            <label className="edit-form-label">{titleLabel}</label>
            <input
              type="text"
              className="auth-input edit-title-input"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={defaultSuffix}
            />
          </div>

          {/* Submit Actions */}
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
              disabled={saving}
            >
              {saving ? savingLabel : saveLabel}
            </button>
          </div>
        </form>
      </ModalDialog>

      {/* Sub-modal: Course Picker */}
      {showCoursePicker && (
        <CoursePickerModal
          initialSelectedCourseId={courseId}
          onClose={() => setShowCoursePicker(false)}
          onSelectCourse={(newCourseId) => {
            setCourseId(newCourseId);
            setShowCoursePicker(false);
          }}
        />
      )}
    </>
  );
};
