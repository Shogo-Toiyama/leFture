import React from 'react';
import { LectureTileSkeleton } from '../LectureTileSkeleton';

export const CourseLecturesSectionSkeleton: React.FC = () => {
  return (
    <div className="course-lectures-list" aria-busy="true" aria-live="polite">
      {[0, 1, 2].map((i) => (
        <LectureTileSkeleton key={i} />
      ))}
    </div>
  );
};
