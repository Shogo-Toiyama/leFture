import { useEffect, useState } from 'react';
import { listAttributes } from '../lib/courses';
import type { CourseAttribute, CourseAttributeType } from '../types/course';

/** コース作成フォームのautocomplete用。既存のyear/term/professor/school/subjectを候補表示する。 */
export function useCourseAttributes(attributeType: CourseAttributeType) {
  const [attributes, setAttributes] = useState<CourseAttribute[]>([]);

  useEffect(() => {
    let cancelled = false;
    listAttributes(attributeType).then((result) => {
      if (!cancelled) setAttributes(result);
    });
    return () => {
      cancelled = true;
    };
  }, [attributeType]);

  return attributes;
}
