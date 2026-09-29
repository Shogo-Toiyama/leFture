import React, { useState } from 'react';
import { adminApi, type AdminOverview, type AdminSeriesPoint } from '../../lib/admin';
import {
  Badge,
  BarChart,
  Card,
  ErrorLine,
  Loading,
  PageHeader,
  Segmented,
  fmtDateTime,
  fmtDec,
  fmtNum,
  fmtUsd,
  useAdminQuery,
} from './adminUi';

type Metric = keyof Omit<AdminSeriesPoint, 'date'>;

const METRICS: { value: Metric; label: string; fmt: (n: number) => string }[] = [
  { value: 'active_users', label: 'アクティブ', fmt: fmtNum },
  { value: 'signups', label: '新規登録', fmt: fmtNum },
  { value: 'lectures', label: '講義作成', fmt: fmtNum },
  { value: 'jobs_completed', label: 'ジョブ完了', fmt: fmtNum },
  { value: 'jobs_failed', label: 'ジョブ失敗', fmt: fmtNum },
  { value: 'credits_consumed', label: 'クレジット消費', fmt: fmtDec },
  { value: 'cost_usd', label: '原価($)', fmt: fmtUsd },
];

const DAYS = [
  { value: 7, label: '7日' },
  { value: 30, label: '30日' },
  { value: 90, label: '90日' },
  { value: 365, label: '365日' },
];

interface Tile {
  label: string;
  value: string;
  emphasis?: 'good' | 'warn' | 'critical' | 'info' | 'accent';
}

function groups(o: AdminOverview): { title: string; tiles: Tile[]; foot?: string }[] {
  return [
    {
      title: 'ユーザー',
      tiles: [
        { label: '総数', value: fmtNum(o.users.total) },
        { label: '新規 24h', value: fmtNum(o.users.new_24h) },
        { label: '新規 7日', value: fmtNum(o.users.new_7d) },
        { label: '新規 30日', value: fmtNum(o.users.new_30d) },
        { label: 'メール確認済', value: fmtNum(o.users.confirmed) },
        { label: '停止中', value: fmtNum(o.users.suspended), emphasis: o.users.suspended ? 'warn' : undefined },
      ],
    },
    {
      title: 'アクティブ',
      tiles: [
        { label: '開いた人 24h', value: fmtNum(o.active.active_24h) },
        { label: '開いた人 7日', value: fmtNum(o.active.active_7d) },
        { label: '開いた人 30日', value: fmtNum(o.active.active_30d) },
        { label: '講義作成 24h', value: fmtNum(o.active.created_lecture_24h), emphasis: 'info' },
        { label: '講義作成 7日', value: fmtNum(o.active.created_lecture_7d), emphasis: 'info' },
        { label: '講義作成 30日', value: fmtNum(o.active.created_lecture_30d), emphasis: 'info' },
      ],
      foot: 'user_activity_hours(10分おきのping)ベース。last_sign_in_at は使わない',
    },
    {
      title: '講義',
      tiles: [
        { label: '総数', value: fmtNum(o.lectures.total) },
        { label: 'ゴミ箱', value: fmtNum(o.lectures.trashed) },
        { label: '新規 24h', value: fmtNum(o.lectures.new_24h) },
        { label: '新規 7日', value: fmtNum(o.lectures.new_7d) },
        { label: '新規 30日', value: fmtNum(o.lectures.new_30d) },
        { label: '音声 30日', value: `${fmtDec(o.lectures.audio_hours_30d)}h` },
      ],
    },
    {
      title: 'ジョブ',
      tiles: [
        { label: '実行中', value: fmtNum(o.jobs.running), emphasis: 'info' },
        { label: '完了 24h', value: fmtNum(o.jobs.completed_24h) },
        { label: '失敗 24h', value: fmtNum(o.jobs.failed_24h), emphasis: o.jobs.failed_24h ? 'critical' : undefined },
        { label: '失敗 7日', value: fmtNum(o.jobs.failed_7d), emphasis: o.jobs.failed_7d ? 'warn' : undefined },
        { label: '総数 7日', value: fmtNum(o.jobs.total_7d) },
      ],
    },
    {
      title: 'クレジット',
      tiles: [
        { label: '消費 24h', value: fmtDec(o.credits.consumed_24h) },
        { label: '消費 30日', value: fmtDec(o.credits.consumed_30d) },
        { label: '付与 30日', value: fmtDec(o.credits.granted_30d) },
        { label: '未消化残高', value: fmtDec(o.credits.outstanding) },
      ],
    },
    {
      title: 'コスト & 収益(概算)',
      tiles: [
        { label: '原価 24h', value: fmtUsd(o.cost.usd_24h) },
        { label: '原価 30日', value: fmtUsd(o.cost.usd_30d) },
        { label: 'MRR 概算', value: fmtUsd(o.mrr_usd_estimate), emphasis: 'accent' },
      ],
      foot: '入金額の正は Stripe / App Store。ここはDB上の契約状態からの概算',
    },
    {
      title: 'サポート',
      tiles: [
        { label: '未対応', value: fmtNum(o.support.open), emphasis: o.support.open ? 'warn' : undefined },
        { label: '総数', value: fmtNum(o.support.total) },
      ],
    },
  ];
}

