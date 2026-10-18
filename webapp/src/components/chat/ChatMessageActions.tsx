import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Check, Copy, Flag, Info, MoreHorizontal, Pencil, RotateCw, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { CHAT_MENTION_RE, type ChatMessage } from '../../types/chat';
import { ReportSheet } from '../ReportSheet';

/** クリップボードへ書く。権限が無い・古い環境では、一時的なtextareaを選択してコピーする。 */
async function writeClipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try {
      return document.execCommand('copy');
    } catch {
      return false;
    } finally {
      document.body.removeChild(area);
    }
  }
}

interface ChatMessageActionsProps {
  /** コピーする文字列(出典の印などの不要なラベルを取り除いた本文) */
  copyText: string;
  /** 渡すと「…」メニュー(回答の詳細)を出す。userのメッセージには渡さない。 */
  detailsFor?: ChatMessage;
  /** この回答のもとになった質問(報告に添える)。detailsForと一緒に渡す。 */
  question?: string;
  /** 自分のメッセージを編集する(下の入力欄で直す) */
  onEdit?: () => void;
  /** 最後の回答を作り直す */
  onRegenerate?: () => void;
}

/**
 * メッセージの下の操作行(コピー・「…」メニュー)。
 * 色はCSS変数(--chat-act-*)で決め、ダーク/ペーパー(.is-paper)の両方に合わせる。
 */
export const ChatMessageActions: React.FC<ChatMessageActionsProps> = ({ copyText, detailsFor, question, onEdit, onRegenerate }) => {
  const { t } = useLanguage();
  const [copied, setCopied] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [showDetails, setShowDetails] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const copiedTimer = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(copiedTimer.current), []);

  // メニューは外を押すかEscで閉じる
  useEffect(() => {
    if (!menuOpen) return;
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setMenuOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setMenuOpen(false);
    };
    document.addEventListener('pointerdown', onPointerDown, true);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [menuOpen]);

  const copy = useCallback(async () => {
    if (!(await writeClipboard(copyText))) return;
    setCopied(true);
    window.clearTimeout(copiedTimer.current);
    copiedTimer.current = window.setTimeout(() => setCopied(false), 1400);
  }, [copyText]);

  return (
    <div className="chat-msg-actions" ref={rootRef}>
      <button
        type="button"
        className={`chat-act-btn ${copied ? 'is-done' : ''}`}
        onClick={copy}
        aria-label={copied ? t('chatActionCopied') : t('chatActionCopy')}
        title={copied ? t('chatActionCopied') : t('chatActionCopy')}
      >
        {copied ? <Check size={16} /> : <Copy size={16} />}
      </button>

      {onEdit && (
        <button type="button" className="chat-act-btn" onClick={onEdit} aria-label={t('chatActionEdit')} title={t('chatActionEdit')}>
          <Pencil size={16} />
        </button>
      )}

      {onRegenerate && (
        <button
          type="button"
          className="chat-act-btn"
          onClick={onRegenerate}
          aria-label={t('chatActionRegenerate')}
          title={t('chatActionRegenerate')}
        >
          <RotateCw size={16} />
        </button>
      )}

      {detailsFor && (
        <span className="chat-act-menu-anchor">
          <button
            type="button"
            className="chat-act-btn"
            onClick={() => setMenuOpen((open) => !open)}
            aria-label={t('chatActionMore')}
            title={t('chatActionMore')}
            aria-haspopup="menu"
            aria-expanded={menuOpen}
          >
            <MoreHorizontal size={16} />
          </button>
          {menuOpen && (
            <div className="chat-act-menu" role="menu">
              <button
                type="button"
                role="menuitem"
                onClick={() => {
                  setMenuOpen(false);
                  setShowDetails(true);
                }}
              >
                <Info size={15} />
                {t('chatActionDetails')}
              </button>
              <button
                type="button"
                role="menuitem"
                onClick={() => {
                  setMenuOpen(false);
                  setShowReport(true);
                }}
              >
                <Flag size={15} />
                {t('chatActionReport')}
              </button>
            </div>
          )}
        </span>
      )}

      {detailsFor && showDetails && <MessageDetailsModal message={detailsFor} onClose={() => setShowDetails(false)} />}
      {detailsFor && showReport && (
        <ReportSheet
          title={t('chatActionReport')}
          categories={['inappropriate', 'incorrect', 'bug', 'feature_request', 'other']}
          context={{
            source: 'ai_chat',
            thread_id: detailsFor.thread_id,
            message_id: detailsFor.id,
            message_status: detailsFor.status,
            message_sent_at: detailsFor.created_at,
            credits_charged_micro: detailsFor.credits_charged_micro,
          }}
          attachment={{
            label: t('chatReportAttach'),
            sections: [
              ...(question?.trim()
                ? [{ heading: t('chatReportQuestion'), text: question.replace(CHAT_MENTION_RE, '[material]') }]
                : []),
              { heading: t('chatReportReply'), text: copyText },
            ],
          }}
          onClose={() => setShowReport(false)}
        />
      )}
    </div>
  );
};

/** 回答の詳細。いつ送ったか・何クレジットかかったか・出典の数。原価や内部の振り分けは出さない。 */
const MessageDetailsModal: React.FC<{ message: ChatMessage; onClose: () => void }> = ({ message, onClose }) => {
  const { t, formatDate, formatNumber } = useLanguage();

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  const credits = (message.credits_charged_micro ?? 0) / 1_000_000;
  const sentAt = formatDate(message.created_at, {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

  return (
    <div className="citation-modal-backdrop" onClick={onClose}>
      <div
        className="citation-modal-card chat-detail-card"
        role="dialog"
        aria-label={t('chatActionDetails')}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="citation-modal-grab-bar" aria-hidden="true">
          <span className="citation-modal-grab-handle" />
        </div>
        <div className="citation-modal-header">
          <div className="citation-modal-title-group">
            <h3 className="citation-modal-title">{t('chatActionDetails')}</h3>
          </div>
          <button type="button" className="citation-modal-close-btn" onClick={onClose} aria-label={t('chatClose')}>
            <X size={18} />
          </button>
        </div>
        <dl className="chat-detail-list">
          <dt>{t('chatDetailSentAt')}</dt>
          <dd>{sentAt}</dd>
          {message.status === 'stopped' && (
            <>
              <dt>{t('chatDetailStatus')}</dt>
              <dd>{t('chatDetailStatusStopped')}</dd>
            </>
          )}
          <dt>{t('chatDetailCredits')}</dt>
          <dd>
            {credits > 0
              ? t('chatCreditsUsed', { credits: formatNumber(credits, { maximumFractionDigits: 2 }) })
              : t('chatDetailNoCharge')}
          </dd>
          <dt>{t('chatDetailSources')}</dt>
          <dd>{t('chatDetailSourcesCount', { count: formatNumber(message.citations.length) })}</dd>
        </dl>
      </div>
    </div>
  );
};
