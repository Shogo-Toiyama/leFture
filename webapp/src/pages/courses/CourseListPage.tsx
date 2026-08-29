import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { useCourses } from '../../hooks/useCourses';
import { CourseFormModal } from './CourseFormModal';

export const CourseListPage: React.FC = () => {
  const { courses, loading, error, refetch } = useCourses();
  const [formOpen, setFormOpen] = useState(false);

  return (
    <div>
      <div className="page-header">
        <h1>Courses</h1>
        <button type="button" onClick={() => setFormOpen(true)}>
          New course
        </button>
      </div>

      {loading && <p>Loading…</p>}
      {error && <p className="auth-error">{error}</p>}
      {!loading && courses.length === 0 && <p>No courses yet. Create one to get started.</p>}

      <ul className="course-list">
        {courses.map((course) => (
          <li key={course.id}>
            <Link to={`/courses/${course.id}`} className="course-list-item">
              <span
                className="course-color-dot"
                style={{ backgroundColor: (course.metadata?.color as string) ?? '#ffb300' }}
              />
              <span>{course.course_title}</span>
            </Link>
          </li>
        ))}
      </ul>

      <CourseFormModal open={formOpen} onClose={() => setFormOpen(false)} onSaved={refetch} />
    </div>
  );
};
