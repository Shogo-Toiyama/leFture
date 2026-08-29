import React, { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { createDraftLecture } from '../../lib/lectures';
import { InsufficientCreditsError, uploadRecordingAndAnalyze, type UploadProgress } from '../../lib/upload';

const ACCEPTED_EXTENSIONS = '.mp3,.m4a,.wav,.aac,.aiff,.caf,.flac,.ogg';

const STEP_LABEL: Record<UploadProgress['step'], string> = {
  'requesting-url': 'Preparing upload…',
  uploading: 'Uploading audio…',
  finalizing: 'Finalizing…',
  'starting-analysis': 'Starting analysis…',
  done: 'Done',
};

function defaultLocale(): string {
  return (navigator.language || 'en').split('-')[0];
}

export const UploadPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();

  const [file, setFile] = useState<File | null>(null);
  const [title, setTitle] = useState('');
  const [lectureDate, setLectureDate] = useState(() => new Date().toISOString().slice(0, 16));
  const [recordingLanguage, setRecordingLanguage] = useState(defaultLocale());
  const [displayLanguage, setDisplayLanguage] = useState(defaultLocale());
  const [progress, setProgress] = useState<UploadProgress['step'] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!courseId || !file) return;

    setSubmitting(true);
    setError(null);
    try {
      const lecture = await createDraftLecture({
        courseId,
        title,
        lectureDatetime: new Date(lectureDate).toISOString(),
        recordingLanguage,
        displayLanguage,
      });

      try {
        await uploadRecordingAndAnalyze(lecture.id, file, (p) => setProgress(p.step));
      } catch (err) {
        if (err instanceof InsufficientCreditsError) {
          navigate(`/lectures/${lecture.id}`, { state: { analysisBlockedReason: err.message } });
          return;
        }
        throw err;
      }

      navigate(`/lectures/${lecture.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed');
      setSubmitting(false);
      setProgress(null);
    }
  };

  return (
    <div>
      <Link to={`/courses/${courseId}`}>← Back to course</Link>
      <h1>Upload recording</h1>

      <form className="upload-form" onSubmit={handleSubmit}>
        <label>
          Audio file
          <input
            type="file"
            accept={ACCEPTED_EXTENSIONS}
            required
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          />
        </label>
        <label>
          Title (optional)
          <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Auto-generated if left blank" />
        </label>
        <label>
          Date
          <input type="datetime-local" value={lectureDate} onChange={(e) => setLectureDate(e.target.value)} required />
        </label>
        <div className="course-form-row">
          <label>
            Recording language
            <input value={recordingLanguage} onChange={(e) => setRecordingLanguage(e.target.value)} />
          </label>
          <label>
            Display language
            <input value={displayLanguage} onChange={(e) => setDisplayLanguage(e.target.value)} />
          </label>
        </div>

        {error && <p className="auth-error">{error}</p>}
        {progress && <p>{STEP_LABEL[progress]}</p>}

        <button type="submit" disabled={submitting || !file}>
          {submitting ? 'Uploading…' : 'Upload and analyze'}
        </button>
      </form>
    </div>
  );
};
