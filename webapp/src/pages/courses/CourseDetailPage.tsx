import React, { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getCourse, softDeleteCourse } from '../../lib/courses';
import { useLectures } from '../../hooks/useLectures';
import { lectureDisplayTitle } from '../../types/lecture';
import type { Course } from '../../types/course';
import { CourseFormModal } from './CourseFormModal';

export const CourseDetailPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();
  const [course, setCourse] = useState<Course | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editOpen, setEditOpen] = useState(false);
  const { lectures, loading: lecturesLoading, error: lecturesError } = useLectures(courseId);

  useEffect(() => {
    if (!courseId) return;
    getCourse(courseId)
      .then(setCourse)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load course'));
  }, [courseId]);

  const handleDelete = async () => {
    if (!courseId) return;
    if (!window.confirm('Delete this course? Lectures under it will remain but the course will be hidden.')) return;
    await softDeleteCourse(courseId);
    navigate('/courses');
  };

  if (error) return <p className="auth-error">{error}</p>;
  if (!course) return <p>Loading…</p>;

  return (
    <div>
      <div className="page-header">
        <div>
          <Link to="/courses">← Courses</Link>
          <h1>{course.course_title}</h1>
        </div>
        <div className="page-header-actions">
          <button type="button" onClick={() => setEditOpen(true)}>
            Edit
          </button>
          <button type="button" className="danger" onClick={handleDelete}>
            Delete
          </button>
        </div>
      </div>

      <div className="page-header">
        <h2>Lectures</h2>
        <Link to={`/courses/${courseId}/upload`}>
          <button type="button">Upload recording</button>
        </Link>
      </div>

      {lecturesLoading && <p>Loading…</p>}
      {lecturesError && <p className="auth-error">{lecturesError}</p>}
      {!lecturesLoading && lectures.length === 0 && <p>No lectures yet. Upload a recording to get started.</p>}

      <ul className="lecture-list">
        {lectures.map((lecture) => (
          <li key={lecture.id}>
            <Link to={`/lectures/${lecture.id}`} className="lecture-list-item">
              <span>{lectureDisplayTitle(lecture)}</span>
              <span className="lecture-list-date">
                {new Date(lecture.lecture_datetime).toLocaleDateString()}
              </span>
            </Link>
          </li>
        ))}
      </ul>

      <CourseFormModal
        open={editOpen}
        onClose={() => setEditOpen(false)}
        existingCourse={course}
        onSaved={setCourse}
      />
    </div>
  );
};
