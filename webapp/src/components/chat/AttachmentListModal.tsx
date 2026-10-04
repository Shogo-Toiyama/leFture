import React, { useEffect } from 'react';
import { ChevronRight, FileText, Paperclip, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { CHAT_MAX_ATTACHMENTS_PER_THREAD, type ChatAttachment } from '../../types/chat';
import { AttachmentStatusBadge } from './AttachmentViewerModal';

interface AttachmentListModalProps {
  open: boolean;
  /** このスレッドの資料(外したものを除く、添付順)。断った・失敗した資料は渡さない。 */
  attachments: ChatAttachment[];
  onOpen: (attachment: ChatAttachment) => void;
  onClose: () => void;
}

/** この会話の資料の一覧(ヘッダーのクリップのボタンから開く)。行を押すと目次付きで全文を読める。 */
export const AttachmentListModal: React.FC<AttachmentListModalProps> = ({ open, attachments, onOpen, onClose }) => {
  const { t, formatNumber, formatDate } = useLanguage();

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [open, onClose]);

  if (!open) return null;

  // 新しく添付したものを上に(一緒に読んでいるのはたいてい最後に貼った資料)
  const ordered = [...attachments].reverse();

  return (
    <div className="citation-modal-backdrop" onClick={onClose}>
      <div
        className="citation-modal-card chat-attachment-list-modal"
        role="dialog"
        aria-modal="true"
        aria-label={t('chatAttachmentsTitle')}
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
                {attachments.length} / {CHAT_MAX_ATTACHMENTS_PER_THREAD}
              </span>
            </div>
            <h3 className="citation-modal-title">{t('chatAttachmentsTitle')}</h3>
          </div>
          <button type="button" className="citation-modal-close-btn" onClick={onClose} aria-label={t('close')}>
            <X size={18} />
          </button>
        </div>

        <div className="citation-modal-body">
          {ordered.length === 0 ? (
            <p className="chat-attachment-list-empty">{t('chatAttachmentsEmpty')}</p>
          ) : (
            <ul className="chat-attachment-list">
              {ordered.map((a) => {
                const meta = [t('chatAttachmentChars', { count: formatNumber(a.char_count) })];
                if (a.sections.length > 1) meta.push(t('chatAttachmentSections', { count: a.sections.length }));
                meta.push(formatDate(a.created_at, { month: 'numeric', day: 'numeric' }));
                return (
                  <li key={a.id}>
                    <button type="button" className="chat-attachment-list-row" onClick={() => onOpen(a)}>
                      <FileText size={17} className="chat-attachment-list-icon" />
                      <span className="chat-attachment-list-text">
                        <span className="chat-attachment-list-title">{a.title || t('chatAttachmentUntitled')}</span>
                        {a.summary && <span className="chat-attachment-list-summary">{a.summary}</span>}
                        <span className="chat-attachment-list-meta">{meta.join('・')}</span>
                      </span>
                      <AttachmentStatusBadge status={a.status} />
                      <ChevronRight size={16} className="chat-attachment-list-chevron" />
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
};

/** ヘッダーのクリップのボタン(この会話の資料の一覧を開く)。全画面のチャットでも使う。 */
export const AttachmentListButton: React.FC<{ count: number; onClick: () => void }> = ({ count, onClick }) => {
  const { t } = useLanguage();
  const label = t('chatAttachmentsOpen', { count });
  return (
    <button type="button" className="chat-icon-btn chat-attachments-btn" onClick={onClick} aria-label={label} title={label}>
      <Paperclip size={16} />
      <span className="chat-attachments-btn-count" aria-hidden="true">
        {count}
      </span>
    </button>
  );
};
