import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { AlertCircle, CheckCircle2, Clock, Loader2, MinusCircle, XCircle } from 'lucide-react';
import { ApiError, extractErrorCode } from '../../lib/api';

// ---------------------------------------------------------------------------
// MFAの再認証要求をページからレイアウトへ伝える
// ---------------------------------------------------------------------------
export const MFA_ERROR_CODES = ['ADMIN_MFA_REQUIRED', 'ADMIN_MFA_STALE'];

export const AdminGateContext = createContext<{ requireMfa: () => void }>({ requireMfa: () => {} });

export function useAdminErrorHandler() {
  const { requireMfa } = useContext(AdminGateContext);
  return useCallback(
    (err: unknown): string => {
      const code = extractErrorCode(err);
      if (code && MFA_ERROR_CODES.includes(code)) requireMfa();
      if (err instanceof ApiError) return err.message;
      return err instanceof Error ? err.message : String(err);
    },
    [requireMfa]
  );
}

export function useAdminQuery<T>(fetcher: () => Promise<T>, deps: React.DependencyList) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const handleError = useAdminErrorHandler();
  const seq = useRef(0);

  const load = useCallback(() => {
    const mine = ++seq.current;
    setLoading(true);
    setError(null);
    fetcher()
      .then((d) => {
        if (mine === seq.current) setData(d);
      })
      .catch((e) => {
        if (mine === seq.current) setError(handleError(e));
      })
      .finally(() => {
        if (mine === seq.current) setLoading(false);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(load, [load]);
  return { data, error, loading, reload: load };
}

/** 操作ボタン用: 実行中フラグとエラーを持ち、成功時にonDoneを呼ぶ。 */
export function useAdminAction() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const handleError = useAdminErrorHandler();
  const run = useCallback(
    async <T,>(fn: () => Promise<T>): Promise<T | undefined> => {
      setBusy(true);
      setError(null);
      try {
        return await fn();
      } catch (e) {
        setError(handleError(e));
        return undefined;
      } finally {
        setBusy(false);
      }
    },
    [handleError]
  );
  return { busy, error, run, setError };
}

// ---------------------------------------------------------------------------
// フォーマッタ
// ---------------------------------------------------------------------------
const nf = new Intl.NumberFormat('ja-JP');
const nf2 = new Intl.NumberFormat('ja-JP', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const fmtNum = (n: number | null | undefined) => (n == null ? '—' : nf.format(n));
export const fmtDec = (n: number | null | undefined) => (n == null ? '—' : nf2.format(n));
export const fmtUsd = (n: number | null | undefined) => (n == null ? '—' : `$${nf2.format(n)}`);
export const microToCredits = (micro: number | null | undefined) => (micro == null ? null : micro / 1_000_000);

export function fmtDateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

export function fmtDate(iso: string | null | undefined): string {
  return iso ? fmtDateTime(iso).slice(0, 10) : '—';
}

export function fmtRelative(iso: string | null | undefined): string {
  if (!iso) return '—';
  const sec = (Date.now() - new Date(iso).getTime()) / 1000;
  if (sec < 60) return 'たった今';
  if (sec < 3600) return `${Math.floor(sec / 60)}分前`;
  if (sec < 86400) return `${Math.floor(sec / 3600)}時間前`;
  if (sec < 86400 * 60) return `${Math.floor(sec / 86400)}日前`;
  return fmtDate(iso);
}

export function fmtDuration(seconds: number | null | undefined): string {
  if (seconds == null) return '—';
  const m = Math.round(seconds / 60);
  return m < 60 ? `${m}分` : `${Math.floor(m / 60)}時間${m % 60}分`;
}

export const shortId = (id: string | null | undefined) => (id ? `${id.slice(0, 8)}…` : '—');

// ---------------------------------------------------------------------------
// 状態バッジ(色だけに頼らず、必ずアイコン+ラベル)
// ---------------------------------------------------------------------------
export type Tone = 'good' | 'warn' | 'critical' | 'info' | 'neutral';

const TONE_ICON: Record<Tone, React.ComponentType<{ size?: number }>> = {
  good: CheckCircle2,
  warn: AlertCircle,
  critical: XCircle,
  info: Loader2,
  neutral: MinusCircle,
};

export const Badge: React.FC<{ tone: Tone; children: React.ReactNode; icon?: boolean }> = ({
  tone,
  children,
  icon = true,
}) => {
  const Icon = TONE_ICON[tone];
  return (
    <span className={`adm-badge adm-tone-${tone}`}>
      {icon && <Icon size={12} />}
      {children}
    </span>
  );
};

export function jobStatusTone(status: string | null | undefined): Tone {
  switch (status) {
    case 'COMPLETED':
      return 'good';
    case 'FAILED':
    case 'ERROR':
      return 'critical';
    case 'CANCELLED':
      return 'neutral';
    case null:
    case undefined:
      return 'neutral';
    default:
      return 'info';
  }
}

export const isJobInFlight = (status: string | null | undefined) =>
  !!status && !['COMPLETED', 'FAILED', 'ERROR', 'CANCELLED'].includes(status);

export const PendingIcon = Clock;

// ---------------------------------------------------------------------------
// レイアウト部品
// ---------------------------------------------------------------------------
export const PageHeader: React.FC<{ title: string; hint?: React.ReactNode; right?: React.ReactNode }> = ({
  title,
  hint,
  right,
}) => (
  <div className="adm-page-header">
    <div>
      <h1 className="adm-page-title">{title}</h1>
      {hint && <p className="adm-page-hint">{hint}</p>}
    </div>
    {right && <div className="adm-page-header-right">{right}</div>}
  </div>
);

export const Card: React.FC<{
  title?: React.ReactNode;
  hint?: React.ReactNode;
  right?: React.ReactNode;
  className?: string;
  children: React.ReactNode;
}> = ({ title, hint, right, className, children }) => (
  <section className={`adm-card ${className ?? ''}`}>
    {(title || right) && (
      <div className="adm-card-head">
        <h2 className="adm-card-title">
          {title}
          {hint && <span className="adm-card-hint"> — {hint}</span>}
        </h2>
        {right}
      </div>
    )}
    {children}
  </section>
);

export function Segmented<T extends string | number>({
  options,
  value,
  onChange,
  small,
  label,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
  small?: boolean;
  label: string;
}) {
  return (
    <div className={`adm-segmented ${small ? 'adm-segmented-sm' : ''}`} role="group" aria-label={label}>
      {options.map((o) => (
        <button
          key={String(o.value)}
          type="button"
          className={`adm-chip ${o.value === value ? 'is-on' : ''}`}
          aria-pressed={o.value === value}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export const ErrorLine: React.FC<{ message: string | null; onRetry?: () => void }> = ({ message, onRetry }) =>
  message ? (
    <div className="adm-error" role="alert">
      <AlertCircle size={14} />
      <span>{message}</span>
      {onRetry && (
        <button type="button" className="adm-link-btn" onClick={onRetry}>
          再読み込み
        </button>
      )}
    </div>
  ) : null;

export const Loading: React.FC<{ label?: string }> = ({ label = '読み込み中…' }) => (
  <div className="adm-loading" aria-busy="true">
    <Loader2 size={16} className="adm-spin" />
    {label}
  </div>
);

// ---------------------------------------------------------------------------
// 棒グラフ(単一系列・1軸)。ホバーで値のツールチップ。
// ---------------------------------------------------------------------------
export interface BarDatum {
  key: string;
  label: string;
  value: number;
  tooltip: React.ReactNode;
  /** 0..1。系列内の強弱(例: engagement)を濃淡で重ねたいときだけ使う */
  intensity?: number;
}

export const BarChart: React.FC<{
  data: BarDatum[];
  height?: number;
  ariaLabel: string;
  showEveryNthLabel?: number;
  color?: string;
}> = ({ data, height = 160, ariaLabel, showEveryNthLabel = 1, color = 'var(--adm-series)' }) => {
  const [hover, setHover] = useState<number | null>(null);
  const max = Math.max(1, ...data.map((d) => d.value));
  return (
    <div className="adm-chart" aria-label={ariaLabel} role="figure">
      <div className="adm-chart-plot" style={{ height }} onMouseLeave={() => setHover(null)}>
        {data.map((d, i) => {
          const h = d.value === 0 ? 0 : Math.max(3, (d.value / max) * (height - 8));
          return (
            <div
              key={d.key}
              className={`adm-chart-col ${hover === i ? 'is-hover' : ''}`}
              onMouseEnter={() => setHover(i)}
              onFocus={() => setHover(i)}
              onBlur={() => setHover(null)}
              tabIndex={0}
              aria-label={`${d.label}: ${d.value}`}
            >
              <div
                className="adm-chart-bar"
                style={{
                  height: h,
                  background: color,
                  opacity: d.intensity == null ? 1 : 0.3 + d.intensity * 0.7,
                }}
              />
              {hover === i && <div className="adm-tooltip">{d.tooltip}</div>}
            </div>
          );
        })}
      </div>
      <div className="adm-chart-axis">
        {data.map((d, i) => (
          <span key={d.key} className="adm-chart-tick">
            {i % showEveryNthLabel === 0 ? d.label : ''}
          </span>
        ))}
      </div>
    </div>
  );
};

/** 横棒(カテゴリの大小比較)。ラベルと値を直接書くので色は1色。 */
export const HBarList: React.FC<{ rows: { key: string; label: string; value: number; sub?: string }[] }> = ({
  rows,
}) => {
  const max = Math.max(1, ...rows.map((r) => r.value));
  return (
    <div className="adm-hbars">
      {rows.map((r) => (
        <div key={r.key} className="adm-hbar-row">
          <span className="adm-hbar-label">{r.label}</span>
          <span className="adm-hbar-track">
            <span className="adm-hbar-fill" style={{ width: `${(r.value / max) * 100}%` }} />
          </span>
          <span className="adm-hbar-value adm-num">
            {fmtNum(r.value)}
            {r.sub && <span className="adm-muted"> {r.sub}</span>}
          </span>
        </div>
      ))}
    </div>
  );
};
