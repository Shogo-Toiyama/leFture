import React, { useEffect, useState } from 'react';
import { Modal } from '../../components/Modal';
import { createCourse, updateCourse } from '../../lib/courses';
import { useCourseAttributes } from '../../hooks/useCourseAttributes';
import type { Course } from '../../types/course';

interface CourseFormModalProps {
  open: boolean;
  onClose: () => void;
  onSaved: (course: Course) => void;
  existingCourse?: Course | null;
}

const DEFAULT_COLOR = '#ffb300';

export const CourseFormModal: React.FC<CourseFormModalProps> = ({
  open,
  onClose,
  onSaved,
  existingCourse,
}) => {
  const years = useCourseAttributes('year');
  const terms = useCourseAttributes('term');
  const professors = useCourseAttributes('professor');
  const schools = useCourseAttributes('school');
  const subjects = useCourseAttributes('subject');

  const [courseTitle, setCourseTitle] = useState('');
  const [courseCode, setCourseCode] = useState('');
  const [summary, setSummary] = useState('');
  const [year, setYear] = useState('');
  const [term, setTerm] = useState('');
  const [professor, setProfessor] = useState('');
  const [school, setSchool] = useState('');
  const [subject, setSubject] = useState('');
  const [color, setColor] = useState(DEFAULT_COLOR);
  const [showMoreInfo, setShowMoreInfo] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setCourseTitle(existingCourse?.course_title ?? '');
    setCourseCode(existingCourse?.course_code ?? '');
    setSummary(existingCourse?.summary ?? '');
    setYear(years.find((a) => a.id === existingCourse?.year_id)?.attribute_name ?? '');
    setTerm(terms.find((a) => a.id === existingCourse?.term_id)?.attribute_name ?? '');
    setProfessor(professors.find((a) => a.id === existingCourse?.professor)?.attribute_name ?? '');
    setSchool(schools.find((a) => a.id === existingCourse?.school_id)?.attribute_name ?? '');
    setSubject(subjects.find((a) => a.id === existingCourse?.subject_id)?.attribute_name ?? '');
    setColor((existingCourse?.metadata?.color as string) ?? DEFAULT_COLOR);
    setShowMoreInfo(
      Boolean(existingCourse?.course_code || existingCourse?.professor || existingCourse?.school_id || existingCourse?.subject_id || existingCourse?.summary)
    );
    setError(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, existingCourse]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!courseTitle.trim()) {
      setError('Course title is required.');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const input = {
        courseTitle,
        courseCode,
        summary,
        year,
        term,
        professor,
        school,
        subject,
        metadata: { ...existingCourse?.metadata, color, icon: existingCourse?.metadata?.icon ?? 'school' },
      };
      const saved = existingCourse
        ? await updateCourse(existingCourse.id, input)
        : await createCourse(input);
      onSaved(saved);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save course');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Modal open={open} onClose={onClose} title={existingCourse ? 'Edit course' : 'New course'}>
      <form className="course-form" onSubmit={handleSubmit}>
        <label>
          Title
          <input value={courseTitle} onChange={(e) => setCourseTitle(e.target.value)} required autoFocus />
        </label>
        <div className="course-form-row">
          <label>
            Year
            <input value={year} onChange={(e) => setYear(e.target.value)} list="course-years" />
            <datalist id="course-years">
              {years.map((a) => (
                <option key={a.id} value={a.attribute_name} />
              ))}
            </datalist>
          </label>
          <label>
            Term
            <input value={term} onChange={(e) => setTerm(e.target.value)} list="course-terms" />
            <datalist id="course-terms">
              {terms.map((a) => (
                <option key={a.id} value={a.attribute_name} />
              ))}
            </datalist>
          </label>
          <label>
            Color
            <input type="color" value={color} onChange={(e) => setColor(e.target.value)} />
          </label>
        </div>

        <button type="button" className="link-button" onClick={() => setShowMoreInfo((v) => !v)}>
          {showMoreInfo ? 'Hide more info' : 'More info'}
        </button>

        {showMoreInfo && (
          <>
            <label>
              Course code
              <input value={courseCode} onChange={(e) => setCourseCode(e.target.value)} />
            </label>
            <div className="course-form-row">
              <label>
                Professor
                <input value={professor} onChange={(e) => setProfessor(e.target.value)} list="course-professors" />
                <datalist id="course-professors">
                  {professors.map((a) => (
                    <option key={a.id} value={a.attribute_name} />
                  ))}
                </datalist>
              </label>
              <label>
                School
                <input value={school} onChange={(e) => setSchool(e.target.value)} list="course-schools" />
                <datalist id="course-schools">
                  {schools.map((a) => (
                    <option key={a.id} value={a.attribute_name} />
                  ))}
                </datalist>
              </label>
              <label>
                Subject
                <input value={subject} onChange={(e) => setSubject(e.target.value)} list="course-subjects" />
                <datalist id="course-subjects">
                  {subjects.map((a) => (
                    <option key={a.id} value={a.attribute_name} />
                  ))}
                </datalist>
              </label>
            </div>
            <label>
              Summary
              <textarea value={summary} onChange={(e) => setSummary(e.target.value)} rows={3} />
            </label>
          </>
        )}

        {error && <p className="auth-error">{error}</p>}
        <button type="submit" disabled={submitting}>
          {submitting ? 'Saving…' : 'Save'}
        </button>
      </form>
    </Modal>
  );
};
