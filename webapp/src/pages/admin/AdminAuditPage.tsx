import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { adminApi, type AdminAuditEntry } from '../../lib/admin';
import { Badge, Card, ErrorLine, Loading, PageHeader, type Tone, fmtDateTime, useAdminErrorHandler } from './adminUi';

const PAGE_SIZE = 100;

const ACTIONS: { value: string; tone: Tone }[] = [
  { value: 'user.email.reveal', tone: 'warn' },
  { value: 'support.email.reveal', tone: 'warn' },
  { value: 'credits.grant', tone: 'good' },
  { value: 'user.suspend', tone: 'critical' },
  { value: 'user.unsuspend', tone: 'info' },
  { value: 'user.delete', tone: 'critical' },
  { value: 'task.retry', tone: 'info' },
  { value: 'lecture.cancel_jobs', tone: 'warn' },
  { value: 'support.status', tone: 'neutral' },
];

const toneOf = (action: string): Tone => ACTIONS.find((a) => a.value === action)?.tone ?? 'neutral';

export const AdminAuditPage: React.FC = () => {
  const [params, setParams] = useSearchParams();
  const action = params.get('action') ?? '';
  const targetId = params.get('target_id') ?? '';
  const [targetInput, setTargetInput] = useState(targetId);
  const [rows, setRows] = useState<AdminAuditEntry[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [openId, setOpenId] = useState<number | null>(null);
  const handleError = useAdminErrorHandler();
  const seq = useRef(0);

  const setParam = useCallback(
    (key: string, value: string) => {
      const next = new URLSearchParams(params);
      if (value) next.set(key, value);
      else next.delete(key);
      setParams(next, { replace: true });
    },
    [params, setParams]
  );

  useEffect(() => setTargetInput(targetId), [targetId]);
  useEffect(() => {
    if (targetInput.trim() === targetId) return;
    const t = setTimeout(() => setParam('target_id', targetInput.trim()), 400);
    return () => clearTimeout(t);
  }, [targetInput, targetId, setParam]);

  const load = useCallback(
    (offset: number) => {
      const mine = ++seq.current;
      setLoading(true);
      setError(null);
      adminApi
        .auditLog({ action: action || undefined, target_id: targetId || undefined, limit: PAGE_SIZE, offset })
        .then((page) => {
          if (mine !== seq.current) return;
          setRows((prev) => (offset === 0 ? page : [...prev, ...page]));
          setHasMore(page.length === PAGE_SIZE);
        })
        .catch((e) => mine === seq.current && setError(handleError(e)))
        .finally(() => mine === seq.current && setLoading(false));
    },
    [action, targetId, handleError]
  );

  useEffect(() => load(0), [load]);

  return (
    <div className="adm-page">
      <PageHeader
        title="監査ログ"
        hint="追記専用(UPDATE/DELETEはDBトリガで拒否)。PIIの開示もここに残る"
        right={
          <div className="adm-filters">
            <select
              className="adm-input adm-select"
              value={action}
              onChange={(e) => setParam('action', e.target.value)}
              aria-label="action で絞り込み"
            >
              <option value="">すべての action</option>
              {ACTIONS.map((a) => (
                <option key={a.value} value={a.value}>
                  {a.value}
                </option>
              ))}
            </select>
            <input
              className="adm-input adm-mono"
              placeholder="target_id"
              value={targetInput}
              onChange={(e) => setTargetInput(e.target.value)}
              aria-label="target_id で絞り込み"
            />
          </div>
        }
      />
      <ErrorLine message={error} onRetry={() => load(0)} />
      <Card>
        <div className="adm-table-wrap">
          <table className="adm-table">
            <thead>
              <tr>
                <th>日時</th>
                <th>admin</th>
                <th>action</th>
                <th>target</th>
                <th>params</th>
                <th>result</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const open = openId === r.id;
                const params = JSON.stringify(r.params);
                return (
                  <React.Fragment key={r.id}>
                    <tr className="adm-row-click" onClick={() => setOpenId(open ? null : r.id)} aria-expanded={open}>
                      <td className="adm-mono adm-nowrap">{fmtDateTime(r.created_at)}</td>
                      <td className="adm-mono adm-muted">{r.admin_email ?? r.admin_user_id.slice(0, 8)}</td>
                      <td>
                        <Badge tone={toneOf(r.action)} icon={false}>
                          {r.action}
                        </Badge>
                      </td>
                      <td className="adm-mono adm-muted adm-nowrap">
                        {r.target_type}:{r.target_id ? r.target_id.slice(0, 8) : '—'}
                      </td>
                      <td className="adm-mono adm-muted adm-ellipsis">{params === '{}' ? '' : params}</td>
                      <td>
                        <Badge tone={r.result === 'ok' ? 'good' : 'critical'}>{r.result}</Badge>
                      </td>
                    </tr>
                    {open && (
                      <tr className="adm-row-detail">
                        <td colSpan={6}>
                          <dl className="adm-dl">
                            <dt>target</dt>
                            <dd className="adm-mono">
                              {r.target_type}:{r.target_id ?? '—'}{' '}
                              {r.target_type === 'user' && r.target_id && (
                                <Link className="adm-link" to={`/admin/users?q=${r.target_id}`}>
                                  ユーザーを開く
                                </Link>
                              )}
                            </dd>
                            <dt>params</dt>
                            <dd>
                              <pre className="adm-pre">{JSON.stringify(r.params, null, 2)}</pre>
                            </dd>
                            {r.error_message && (
                              <>
                                <dt>error</dt>
                                <dd className="adm-mono adm-em-critical">{r.error_message}</dd>
                              </>
                            )}
                            <dt>admin</dt>
                            <dd className="adm-mono">{r.admin_user_id}</dd>
                            <dt>ip / UA</dt>
                            <dd className="adm-mono adm-muted">
                              {r.ip ?? '—'} · {r.user_agent ?? '—'}
                            </dd>
                          </dl>
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                );
              })}
              {!loading && rows.length === 0 && (
                <tr>
                  <td colSpan={6} className="adm-empty">
                    記録はありません
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        {loading && <Loading />}
        {!loading && hasMore && (
          <button type="button" className="adm-btn adm-load-more" onClick={() => load(rows.length)}>
            さらに読み込む
          </button>
        )}
      </Card>
    </div>
  );
};
