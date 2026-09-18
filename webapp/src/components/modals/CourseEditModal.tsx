import React, { useState, useEffect, useRef, useMemo } from 'react';
import {
  ChevronUp,
  ChevronDown,
  Calendar,
  Bookmark,
  Tag,
  User,
  GraduationCap,
  Layers,
  FileText,
  Pipette,
  Check,
  Pencil,
  AlertCircle,
  Loader2,
} from 'lucide-react';
import type { Course } from '../../types/course';
import { createCourse, updateCourse } from '../../lib/courses';
import { useCourseAttributes } from '../../hooks/useCourseAttributes';
import { ModalDialog } from './ModalDialog';
import { CustomColorPickerDialog } from './CustomColorPickerDialog';
import { useLanguage } from '../../i18n/LanguageContext';
import {
  CourseIconGlyph,
  COURSE_PRESET_COLORS,
  COURSE_ICON_CATEGORIES,
  DEFAULT_COURSE_COLOR,
  DEFAULT_COURSE_ICON,
} from '../../lib/courseIcons';

export interface CourseEditModalProps {
  existingCourse?: Course | null;
  onClose: () => void;
  onCourseSaved?: (course: Course) => void;
  preselectedYearName?: string;
  preselectedTermName?: string;
}

export const CourseEditModal: React.FC<CourseEditModalProps> = ({
  existingCourse,
  onClose,
  onCourseSaved,
  preselectedYearName,
  preselectedTermName,
}) => {
  const { language } = useLanguage();
  const isEditing = Boolean(existingCourse);

  // 属性リストを取得 (サジェスト用)
  const existingYears = useCourseAttributes('year');
  const existingTerms = useCourseAttributes('term');
  const existingProfessors = useCourseAttributes('professor');
  const existingSchools = useCourseAttributes('school');
  const existingSubjects = useCourseAttributes('subject');

  // 既存コースの属性名解決用マップ
  const yearNameMap = useMemo(() => new Map(existingYears.map((a) => [a.id, a.attribute_name])), [existingYears]);
  const termNameMap = useMemo(() => new Map(existingTerms.map((a) => [a.id, a.attribute_name])), [existingTerms]);
  const profNameMap = useMemo(() => new Map(existingProfessors.map((a) => [a.id, a.attribute_name])), [existingProfessors]);
  const schoolNameMap = useMemo(() => new Map(existingSchools.map((a) => [a.id, a.attribute_name])), [existingSchools]);
  const subjectNameMap = useMemo(() => new Map(existingSubjects.map((a) => [a.id, a.attribute_name])), [existingSubjects]);

  // フォーム状態
  const [title, setTitle] = useState(existingCourse?.course_title ?? '');
  const [color, setColor] = useState(
    (existingCourse?.metadata?.color as string) || DEFAULT_COURSE_COLOR
  );
  const [icon, setIcon] = useState(
    (existingCourse?.metadata?.icon as string) || DEFAULT_COURSE_ICON
  );
  const [selectedCategoryIdx, setSelectedCategoryIdx] = useState(0);

  const [year, setYear] = useState(
    (existingCourse?.year_id ? yearNameMap.get(existingCourse.year_id) : undefined) ??
    preselectedYearName ??
    ''
  );
  const [term, setTerm] = useState(
    (existingCourse?.term_id ? termNameMap.get(existingCourse.term_id) : undefined) ??
    preselectedTermName ??
    ''
  );
  const [code, setCode] = useState(existingCourse?.course_code ?? '');
  const [professor, setProfessor] = useState(
    (existingCourse?.professor ? profNameMap.get(existingCourse.professor) : undefined) ?? ''
  );
  const [school, setSchool] = useState(
    (existingCourse?.school_id ? schoolNameMap.get(existingCourse.school_id) : undefined) ?? ''
  );
  const [subject, setSubject] = useState(
    (existingCourse?.subject_id ? subjectNameMap.get(existingCourse.subject_id) : undefined) ?? ''
  );
  const [summary, setSummary] = useState(existingCourse?.summary ?? '');

  // 属性が後から非同期ロードされた場合の同期 (既存コース編集時)
  useEffect(() => {
    if (existingCourse?.year_id && yearNameMap.has(existingCourse.year_id)) {
      setYear((prev) => prev || yearNameMap.get(existingCourse.year_id!) || '');
    }
  }, [existingCourse?.year_id, yearNameMap]);

  useEffect(() => {
    if (existingCourse?.term_id && termNameMap.has(existingCourse.term_id)) {
      setTerm((prev) => prev || termNameMap.get(existingCourse.term_id!) || '');
    }
  }, [existingCourse?.term_id, termNameMap]);

  useEffect(() => {
    if (existingCourse?.professor && profNameMap.has(existingCourse.professor)) {
      setProfessor((prev) => prev || profNameMap.get(existingCourse.professor!) || '');
    }
  }, [existingCourse?.professor, profNameMap]);

  useEffect(() => {
    if (existingCourse?.school_id && schoolNameMap.has(existingCourse.school_id)) {
      setSchool((prev) => prev || schoolNameMap.get(existingCourse.school_id!) || '');
    }
  }, [existingCourse?.school_id, schoolNameMap]);

  useEffect(() => {
    if (existingCourse?.subject_id && subjectNameMap.has(existingCourse.subject_id)) {
      setSubject((prev) => prev || subjectNameMap.get(existingCourse.subject_id!) || '');
    }
  }, [existingCourse?.subject_id, subjectNameMap]);

  // More Info 初期状態 (既存データがあれば最初から展開)
  const [showMore, setShowMore] = useState(
    Boolean(
      existingCourse?.course_code ||
      existingCourse?.professor ||
      existingCourse?.school_id ||
      existingCourse?.subject_id ||
      existingCourse?.summary
    )
  );

  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [showCustomColorPicker, setShowCustomColorPicker] = useState(false);

  const titleInputRef = useRef<HTMLInputElement>(null);

  // 初期アイコンの所属カテゴリを選択状態にする
  useEffect(() => {
    const idx = COURSE_ICON_CATEGORIES.findIndex((c) => c.iconNames.includes(icon));
    if (idx >= 0) {
      setSelectedCategoryIdx(idx);
    }
  }, [icon]);

  // 多言語ラベル
  const isJa = language === 'ja';
  const modalTitle = isEditing
    ? (isJa ? 'コースを編集' : 'Edit Course')
    : (isJa ? 'コースを作成' : 'Create Course');
  const previewLabel = isJa ? 'デザインプレビュー' : 'Design Preview';
  const titlePlaceholder = isJa ? 'コース名を入力…' : 'Enter course title…';
  const colorLabel = isJa ? 'コースカラー' : 'Course Color';
  const iconLabel = isJa ? 'コースアイコン' : 'Course Icon';
  const customColorTitle = isJa ? 'カスタムカラーを選択' : 'Select custom color';
  const yearLabel = isJa ? '開講年度' : 'Year';
  const yearPlaceholder = isJa ? '例: 2026' : 'e.g. 2026';
  const termLabel = isJa ? '開講学期' : 'Term';
  const termPlaceholder = isJa ? '例: Fall / 秋学期' : 'e.g. Fall / Spring';
  const moreInfoLabel = isJa ? '詳細情報（任意）' : 'More Information (Optional)';
  const codeLabel = isJa ? 'コースコード' : 'Course Code';
  const codePlaceholder = isJa ? '例: CS101' : 'e.g. CS101';
  const profLabel = isJa ? '担当教員' : 'Professor';
  const profPlaceholder = isJa ? '例: 山田 太郎' : 'e.g. Prof. Smith';
  const schoolLabel = isJa ? '学部・研究科・機関' : 'School / Faculty';
  const schoolPlaceholder = isJa ? '例: 理工学部' : 'e.g. School of Engineering';
  const subjectLabel = isJa ? '科目区分・分野' : 'Subject / Field';
  const subjectPlaceholder = isJa ? '例: 情報科学' : 'e.g. Computer Science';
  const summaryLabel = isJa ? '概要・シラバス' : 'Summary / Syllabus';
  const summaryPlaceholder = isJa ? '講義の目的や到達目標、シラバスなど' : 'Course overview, objectives, syllabus, etc.';
  const saveLabel = isEditing
    ? (isJa ? '保存する' : 'Save')
    : (isJa ? '作成する' : 'Create');
  const cancelLabel = isJa ? 'キャンセル' : 'Cancel';

  const isCustomColor = !COURSE_PRESET_COLORS.includes(color);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) {
      setErrorMsg(isJa ? 'コース名を入力してください' : 'Please enter a course title');
      titleInputRef.current?.focus();
      return;
    }

    setSaving(true);
    setErrorMsg(null);

    try {
      const input = {
        courseTitle: title.trim(),
        courseCode: code.trim(),
        summary: summary.trim(),
        year: year.trim(),
        term: term.trim(),
        professor: professor.trim(),
        school: school.trim(),
        subject: subject.trim(),
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

  const activeCategory = COURSE_ICON_CATEGORIES[selectedCategoryIdx] || COURSE_ICON_CATEGORIES[0];

  return (
    <ModalDialog title={modalTitle} onClose={onClose} maxWidth={580}>
      <form onSubmit={handleSave} className="course-edit-form">
        {errorMsg && (
          <div className="course-edit-error-banner" role="alert">
            <AlertCircle size={18} className="course-edit-error-icon" />
            <span>{errorMsg}</span>
          </div>
        )}

        {/* 1. Live Preview Card (Flutterライクなリアルタイムプレビュー) */}
        <div className="course-edit-field">
          <div className="course-edit-field-header">
            <span className="course-edit-field-label">{previewLabel}</span>
          </div>
          <div
            className="course-preview-card"
            style={{
              backgroundColor: `${color}18`,
              borderColor: `${color}4d`,
              boxShadow: `0 8px 24px -4px ${color}26`,
            }}
            onClick={() => titleInputRef.current?.focus()}
          >
            <div
              className="course-preview-badge"
              style={{
                backgroundColor: `${color}28`,
                borderColor: `${color}66`,
              }}
            >
              <CourseIconGlyph icon={icon} size={28} color={color} />
            </div>

            <div className="course-preview-input-wrap">
              <input
                ref={titleInputRef}
                type="text"
                className="course-preview-title-input"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder={titlePlaceholder}
                autoFocus
                required
              />
              <span className="course-preview-hint">
                <Pencil size={14} />
              </span>
            </div>
          </div>
        </div>

        <div className="course-edit-divider" />

        {/* 2. Color Selection (プリセット + カスタムカラーピッカー) */}
        <div className="course-edit-field">
          <div className="course-edit-field-header">
            <span className="course-edit-field-label">{colorLabel}</span>
            <span className="course-edit-color-hex">{color.toUpperCase()}</span>
          </div>
          <div className="course-color-picker-row">
            {COURSE_PRESET_COLORS.map((c) => {
              const isSelected = color.toLowerCase() === c.toLowerCase();
              return (
                <button
                  key={c}
                  type="button"
                  className={`course-color-dot ${isSelected ? 'is-selected' : ''}`}
                  style={{ backgroundColor: c }}
                  onClick={() => setColor(c)}
                  aria-label={`Color ${c}`}
                >
                  {isSelected && (
                    <Check size={18} color="#ffffff" strokeWidth={3} className="course-color-check" />
                  )}
                </button>
              );
            })}

            {/* プリセット外のカスタムカラーが選ばれている場合に表示 */}
            {isCustomColor && (
              <button
                type="button"
                className="course-color-dot is-selected is-custom"
                style={{ backgroundColor: color }}
                aria-label={`Custom color ${color}`}
              >
                <Check size={18} color="#ffffff" strokeWidth={3} className="course-color-check" />
              </button>
            )}

            {/* レインボーグラデーションのカスタムカラーボタン (Flutter同等ダイアログを開く) */}
            <button
              type="button"
              className="course-custom-color-btn"
              onClick={() => setShowCustomColorPicker(true)}
              title={customColorTitle}
              aria-label={customColorTitle}
            >
              <Pipette size={16} />
            </button>
          </div>
        </div>

        <div className="course-edit-divider" />

        {/* 3. Icon Selection (9カテゴリタブ + 70種以上のアイコングリッド) */}
        <div className="course-edit-field">
          <div className="course-edit-field-header">
            <span className="course-edit-field-label">{iconLabel}</span>
            <span className="course-edit-icon-name">{icon}</span>
          </div>

          {/* カテゴリピル (絵文字は除外しアイコンのみ表示) */}
          <div className="course-category-tabs-scroll" role="tablist">
            {COURSE_ICON_CATEGORIES.map((cat, idx) => {
              const isCatActive = selectedCategoryIdx === idx;
              const firstIcon = cat.iconNames[0];
              return (
                <button
                  key={cat.titleEn}
                  type="button"
                  role="tab"
                  aria-selected={isCatActive}
                  className={`course-category-tab ${isCatActive ? 'is-active' : ''}`}
                  style={
                    isCatActive
                      ? {
                          backgroundColor: color,
                          borderColor: color,
                          color: '#111422',
                        }
                      : undefined
                  }
                  onClick={() => setSelectedCategoryIdx(idx)}
                >
                  <CourseIconGlyph
                    icon={firstIcon}
                    size={16}
                    className="course-category-icon-glyph"
                  />
                  <span>{isJa ? cat.titleJa : cat.titleEn}</span>
                </button>
              );
            })}
          </div>

          {/* アイコングリッド */}
          <div className="course-icon-grid-box">
            <div className="course-icon-grid">
              {activeCategory.iconNames.map((ic) => {
                const isSelected = icon === ic;
                return (
                  <button
                    key={ic}
                    type="button"
                    title={ic}
                    className={`course-icon-tile ${isSelected ? 'is-selected' : ''}`}
                    style={
                      isSelected
                        ? {
                            backgroundColor: `${color}28`,
                            borderColor: color,
                            color: color,
                            boxShadow: `0 0 12px ${color}40`,
                          }
                        : undefined
                    }
                    onClick={() => setIcon(ic)}
                    aria-label={ic}
                  >
                    <CourseIconGlyph icon={ic} size={24} />
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        <div className="course-edit-divider" />

        {/* 4. Year & Term (2カラム) */}
        <div className="course-edit-two-col">
          <div className="course-edit-field">
            <label className="course-edit-field-label">
              <Calendar size={13} className="course-edit-label-icon" />
              {yearLabel}
            </label>
            <input
              type="text"
              list="course-year-datalist"
              className="course-edit-input"
              value={year}
              onChange={(e) => setYear(e.target.value)}
              placeholder={yearPlaceholder}
            />
            <datalist id="course-year-datalist">
              {existingYears.map((a) => (
                <option key={a.id} value={a.attribute_name} />
              ))}
            </datalist>
          </div>

          <div className="course-edit-field">
            <label className="course-edit-field-label">
              <Bookmark size={13} className="course-edit-label-icon" />
              {termLabel}
            </label>
            <input
              type="text"
              list="course-term-datalist"
              className="course-edit-input"
              value={term}
              onChange={(e) => setTerm(e.target.value)}
              placeholder={termPlaceholder}
            />
            <datalist id="course-term-datalist">
              {existingTerms.map((a) => (
                <option key={a.id} value={a.attribute_name} />
              ))}
            </datalist>
          </div>
        </div>

        <div className="course-edit-divider" />

        {/* 5. More Information Accordion (任意・詳細情報) */}
        <div className={`course-more-accordion ${showMore ? 'is-expanded' : ''}`}>
          <button
            type="button"
            className="course-more-toggle"
            onClick={() => setShowMore((prev) => !prev)}
            aria-expanded={showMore}
          >
            <div className="course-more-toggle-title">
              <Layers size={15} style={{ color: showMore ? color : 'var(--comet)' }} />
              <span style={{ color: showMore ? 'var(--starlight)' : 'var(--comet)' }}>
                {moreInfoLabel}
              </span>
            </div>
            <span className="course-more-chevron">
              {showMore ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
            </span>
          </button>

          {showMore && (
            <div className="course-more-body">
              {/* コースコード */}
              <div className="course-edit-field">
                <label className="course-edit-field-label">
                  <Tag size={13} className="course-edit-label-icon" />
                  {codeLabel}
                </label>
                <input
                  type="text"
                  className="course-edit-input"
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  placeholder={codePlaceholder}
                />
              </div>

              {/* 担当教員 & 学部・所属 (2カラム) */}
              <div className="course-edit-two-col">
                <div className="course-edit-field">
                  <label className="course-edit-field-label">
                    <User size={13} className="course-edit-label-icon" />
                    {profLabel}
                  </label>
                  <input
                    type="text"
                    list="course-prof-datalist"
                    className="course-edit-input"
                    value={professor}
                    onChange={(e) => setProfessor(e.target.value)}
                    placeholder={profPlaceholder}
                  />
                  <datalist id="course-prof-datalist">
                    {existingProfessors.map((a) => (
                      <option key={a.id} value={a.attribute_name} />
                    ))}
                  </datalist>
                </div>

                <div className="course-edit-field">
                  <label className="course-edit-field-label">
                    <GraduationCap size={13} className="course-edit-label-icon" />
                    {schoolLabel}
                  </label>
                  <input
                    type="text"
                    list="course-school-datalist"
                    className="course-edit-input"
                    value={school}
                    onChange={(e) => setSchool(e.target.value)}
                    placeholder={schoolPlaceholder}
                  />
                  <datalist id="course-school-datalist">
                    {existingSchools.map((a) => (
                      <option key={a.id} value={a.attribute_name} />
                    ))}
                  </datalist>
                </div>
              </div>

              {/* 科目区分 */}
              <div className="course-edit-field">
                <label className="course-edit-field-label">
                  <Layers size={13} className="course-edit-label-icon" />
                  {subjectLabel}
                </label>
                <input
                  type="text"
                  list="course-subject-datalist"
                  className="course-edit-input"
                  value={subject}
                  onChange={(e) => setSubject(e.target.value)}
                  placeholder={subjectPlaceholder}
                />
                <datalist id="course-subject-datalist">
                  {existingSubjects.map((a) => (
                    <option key={a.id} value={a.attribute_name} />
                  ))}
                </datalist>
              </div>

              {/* 概要・シラバス */}
              <div className="course-edit-field">
                <label className="course-edit-field-label">
                  <FileText size={13} className="course-edit-label-icon" />
                  {summaryLabel}
                </label>
                <textarea
                  className="course-edit-textarea"
                  value={summary}
                  onChange={(e) => setSummary(e.target.value)}
                  placeholder={summaryPlaceholder}
                  rows={3}
                />
              </div>
            </div>
          )}
        </div>

        {/* フッターアクションボタン */}
        <div className="course-edit-actions">
          <button
            type="button"
            className="course-btn-cancel"
            onClick={onClose}
            disabled={saving}
          >
            {cancelLabel}
          </button>
          <button
            type="submit"
            className="course-btn-submit"
            style={{
              backgroundColor: color,
              borderColor: color,
              color: '#111422',
              boxShadow: `0 4px 14px 0 ${color}40`,
            }}
            disabled={saving || !title.trim()}
          >
            {saving ? (
              <>
                <Loader2 size={16} className="course-btn-spinner" />
                <span>{isJa ? '保存中…' : 'Saving…'}</span>
              </>
            ) : (
              saveLabel
            )}
          </button>
        </div>
      </form>

      {/* Flutter互換カスタムカラーダイアログ */}
      {showCustomColorPicker && (
        <CustomColorPickerDialog
          initialColor={color}
          onClose={() => setShowCustomColorPicker(false)}
          onSelectColor={(newColor) => {
            setColor(newColor);
            setShowCustomColorPicker(false);
          }}
        />
      )}
    </ModalDialog>
  );
};
