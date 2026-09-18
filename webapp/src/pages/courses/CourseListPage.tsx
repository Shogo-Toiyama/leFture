import React, { useMemo, useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Folder,
  FolderOpen,
  ChevronDown,
  ChevronRight,
  Pencil,
  Trash2,
  GraduationCap,
  MoreVertical,
  Plus,
} from 'lucide-react';
import { useCourses } from '../../hooks/useCourses';
import { useCourseAttributes } from '../../hooks/useCourseAttributes';
import { useLanguage } from '../../i18n/LanguageContext';
import { softDeleteCourse } from '../../lib/courses';
import { CourseEditModal } from '../../components/modals/CourseEditModal';
import { PageState } from '../../components/PageState';
import { CourseListSkeleton } from '../../components/courses/CourseListSkeleton';
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
  // 英語表記を Flutter 版と一致（"No Year" / "No Term"）
  const noYearLabel = language === 'ja' ? '年度未設定' : 'No Year';
  const noTermLabel = language === 'ja' ? '学期未設定' : 'No Term';

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
  const navigate = useNavigate();
  const { courses, loading, error, refetch } = useCourses();
  const years = useCourseAttributes('year');
  const terms = useCourseAttributes('term');

  const [createModalOpen, setCreateModalOpen] = useState(false);
  const [editingCourse, setEditingCourse] = useState<Course | null>(null);
  const [collapsedYears, setCollapsedYears] = useState<Set<string>>(new Set());
  const [collapsedTerms, setCollapsedTerms] = useState<Set<string>>(new Set());
  const [activeMenuCourseId, setActiveMenuCourseId] = useState<string | null>(null);

  const yearNames = useMemo(() => new Map(years.map((a) => [a.id, a.attribute_name])), [years]);
  const termNames = useMemo(() => new Map(terms.map((a) => [a.id, a.attribute_name])), [terms]);
  const groups = useMemo(() => groupCourses(courses, yearNames, termNames, language), [courses, yearNames, termNames, language]);

  const pageTitle = language === 'ja' ? 'コース一覧' : 'Courses';
  const newCourseLabel = language === 'ja' ? '新規コース' : 'New Course';
  const newCourseButtonText = language === 'ja' ? '+ 新規コース' : '+ New Course';
  const emptyTitle = language === 'ja' ? 'コースがまだありません' : 'No courses yet';
  const emptySubtitle = language === 'ja'
    ? 'コースを作成して、最初の講義録音をアップロードしましょう。'
    : 'Create a course, then upload your first lecture recording.';
  const deleteConfirmMessage = (title: string) =>
    language === 'ja'
      ? `コース「${title}」を削除しますか？講義は保持されますがコースは非表示になります。`
      : `Delete course "${title}"? Its lectures stay in your account but the course will be hidden.`;

  // ドロップダウンメニュー外クリック・Escキーでクローズ
  useEffect(() => {
    if (!activeMenuCourseId) return;
    const handleOutsideClick = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (!target.closest('.course-card-menu-wrap')) {
        setActiveMenuCourseId(null);
      }
    };
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setActiveMenuCourseId(null);
    };
    window.addEventListener('click', handleOutsideClick);
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('click', handleOutsideClick);
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [activeMenuCourseId]);

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
      {/* Top Header Row (タイトルのみ、ボタンは右下FABへ移行) */}
      <div className="courses-page-header">
        <h1 className="courses-page-title">{pageTitle}</h1>
      </div>

      {loading && <CourseListSkeleton />}
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
              {/* Year Header (フォルダ + ラベル + すぐ右にシェブロン) */}
              <div className="courses-year-header-row">
                <button
                  type="button"
                  className="courses-folder-toggle-btn courses-year-folder-btn"
                  onClick={() => toggleYear(year.key)}
                  aria-expanded={yearOpen}
                >
                  {yearOpen ? (
                    <FolderOpen size={18} className="courses-year-folder-icon" />
                  ) : (
                    <Folder size={18} className="courses-year-folder-icon" />
                  )}
                  <span className="courses-year-label">{year.label}</span>
                  {yearOpen ? (
                    <ChevronDown size={18} className="courses-folder-chevron is-open" />
                  ) : (
                    <ChevronRight size={18} className="courses-folder-chevron" />
                  )}
                </button>
              </div>

              {yearOpen && (
                <div className="courses-year-body">
                  {year.terms.map((term) => {
                    const termKey = `${year.key}:${term.key}`;
                    const termOpen = !collapsedTerms.has(termKey);
                    return (
                      <div key={termKey} className="courses-term-section">
                        {/* Term Header (サブフォルダ + ラベル + すぐ右にシェブロン) */}
                        <div className="courses-term-header-row">
                          <button
                            type="button"
                            className="courses-folder-toggle-btn courses-term-folder-btn"
                            onClick={() => toggleTerm(termKey)}
                            aria-expanded={termOpen}
                          >
                            {termOpen ? (
                              <FolderOpen size={16} className="courses-term-folder-icon" />
                            ) : (
                              <Folder size={16} className="courses-term-folder-icon" />
                            )}
                            <span className="courses-term-label">{term.label}</span>
                            {termOpen ? (
                              <ChevronDown size={16} className="courses-folder-chevron is-open" />
                            ) : (
                              <ChevronRight size={16} className="courses-folder-chevron" />
                            )}
                          </button>
                        </div>

                        {/* Course List in Term (4:3 スタイリッシュカードグリッド) */}
                        {termOpen && (
                          <div className="courses-card-grid-4x3">
                            {term.courses.map((course) => {
                              const color = (course.metadata?.color as string) || '#FFB300';
                              const iconName = (course.metadata?.icon as string) || 'school';
                              const isMenuOpen = activeMenuCourseId === course.id;

                              return (
                                <div
                                  key={course.id}
                                  className={`course-card-4x3 ${isMenuOpen ? 'is-menu-open' : ''}`}
                                  style={{
                                    ['--course-color' as string]: color,
                                    borderColor: `${color}40`,
                                    background: `linear-gradient(135deg, ${color}26 0%, rgba(20, 24, 42, 0.94) 55%, rgba(13, 16, 28, 0.98) 100%)`,
                                  }}
                                  onClick={() => navigate(`/courses/${course.id}`)}
                                >
                                  {/* 背景グラデーション & 透かし大型アイコン (3倍大: 320px) - 別レイヤーでクリップ */}
                                  <div className="course-card-bg-watermark-wrap" aria-hidden="true">
                                    <div
                                      className="course-card-watermark"
                                      style={{ color }}
                                    >
                                      <CourseIconGlyph icon={iconName} size={320} />
                                    </div>
                                  </div>

                                  {/* アイコンバッジ (スマホ時のみ表示、デスクトップ巨大アイコン時は非表示) */}
                                  <div
                                    className="course-card-badge"
                                    style={{
                                      backgroundColor: `${color}28`,
                                      borderColor: `${color}66`,
                                      color: color,
                                    }}
                                  >
                                    <CourseIconGlyph icon={iconName} size={20} />
                                  </div>

                                  {/* コース情報 (デスクトップ: 右下配置 / スマホ: 中央配置) */}
                                  <div className="course-card-info">
                                    {course.course_code && (
                                      <span
                                        className="course-card-code-pill"
                                        style={{
                                          backgroundColor: `${color}1c`,
                                          borderColor: `${color}4d`,
                                          color: color,
                                        }}
                                      >
                                        {course.course_code}
                                      </span>
                                    )}
                                    <h3 className="course-card-title" title={course.course_title}>
                                      {course.course_title}
                                    </h3>
                                  </div>

                                  {/* 三点リーダー「...」メニュー (右上/スマホ右端) */}
                                  <div
                                    className="course-card-menu-wrap"
                                    onClick={(e) => e.stopPropagation()}
                                  >
                                    <button
                                      type="button"
                                      className={`course-card-menu-btn ${isMenuOpen ? 'is-active' : ''}`}
                                      onClick={(e) => {
                                        e.stopPropagation();
                                        setActiveMenuCourseId(isMenuOpen ? null : course.id);
                                      }}
                                      aria-label="Course options"
                                      aria-expanded={isMenuOpen}
                                    >
                                      <MoreVertical size={18} />
                                    </button>

                                    {isMenuOpen && (
                                      <div className="course-card-dropdown">
                                        <button
                                          type="button"
                                          className="course-dropdown-item"
                                          onClick={() => {
                                            setActiveMenuCourseId(null);
                                            setEditingCourse(course);
                                          }}
                                        >
                                          <Pencil size={15} />
                                          <span>{language === 'ja' ? '編集' : 'Edit'}</span>
                                        </button>
                                        <button
                                          type="button"
                                          className="course-dropdown-item is-delete"
                                          onClick={() => {
                                            setActiveMenuCourseId(null);
                                            handleDeleteCourse(course);
                                          }}
                                        >
                                          <Trash2 size={15} />
                                          <span>{language === 'ja' ? '削除' : 'Delete'}</span>
                                        </button>
                                      </div>
                                    )}
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

      {/* Floating Action Button (Flutter風固定右下: プラスアイコン + 'New Course' / '新規コース') */}
      <button
        type="button"
        className="courses-fab"
        onClick={() => setCreateModalOpen(true)}
        aria-label={newCourseLabel}
      >
        <Plus size={19} strokeWidth={2.6} />
        <span>{newCourseLabel}</span>
      </button>

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
