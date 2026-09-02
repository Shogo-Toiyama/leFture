import React, { useState } from 'react';
import type { Course } from '../../types/course';
import { useCourses } from '../../hooks/useCourses';
import { ModalDialog } from './ModalDialog';
import { CourseEditModal } from './CourseEditModal';
import { useLanguage } from '../../i18n/LanguageContext';

export interface CoursePickerModalProps {
  initialSelectedCourseId?: string | null;
  onClose: () => void;
  onSelectCourse: (courseId: string | null) => void;
}

export const CoursePickerModal: React.FC<CoursePickerModalProps> = ({
  initialSelectedCourseId,
  onClose,
  onSelectCourse,
}) => {
  const { language } = useLanguage();
  const { courses, refetch } = useCourses();

  const [selectedId, setSelectedId] = useState<string | null>(initialSelectedCourseId ?? null);
  const [searchQuery, setSearchQuery] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);

  const title = language === 'ja' ? 'コースを選択' : 'Select Course';
  const searchPlaceholder = language === 'ja' ? 'コースを検索…' : 'Search courses…';
  const confirmLabel = language === 'ja' ? 'このコースを選択' : 'Select Course';
  const cancelLabel = language === 'ja' ? 'キャンセル' : 'Cancel';
  const noResultsText = language === 'ja' ? 'コースが見つかりません' : 'No courses found';

  const filteredCourses = courses.filter((c) => {
    const q = searchQuery.toLowerCase().trim();
    if (!q) return true;
    return (
      c.course_title.toLowerCase().includes(q) ||
      (c.course_code && c.course_code.toLowerCase().includes(q))
    );
  });

  const handleConfirm = () => {
    if (!selectedId) return;
    onSelectCourse(selectedId);
    onClose();
  };

  const handleCourseCreated = async (newCourse: Course) => {
    await refetch();
    setSelectedId(newCourse.id);
    setShowCreateModal(false);
  };

  return (
    <>
      <ModalDialog title={title} onClose={onClose} maxWidth={540}>
        <div className="course-picker-flow">
          {/* Search & Add New Course Row */}
          <div className="course-picker-search-row">
            <div className="course-picker-search-box">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="picker-search-svg">
                <circle cx="11" cy="11" r="8" />
                <line x1="21" y1="21" x2="16.65" y2="16.65" />
              </svg>
              <input
                type="text"
                className="course-picker-search-input"
                placeholder={searchPlaceholder}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                autoFocus
              />
              {searchQuery && (
                <button
                  type="button"
                  className="picker-search-clear"
                  onClick={() => setSearchQuery('')}
                >
                  ✕
                </button>
              )}
            </div>

            <button
              type="button"
              className="course-picker-add-btn"
              onClick={() => setShowCreateModal(true)}
              title={language === 'ja' ? '新規コース作成' : 'Create new course'}
            >
              +
            </button>
          </div>

          {/* Course List */}
          <div className="course-picker-list">
            {filteredCourses.map((c) => {
              const isSelected = selectedId === c.id;
              const courseColor = (c.metadata?.color as string) || '#FFB300';

              return (
                <div
                  key={c.id}
                  className={`course-picker-item ${isSelected ? 'is-selected' : ''}`}
                  onClick={() => setSelectedId(c.id)}
                >
                  <div
                    className="picker-item-icon-wrap"
                    style={{
                      backgroundColor: `${courseColor}22`,
                      color: courseColor,
                      borderColor: `${courseColor}44`,
                    }}
                  >
                    <span className="picker-item-icon">✦</span>
                  </div>
                  <div className="picker-item-info">
                    <span className="picker-item-title">{c.course_title}</span>
                    {c.course_code && <span className="picker-item-code">{c.course_code}</span>}
                  </div>
                  <div className="picker-item-radio">
                    <div className={`picker-radio-dot ${isSelected ? 'is-checked' : ''}`} />
                  </div>
                </div>
              );
            })}

            {filteredCourses.length === 0 && (
              <div className="modal-empty-state" style={{ padding: '2rem 1rem' }}>
                <p>{noResultsText}</p>
              </div>
            )}
          </div>

          {/* Confirm Button Footer */}
          <div className="course-picker-footer">
            <button
              type="button"
              className="keyword-btn-cancel"
              onClick={onClose}
            >
              {cancelLabel}
            </button>
            <button
              type="button"
              className="auth-submit-btn picker-btn-confirm"
              onClick={handleConfirm}
              disabled={!selectedId}
            >
              {confirmLabel}
            </button>
          </div>
        </div>
      </ModalDialog>

      {/* Sub-modal: Create Course Modal */}
      {showCreateModal && (
        <CourseEditModal
          onClose={() => setShowCreateModal(false)}
          onCourseSaved={handleCourseCreated}
        />
      )}
    </>
  );
};
