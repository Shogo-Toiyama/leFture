import React, { Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { Navigate, NavLink, Outlet } from 'react-router-dom';
import { Activity, BarChart3, LayoutDashboard, LifeBuoy, ScrollText, ShieldCheck, Users } from 'lucide-react';
import { ApiError, extractErrorCode } from '../../lib/api';
import { adminApi, type AdminMe } from '../../lib/admin';
import { AdminMfaGate } from './AdminMfaGate';
import { AdminGateContext, ErrorLine, Loading } from './adminUi';
import './admin.css';

type Gate =
  | { kind: 'checking' }
  | { kind: 'ok'; me: AdminMe }
  | { kind: 'mfa'; stale: boolean }
  | { kind: 'denied' }
  | { kind: 'error'; message: string };

const NAV = [
  { to: '/admin', end: true, label: 'Overview', icon: LayoutDashboard },
  { to: '/admin/usage', label: '利用状況', icon: BarChart3 },
  { to: '/admin/pipeline', label: 'パイプライン', icon: Activity },
  { to: '/admin/users', label: 'ユーザー', icon: Users },
  { to: '/admin/support', label: 'サポート', icon: LifeBuoy },
  { to: '/admin/audit', label: '監査ログ', icon: ScrollText },
];

/**
 * /admin のシェル。ここでの出し分けはUXのためだけで、セキュリティ境界ではない
 * (境界はバックエンドの require_admin)。GET /admin/me の結果で:
 *   200 → 表示 / 403 MFA系 → TOTP入力 / 404・401 → 通常画面へ戻す
 */
export const AdminLayout: React.FC = () => {
  const [gate, setGate] = useState<Gate>({ kind: 'checking' });

  const check = useCallback(() => {
    setGate({ kind: 'checking' });
    adminApi
      .me()
      .then((me) => setGate({ kind: 'ok', me }))
      .catch((err) => {
        const code = extractErrorCode(err);
        if (code === 'ADMIN_MFA_REQUIRED' || code === 'ADMIN_MFA_STALE') {
          setGate({ kind: 'mfa', stale: code === 'ADMIN_MFA_STALE' });
        } else if (err instanceof ApiError && (err.status === 404 || err.status === 401)) {
          setGate({ kind: 'denied' });
        } else {
          setGate({ kind: 'error', message: err instanceof Error ? err.message : String(err) });
        }
      });
  }, []);

  useEffect(check, [check]);

  const ctx = useMemo(() => ({ requireMfa: () => setGate({ kind: 'mfa', stale: true }) }), []);

  if (gate.kind === 'denied') return <Navigate to="/" replace />;

  if (gate.kind === 'checking') {
    return (
      <div className="adm-root adm-gate">
        <Loading label="権限を確認しています…" />
      </div>
    );
  }

  if (gate.kind === 'mfa') {
    return (
      <div className="adm-root">
        <AdminMfaGate stale={gate.stale} onVerified={check} />
      </div>
    );
  }

  if (gate.kind === 'error') {
    return (
      <div className="adm-root adm-gate">
        <ErrorLine message={gate.message} onRetry={check} />
      </div>
    );
  }

  return (
    <AdminGateContext.Provider value={ctx}>
      <div className="adm-root adm-shell">
        <aside className="adm-sidebar">
          <div className="adm-brand">
            <span className="adm-brand-name">Lefture Admin</span>
            <span className="adm-muted">操作はすべて監査ログに記録されます</span>
          </div>
          <nav className="adm-nav" aria-label="Admin">
            {NAV.map(({ to, end, label, icon: Icon }) => (
              <NavLink key={to} to={to} end={end} className={({ isActive }) => `adm-nav-item ${isActive ? 'is-active' : ''}`}>
                <Icon size={16} />
                <span>{label}</span>
              </NavLink>
            ))}
          </nav>
          <div className="adm-sidebar-foot">
            <div className="adm-me" title={gate.me.user_id}>
              {gate.me.email ?? gate.me.user_id}
            </div>
            <div className="adm-mfa-ok">
              <ShieldCheck size={13} />
              MFA ({gate.me.aal ?? '—'})
            </div>
            <NavLink to="/" className="adm-link-btn">
              アプリに戻る
            </NavLink>
          </div>
        </aside>
        <main className="adm-main">
          <Suspense fallback={<Loading />}>
            <Outlet />
          </Suspense>
        </main>
      </div>
    </AdminGateContext.Provider>
  );
};
