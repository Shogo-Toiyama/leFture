import React, { useState } from 'react';
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom';
import { useProcessingStatus } from '../../hooks/useProcessingStatus';
import { useFunFacts } from '../../hooks/useFunFacts';
import { softDeleteLecture } from '../../lib/lectures';
import { startAnalysis, InsufficientCreditsError } from '../../lib/upload';
import { lectureDisplayTitle, DEAD_JOB_STATUSES } from '../../types/lecture';
import { PipelineStepsList } from '../../components/PipelineStepsList';

export const LectureViewerPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const analysisBlockedReason = (location.state as { analysisBlockedReason?: string } | null)?.analysisBlockedReason;

  const { lecture, job, tasks, loading, error, refetch } = useProcessingStatus(lectureId);
  const { funFacts } = useFunFacts(lectureId);
  const [starting, setStarting] = useState(false);
  const [startError, setStartError] = useState<string | null>(analysisBlockedReason ?? null);

  const handleDelete = async () => {
    if (!lectureId || !lecture) return;
    if (!window.confirm('Delete this lecture?')) return;
    await softDeleteLecture(lectureId);
    navigate(`/courses/${lecture.course_id}`);
  };

  const handleStart = async (force = false) => {
    if (!lectureId) return;
    setStarting(true);
    setStartError(null);
    try {
      await startAnalysis(lectureId, force);
      await refetch();
    } catch (err) {
      setStartError(err instanceof InsufficientCreditsError ? err.message : 'Failed to start analysis.');
    } finally {
      setStarting(false);
    }
  };

  if (loading) return <p>Loading…</p>;
  if (error) return <p className="auth-error">{error}</p>;
  if (!lecture) return <p>Lecture not found.</p>;

  const isTerminalFailure = job ? DEAD_JOB_STATUSES.includes(job.status) : false;
  const isReady = job?.status === 'COMPLETED';
  const isProcessing = job && !isTerminalFailure && !isReady;

  return (
    <div>
      <Link to={`/courses/${lecture.course_id}`}>← Back to course</Link>
      <div className="page-header">
        <h1>{lectureDisplayTitle(lecture)}</h1>
        <button type="button" className="danger" onClick={handleDelete}>
          Delete
        </button>
      </div>
      <p>{new Date(lecture.lecture_datetime).toLocaleString()}</p>

      {startError && <p className="auth-error">{startError}</p>}

      {!job && (
        <div className="status-banner">
          <p>Analysis has not started yet.</p>
          <button type="button" onClick={() => handleStart(false)} disabled={starting}>
            {starting ? 'Starting…' : 'Start analysis'}
          </button>
        </div>
      )}

      {isProcessing && (
        <div className="status-banner">
          <strong>Status: {job!.status}</strong>
          <PipelineStepsList tasks={tasks} onRetried={refetch} />
        </div>
      )}

      {isTerminalFailure && (
        <div className="status-banner status-banner-error">
          <strong>Status: {job!.status}</strong>
          <PipelineStepsList tasks={tasks} onRetried={refetch} />
          <button type="button" onClick={() => handleStart(true)} disabled={starting}>
            {starting ? 'Starting…' : 'Start over'}
          </button>
        </div>
      )}

      {isReady && (
        <div>
          <ul className="lecture-content-links">
            <li>
              <Link to={`/lectures/${lectureId}/review-cards`}>Review cards →</Link>
            </li>
            <li>
              <Link to={`/lectures/${lectureId}/deep-notes`}>Deep notes →</Link>
            </li>
            <li>
              <Link to={`/lectures/${lectureId}/transcript`}>Transcript →</Link>
            </li>
            <li>
              <Link to={`/courses/${lecture.course_id}/topic-map`}>Topic map →</Link>
            </li>
          </ul>

          {funFacts.length > 0 && (
            <div>
              <h2>Fun facts</h2>
              <ul className="fun-fact-list">
                {funFacts.map((fact) => (
                  <li key={fact.id} className="fun-fact-card">
                    <strong>{fact.title}</strong>
                    <p>
                      {fact.hook} {fact.body}
                    </p>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
