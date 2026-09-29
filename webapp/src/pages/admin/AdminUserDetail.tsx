import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { adminApi, type AdminUserLecture } from '../../lib/admin';
import { ActionDialog } from './AdminDialog';
import {
  Badge,
  ErrorLine,
  Loading,
  fmtDate,
  fmtDateTime,
  fmtDec,
  fmtDuration,
  fmtNum,
  fmtRelative,
  fmtUsd,
  isJobInFlight,
  jobStatusTone,
  microToCredits,
  shortId,
  useAdminAction,
  useAdminQuery,
} from './adminUi';

const MAX_GRANT = 10_000;
const PREVIEW_ROWS = 8;

type Dialog =
  | { kind: 'grant' }
  | { kind: 'suspend' }
  | { kind: 'unsuspend' }
  | { kind: 'delete' }
  | { kind: 'retry'; lecture: AdminUserLecture }
  | { kind: 'cancel'; lecture: AdminUserLecture };

export const AdminUserDetail: React.FC<{
  userId: string;
  onSuspendedChange: (suspended: boolean) => void;
  onDeleted: () => void;
}> = ({ userId, onSuspendedChange, onDeleted }) => {
  const detail = useAdminQuery(() => adminApi.userDetail(userId), [userId]);
  const lectures = useAdminQuery(() => adminApi.userLectures(userId), [userId]);
  const credits = useAdminQuery(() => adminApi.userCredits(userId), [userId]);
  const reveal = useAdminAction();
  const [email, setEmail] = useState<string | null>(null);
  const [dialog, setDialog] = useState<Dialog | null>(null);
  const [showAllLectures, setShowAllLectures] = useState(false);
  const [showAllLedger, setShowAllLedger] = useState(false);

  // フォーム状態(ダイアログ共通)
  const [grantCredits, setGrantCredits] = useState('');
  const [grantDays, setGrantDays] = useState('');
  const [reason, setReason] = useState('');
  const [confirmId, setConfirmId] = useState('');

  const openDialog = (d: Dialog) => {
    setReason('');
    setGrantCredits('');
    setGrantDays('');
    setConfirmId('');
    setDialog(d);
  };
  const close = () => setDialog(null);

  const d = detail.data;
  if (detail.loading && !d) return <div className="adm-user-detail"><Loading /></div>;
  if (!d) return <div className="adm-user-detail"><ErrorLine message={detail.error} onRetry={detail.reload} /></div>;

  const reasonOk = reason.trim().length >= 3;
  const grantNum = Number(grantCredits);
  const grantOk = reasonOk && grantNum > 0 && grantNum <= MAX_GRANT;
  const lectureRows = lectures.data ?? [];
  const grants = credits.data?.grants ?? [];
  const txs = credits.data?.transactions ?? [];

  return (
    <div className="adm-user-detail">
      <div className="adm-detail-top">
        <div className="adm-detail-ids">
          <span className="adm-mono adm-muted">user_id: {d.user_id}</span>
          {email ? (
            <span className="adm-mono adm-revealed">{email}</span>
          ) : (
            <button
              type="button"
              className="adm-btn adm-btn-sm"
              disabled={reveal.busy}
              onClick={() => reveal.run(() => adminApi.revealUserEmail(userId)).then((r) => r && setEmail(r.email))}
            >
              メールを開示(監査ログに記録)
            </button>
          )}
          <ErrorLine message={reveal.error} />
        </div>
        <div className="adm-detail-actions">
          <Link className="adm-link" to={`/admin/audit?target_id=${userId}`}>
            操作履歴
          </Link>
          {d.suspension ? (
            <button type="button" className="adm-btn" onClick={() => openDialog({ kind: 'unsuspend' })}>
              停止を解除
            </button>
          ) : (
            <button type="button" className="adm-btn" onClick={() => openDialog({ kind: 'suspend' })}>
              停止する
            </button>
          )}
          <button type="button" className="adm-btn adm-btn-primary" onClick={() => openDialog({ kind: 'grant' })}>
            クレジット付与
          </button>
        </div>
      </div>

      {d.suspension && (
        <div className="adm-notice adm-tone-warn">
          <Badge tone="warn">停止中</Badge>
          <span>
            {fmtDateTime(d.suspension.suspended_at)} · 理由: {d.suspension.reason ?? '—'}
          </span>
        </div>
      )}

      <div className="adm-facts">
        <Fact label="登録" value={fmtDate(d.created_at)} />
        <Fact
          label="実際の利用(最終)"
          value={fmtRelative(d.last_active_at)}
          sub={`直近30日で${d.active_days_30d}日アクティブ`}
        />
        <Fact label="最終再認証" value={fmtRelative(d.last_reauth_at)} sub="利用状況の指標ではない" />
        <Fact
          label="認証"
          value={d.providers.length ? d.providers.join(', ') : '—'}
          sub={`${d.username ?? 'username なし'} · ${d.confirmed ? 'メール確認済' : 'メール未確認'}`}
        />
      </div>

      <div className="adm-facts adm-facts-3">
        <div className="adm-fact">
          <div className="adm-fact-label">サブスクリプション</div>
          {d.subscription ? (
            <>
              <div className="adm-fact-value">
                {d.subscription.plan_name ?? d.subscription.plan_id}{' '}
                <span className="adm-muted">{fmtUsd(d.subscription.price_usd)}</span>
              </div>
              <div className="adm-fact-sub">
                {fmtDate(d.subscription.current_period_start)} 〜 {fmtDate(d.subscription.current_period_end)}
                {d.subscription.pending_plan_id && ' · プラン変更予約あり'}
              </div>
            </>
          ) : (
            <div className="adm-fact-value adm-muted">有効な契約なし</div>
          )}
        </div>
        <div className="adm-fact">
          <div className="adm-fact-label">クレジット</div>
          <div className="adm-fact-value adm-num adm-em-info">{fmtDec(d.credits.balance)} 残高</div>
          <div className="adm-fact-sub adm-num">
            付与合計 {fmtDec(d.credits.granted_total)} · 消費合計 {fmtDec(d.credits.consumed_total)}
          </div>
        </div>
        <div className="adm-fact">
          <div className="adm-fact-label">利用状況</div>
          <div className="adm-fact-sub adm-num">
            講義 {fmtNum(d.usage.lectures)}件(ゴミ箱 {fmtNum(d.usage.lectures_trashed)}) · コース {fmtNum(d.usage.courses)}
          </div>
          <div className="adm-fact-sub adm-num">
            音声 {fmtDec(d.usage.audio_hours)}h · 原価 {fmtUsd(d.usage.cost_usd)} · デバイス {fmtNum(d.usage.devices)}台
          </div>
          <div className={`adm-fact-sub adm-num ${d.usage.jobs_failed ? 'adm-em-warn' : ''}`}>
            失敗ジョブ {fmtNum(d.usage.jobs_failed)}件
          </div>
        </div>
      </div>

      <section className="adm-subsection">
        <h3 className="adm-sub-title">
          講義 <span className="adm-card-hint">— メタデータのみ(タイトル・要約は返らない)</span>
        </h3>
        <ErrorLine message={lectures.error} onRetry={lectures.reload} />
        {lectures.loading && !lectures.data && <Loading />}
        {lectures.data && (
          <div className="adm-table-wrap">
            <table className="adm-table adm-table-compact">
              <thead>
                <tr>
                  <th>lecture_id</th>
                  <th>作成</th>
                  <th className="adm-right">長さ</th>
                  <th className="adm-right">消費CR</th>
                  <th>言語</th>
                  <th>ジョブ</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {(showAllLectures ? lectureRows : lectureRows.slice(0, PREVIEW_ROWS)).map((l) => (
                  <tr key={l.lecture_id} className={l.deleted_at ? 'adm-row-dim' : undefined}>
                    <td className="adm-mono" title={l.lecture_id}>
                      {shortId(l.lecture_id)}
                      {l.deleted_at && <span className="adm-muted"> (ゴミ箱)</span>}
                    </td>
                    <td>{fmtDateTime(l.created_at)}</td>
                    <td className="adm-right adm-num">{fmtDuration(l.duration_seconds)}</td>
                    <td className="adm-right adm-num">{fmtDec(l.credits_used)}</td>
                    <td className="adm-muted">{l.recording_language ?? '—'}</td>
                    <td>{l.job_status ? <Badge tone={jobStatusTone(l.job_status)}>{l.job_status}</Badge> : '—'}</td>
                    <td className="adm-right">
                      {isJobInFlight(l.job_status) && (
                        <button type="button" className="adm-btn adm-btn-sm" onClick={() => openDialog({ kind: 'cancel', lecture: l })}>
                          中断
                        </button>
                      )}
                      {l.failed_task_id && !isJobInFlight(l.job_status) && (
                        <button type="button" className="adm-btn adm-btn-sm" onClick={() => openDialog({ kind: 'retry', lecture: l })}>
                          再試行
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
                {lectureRows.length === 0 && (
                  <tr>
                    <td colSpan={7} className="adm-empty">
                      講義はありません
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}
        {lectureRows.length > PREVIEW_ROWS && (
          <button type="button" className="adm-link-btn" onClick={() => setShowAllLectures((v) => !v)}>
            {showAllLectures ? '折りたたむ' : `すべて表示(${lectureRows.length}件)`}
          </button>
        )}
      </section>

      <section className="adm-subsection">
        <h3 className="adm-sub-title">クレジット台帳</h3>
        <ErrorLine message={credits.error} onRetry={credits.reload} />
        {credits.data && (
          <div className="adm-grid-2">
            <div>
              <div className="adm-fact-label">付与 (credit_grants)</div>
              <ul className="adm-ledger">
                {(showAllLedger ? grants : grants.slice(0, PREVIEW_ROWS)).map((g) => (
                  <li key={g.id}>
                    <span className="adm-muted">
                      {fmtDate(g.created_at)} · <span className="adm-mono">{g.source}</span>
                      {g.expires_at && ` · 失効 ${fmtDate(g.expires_at)}`}
                    </span>
                    <span className="adm-num">
                      +{fmtDec(microToCredits(g.amount))}
                      <span className="adm-muted"> (残 {fmtDec(microToCredits(g.remaining_amount))})</span>
                    </span>
                  </li>
                ))}
                {grants.length === 0 && <li className="adm-empty">なし</li>}
              </ul>
            </div>
            <div>
              <div className="adm-fact-label">増減 (credit_transactions)</div>
              <ul className="adm-ledger">
                {(showAllLedger ? txs : txs.slice(0, PREVIEW_ROWS)).map((t) => (
                  <li key={t.id}>
                    <span className="adm-muted">
                      {fmtDateTime(t.created_at)} · <span className="adm-mono">{t.reason ?? '—'}</span>
                    </span>
                    <span className={`adm-num ${t.delta < 0 ? '' : 'adm-em-good'}`}>
                      {t.delta > 0 ? '+' : ''}
                      {fmtDec(microToCredits(t.delta))}
                    </span>
                  </li>
                ))}
                {txs.length === 0 && <li className="adm-empty">なし</li>}
              </ul>
            </div>
          </div>
        )}
        {(grants.length > PREVIEW_ROWS || txs.length > PREVIEW_ROWS) && (
          <button type="button" className="adm-link-btn" onClick={() => setShowAllLedger((v) => !v)}>
            {showAllLedger ? '折りたたむ' : 'すべて表示'}
          </button>
        )}
      </section>

      <div className="adm-danger-zone">
        <button type="button" className="adm-btn adm-btn-danger" onClick={() => openDialog({ kind: 'delete' })}>
          アカウントを削除
        </button>
      </div>

      {/* ---- ダイアログ ---- */}
      <ActionDialog
        open={dialog?.kind === 'grant'}
        onClose={close}
        title="クレジットを付与"
        confirmLabel="付与する"
        canSubmit={grantOk}
        onConfirm={() => adminApi.grantCredits(userId, grantNum, reason.trim(), grantDays ? Number(grantDays) : null)}
        onDone={() => {
          detail.reload();
          credits.reload();
        }}
      >
        <label className="adm-field">
          <span>クレジット(表示単位、最大 {fmtNum(MAX_GRANT)})</span>
          <input
            className="adm-input"
            type="number"
            min="0.01"
            max={MAX_GRANT}
            step="0.01"
            value={grantCredits}
            onChange={(e) => setGrantCredits(e.target.value)}
            required
          />
        </label>
        <label className="adm-field">
          <span>有効期限(日数、空欄なら無期限)</span>
          <input
            className="adm-input"
            type="number"
            min="1"
            max="3650"
            value={grantDays}
            onChange={(e) => setGrantDays(e.target.value)}
          />
        </label>
        <ReasonField value={reason} onChange={setReason} />
      </ActionDialog>

      <ActionDialog
        open={dialog?.kind === 'suspend'}
        onClose={close}
        title="アカウントを停止"
        confirmLabel="停止する"
        danger
        canSubmit={reasonOk}
        onConfirm={() => adminApi.suspend(userId, reason.trim())}
        onDone={() => {
          detail.reload();
          onSuspendedChange(true);
        }}
      >
        <p className="adm-dialog-text">
          停止中も閲覧・サブスク解約・問い合わせ・アカウント削除はできます(課金だけ続く状態を作らないため)。
        </p>
        <ReasonField value={reason} onChange={setReason} />
      </ActionDialog>

      <ActionDialog
        open={dialog?.kind === 'unsuspend'}
        onClose={close}
        title="停止を解除"
        confirmLabel="解除する"
        onConfirm={() => adminApi.unsuspend(userId)}
        onDone={() => {
          detail.reload();
          onSuspendedChange(false);
        }}
      >
        <p className="adm-dialog-text">このユーザーの停止を解除します。</p>
      </ActionDialog>

      <ActionDialog
        open={dialog?.kind === 'delete'}
        onClose={close}
        title="アカウントを完全に削除"
        confirmLabel="完全に削除する"
        danger
        canSubmit={reasonOk && confirmId.trim() === userId}
        onConfirm={() => adminApi.deleteUser(userId, confirmId.trim(), reason.trim())}
        onDone={onDeleted}
      >
        <p className="adm-dialog-text adm-em-critical">
          講義・生成物・クレジット・アカウントを含むすべてのデータが削除され、取り消せません。
        </p>
        <label className="adm-field">
          <span>
            確認のため user_id を入力: <span className="adm-mono">{userId}</span>
          </span>
          <input className="adm-input adm-mono" value={confirmId} onChange={(e) => setConfirmId(e.target.value)} />
        </label>
        <ReasonField value={reason} onChange={setReason} />
      </ActionDialog>

      <ActionDialog
        open={dialog?.kind === 'retry'}
        onClose={close}
        title="失敗したタスクを再試行"
        confirmLabel="再試行する"
        onConfirm={() => adminApi.retryTask(dialog?.kind === 'retry' ? dialog.lecture.failed_task_id! : '')}
        onDone={lectures.reload}
      >
        <p className="adm-dialog-text">
          最後に失敗したタスクと、それに依存する後続タスクを PENDING に戻して再実行します。
        </p>
      </ActionDialog>

      <ActionDialog
        open={dialog?.kind === 'cancel'}
        onClose={close}
        title="講義のジョブを中断"
        confirmLabel="中断する"
        danger
        onConfirm={() => adminApi.cancelLectureJobs(dialog?.kind === 'cancel' ? dialog.lecture.lecture_id : '')}
        onDone={lectures.reload}
      >
        <p className="adm-dialog-text">未完了のジョブとタスクをすべて CANCELLED にします。行は削除されません。</p>
      </ActionDialog>
    </div>
  );
};

const Fact: React.FC<{ label: string; value: string; sub?: string }> = ({ label, value, sub }) => (
  <div className="adm-fact">
    <div className="adm-fact-label">{label}</div>
    <div className="adm-fact-value">{value}</div>
    {sub && <div className="adm-fact-sub">{sub}</div>}
  </div>
);

const ReasonField: React.FC<{ value: string; onChange: (v: string) => void }> = ({ value, onChange }) => (
  <label className="adm-field">
    <span>理由(監査ログに残ります・3文字以上)</span>
    <textarea className="adm-input" rows={3} maxLength={500} value={value} onChange={(e) => onChange(e.target.value)} required />
  </label>
);
