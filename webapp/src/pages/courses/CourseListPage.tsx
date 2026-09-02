import React, { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useCourses } from '../../hooks/useCourses';
import { useCourseAttributes } from '../../hooks/useCourseAttributes';
import { useLanguage } from '../../i18n/LanguageContext';
import { softDeleteCourse } from '../../lib/courses';
import { CourseEditModal } from '../../components/modals/CourseEditModal';
import { PageState } from '../../components/PageState';
import type { Course } from '../../types/course';

const NO_YEAR = '__no_year__';
const NO_TERM = '__no_term__';

interface TermGroup {
  key: string;
  label: string;
  courses: Course[];
}

interface YearGroup {
  key: string;
  label: string;
  terms: TermGroup[];
}

function groupCourses(
  courses: Course[],
  yearNames: Map<string, string>,
  termNames: Map<string, string>,
  language: string
): YearGroup[] {
  const noYearLabel = language === 'ja' ? '年度未設定' : 'Unsorted';
  const noTermLabel = language === 'ja' ? '学期未設定' : 'No term';

  const years = new Map<string, Map<string, Course[]>>();

  for (const course of courses) {
    const yearKey = course.year_id ?? NO_YEAR;
    const termKey = course.term_id ?? NO_TERM;
    if (!years.has(yearKey)) years.set(yearKey, new Map());
    const terms = years.get(yearKey)!;
    if (!terms.has(termKey)) terms.set(termKey, []);
    terms.get(termKey)!.push(course);
  }

  return Array.from(years.entries())
    .map(([yearKey, terms]) => ({
      key: yearKey,
      label: yearKey === NO_YEAR ? noYearLabel : yearNames.get(yearKey) ?? 'Year',
      terms: Array.from(terms.entries()).map(([termKey, list]) => ({
        key: termKey,
        label: termKey === NO_TERM ? noTermLabel : termNames.get(termKey) ?? 'Term',
        courses: list,
      })),
    }))
    .sort((a, b) => (a.key === NO_YEAR ? 1 : b.key === NO_YEAR ? -1 : b.label.localeCompare(a.label)));
}

