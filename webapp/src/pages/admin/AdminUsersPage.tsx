import React, { useCallback, useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { ChevronDown, Search } from 'lucide-react';
import { adminApi, type AdminUserRow } from '../../lib/admin';
import { AdminUserDetail } from './AdminUserDetail';
import { Badge, ErrorLine, Loading, PageHeader, fmtDateTime, fmtNum, fmtRelative, useAdminErrorHandler } from './adminUi';

const PAGE_SIZE = 50;

export const AdminUsersPage: React.FC = () => {
  const [params, setParams] = useSearchParams();
  const urlQuery = params.get('q') ?? '';
  const [input, setInput] = useState(urlQuery);
  const [rows, setRows] = useState<AdminUserRow[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  const handleError = useAdminErrorHandler();
  const seq = useRef(0);

  // 入力は300ms待ってからURLへ(URLが検索条件の正。監査ログからのリンクもここに入る)
  useEffect(() => {
    if (input === urlQuery) return;
    const t = setTimeout(() => setParams(input ? { q: input } : {}, { replace: true }), 300);
    return () => clearTimeout(t);
  }, [input, urlQuery, setParams]);

  useEffect(() => setInput(urlQuery), [urlQuery]);

  const load = useCallback(
    (offset: number) => {
      const mine = ++seq.current;
      setLoading(true);
      setError(null);
      adminApi
        .users(urlQuery.trim(), PAGE_SIZE, offset)
        .then((page) => {
          if (mine !== seq.current) return;
          setRows((prev) => (offset === 0 ? page : [...prev, ...page]));
          setHasMore(page.length === PAGE_SIZE);
          // IDで1件だけ当たったときは最初から開いておく
          if (offset === 0 && page.length === 1 && page[0].user_id === urlQuery.trim()) setExpanded(page[0].user_id);
        })
        .catch((e) => mine === seq.current && setError(handleError(e)))
        .finally(() => mine === seq.current && setLoading(false));
    },
    [urlQuery, handleError]
  );

  useEffect(() => load(0), [load]);

  const patchRow = (id: string, patch: Partial<AdminUserRow>) =>
    setRows((prev) => prev.map((r) => (r.user_id === id ? { ...r, ...patch } : r)));
  const removeRow = (id: string) => {
    setRows((prev) => prev.filter((r) => r.user_id !== id));
    setExpanded(null);
  };

  return (
    <div className="adm-page">
      <PageHeader
        title="ユーザー"
        hint="行をクリックすると詳細が開きます。メールは常にマスク済み(開示は監査ログに残ります)"
        right={
          <label className="adm-search">
            <Search size={14} />
            <input
              className="adm-input"
              placeholder="email / username / user_id"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              aria-label="ユーザー検索"
            />
          </label>
        }
      />

      <ErrorLine message={error} onRetry={() => load(0)} />

      <div className="adm-user-list">
        <div className="adm-user-row adm-user-row-head" aria-hidden="true">
          <span>メール</span>
          <span>username</span>
          <span>プラン</span>
          <span className="adm-right">講義</span>
          <span>最終利用</span>
          <span>状態</span>
          <span />
        </div>
        {rows.map((u) => {
          const open = expanded === u.user_id;
          return (
            <div key={u.user_id} className={`adm-user ${open ? 'is-open' : ''}`}>
              <button
                type="button"
                className="adm-user-row"
                aria-expanded={open}
                onClick={() => setExpanded(open ? null : u.user_id)}
              >
                <span className="adm-mono adm-strong">{u.email_masked ?? '(メールなし)'}</span>
                <span className="adm-muted">{u.username ?? '—'}</span>
                <span className="adm-muted">{u.plan_name ?? 'なし'}</span>
                <span className="adm-right adm-num">{fmtNum(u.lecture_count)}</span>
                <span title={u.last_active_at ? fmtDateTime(u.last_active_at) : undefined}>
                  {fmtRelative(u.last_active_at)}
                </span>
                <span className="adm-badges">
                  {u.suspended && <Badge tone="warn">停止中</Badge>}
                  {!u.confirmed && <Badge tone="neutral">未確認</Badge>}
                </span>
                <ChevronDown size={16} className="adm-chevron" />
              </button>
              {open && (
                <AdminUserDetail
                  userId={u.user_id}
                  onSuspendedChange={(s) => patchRow(u.user_id, { suspended: s })}
                  onDeleted={() => removeRow(u.user_id)}
                />
              )}
            </div>
          );
        })}
        {!loading && rows.length === 0 && !error && <p className="adm-empty">該当するユーザーはいません</p>}
      </div>

      {loading && <Loading />}
      {!loading && hasMore && (
        <button type="button" className="adm-btn adm-load-more" onClick={() => load(rows.length)}>
          さらに読み込む
        </button>
      )}
    </div>
  );
};
