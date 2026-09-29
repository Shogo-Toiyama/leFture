import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { adminApi, type AdminTicket, type TicketStatus } from '../../lib/admin';
import {
  Badge,
  Card,
  ErrorLine,
  Loading,
  PageHeader,
  Segmented,
  type Tone,
  fmtDateTime,
  fmtRelative,
  useAdminAction,
  useAdminQuery,
} from './adminUi';

const STATUS: { value: TicketStatus; label: string; tone: Tone }[] = [
  { value: 'open', label: '未対応', tone: 'warn' },
  { value: 'in_progress', label: '対応中', tone: 'info' },
  { value: 'resolved', label: '解決済', tone: 'good' },
  { value: 'closed', label: '終了', tone: 'neutral' },
];

type Filter = TicketStatus | 'all';

export const AdminSupportPage: React.FC = () => {
  const [filter, setFilter] = useState<Filter>('open');
  const q = useAdminQuery(() => adminApi.tickets(filter === 'all' ? null : filter), [filter]);
  const [openId, setOpenId] = useState<string | null>(null);

  return (
    <div className="adm-page">
      <PageHeader
        title="サポート"
        hint="本文はユーザーが運営宛てに書いたものなので表示してよい。メールは開示時に監査ログへ記録"
        right={
          <Segmented
            label="状態で絞り込み"
            options={[...STATUS.map((s) => ({ value: s.value as Filter, label: s.label })), { value: 'all' as Filter, label: 'すべて' }]}
            value={filter}
            onChange={setFilter}
          />
        }
      />
      <ErrorLine message={q.error} onRetry={q.reload} />
      {q.loading && !q.data && <Loading />}
      {q.data && (
        <Card>
          <div className="adm-tickets">
            {q.data.map((t) => (
              <TicketRow
                key={t.id}
                ticket={t}
                open={openId === t.id}
                onToggle={() => setOpenId(openId === t.id ? null : t.id)}
                onChanged={q.reload}
              />
            ))}
            {q.data.length === 0 && <p className="adm-empty">チケットはありません</p>}
          </div>
        </Card>
      )}
    </div>
  );
};

const TicketRow: React.FC<{ ticket: AdminTicket; open: boolean; onToggle: () => void; onChanged: () => void }> = ({
  ticket: t,
  open,
  onToggle,
  onChanged,
}) => {
  const [email, setEmail] = useState<string | null>(null);
  const reveal = useAdminAction();
  const update = useAdminAction();
  const st = STATUS.find((s) => s.value === t.status);

  return (
    <div className={`adm-ticket ${open ? 'is-open' : ''}`}>
      <button type="button" className="adm-ticket-row" aria-expanded={open} onClick={onToggle}>
        <span className="adm-mono adm-strong">{t.ticket_code}</span>
        <span className="adm-mono adm-muted">{t.user_email_masked ?? '—'}</span>
        <span className="adm-muted adm-mono">{t.category}</span>
        <span className={open ? 'adm-ticket-msg is-open' : 'adm-ticket-msg'}>{t.message}</span>
        <span className="adm-muted" title={fmtDateTime(t.created_at)}>
          {fmtRelative(t.created_at)}
        </span>
        <span>{st ? <Badge tone={st.tone}>{st.label}</Badge> : t.status}</span>
      </button>
      {open && (
        <div className="adm-ticket-detail">
          <p className="adm-ticket-full">{t.message}</p>
          <div className="adm-ticket-actions">
            <label className="adm-inline-field">
              <span className="adm-muted">状態</span>
              <select
                className="adm-input adm-select"
                value={t.status}
                disabled={update.busy}
                onChange={(e) =>
                  update.run(() => adminApi.setTicketStatus(t.id, e.target.value as TicketStatus)).then(onChanged)
                }
              >
                {STATUS.map((s) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </select>
            </label>
            {email ? (
              <span className="adm-mono adm-revealed">{email}</span>
            ) : (
              <button
                type="button"
                className="adm-btn adm-btn-sm"
                disabled={reveal.busy}
                onClick={() =>
                  reveal.run(() => adminApi.revealTicketEmail(t.id)).then((r) => r && setEmail(r.user_email))
                }
              >
                返信用にメールを開示(監査ログに記録)
              </button>
            )}
            {t.user_id && (
              <Link className="adm-link" to={`/admin/users?q=${t.user_id}`}>
                このユーザーを開く
              </Link>
            )}
            <span className="adm-muted">更新 {fmtDateTime(t.updated_at)}</span>
          </div>
          <ErrorLine message={reveal.error ?? update.error} />
        </div>
      )}
    </div>
  );
};
