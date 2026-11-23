import React, { useState } from 'react';
import { CheckCircle2, Circle, AlertCircle, Ban, RefreshCw, RotateCw } from 'lucide-react';
import { apiFetch } from '../lib/api';
import { PROCESSING_TASK_ORDER, TASK_FAILURE_TEXT_KEYS, taskFailureCode, taskLabel } from '../lib/pipelineSteps';
import { useLanguage } from '../i18n/LanguageContext';
import { LOCALE_MAP } from '../i18n/translations';
import type { ProcessingTask } from '../types/lecture';

interface PipelineStepsListProps {
  tasks: ProcessingTask[];
  jobFailed?: boolean;
  onRetried: () => void;
}

function isStaleFailed(task: ProcessingTask): boolean {
  if (task.status !== 'FAILED' && task.status !== 'ERROR') return false;
  const updatedMs = new Date(task.updated_at).getTime();
  return Date.now() - updatedMs > 5 * 60 * 1000;
}

export const PipelineStepsList: React.FC<PipelineStepsListProps> = ({ tasks, jobFailed = false, onRetried }) => {
  const { language, t } = useLanguage();
  const [retryingId, setRetryingId] = useState<string | null>(null);

  const byType = new Map<string, ProcessingTask>();
  tasks.forEach((t) => byType.set(t.task_type, t));

  // TRANSCRIBE_MASTER と CHECK_AND_ASSEMBLE は排他
  const visibleTaskOrder = tasks.length === 0
    ? PROCESSING_TASK_ORDER
    : PROCESSING_TASK_ORDER.filter((type) => {
        if (type === 'TRANSCRIBE_MASTER' || type === 'CHECK_AND_ASSEMBLE') {
          return byType.has(type);
        }
        return true;
      });

  // 順番的に最初の未完了ステップを実行中として扱う
  let currentType: string | undefined;
  for (const type of visibleTaskOrder) {
    const task = byType.get(type);
    if (!task || (task.status !== 'COMPLETED' && task.status !== 'CANCELLED')) {
      currentType = type;
      break;
    }
  }

  const handleRetry = async (taskId: string) => {
    setRetryingId(taskId);
    try {
      await apiFetch('/retry-task', { method: 'POST', body: JSON.stringify({ task_id: taskId }) });
      onRetried();
    } catch (e) {
      console.error('Task retry failed', e);
    } finally {
      setRetryingId(null);
    }
  };

  const formatTaskTime = (updatedAtStr: string) => {
    try {
      const d = new Date(updatedAtStr);
      const locale = LOCALE_MAP[language] || 'en-US';
      return d.toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' });
    } catch {
      return '';
    }
  };

  return (
    <div className="pipeline-steps-container">
      <ol className="pipeline-steps-list">
        {visibleTaskOrder.map((taskType) => {
          const task = byType.get(taskType);
          const isCurrent = taskType === currentType;
          const label = taskLabel(taskType, language);

          if (!task) {
            // タスク未到着時
            if (isCurrent) {
              return (
                <li key={taskType} className="pipeline-step-item is-current">
                  <div className="pipeline-step-icon-wrap">
                    <div className="pipeline-step-spinner" />
                  </div>
                  <div className="pipeline-step-content">
                    <span className="pipeline-step-label">{label}</span>
                    <span className="pipeline-step-subtitle">{t('pipelineStepsInProgressLabel')}</span>
                  </div>
                </li>
              );
            }
            return (
              <li key={taskType} className="pipeline-step-item is-pending">
                <div className="pipeline-step-icon-wrap">
                  <Circle size={18} className="pipeline-step-icon is-pending" />
                </div>
                <div className="pipeline-step-content">
                  <span className="pipeline-step-label is-pending">{label}</span>
                </div>
              </li>
            );
          }

          if (task.status === 'CANCELLED') {
            return (
              <li key={task.id} className="pipeline-step-item is-cancelled">
                <div className="pipeline-step-icon-wrap">
                  <Ban size={18} className="pipeline-step-icon is-cancelled" />
                </div>
                <div className="pipeline-step-content">
                  <span className="pipeline-step-label is-cancelled">{label}</span>
                  <span className="pipeline-step-subtitle">{t('pipelineStepsCancelledLabel')}</span>
                </div>
              </li>
            );
          }

          if (task.status === 'COMPLETED') {
            const timeStr = formatTaskTime(task.updated_at);
            return (
              <li key={task.id} className="pipeline-step-item is-completed">
                <div className="pipeline-step-icon-wrap">
                  <CheckCircle2 size={18} className="pipeline-step-icon is-completed" />
                </div>
                <div className="pipeline-step-content">
                  <span className="pipeline-step-label">{label}</span>
                  {timeStr && <span className="pipeline-step-subtitle">{timeStr}</span>}
                </div>
              </li>
            );
          }

          const isFailed = task.status === 'FAILED' || task.status === 'ERROR';
          if (isFailed) {
            // やり直しても結果が変わらない失敗(無音・音声なし)は自動リトライもされないので即確定扱い
            const failureCode = taskFailureCode(task);
            const isStuck = jobFailed || isStaleFailed(task) || failureCode !== null;
            if (!isStuck) {
              return (
                <li key={task.id} className="pipeline-step-item is-retrying">
                  <div className="pipeline-step-icon-wrap">
                    <RotateCw size={18} className="pipeline-step-icon is-retrying animate-spin" />
                  </div>
                  <div className="pipeline-step-content">
                    <span className="pipeline-step-label">{label}</span>
                    <span className="pipeline-step-subtitle is-retrying">
                      {t('pipelineStepsRetryingAutomaticallyLabel')}
                    </span>
                  </div>
                </li>
              );
            }

            if (failureCode) {
              // 理由を説明し、リトライボタンは出さない(押しても同じ失敗を繰り返すだけ)
              return (
                <li key={task.id} className="pipeline-step-item is-failed">
                  <div className="pipeline-step-icon-wrap">
                    <AlertCircle size={18} className="pipeline-step-icon is-failed" />
                  </div>
                  <div className="pipeline-step-content">
                    <span className="pipeline-step-label is-failed">{label}</span>
                    <span className="pipeline-step-subtitle">{t(TASK_FAILURE_TEXT_KEYS[failureCode].message)}</span>
                  </div>
                </li>
              );
            }

            const isRetrying = retryingId === task.id;
            return (
              <li key={task.id} className="pipeline-step-item is-failed">
                <div className="pipeline-step-icon-wrap">
                  <AlertCircle size={18} className="pipeline-step-icon is-failed" />
                </div>
                <div className="pipeline-step-content">
                  <span className="pipeline-step-label is-failed">{label}</span>
                  <button
                    type="button"
                    className="pipeline-step-retry-btn"
                    onClick={() => handleRetry(task.id)}
                    disabled={isRetrying}
                  >
                    <RefreshCw size={12} className={isRetrying ? 'animate-spin' : ''} />
                    <span>{isRetrying ? t('pipelineStepsRetryingLabel') : t('pipelineStepsRetryConfirmButton')}</span>
                  </button>
                </div>
              </li>
            );
          }

          if (isCurrent) {
            return (
              <li key={task.id} className="pipeline-step-item is-current">
                <div className="pipeline-step-icon-wrap">
                  <div className="pipeline-step-spinner" />
                </div>
                <div className="pipeline-step-content">
                  <span className="pipeline-step-label">{label}</span>
                  <span className="pipeline-step-subtitle">{t('pipelineStepsInProgressLabel')}</span>
                </div>
              </li>
            );
          }

          // PENDING
          return (
            <li key={task.id} className="pipeline-step-item is-pending">
              <div className="pipeline-step-icon-wrap">
                <Circle size={18} className="pipeline-step-icon is-pending" />
              </div>
              <div className="pipeline-step-content">
                <span className="pipeline-step-label is-pending">{label}</span>
              </div>
            </li>
          );
        })}
      </ol>
    </div>
  );
};