export const AdminOverviewPage: React.FC = () => {
  const [days, setDays] = useState(30);
  const [metric, setMetric] = useState<Metric>('active_users');
  const overview = useAdminQuery(() => adminApi.overview(), []);
  const series = useAdminQuery(() => adminApi.series(days), [days]);
  const plans = useAdminQuery(() => adminApi.plans(), []);

  const m = METRICS.find((x) => x.value === metric)!;
  const points = series.data ?? [];
  const labelEvery = Math.max(1, Math.ceil(points.length / 10));

  return (
    <div className="adm-page">
      <PageHeader
        title="Overview"
        hint={
          overview.data ? `集計時刻 ${fmtDateTime(overview.data.generated_at)} · 個人を跨ぐ生データは含まない` : undefined
        }
      />

      <ErrorLine message={overview.error} onRetry={overview.reload} />
      {overview.loading && !overview.data && <Loading />}
      {overview.data && (
        <div className="adm-kpi-grid">
          {groups(overview.data).map((g) => (
            <section key={g.title} className="adm-card adm-kpi-card">
              <h2 className="adm-kpi-title">{g.title}</h2>
              <div className="adm-kpi-tiles">
                {g.tiles.map((t) => (
                  <div key={t.label} className="adm-kpi-tile">
                    <div className={`adm-kpi-value adm-num ${t.emphasis ? `adm-em-${t.emphasis}` : ''}`}>{t.value}</div>
                    <div className="adm-kpi-label">{t.label}</div>
                  </div>
                ))}
              </div>
              {g.foot && <p className="adm-kpi-foot">{g.foot}</p>}
            </section>
          ))}
        </div>
      )}

      <Card
        title={`日次推移: ${m.label}`}
        hint={`過去${days}日 (UTC日付)`}
        right={<Segmented label="期間" options={DAYS} value={days} onChange={setDays} small />}
      >
        <Segmented label="指標" options={METRICS} value={metric} onChange={setMetric} small />
        <ErrorLine message={series.error} onRetry={series.reload} />
        {series.loading && !series.data ? (
          <Loading />
        ) : (
          <BarChart
            ariaLabel={`日次の${m.label}`}
            height={180}
            showEveryNthLabel={labelEvery}
            data={points.map((p) => ({
              key: p.date,
              label: p.date.slice(5),
              value: p[metric],
              tooltip: (
                <>
                  <strong>{p.date}</strong>
                  <span>
                    {m.label}: {m.fmt(p[metric])}
                  </span>
                </>
              ),
            }))}
          />
        )}
      </Card>

      <Card title="プラン別契約">
        <ErrorLine message={plans.error} onRetry={plans.reload} />
        {plans.data && (
          <div className="adm-table-wrap">
            <table className="adm-table">
              <thead>
                <tr>
                  <th>プラン</th>
                  <th className="adm-right">価格</th>
                  <th>課金間隔</th>
                  <th>claim_mode</th>
                  <th className="adm-right">有効契約</th>
                  <th className="adm-right">非アクティブ</th>
                </tr>
              </thead>
              <tbody>
                {plans.data.map((p) => (
                  <tr key={p.plan_id}>
                    <td>
                      {p.name} {p.disabled && <Badge tone="neutral">disabled</Badge>}
                    </td>
                    <td className="adm-right adm-num">{fmtUsd(p.price_usd)}</td>
                    <td className="adm-muted">{p.billing_interval_months ? `${p.billing_interval_months}ヶ月` : '—'}</td>
                    <td className="adm-muted adm-mono">{p.claim_mode}</td>
                    <td className="adm-right adm-num">{fmtNum(p.active)}</td>
                    <td className="adm-right adm-num adm-muted">{fmtNum(p.inactive)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
};
