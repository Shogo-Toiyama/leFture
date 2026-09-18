import React from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { UploadModal } from '../../components/modals/UploadModal';

export const UploadPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();

  const handleClose = () => {
    if (courseId) {
      navigate(`/courses/${courseId}`);
    } else {
      navigate('/');
    }
  };

  return (
    <div className="upload-page-wrapper">
      <UploadModal
        open={true}
        onClose={handleClose}
        initialCourseId={courseId}
      />
    </div>
  );
};
