import React, { useState } from 'react';
import { adminApi } from '../../lib/admin';
import { BarChart, Card, ErrorLine, HBarList, Loading, PageHeader, Segmented, fmtNum, useAdminQuery } from './adminUi';

const DAYS = [
  { value: 7, label: '7日' },
  { value: 30, label: '30日' },
  { value: 90, label: '90日' },
];

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

function tzLabel(offsetMinutes: number): string {
  const sign = offsetMinutes >= 0 ? '+' : '−';
  const abs = Math.abs(offsetMinutes);
  const h = Math.floor(abs / 60);
  const m = abs % 60;
  return `UTC${sign}${h}${m ? `:${String(m).padStart(2, '0')}` : ''}`;
}

export const AdminUsagePage: React.FC = () => {
  const [days, setDays] = useState(30);
  const [clock, setClock] = useState<'local' | 'utc'>('local');
  const q = useAdminQuery(() => adminApi.hourly(days), [days]);
  const d = q.data;

  const hours = d ? d[clock] : [];
  const maxEng = Math.max(1, ...hours.map((h) => h.engagement));

  return (
    <div className="adm-page">
      <PageHeader
        title="利用状況"
        hint="時間帯は基本 local で見る。UTCで集計すると地域が混ざって分布が潰れる"
        right={<Segmented label="期間" options={DAYS} value={days} onChange={setDays} />}
      />
      <ErrorLine message={q.error} onRetry={q.reload} />
      {q.loading && !d && <Loading />}

      {d && (
        <>
          <Card
            title="時間帯別"
            hint={clock === 'local' ? '利用者それぞれのローカル時刻' : 'UTC'}
            right={
              <Segmented
                label="時刻の基準"
                small
                options={[
                  { value: 'local', label: 'local' },
                  { value: 'utc', label: 'utc' },
                ]}
                value={clock}
                onChange={setClock}
              />
            }
          >
            <BarChart
              ariaLabel="時間帯別のユニークユーザー数"
              height={170}
              showEveryNthLabel={3}
              data={hours.map((h) => ({
                key: String(h.hour),
                label: `${h.hour}時`,
                value: h.users,
                intensity: h.engagement / maxEng,
                tooltip: (
                  <>
                    <strong>{h.hour}:00〜</strong>
                    <span>ユーザー {fmtNum(h.users)}人</span>
                    <span>engagement {fmtNum(h.engagement)}</span>
                  </>
                ),
              }))}
            />
            <div className="adm-legend">
              <span>棒の高さ = ユニークユーザー数</span>
              <span className="adm-legend-ramp" aria-hidden="true" />
              <span>濃さ = engagement(ping数。1時間フルに使うと6)</span>
            </div>
            {clock === 'local' && (
              <p className="adm-kpi-foot">platform = unknown(バックフィルの推定値)はタイムゾーン不明のため local から除外</p>
            )}
          </Card>

          <div className="adm-grid-2">
            <Card title="曜日別" hint="local">
              <BarChart
                ariaLabel="曜日別のユニークユーザー数"
                height={120}
                data={d.by_weekday.map((w) => ({
                  key: String(w.weekday),
                  label: WEEKDAYS[w.weekday],
                  value: w.users,
                  tooltip: (
                    <>
                      <strong>{WEEKDAYS[w.weekday]}曜日</strong>
                      <span>ユーザー {fmtNum(w.users)}人</span>
                    </>
                  ),
                }))}
              />
            </Card>

            <Card title="プラットフォーム別">
              <HBarList
                rows={d.by_platform.map((p) => ({
                  key: p.platform,
                  label: p.platform,
                  value: p.users,
                  sub: `人 · ${fmtNum(p.hours)}時間枠`,
                }))}
              />
              <p className="adm-kpi-foot">unknown = マイグレーション時に埋めた推定値(実測ではない)</p>
            </Card>
          </div>

          <Card title="タイムゾーン分布" hint="利用者の地理的な広がりの目安">
            <HBarList
              rows={[...d.by_tz_offset]
                .sort((a, b) => b.users - a.users)
                .map((t) => ({ key: String(t.offset_minutes), label: tzLabel(t.offset_minutes), value: t.users, sub: '人' }))}
            />
          </Card>
        </>
      )}
    </div>
  );
};
