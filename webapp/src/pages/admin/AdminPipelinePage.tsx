import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { adminApi, type AdminPipeline } from '../../lib/admin';
import { ActionDialog } from './AdminDialog';
import {
  Badge,
  Card,
  ErrorLine,
  Loading,
  PageHeader,
  Segmented,
  fmtDateTime,
  fmtDec,
  fmtNum,
  fmtRelative,
  isJobInFlight,
  jobStatusTone,
  shortId,
  useAdminQuery,
} from './adminUi';

type Failure = AdminPipeline['recent_failures'][number];

const DAYS = [
  { value: 7, label: '7日' },
  { value: 30, label: '30日' },
  { value: 90, label: '90日' },
];

function rateTone(rate: number, failed: number) {
  if (rate > 0.02) return 'critical' as const;
  if (failed > 0) return 'warn' as const;
  return 'good' as const;
}

export const AdminPipelinePage: React.FC = () => {
  const [days, setDays] = useState(7);
  const q = useAdminQuery(() => adminApi.pipeline(days), [days]);
  const [pending, setPending] = useState<{ kind: 'retry' | 'cancel'; f: Failure } | null>(null);
  const d = q.data;

  return (
    <div className="adm-page">
      <PageHeader
        title="パイプライン"
        hint="タスク種別ごとの失敗率・所要時間と、失敗タスクの復旧"
        right={<Segmented label="期間" options={DAYS} value={days} onChange={setDays} />}
      />
      <ErrorLine message={q.error} onRetry={q.reload} />
      {q.loading && !d && <Loading />}

      {d && (
        <>
          <Card title="タスク種別ごとの状況" hint={`過去${d.window_days}日に作成されたタスク`}>
            <div className="adm-table-wrap">
              <table className="adm-table">
                <thead>
                  <tr>
                    <th>task_type</th>
                    <th className="adm-right">total</th>
                    <th className="adm-right">completed</th>
                    <th className="adm-right">failed</th>
                    <th className="adm-right">running</th>
                    <th>failure_rate</th>
                    <th className="adm-right">平均所要</th>
                  </tr>
                </thead>
                <tbody>
                  {d.by_task_type.map((t) => {
                    const tone = rateTone(t.failure_rate, t.failed);
                    return (
                      <tr key={t.task_type}>
                        <td className="adm-mono">{t.task_type}</td>
                        <td className="adm-right adm-num">{fmtNum(t.total)}</td>
                        <td className="adm-right adm-num">{fmtNum(t.completed)}</td>
                        <td className="adm-right adm-num">{fmtNum(t.failed)}</td>
                        <td className="adm-right adm-num">{fmtNum(t.running)}</td>
                        <td>
                          <Badge tone={tone}>{(t.failure_rate * 100).toFixed(1)}%</Badge>
                        </td>
                        <td className="adm-right adm-num adm-muted">{fmtDec(t.avg_seconds)}s</td>
                      </tr>
                    );
                  })}
                  {d.by_task_type.length === 0 && (
                    <tr>
                      <td colSpan={7} className="adm-empty">
                        この期間のタスクはありません
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </Card>

          <Card title="直近の失敗タスク" hint="最大50件 · error は300文字で切ってある">
            <div className="adm-failures">
              {d.recent_failures.map((f) => (
                <div key={f.task_id} className="adm-failure">
                  <div className="adm-failure-main">
                    <div className="adm-failure-top">
                      <Badge tone="critical">{f.task_type}</Badge>
                      {f.job_status && <Badge tone={jobStatusTone(f.job_status)}>job: {f.job_status}</Badge>}
                      <span className="adm-muted" title={fmtDateTime(f.updated_at)}>
                        {fmtRelative(f.updated_at)}
                      </span>
                    </div>
                    <code className="adm-failure-error">{f.error || '(error_message なし)'}</code>
                    <div className="adm-failure-ids adm-mono">
                      task {shortId(f.task_id)} · job {shortId(f.job_id)} · lecture {shortId(f.lecture_id)}
                      {' · '}
                      <Link to={`/admin/audit?target_id=${f.task_id}`} className="adm-link">
                        このタスクの操作履歴
                      </Link>
                    </div>
                  </div>
                  <div className="adm-failure-actions">
                    <button
                      type="button"
                      className="adm-btn"
                      disabled={!f.lecture_id || !isJobInFlight(f.job_status)}
                      title={isJobInFlight(f.job_status) ? undefined : 'ジョブは既に終了しています'}
                      onClick={() => setPending({ kind: 'cancel', f })}
                    >
                      講義のジョブ中断
                    </button>
                    <button type="button" className="adm-btn adm-btn-primary" onClick={() => setPending({ kind: 'retry', f })}>
                      タスク再試行
                    </button>
                  </div>
                </div>
              ))}
              {d.recent_failures.length === 0 && <p className="adm-empty">この期間の失敗はありません</p>}
            </div>
          </Card>
        </>
      )}

      <ActionDialog
        open={pending?.kind === 'retry'}
        onClose={() => setPending(null)}
        title="タスクを再試行"
        confirmLabel="再試行する"
        onConfirm={() => adminApi.retryTask(pending!.f.task_id)}
        onDone={q.reload}
      >
        <p className="adm-dialog-text">
          <span className="adm-mono">{pending?.f.task_type}</span> と、それに依存する後続タスクをすべて PENDING
          に戻して再実行します(再生成スキップ用のキャッシュも消えます)。
        </p>
      </ActionDialog>

      <ActionDialog
        open={pending?.kind === 'cancel'}
        onClose={() => setPending(null)}
        title="講義のジョブを中断"
        confirmLabel="中断する"
        danger
        onConfirm={() => adminApi.cancelLectureJobs(pending!.f.lecture_id!)}
        onDone={q.reload}
      >
        <p className="adm-dialog-text">
          講義 <span className="adm-mono">{shortId(pending?.f.lecture_id)}</span> の未完了ジョブとタスクをすべて
          CANCELLED にします。行は削除されません。
        </p>
      </ActionDialog>
    </div>
  );
};
