import React, { useEffect, useState } from 'react';
import { ChevronRight, FileText, Paperclip, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { extractErrorCode } from '../../lib/api';
import {
  CHAT_CREDITS_PER_10K_TOKENS,
  CHAT_MAX_ATTACHMENTS_PER_THREAD,
  CHAT_MAX_SELECTED_TOKENS,
  type ChatAttachment,
} from '../../types/chat';
import { AttachmentStatusBadge } from './AttachmentViewerModal';

interface AttachmentListModalProps {
  open: boolean;
  /** このスレッドの資料(外したものを除く、添付順)。断った・失敗した資料は渡さない。 */
  attachments: ChatAttachment[];
  onOpen: (attachment: ChatAttachment) => void;
  /** 「全文で読む」の切り替え。上限などで断られたら例外を投げる。 */
  onToggleSelected: (attachmentId: string, selected: boolean) => Promise<void>;
  onClose: () => void;
}

/** 1万トークン単位の数字を読みやすく(例: 12,400 → 1.2万 / 12.4k)。 */
function useTokenFormat() {
  const { formatNumber } = useLanguage();
  return (tokens: number) => formatNumber(tokens, { notation: 'compact', maximumFractionDigits: 1 });
}

/**
 * この会話の資料の一覧(ヘッダーのクリップのボタン・＋メニューの「既存の資料を選ぶ」から開く)。
 * 行を押すと目次付きで全文を読める。「全文で読む」にした資料は、AIが毎回全文を読む
 * (選択中の合計はCHAT_MAX_SELECTED_TOKENSまで。超える選択は、押す前に理由を出して止める)。
 */
export const AttachmentListModal: React.FC<AttachmentListModalProps> = ({
  open,
  attachments,
  onOpen,
  onToggleSelected,
  onClose,
}) => {
  const { t, formatNumber, formatDate } = useLanguage();
  const formatTokens = useTokenFormat();
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [failed, setFailed] = useState<{ id: string; message: string } | null>(null);

  useEffect(() => {
    if (!open) return;
    setFailed(null);
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [open, onClose]);

  if (!open) return null;

  // 新しく添付したものを上に(一緒に読んでいるのはたいてい最後に貼った資料)
  const ordered = [...attachments].reverse();
  const selectedTokens = attachments.filter((a) => a.selected).reduce((sum, a) => sum + a.token_count, 0);
  const limitText = formatTokens(CHAT_MAX_SELECTED_TOKENS);

  /** 選べない理由(選べるならnull)。 */
  const blockReason = (a: ChatAttachment): string | null => {
    if (a.selected || a.status !== 'ready') return null;
    if (a.token_count > CHAT_MAX_SELECTED_TOKENS) return t('chatAttachmentTooLongToSelect');
    if (selectedTokens + a.token_count > CHAT_MAX_SELECTED_TOKENS) {
      return t('chatAttachmentSelectionLimit', { max: limitText });
    }
    return null;
  };

  const toggle = async (a: ChatAttachment) => {
    setFailed(null);
    setPendingId(a.id);
    try {
      await onToggleSelected(a.id, !a.selected);
    } catch (e) {
      const code = extractErrorCode(e);
      const message =
        code === 'ATTACHMENT_TOO_LONG_TO_SELECT'
          ? t('chatAttachmentTooLongToSelect')
          : code === 'ATTACHMENT_SELECTION_LIMIT'
            ? t('chatAttachmentSelectionLimit', { max: limitText })
            : t('chatAttachmentSelectFailed');
      setFailed({ id: a.id, message });
    } finally {
      setPendingId(null);
    }
  };

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
            <>
              <div className="chat-attachment-list-budget">
                <span>{t('chatAttachmentSelectedTotal', { used: formatTokens(selectedTokens), max: limitText })}</span>
                <span className="chat-attachment-list-budget-bar" aria-hidden="true">
                  <span style={{ width: `${Math.min(100, (selectedTokens / CHAT_MAX_SELECTED_TOKENS) * 100)}%` }} />
                </span>
                <p>{t('chatAttachmentListHint')}</p>
              </div>
              <ul className="chat-attachment-list">
                {ordered.map((a) => {
                  const meta = [t('chatAttachmentChars', { count: formatNumber(a.char_count) })];
                  if (a.sections.length > 1) meta.push(t('chatAttachmentSections', { count: a.sections.length }));
                  meta.push(formatDate(a.created_at, { month: 'numeric', day: 'numeric' }));
                  const reason = blockReason(a);
                  const cost = formatNumber((a.token_count / 10_000) * CHAT_CREDITS_PER_10K_TOKENS, {
                    maximumFractionDigits: 1,
                  });
                  return (
                    <li key={a.id} className={`chat-attachment-list-item ${a.selected ? 'is-selected' : ''}`}>
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
                      {a.status === 'ready' && (
                        <div className="chat-attachment-list-select">
                          <label className={`chat-switch ${reason ? 'is-disabled' : ''}`}>
                            <input
                              type="checkbox"
                              role="switch"
                              checked={a.selected}
                              disabled={pendingId === a.id || Boolean(reason)}
                              onChange={() => void toggle(a)}
                            />
                            <span className="chat-switch-track" aria-hidden="true">
                              <span className="chat-switch-thumb" />
                            </span>
                            <span className="chat-switch-label">
                              {a.selected ? t('chatAttachmentFullRead') : t('chatAttachmentTocRead')}
                            </span>
                          </label>
                          <span className="chat-attachment-list-cost">
                            {t('chatAttachmentTokens', { count: formatTokens(a.token_count) })}
                            {!reason && ` · ${t('chatAttachmentCostPerTurn', { credits: cost })}`}
                          </span>
                          {(reason || failed?.id === a.id) && (
                            <p className="chat-attachment-list-note" role={failed?.id === a.id ? 'alert' : undefined}>
                              {failed?.id === a.id ? failed.message : reason}
                            </p>
                          )}
                        </div>
                      )}
                    </li>
                  );
                })}
              </ul>
            </>
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
