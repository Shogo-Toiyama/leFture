import React, { useState } from 'react';
import { apiFetch } from '../lib/api';
import { PROCESSING_TASK_ORDER, taskLabel } from '../lib/pipelineSteps';
import type { ProcessingTask } from '../types/lecture';

interface PipelineStepsListProps {
  tasks: ProcessingTask[];
  onRetried: () => void;
}

function statusIcon(status: ProcessingTask['status']): string {
  switch (status) {
    case 'COMPLETED':
      return '✓';
    case 'RUNNING':
    case 'QUEUED':
    case 'WAITING':
      return '◐';
    case 'CANCELLED':
      return '⊘';
    case 'FAILED':
    case 'ERROR':
      return '✕';
    default:
      return '○';
  }
}

const RetryButton: React.FC<{ taskId: string; onRetried: () => void }> = ({ taskId, onRetried }) => {
  const [retrying, setRetrying] = useState(false);

  const handleRetry = async () => {
    setRetrying(true);
    try {
      await apiFetch('/retry-task', { method: 'POST', body: JSON.stringify({ task_id: taskId }) });
      onRetried();
    } finally {
      setRetrying(false);
    }
  };

  return (
    <button type="button" className="link-button" onClick={handleRetry} disabled={retrying}>
      {retrying ? 'Retrying…' : 'Retry'}
    </button>
  );
};

export const PipelineStepsList: React.FC<PipelineStepsListProps> = ({ tasks, onRetried }) => {
  const ordered = [...tasks].sort(
    (a, b) => PROCESSING_TASK_ORDER.indexOf(a.task_type) - PROCESSING_TASK_ORDER.indexOf(b.task_type)
  );

  return (
    <ul className="pipeline-steps">
      {ordered.map((task) => (
        <li key={task.id} className={`pipeline-step pipeline-step-${task.status.toLowerCase()}`}>
          <span className="pipeline-step-icon">{statusIcon(task.status)}</span>
          <span className="pipeline-step-label">{taskLabel(task.task_type)}</span>
          {(task.status === 'FAILED' || task.status === 'ERROR') && (
            <RetryButton taskId={task.id} onRetried={onRetried} />
          )}
        </li>
      ))}
    </ul>
  );
};
