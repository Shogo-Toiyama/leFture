import React, { useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { createDraftLecture } from '../../lib/lectures';
import { getCreditSummary } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { InsufficientCreditsError, uploadRecordingAndAnalyze, type UploadProgress } from '../../lib/upload';
import { useProfile } from '../../hooks/useProfile';

const ACCEPTED_EXTENSIONS = '.mp3,.m4a,.wav,.aac,.aiff,.caf,.flac,.ogg';

const STEP_LABEL: Record<UploadProgress['step'], string> = {
  'requesting-url': 'Preparing upload…',
  uploading: 'Uploading audio…',
  finalizing: 'Finalising…',
  'starting-analysis': 'Starting analysis…',
  done: 'Done',
};

function defaultLocale(): string {
  return (navigator.language || 'en').split('-')[0];
}

function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** datetime-local入力用のローカル時刻文字列(ISOのZ付きだとブラウザが受け付けない)。 */
function localDateTimeValue(date: Date): string {
  const offset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

export const UploadPage: React.FC = () => {
  const { courseId } = useParams<{ courseId: string }>();
  const navigate = useNavigate();
  const { profile } = useProfile();
  const inputRef = useRef<HTMLInputElement>(null);

  const [file, setFile] = useState<File | null>(null);
  const [dragging, setDragging] = useState(false);
  const [title, setTitle] = useState('');
  const [lectureDate, setLectureDate] = useState(() => localDateTimeValue(new Date()));
  const [recordingLanguage, setRecordingLanguage] = useState(defaultLocale());
  const [displayLanguage, setDisplayLanguage] = useState(defaultLocale());
  const [progress, setProgress] = useState<UploadProgress | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [credits, setCredits] = useState<number | null>(null);
  const [hasPlan, setHasPlan] = useState(true);

  useEffect(() => {
    if (!profile) return;
    setRecordingLanguage(profile.metadata?.recording_language ?? defaultLocale());
    setDisplayLanguage(profile.metadata?.display_language ?? defaultLocale());
  }, [profile]);

  useEffect(() => {
    getCreditSummary()
      .then((summary) => {
        setCredits(toDisplayCredits(summary.credit_balance));
        setHasPlan(summary.has_active_plan);
      })
      .catch(() => setCredits(null));
  }, []);

  const blocked = credits !== null && (!hasPlan || credits <= 0);

  const pickFile = (next: File | null) => {
    setFile(next);
    if (next && !title) {
      setTitle(next.name.replace(/\.[^.]+$/, ''));
    }
  };

  const handleDrop = (event: React.DragEvent) => {
    event.preventDefault();
    setDragging(false);
    const dropped = event.dataTransfer.files?.[0];
    if (dropped) pickFile(dropped);
  };

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
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
        await uploadRecordingAndAnalyze(lecture.id, file, setProgress);
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
    <div className="upload-page">
      <header className="page-header">
        <div>
          <Link to={`/courses/${courseId}`} className="back-link">
            ← Course
          </Link>
          <h1>Upload a recording</h1>
          <p className="muted">Drop an audio file and we'll transcribe it and build your study material.</p>
        </div>
      </header>

      {blocked && (
        <p className="notice notice-error">
          {hasPlan ? "You've run out of credits." : "You don't have an active plan yet."}{' '}
          <Link to="/account/credits">Manage credits →</Link>
        </p>
      )}

      <form className="upload-form" onSubmit={handleSubmit}>
        <div
          className={`dropzone ${dragging ? 'is-dragging' : ''} ${file ? 'has-file' : ''}`}
          onDragOver={(e) => {
            e.preventDefault();
            setDragging(true);
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={handleDrop}
          onClick={() => inputRef.current?.click()}
          role="button"
          tabIndex={0}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ') inputRef.current?.click();
          }}
        >
          <input
            ref={inputRef}
            type="file"
            accept={ACCEPTED_EXTENSIONS}
            hidden
            onChange={(e) => pickFile(e.target.files?.[0] ?? null)}
          />
          {file ? (
            <>
              <strong>{file.name}</strong>
              <span className="muted">{formatBytes(file.size)} · click to choose a different file</span>
            </>
          ) : (
            <>
              <strong>Drop your recording here</strong>
              <span className="muted">or click to browse · mp3, m4a, wav, aac, flac, ogg</span>
            </>
          )}
        </div>

        <label>
          Title
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Left blank, we'll name it for you"
          />
        </label>

        <div className="form-row">
          <label>
            Date &amp; time
            <input
              type="datetime-local"
              value={lectureDate}
              onChange={(e) => setLectureDate(e.target.value)}
              required
            />
          </label>
          <label>
            Spoken language
            <input value={recordingLanguage} onChange={(e) => setRecordingLanguage(e.target.value)} />
          </label>
          <label>
            Notes language
            <input value={displayLanguage} onChange={(e) => setDisplayLanguage(e.target.value)} />
          </label>
        </div>

        {error && <p className="notice notice-error">{error}</p>}

        {progress && (
          <div className="upload-progress">
            <span>{STEP_LABEL[progress.step]}</span>
            <div className="progress-track">
              <div
                className="progress-fill"
                style={{ width: progress.ratio !== undefined ? `${Math.round(progress.ratio * 100)}%` : '100%' }}
              />
            </div>
          </div>
        )}

        <button type="submit" disabled={submitting || !file || blocked}>
          {submitting ? 'Uploading…' : 'Upload and analyse'}
        </button>
      </form>
    </div>
  );
};
