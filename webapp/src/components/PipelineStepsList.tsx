import React, { useState } from 'react';
import { apiFetch } from '../lib/api';
import { PROCESSING_TASK_ORDER, taskLabel } from '../lib/pipelineSteps';
import type { ProcessingTask } from '../types/lecture';

interface PipelineStepsListProps {
  tasks: ProcessingTask[];
  onRetried: () => void;
}

const TERMINAL = new Set(['COMPLETED', 'FAILED', 'ERROR', 'CANCELLED']);

function statusGlyph(status: ProcessingTask['status'], isCurrent: boolean): string {
  if (status === 'COMPLETED') return '✓';
  if (status === 'CANCELLED') return '⊘';
  if (status === 'FAILED' || status === 'ERROR') return '!';
  return isCurrent ? '◆' : '○';
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
  // 進行中のステップ = 順序上いちばん手前の未終了タスク(pipeline_steps_list.dartと同じ判定)。
  const currentId = ordered.find((task) => !TERMINAL.has(task.status))?.id;

  return (
    <ol className="pipeline-steps">
      {ordered.map((task) => {
        const isCurrent = task.id === currentId;
        return (
          <li key={task.id} className={`pipeline-step is-${task.status.toLowerCase()} ${isCurrent ? 'is-current' : ''}`}>
            <span className="pipeline-step-glyph" aria-hidden="true">
              {statusGlyph(task.status, isCurrent)}
            </span>
            <span className="pipeline-step-label">{taskLabel(task.task_type)}</span>
            {(task.status === 'FAILED' || task.status === 'ERROR') && (
              <RetryButton taskId={task.id} onRetried={onRetried} />
            )}
          </li>
        );
      })}
    </ol>
  );
};