export const CourseListPage: React.FC = () => {
  const { language } = useLanguage();
  const { courses, loading, error, refetch } = useCourses();
  const years = useCourseAttributes('year');
  const terms = useCourseAttributes('term');

  const [createModalOpen, setCreateModalOpen] = useState(false);
  const [editingCourse, setEditingCourse] = useState<Course | null>(null);
  const [collapsedYears, setCollapsedYears] = useState<Set<string>>(new Set());
  const [collapsedTerms, setCollapsedTerms] = useState<Set<string>>(new Set());

  const yearNames = useMemo(() => new Map(years.map((a) => [a.id, a.attribute_name])), [years]);
  const termNames = useMemo(() => new Map(terms.map((a) => [a.id, a.attribute_name])), [terms]);
  const groups = useMemo(() => groupCourses(courses, yearNames, termNames, language), [courses, yearNames, termNames, language]);

  const pageTitle = language === 'ja' ? 'コース一覧' : 'Courses';
  const newCourseButtonText = language === 'ja' ? '+ 新規コース' : '+ New Course';
  const emptyTitle = language === 'ja' ? 'コースがまだありません' : 'No courses yet';
  const emptySubtitle = language === 'ja'
    ? 'コースを作成して、最初の講義録音をアップロードしましょう。'
    : 'Create a course, then upload your first lecture recording.';
  const deleteConfirmMessage = (title: string) =>
    language === 'ja'
      ? `コース「${title}」を削除しますか？講義は保持されますがコースは非表示になります。`
      : `Delete course "${title}"? Its lectures stay in your account but the course will be hidden.`;

  const toggleYear = (key: string) =>
    setCollapsedYears((prev) => {
      const next = new Set(prev);
      next.has(key) ? next.delete(key) : next.add(key);
      return next;
    });

  const toggleTerm = (key: string) =>
    setCollapsedTerms((prev) => {
      const next = new Set(prev);
      next.has(key) ? next.delete(key) : next.add(key);
      return next;
    });

  const handleDeleteCourse = async (course: Course) => {
    if (!window.confirm(deleteConfirmMessage(course.course_title))) return;
    try {
      await softDeleteCourse(course.id);
      await refetch();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to delete course');
    }
  };

  return (
    <div className="courses-page-container">
      {/* Top Header Row */}
      <div className="courses-page-header">
        <h1 className="courses-page-title">{pageTitle}</h1>
        <button
          type="button"
          className="auth-submit-btn courses-create-btn"
          onClick={() => setCreateModalOpen(true)}
        >
          {newCourseButtonText}
        </button>
      </div>

      {loading && <PageState kind="loading" />}
      {error && <PageState kind="error" message={error} />}

      {!loading && courses.length === 0 && (
        <div className="courses-empty-container">
          <div className="courses-empty-icon-wrap">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="courses-empty-svg">
              <path d="M22 10v6M2 10l10-5 10 5-10 5z" />
              <path d="M6 12v5c0 2 2 3 6 3s6-1 6-3v-5" />
            </svg>
          </div>
          <h2 className="courses-empty-title">{emptyTitle}</h2>
          <p className="courses-empty-desc">{emptySubtitle}</p>
          <button
            type="button"
            className="auth-submit-btn courses-empty-btn"
            onClick={() => setCreateModalOpen(true)}
          >
            {newCourseButtonText}
          </button>
        </div>
      )}

      {/* Course Tree with Folders */}
      <div className="courses-tree-flow">
        {groups.map((year) => {
          const yearOpen = !collapsedYears.has(year.key);
          return (
            <div key={year.key} className="courses-year-section">
              {/* Year Header */}
              <button
                type="button"
                className="courses-year-header-btn"
                onClick={() => toggleYear(year.key)}
              >
                <div className="courses-year-header-left">
                  <span className="courses-folder-icon">📁</span>
                  <span className="courses-year-label">{year.label}</span>
                </div>
                <span className={`courses-caret-icon ${yearOpen ? 'is-open' : ''}`}>›</span>
              </button>

              {yearOpen && (
                <div className="courses-year-body">
                  {year.terms.map((term) => {
                    const termKey = `${year.key}:${term.key}`;
                    const termOpen = !collapsedTerms.has(termKey);
                    return (
                      <div key={termKey} className="courses-term-section">
                        {/* Term Header */}
                        <button
                          type="button"
                          className="courses-term-header-btn"
                          onClick={() => toggleTerm(termKey)}
                        >
                          <div className="courses-term-header-left">
                            <span className="courses-subfolder-icon">📂</span>
                            <span className="courses-term-label">{term.label}</span>
                          </div>
                          <span className={`courses-caret-icon ${termOpen ? 'is-open' : ''}`}>›</span>
                        </button>

                        {/* Course List in Term */}
                        {termOpen && (
                          <div className="courses-card-grid">
                            {term.courses.map((course) => {
                              const color = (course.metadata?.color as string) || '#FFB300';
                              return (
                                <div
                                  key={course.id}
                                  className="course-card-item-wrap"
                                  style={{ ['--course-accent' as string]: color }}
                                >
                                  <Link to={`/courses/${course.id}`} className="course-card-tile">
                                    <div
                                      className="course-tile-icon-box"
                                      style={{
                                        backgroundColor: `${color}1A`,
                                        borderColor: `${color}44`,
                                        color: color,
                                      }}
                                    >
                                      <span className="course-icon-symbol">✦</span>
                                    </div>
                                    <div className="course-tile-info">
                                      <span className="course-tile-title">{course.course_title}</span>
                                      {course.course_code && (
                                        <span className="course-tile-code">{course.course_code}</span>
                                      )}
                                    </div>
                                    <span className="course-tile-chevron">›</span>
                                  </Link>

                                  {/* Action Buttons */}
                                  <div className="course-card-actions">
                                    <button
                                      type="button"
                                      className="course-action-btn"
                                      onClick={() => setEditingCourse(course)}
                                      title={language === 'ja' ? 'コースを編集' : 'Edit course'}
                                    >
                                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="course-btn-svg">
                                        <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                                        <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
                                      </svg>
                                    </button>
                                    <button
                                      type="button"
                                      className="course-action-btn course-action-delete"
                                      onClick={() => handleDeleteCourse(course)}
                                      title={language === 'ja' ? 'コースを削除' : 'Delete course'}
                                    >
                                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="course-btn-svg">
                                        <polyline points="3 6 5 6 21 6" />
                                        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
                                      </svg>
                                    </button>
                                  </div>
                                </div>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Create Modal */}
      {createModalOpen && (
        <CourseEditModal
          onClose={() => setCreateModalOpen(false)}
          onCourseSaved={async () => {
            await refetch();
            setCreateModalOpen(false);
          }}
        />
      )}

      {/* Edit Modal */}
      {editingCourse && (
        <CourseEditModal
          existingCourse={editingCourse}
          onClose={() => setEditingCourse(null)}
          onCourseSaved={async () => {
            await refetch();
            setEditingCourse(null);
          }}
        />
      )}
    </div>
  );
};
