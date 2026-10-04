import React, { useEffect, useRef, useState } from 'react';
import { AlertCircle, Paperclip, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import type { ChatAttachment, ChatAttachmentSection, ChatAttachmentStatus } from '../../types/chat';

/** 見せる資料。送った資料(DBの行)のほか、送る前・送信中の下書きも同じ形で見せる。 */
export interface ViewableAttachment {
  title: string | null;
  content: string;
  status?: ChatAttachmentStatus;
  summary?: string | null;
  sections?: ChatAttachmentSection[];
}

export function viewableFromAttachment(a: ChatAttachment): ViewableAttachment {
  return { title: a.title, content: a.content, status: a.status, summary: a.summary, sections: a.sections };
}

interface AttachmentViewerModalProps {
  attachment: ViewableAttachment | null;
  /** 渡すと「この会話から外す」ボタンを出す(送った資料のときだけ)。 */
  onRemove?: () => Promise<void>;
  onClose: () => void;
}

/** 資料を読む(編集はできない)。目次があれば、押すとその節の本文へ飛ぶ。 */
export const AttachmentViewerModal: React.FC<AttachmentViewerModalProps> = ({ attachment, onRemove, onClose }) => {
  const { t, formatNumber } = useLanguage();
  const bodyRef = useRef<HTMLDivElement>(null);
  const [confirmingRemove, setConfirmingRemove] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [removeFailed, setRemoveFailed] = useState(false);

  useEffect(() => {
    setConfirmingRemove(false);
    setRemoveFailed(false);
    if (!attachment) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [attachment, onClose]);

  if (!attachment) return null;

  const sections = attachment.sections ?? [];
  const title = attachment.title || t('chatAttachmentUntitled');
  const jumpTo = (index: number) => {
    const el = bodyRef.current?.querySelector<HTMLElement>(`[data-section="${index}"]`);
    el?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  const remove = async () => {
    if (!onRemove) return;
    setRemoving(true);
    setRemoveFailed(false);
    try {
      await onRemove();
      onClose();
    } catch {
      setRemoveFailed(true);
    } finally {
      setRemoving(false);
    }
  };

  return (
    <div className="citation-modal-backdrop" onClick={onClose}>
      <div
        className="citation-modal-card chat-attachment-modal"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="citation-modal-grab-bar" aria-hidden="true">
          <span className="citation-modal-grab-handle" />
        </div>
        <div className="citation-modal-header">
          <div className="citation-modal-title-group">
            <div className="citation-modal-badges">
              <span className="citation-modal-badge-kind">
                <Paperclip size={14} />
                <span>{t('chatSourceAttachment')}</span>
              </span>
              <span className="citation-modal-badge-meta">
                {t('chatAttachmentChars', { count: formatNumber(attachment.content.length) })}
              </span>
              {attachment.status && attachment.status !== 'ready' && <AttachmentStatusBadge status={attachment.status} />}
            </div>
            <h3 className="citation-modal-title">{title}</h3>
          </div>
          <button type="button" className="citation-modal-close-btn" onClick={onClose} aria-label={t('close')}>
            <X size={18} />
          </button>
        </div>

        <div className="citation-modal-body chat-attachment-viewer" ref={bodyRef}>
          {attachment.summary && <p className="chat-attachment-viewer-summary">{attachment.summary}</p>}

          {sections.length > 1 && (
            <nav className="chat-attachment-toc" aria-label={t('chatAttachmentContents')}>
              <h4>{t('chatAttachmentContents')}</h4>
              <ol>
                {sections.map((s) => (
                  <li key={s.index}>
                    <button type="button" onClick={() => jumpTo(s.index)}>
                      <span className="chat-attachment-toc-title">{s.title}</span>
                      {s.description && <span className="chat-attachment-toc-desc">{s.description}</span>}
                    </button>
                  </li>
                ))}
              </ol>
            </nav>
          )}

          <h4 className="chat-attachment-viewer-heading">{t('chatAttachmentFullText')}</h4>
          {sections.length > 1 ? (
            sections.map((s) => (
              <section key={s.index} data-section={s.index} className="chat-attachment-viewer-section">
                <span className="chat-attachment-viewer-section-label">
                  {s.index}. {s.title}
                </span>
                <div className="chat-attachment-viewer-text">{attachment.content.slice(s.start, s.end).trim()}</div>
              </section>
            ))
          ) : (
            <div className="chat-attachment-viewer-text">{attachment.content}</div>
          )}
        </div>

        <div className="citation-modal-footer">
          {removeFailed && (
            <span className="chat-attachment-remove-error" role="alert">
              <AlertCircle size={14} />
              {t('chatAttachmentRemoveFailed')}
            </span>
          )}
          {onRemove &&
            (confirmingRemove ? (
              <div className="chat-attachment-remove-confirm">
                <span>{t('chatAttachmentRemoveConfirm')}</span>
                <button type="button" className="citation-modal-btn-secondary" onClick={() => setConfirmingRemove(false)}>
                  {t('cancel')}
                </button>
                <button type="button" className="citation-modal-btn-danger" disabled={removing} onClick={remove}>
                  {t('chatAttachmentRemove')}
                </button>
              </div>
            ) : (
              <button type="button" className="citation-modal-btn-secondary" onClick={() => setConfirmingRemove(true)}>
                {t('chatAttachmentRemove')}
              </button>
            ))}
          {!confirmingRemove && (
            <button type="button" className="citation-modal-btn-secondary" onClick={onClose}>
              {t('chatClose')}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

/** 資料の状態(確認中・使えなかった)の小さな印。 */
export const AttachmentStatusBadge: React.FC<{ status: ChatAttachmentStatus }> = ({ status }) => {
  const { t } = useLanguage();
  if (status === 'ready') return null;
  const key =
    status === 'processing'
      ? 'chatAttachmentProcessing'
      : status === 'blocked'
        ? 'chatAttachmentBlocked'
        : 'chatAttachmentFailed';
  return <span className={`chat-attachment-status is-${status}`}>{t(key)}</span>;
};
