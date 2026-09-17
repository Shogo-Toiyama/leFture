import React, { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Folder, FolderOpen, ChevronRight, Pencil, Trash2, GraduationCap } from 'lucide-react';
import { useCourses } from '../../hooks/useCourses';
import { useCourseAttributes } from '../../hooks/useCourseAttributes';
import { useLanguage } from '../../i18n/LanguageContext';
import { softDeleteCourse } from '../../lib/courses';
import { CourseEditModal } from '../../components/modals/CourseEditModal';
import { PageState } from '../../components/PageState';
import { CourseIconGlyph } from '../../lib/courseIcons';
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
            <GraduationCap className="courses-empty-svg" />
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
                  {yearOpen ? (
                    <FolderOpen size={17} className="courses-folder-icon" />
                  ) : (
                    <Folder size={17} className="courses-folder-icon" />
                  )}
                  <span className="courses-year-label">{year.label}</span>
                </div>
                <ChevronRight size={16} className={`courses-caret-icon ${yearOpen ? 'is-open' : ''}`} />
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
                            {termOpen ? (
                              <FolderOpen size={16} className="courses-subfolder-icon" />
                            ) : (
                              <Folder size={16} className="courses-subfolder-icon" />
                            )}
                            <span className="courses-term-label">{term.label}</span>
                          </div>
                          <ChevronRight size={16} className={`courses-caret-icon ${termOpen ? 'is-open' : ''}`} />
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
                                      <CourseIconGlyph
                                        icon={course.metadata?.icon as string}
                                        size={20}
                                        className="course-icon-symbol"
                                      />
                                    </div>
                                    <div className="course-tile-info">
                                      <span className="course-tile-title">{course.course_title}</span>
                                      {course.course_code && (
                                        <span className="course-tile-code">{course.course_code}</span>
                                      )}
                                    </div>
                                    <ChevronRight size={18} className="course-tile-chevron" />
                                  </Link>

                                  {/* Action Buttons */}
                                  <div className="course-card-actions">
                                    <button
                                      type="button"
                                      className="course-action-btn"
                                      onClick={() => setEditingCourse(course)}
                                      title={language === 'ja' ? 'コースを編集' : 'Edit course'}
                                    >
                                      <Pencil size={16} className="course-btn-svg" />
                                    </button>
                                    <button
                                      type="button"
                                      className="course-action-btn course-action-delete"
                                      onClick={() => handleDeleteCourse(course)}
                                      title={language === 'ja' ? 'コースを削除' : 'Delete course'}
                                    >
                                      <Trash2 size={16} className="course-btn-svg" />
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
