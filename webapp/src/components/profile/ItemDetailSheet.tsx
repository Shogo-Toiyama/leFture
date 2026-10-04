import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Pencil, Trash2, XCircle } from 'lucide-react';
import { AdaptiveSheet } from '../modals/AdaptiveSheet';
import { ConfirmModal } from '../modals/ConfirmModal';
import { useLanguage } from '../../i18n/LanguageContext';
import { selfPortraitApi, shortDate, type ItemDetail, type ProfileItem } from '../../lib/selfPortrait';

type Mode = 'view' | 'edit' | 'reject';

const ITEM_MAX_CHARS = 500;

/**
 * 自分像の項目を開いたとき: 根拠になった会話(本人の言葉)・書き直しの変化・
 * 「直す / 違う / 残したくない」(確認待ちの項目なら「残す / 残さない」)。
 */
export const ItemDetailSheet: React.FC<{
  itemId: string | null;
  item: ProfileItem | null;
  categoryLabel: string;
  onClose: () => void;
  onChanged: () => Promise<void>;
}> = ({ itemId, item, categoryLabel, onClose, onChanged }) => {
  const { t, locale } = useLanguage();
  const [detail, setDetail] = useState<ItemDetail | null>(null);
  const [mode, setMode] = useState<Mode>('view');
  const [draft, setDraft] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmDiscard, setConfirmDiscard] = useState(false);

  useEffect(() => {
    setDetail(null);
    setMode('view');
    setReason('');
    setError(null);
    if (!itemId) return;
    let cancelled = false;
    selfPortraitApi.item(itemId)
      .then((d) => { if (!cancelled) setDetail(d); })
      .catch(() => { if (!cancelled) setError(t('spLoadError')); });
    return () => { cancelled = true; };
  }, [itemId, t]);

  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      await onChanged();
      onClose();
    } catch {
      setError(t('spActionFailed'));
    } finally {
      setBusy(false);
    }
  };

  const isPending = item?.status === 'pending_confirm';
  const content = detail?.item.content ?? item?.content ?? '';

  return (
    <>
      <AdaptiveSheet open={itemId !== null} onClose={onClose} title={categoryLabel}>
        <div className="sp-sheet">
          <p className="sp-sheet-content">{content}</p>
          {detail?.item.origin === 'user' && <span className="sp-sheet-origin">{t('spEditedByYou')}</span>}
          {error && <p className="auth-error">{error}</p>}

          {mode === 'edit' && (
            <form
              className="sp-inline-form"
              onSubmit={(e) => {
                e.preventDefault();
                const next = draft.trim();
                if (!next || next === content || !itemId) return;
                void run(() => selfPortraitApi.edit(itemId, next));
              }}
            >
              <label htmlFor="sp-edit-text" className="sheet-field-label">{t('spActionEdit')}</label>
              <textarea
                id="sp-edit-text"
                className="sheet-textarea"
                rows={4}
                maxLength={ITEM_MAX_CHARS}
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
              />
              <p className="sheet-field-hint">{t('spActionEditHint')}</p>
              <div className="sp-inline-actions">
                <button type="submit" className="btn btn-primary" disabled={busy || !draft.trim() || draft.trim() === content}>
                  {busy ? t('saving') : t('save')}
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => setMode('view')}>{t('cancel')}</button>
              </div>
            </form>
          )}

          {mode === 'reject' && (
            <form
              className="sp-inline-form"
              onSubmit={(e) => {
                e.preventDefault();
                if (itemId) void run(() => selfPortraitApi.reject(itemId, reason.trim()));
              }}
            >
              <label htmlFor="sp-reject-reason" className="sheet-field-label">{t('spRejectReasonLabel')}</label>
              <textarea
                id="sp-reject-reason"
                className="sheet-textarea"
                rows={3}
                maxLength={ITEM_MAX_CHARS}
                placeholder={t('spRejectReasonPlaceholder')}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />
              <p className="sheet-field-hint">{t('spActionRejectHint')}</p>
              <div className="sp-inline-actions">
                <button type="submit" className="btn btn-primary" disabled={busy}>{t('spActionReject')}</button>
                <button type="button" className="btn btn-ghost" onClick={() => setMode('view')}>{t('cancel')}</button>
              </div>
            </form>
          )}

          {mode === 'view' && (
            isPending ? (
              <div className="sp-pending-actions">
                <p className="sheet-field-hint">{t('spPendingNotice')}</p>
                <div className="sp-inline-actions">
                  <button type="button" className="btn btn-primary" disabled={busy} onClick={() => itemId && run(() => selfPortraitApi.keep(itemId))}>{t('spKeep')}</button>
                  <button type="button" className="btn btn-ghost" disabled={busy} onClick={() => itemId && run(() => selfPortraitApi.discard(itemId))}>{t('spDontKeep')}</button>
                </div>
              </div>
            ) : (
              <div className="sp-actions">
                <button type="button" className="sp-action" onClick={() => { setDraft(content); setMode('edit'); }}>
                  <Pencil size={18} className="sp-action-icon is-gold" />
                  <span><span className="sp-action-title">{t('spActionEdit')}</span><span className="sp-action-hint">{t('spActionEditHint')}</span></span>
                </button>
                <button type="button" className="sp-action" onClick={() => setMode('reject')}>
                  <XCircle size={18} className="sp-action-icon" />
                  <span><span className="sp-action-title">{t('spActionReject')}</span><span className="sp-action-hint">{t('spActionRejectHint')}</span></span>
                </button>
                <button type="button" className="sp-action is-danger" onClick={() => setConfirmDiscard(true)}>
                  <Trash2 size={18} className="sp-action-icon" />
                  <span><span className="sp-action-title">{t('spActionDiscard')}</span><span className="sp-action-hint">{t('spActionDiscardHint')}</span></span>
                </button>
              </div>
            )
          )}

          {detail && detail.evidence.length > 0 && (
            <section className="sp-sheet-section">
              <h3 className="sp-sheet-heading">{t('spEvidenceSection')}</h3>
              {detail.evidence.map((ev) => (
                <Link key={ev.observation_id} to={`/chat/${ev.thread_id}`} className="sp-evidence" onClick={onClose}>
                  <span className="sp-evidence-meta">
                    <span>{ev.thread_title || t('chatThreadUntitled')} · {shortDate(ev.observed_at, locale)}</span>
                    <span className="sp-evidence-open">{t('spOpenChat')}</span>
                  </span>
                  <span className="sp-evidence-text">{ev.quote ? t('spQuote', { text: ev.quote }) : ev.note}</span>
                </Link>
              ))}
            </section>
          )}

          {detail && detail.versions.length > 0 && (
            <section className="sp-sheet-section">
              <h3 className="sp-sheet-heading">{t('spHistorySection')}</h3>
              {detail.versions.map((v) => (
                <p key={v.replaced_at} className="sp-version">
                  {t('spUntil', { date: shortDate(v.replaced_at, locale) })}{v.content}
                </p>
              ))}
            </section>
          )}
        </div>
      </AdaptiveSheet>

      <ConfirmModal
        open={confirmDiscard}
        onClose={() => setConfirmDiscard(false)}
        onConfirm={() => {
          setConfirmDiscard(false);
          if (itemId) void run(() => selfPortraitApi.discard(itemId));
        }}
        title={t('spDiscardConfirmTitle')}
        message={t('spDiscardConfirmMessage')}
        confirmLabel={t('spDiscardConfirmButton')}
        cancelLabel={t('cancel')}
        isDanger
      />
    </>
  );
};
