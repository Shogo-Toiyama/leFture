import React, { useEffect, useState } from 'react';
import { AtSign, BookOpenText, ChevronDown, FileStack, Paperclip, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import {
  CHAT_CREDITS_PER_10K_TOKENS,
  CHAT_MAX_ATTACHMENTS_PER_THREAD,
  CHAT_MAX_SELECTED_TOKENS,
  type ChatAttachment,
  type ChatAttachmentRef,
} from '../../types/chat';
import { useAttachmentImageUrl } from '../../hooks/useAttachmentImageUrl';
import { AttachmentKindIcon, AttachmentStatusBadge } from './AttachmentViewerModal';

interface AttachmentListModalProps {
  open: boolean;
  /** このスレッドの資料(外したものを除く、添付順)。断った・失敗した資料は渡さない。 */
  attachments: ChatAttachment[];
  /** 中身を見る。 */
  onView: (attachment: ChatAttachment) => void;
  /** 入力欄で指している資料(送る前。全文で添付する予定 / メンションする予定)。 */
  pendingRefs?: ChatAttachmentRef[];
  /** 入力欄に入れる(メンション)・入力欄から外す。一覧は開いたまま。 */
  onAttach: (attachment: ChatAttachment, mode: 'full' | 'mention' | 'remove') => void;
  /** 全文で読む(ピン留め・チップ化)。失敗したら例外を投げる。 */
  onPin?: (attachment: ChatAttachment) => Promise<void>;
  /** 全文で読むのをやめる。失敗したら例外を投げる。 */
  onUnpin: (attachment: ChatAttachment) => Promise<void>;
  onClose: () => void;
}

/** 1万トークン単位の数字を読みやすく(例: 12,400 → 1.2万 / 12.4k)。 */
function useTokenFormat() {
  const { formatNumber } = useLanguage();
  return (tokens: number) => formatNumber(tokens, { notation: 'compact', maximumFractionDigits: 1 });
}

/**
 * この会話の資料の一覧(ヘッダーのクリップのボタン・＋メニューの「この会話の資料」から開く)。
 * 行を押すと「全文で添付」「メンション」「中身を見る」を選べる(2026-10-07にユーザーと合意。以前の
 * 「全文で読む / 目次で読む」の切り替えは、何もしていない状態がどちらなのか分かりにくかったのでやめた)。
 * - 全文で添付: 入力欄に「@名前」を入れ、送るとAIが毎回全文を読む(外すまで続く)
 * - メンション: 入力欄に「@名前」を入れ、そのメッセージでこの資料を指していることをAIに伝える
 * 何もしていない資料も、名前と要約はAIが知っていて、必要なら目次と検索で読む。
 */
export const AttachmentListModal: React.FC<AttachmentListModalProps> = ({
  open,
  attachments,
  onView,
  pendingRefs = [],
  onAttach,
  onPin,
  onUnpin,
  onClose,
}) => {
  const { t, formatNumber, formatDate } = useLanguage();
  const formatTokens = useTokenFormat();
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [failedId, setFailedId] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setFailedId(null);
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [open, onClose]);

  if (!open) return null;

  // 新しく添付したものを上に(一緒に読んでいるのはたいてい最後に貼った資料)
  const ordered = [...attachments].reverse();
  const pendingMode = new Map(pendingRefs.map((r) => [r.attachment_id, r.mode]));
  // 送ったときに全文で読む資料: 今全文で読んでいる資料 + 入力欄で「全文で添付」にした資料
  const pinnedTokens = attachments
    .filter((a) => a.selected || pendingMode.get(a.id) === 'full')
    .reduce((sum, a) => sum + a.token_count, 0);
  const hasPendingFull = attachments.some((a) => !a.selected && pendingMode.get(a.id) === 'full');
  const limitText = formatTokens(CHAT_MAX_SELECTED_TOKENS);

  const pin = async (a: ChatAttachment) => {
    setFailedId(null);
    setPendingId(a.id);
    try {
      if (onPin) {
        await onPin(a);
      } else {
        onAttach(a, 'full');
      }
    } catch {
      setFailedId(a.id);
    } finally {
      setPendingId(null);
    }
  };

  const unpin = async (a: ChatAttachment) => {
    setFailedId(null);
    setPendingId(a.id);
    try {
      await onUnpin(a);
    } catch {
      setFailedId(a.id);
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
                <span>
                  {t(hasPendingFull ? 'chatAttachmentSelectedPending' : 'chatAttachmentSelectedTotal', {
                    used: formatTokens(pinnedTokens),
                    max: limitText,
                  })}
                </span>
                <span
                  className={`chat-attachment-list-budget-bar ${pinnedTokens > CHAT_MAX_SELECTED_TOKENS ? 'is-over' : ''}`}
                  aria-hidden="true"
                >
                  <span style={{ width: `${Math.min(100, (pinnedTokens / CHAT_MAX_SELECTED_TOKENS) * 100)}%` }} />
                </span>
                {pinnedTokens > CHAT_MAX_SELECTED_TOKENS && (
                  <p className="chat-attachment-list-note">{t('chatAttachmentOverLimitNote')}</p>
                )}
                <p>{t('chatAttachmentListHint')}</p>
              </div>
              <ul className="chat-attachment-list">
                {ordered.map((a) => {
                  const meta: string[] = [];
                  if (a.kind === 'image') meta.push(t('chatFileImage'));
                  else if (a.kind === 'pdf' && a.page_count) meta.push(t('chatFilePages', { count: a.page_count }));
                  else if (a.kind === 'pptx' && a.page_count) meta.push(t('chatFileSlides', { count: a.page_count }));
                  if (a.kind !== 'image') meta.push(t('chatAttachmentChars', { count: formatNumber(a.char_count) }));
                  if (a.metadata?.compressed) meta.push(t('chatAttachmentCondensed'));
                  meta.push(formatDate(a.created_at, { month: 'numeric', day: 'numeric' }));
                  const ready = a.status === 'ready';
                  const tooLong = a.token_count > CHAT_MAX_SELECTED_TOKENS;
                  const cost = formatNumber((a.token_count / 10_000) * CHAT_CREDITS_PER_10K_TOKENS, {
                    maximumFractionDigits: 1,
                  });
                  const expanded = expandedId === a.id;
                  const pending = pendingMode.get(a.id);
                  return (
                    <li
                      key={a.id}
                      className={`chat-attachment-list-item ${a.selected ? 'is-selected' : ''} ${expanded ? 'is-expanded' : ''}`}
                    >
                      <button
                        type="button"
                        className="chat-attachment-list-row"
                        onClick={() => setExpandedId(expanded ? null : a.id)}
                        aria-expanded={expanded}
                      >
                        <RowIcon attachment={a} />
                        <span className="chat-attachment-list-text">
                          <span className="chat-attachment-list-title">
                            {a.title || a.file_name || t('chatAttachmentUntitled')}
                          </span>
                          {a.summary && <span className="chat-attachment-list-summary">{a.summary}</span>}
                          <span className="chat-attachment-list-meta">{meta.join('・')}</span>
                        </span>
                        {pending && (
                          <span className={`chat-attachment-pending-badge is-${pending}`}>
                            {pending === 'full' ? t('chatAttachPendingFull') : t('chatAttachPendingMention')}
                          </span>
                        )}
                        {a.selected && !pending && (
                          <span className="chat-attachment-pinned-badge">{t('chatAttachPinned')}</span>
                        )}
                        <AttachmentStatusBadge status={a.status} />
                        <ChevronDown size={16} className="chat-attachment-list-chevron" />
                      </button>
                      {expanded && (
                        <div className="chat-attachment-list-actions">
                          {ready && !a.selected && a.kind !== 'image' && (
                            <button
                              type="button"
                              className="chat-attachment-action is-primary"
                              disabled={tooLong || pendingId === a.id}
                              onClick={() => void pin(a)}
                            >
                              <FileStack size={15} />
                              <span>
                                {t('chatAttachFull')}
                                <small>
                                  {tooLong
                                    ? t('chatAttachmentTooLongToSelect')
                                    : `${t('chatAttachmentTokens', { count: formatTokens(a.token_count) })} · ${t('chatAttachmentCostPerTurn', { credits: cost })}`}
                                </small>
                              </span>
                            </button>
                          )}
                          {ready && pending !== 'mention' && (
                            <button type="button" className="chat-attachment-action" onClick={() => onAttach(a, 'mention')}>
                              <AtSign size={15} />
                              <span>
                                {t('chatAttachMention')}
                                <small>{t('chatAttachMentionHint')}</small>
                              </span>
                            </button>
                          )}
                          {pending && (
                            <button type="button" className="chat-attachment-action" onClick={() => onAttach(a, 'remove')}>
                              <X size={15} />
                              <span>{t('chatAttachUndo')}</span>
                            </button>
                          )}
                          <button type="button" className="chat-attachment-action" onClick={() => onView(a)}>
                            <BookOpenText size={15} />
                            <span>{t('chatAttachView')}</span>
                          </button>
                          {a.selected && (
                            <button
                              type="button"
                              className="chat-attachment-action"
                              disabled={pendingId === a.id}
                              onClick={() => void unpin(a)}
                            >
                              <X size={15} />
                              <span>
                                {t('chatAttachmentUnselect')}
                                <small>{t('chatAttachUnpinHint')}</small>
                              </span>
                            </button>
                          )}
                          {failedId === a.id && (
                            <p className="chat-attachment-list-note" role="alert">
                              {t('chatAttachmentSelectFailed')}
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

/** 一覧の行の左: 画像は小さな見本、それ以外は種類のアイコン。 */
const RowIcon: React.FC<{ attachment: ChatAttachment }> = ({ attachment }) => {
  const url = useAttachmentImageUrl(attachment.kind === 'image' && attachment.status === 'ready' ? attachment.id : null);
  if (url) return <img className="chat-attachment-list-thumb" src={url} alt="" />;
  return (
    <span className="chat-attachment-list-icon">
      <AttachmentKindIcon kind={attachment.kind} size={17} />
    </span>
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
