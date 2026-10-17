import React, { useEffect, useState } from 'react';
import { X } from 'lucide-react';
import { useLanguage } from '../i18n/LanguageContext';
import type { TranslationKey } from '../i18n/translations';
import { submitSupportTicket, type SupportCategory } from '../lib/support';

const CATEGORY_LABEL_KEYS: Record<SupportCategory, TranslationKey> = {
  bug: 'reportCategoryBug',
  feature_request: 'reportCategoryFeedback',
  account: 'reportCategoryAccount',
  other: 'reportCategoryOther',
  inappropriate: 'reportCategoryInappropriate',
  incorrect: 'reportCategoryIncorrect',
};

/** 管理者宛のメール(device_info)が長くなりすぎないよう、添付する本文の上限 */
const MAX_ATTACHED_CHARS = 4000;
const MAX_MESSAGE_CHARS = 2000;

export interface ReportAttachmentSection {
  heading: string;
  text: string;
}

interface ReportSheetProps {
  title: string;
  /** 選べる種類(先頭が初期値) */
  categories: SupportCategory[];
  /** いつも一緒に送る識別情報(どの画面の何についてか)。ユーザーの本文ではない。 */
  context: Record<string, unknown>;
  /** 任意で添える本文。チェックを入れたときだけ送り、内容はプレビューで見せる。 */
  attachment?: { label: string; sections: ReportAttachmentSection[] };
  onClose: () => void;
}

/**
 * 画面を問わない「問題を報告」シート。お問い合わせと同じ /support/submit に、同じ形式で送る
 * (受付コード・確認メール・管理者への通知もお問い合わせと同じ)。どこの何についての報告かは
 * contextとして device_info.report に入る。チャットの回答に限らず、contextとattachmentを変えれば使える。
 *
 * 枠(背景・カード・見出し・閉じるボタン)は引用モーダルのクラスを借り、中身の色は currentColor 基準にして、
 * ダーク/ライト(.is-paper)のどちらの親の中でも読める。
 */
export const ReportSheet: React.FC<ReportSheetProps> = ({ title, categories, context, attachment, onClose }) => {
  const { t } = useLanguage();
  const [category, setCategory] = useState<SupportCategory>(categories[0] ?? 'other');
  const [message, setMessage] = useState('');
  const [attach, setAttach] = useState(Boolean(attachment));
  const [state, setState] = useState<'editing' | 'sending' | 'sent' | 'failed'>('editing');
  const [ticketCode, setTicketCode] = useState('');

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && state !== 'sending') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose, state]);

  const trimmed = message.trim();
  const canSend = trimmed.length > 0 && state !== 'sending';

  const submit = async () => {
    if (!canSend) return;
    setState('sending');
    try {
      const sections =
        attachment && attach
          ? attachment.sections.map((s) => ({ heading: s.heading, text: s.text.slice(0, MAX_ATTACHED_CHARS) }))
          : undefined;
      const code = await submitSupportTicket(category, trimmed, {
        ...context,
        ...(sections ? { attached: sections } : {}),
      });
      setTicketCode(code);
      setState('sent');
    } catch {
      setState('failed');
    }
  };

  return (
    <div className="citation-modal-backdrop" onClick={state === 'sending' ? undefined : onClose}>
      <div
        className="citation-modal-card report-sheet"
        role="dialog"
        aria-label={title}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="citation-modal-grab-bar" aria-hidden="true">
          <span className="citation-modal-grab-handle" />
        </div>
        <div className="citation-modal-header">
          <div className="citation-modal-title-group">
            <h3 className="citation-modal-title">{state === 'sent' ? t('reportSentTitle') : title}</h3>
          </div>
          <button type="button" className="citation-modal-close-btn" onClick={onClose} aria-label={t('chatClose')}>
            <X size={18} />
          </button>
        </div>

        {state === 'sent' ? (
          <div className="report-body">
            <p className="report-sent">{t('reportSentBody', { code: ticketCode })}</p>
            <div className="report-actions">
              <button type="button" className="report-btn is-primary" onClick={onClose}>
                {t('chatClose')}
              </button>
            </div>
          </div>
        ) : (
          <form
            className="report-body"
            onSubmit={(event) => {
              event.preventDefault();
              void submit();
            }}
          >
            <fieldset className="report-field" disabled={state === 'sending'}>
              <legend>{t('reportCategoryLabel')}</legend>
              <div className="report-chips">
                {categories.map((c) => (
                  <label key={c} className={`report-chip ${category === c ? 'is-active' : ''}`}>
                    <input
                      type="radio"
                      name="report-category"
                      value={c}
                      checked={category === c}
                      onChange={() => setCategory(c)}
                    />
                    {t(CATEGORY_LABEL_KEYS[c])}
                  </label>
                ))}
              </div>
            </fieldset>

            <label className="report-field">
              <span className="report-legend">{t('reportMessageLabel')}</span>
              <textarea
                className="report-textarea"
                value={message}
                maxLength={MAX_MESSAGE_CHARS}
                rows={5}
                placeholder={t('reportMessagePlaceholder')}
                disabled={state === 'sending'}
                onChange={(event) => setMessage(event.target.value)}
                autoFocus
              />
            </label>

            {attachment && (
              <div className="report-field">
                <label className="report-check">
                  <input
                    type="checkbox"
                    checked={attach}
                    disabled={state === 'sending'}
                    onChange={(event) => setAttach(event.target.checked)}
                  />
                  {attachment.label}
                </label>
                {attach && (
                  <details className="report-preview">
                    <summary>{t('reportAttachPreview')}</summary>
                    {attachment.sections.map((section) => (
                      <div key={section.heading} className="report-preview-section">
                        <strong>{section.heading}</strong>
                        <p>{section.text.slice(0, MAX_ATTACHED_CHARS)}</p>
                      </div>
                    ))}
                  </details>
                )}
              </div>
            )}

            <p className="report-note">{t('reportAutoNote')}</p>
            {state === 'failed' && (
              <p className="report-error" role="alert">
                {t('reportFailed')}
              </p>
            )}

            <div className="report-actions">
              <button type="submit" className="report-btn is-primary" disabled={!canSend}>
                {state === 'sending' ? t('reportSending') : t('reportSubmit')}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
};
