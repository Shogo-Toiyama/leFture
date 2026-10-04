import React, { useEffect, useRef, useState } from 'react';
import { Paperclip, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import {
  CHAT_MAX_ATTACHMENT_CHARS,
  CHAT_MAX_ATTACHMENT_TITLE_CHARS,
  CHAT_MAX_MESSAGE_CHARS,
} from '../../types/chat';

export interface AttachmentEditorValue {
  title: string;
  content: string;
}

interface AttachmentEditorModalProps {
  /** 開いているときの初期値(新規ならcontentが空、貼り付けから来たら貼った文章)。nullなら閉じている。 */
  initial: AttachmentEditorValue | null;
  /** 既に添付した下書きを直しているか(見出しとボタンの文言が変わる)。 */
  editing?: boolean;
  /** 長い文章を入力欄に貼ったので、こちらへ回したことを伝える。 */
  fromPaste?: boolean;
  onSave: (value: AttachmentEditorValue) => void;
  onClose: () => void;
}

/**
 * テキストの資料を添付する(送るまでは何度でも直せる)。送った後は編集できない
 * (バックエンドが審査・目次づくりをした中身だけを使うため)。
 */
export const AttachmentEditorModal: React.FC<AttachmentEditorModalProps> = ({
  initial,
  editing,
  fromPaste,
  onSave,
  onClose,
}) => {
  const { t, formatNumber } = useLanguage();
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!initial) return;
    setTitle(initial.title);
    setContent(initial.content);
    // 貼り付けから来たときは本文が入っているので、名前の欄から書けるように本文の先頭へは飛ばさない
    if (!initial.content) requestAnimationFrame(() => textareaRef.current?.focus());
  }, [initial]);

  useEffect(() => {
    if (!initial) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [initial, onClose]);

  if (!initial) return null;

  const trimmed = content.trim();
  const overLimit = content.length > CHAT_MAX_ATTACHMENT_CHARS;
  const canSave = trimmed.length > 0 && !overLimit;

  return (
    <div className="citation-modal-backdrop" onClick={onClose}>
      <div
        className="citation-modal-card chat-attachment-modal"
        role="dialog"
        aria-modal="true"
        aria-label={editing ? t('chatAttachmentEditorEditTitle') : t('chatAttachmentEditorTitle')}
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
                <span>{t('chatAttachText')}</span>
              </span>
            </div>
            <h3 className="citation-modal-title">
              {editing ? t('chatAttachmentEditorEditTitle') : t('chatAttachmentEditorTitle')}
            </h3>
          </div>
          <button type="button" className="citation-modal-close-btn" onClick={onClose} aria-label={t('close')}>
            <X size={18} />
          </button>
        </div>

        <div className="citation-modal-body chat-attachment-editor">
          {fromPaste && (
            <p className="chat-attachment-editor-notice">
              {t('chatAttachmentPasteNotice', { max: formatNumber(CHAT_MAX_MESSAGE_CHARS) })}
            </p>
          )}
          <input
            type="text"
            className="chat-attachment-editor-title"
            value={title}
            maxLength={CHAT_MAX_ATTACHMENT_TITLE_CHARS}
            placeholder={t('chatAttachmentTitlePlaceholder')}
            onChange={(e) => setTitle(e.target.value)}
            // 入力欄のformの中に置かれるので、Enterでメッセージが送られないようにする
            onKeyDown={(e) => {
              if (e.key === 'Enter') e.preventDefault();
            }}
            aria-label={t('chatAttachmentTitlePlaceholder')}
          />
          <textarea
            ref={textareaRef}
            className={`chat-attachment-editor-content ${overLimit ? 'is-over' : ''}`}
            value={content}
            placeholder={t('chatAttachmentContentPlaceholder')}
            onChange={(e) => setContent(e.target.value)}
            aria-label={t('chatAttachmentContentPlaceholder')}
          />
          <div className="chat-attachment-editor-meta">
            <span>{t('chatAttachmentEditorNote')}</span>
            <span className={`chat-counter ${overLimit ? 'is-over' : ''}`}>
              {overLimit
                ? t('chatAttachmentTooLong', { max: formatNumber(CHAT_MAX_ATTACHMENT_CHARS) })
                : `${formatNumber(content.length)} / ${formatNumber(CHAT_MAX_ATTACHMENT_CHARS)}`}
            </span>
          </div>
        </div>

        <div className="citation-modal-footer">
          <button type="button" className="citation-modal-btn-secondary" onClick={onClose}>
            {t('cancel')}
          </button>
          <button
            type="button"
            className="citation-modal-btn-primary"
            disabled={!canSave}
            onClick={() => canSave && onSave({ title: title.trim(), content: trimmed })}
          >
            <Paperclip size={15} />
            <span>{editing ? t('chatAttachmentSave') : t('chatAttachmentAdd')}</span>
          </button>
        </div>
      </div>
    </div>
  );
};
