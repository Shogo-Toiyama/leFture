import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { ArrowUp, BookOpen, FileText, FileType, Image as ImageIcon, Paperclip, Plus, Quote, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import {
  CHAT_MAX_ATTACHMENTS_PER_MESSAGE,
  CHAT_MAX_MESSAGE_CHARS,
  type ChatDraftAttachment,
} from '../../types/chat';
import { newClientMessageId } from '../../lib/chat';
import { AttachmentEditorModal, type AttachmentEditorValue } from './AttachmentEditorModal';

interface ChatComposerProps {
  disabled: boolean;
  placeholder: string;
  /** 送信。draftsはこの送信で添付する資料(無ければ空)。 */
  onSend: (content: string, drafts: ChatDraftAttachment[]) => void;
  /** 次の送信に添える選択テキスト(チップとして見せ、外せる)。 */
  selectedText: string | null;
  onClearSelectedText?: () => void;
  /** 話題にしている講義名(チップとして見せ、外せる)。 */
  lectureTitle: string | null;
  onDetachLecture?: () => void;
  /** 候補の質問を押したとき・送れなかった送信を戻すときに、外から入力欄(と資料)を埋める。 */
  prefill?: { text: string; attachments?: ChatDraftAttachment[]; nonce: number } | null;
  autoFocus?: boolean;
}

/** 入力欄が伸びる上限(行数ではなく高さで止める)。 */
const MAX_TEXTAREA_HEIGHT = 168;
/** 文字数の残りを出し始める目安。 */
const COUNTER_THRESHOLD = CHAT_MAX_MESSAGE_CHARS - 500;

/** 編集モーダルの状態: 新しく添付する(貼り付けから来たか) / 下書きを直す。 */
type EditorState =
  | { mode: 'new'; value: AttachmentEditorValue; fromPaste: boolean }
  | { mode: 'edit'; localId: string; value: AttachmentEditorValue };

/** チップに出す名前(名前が無ければ本文の最初の行)。 */
function draftLabel(draft: ChatDraftAttachment): string {
  if (draft.title.trim()) return draft.title.trim();
  return draft.content.split('\n').find((line) => line.trim())?.trim() ?? '';
}

export const ChatComposer: React.FC<ChatComposerProps> = ({
  disabled,
  placeholder,
  onSend,
  selectedText,
  onClearSelectedText,
  lectureTitle,
  onDetachLecture,
  prefill,
  autoFocus,
}) => {
  const { t, formatNumber } = useLanguage();
  const [value, setValue] = useState('');
  const [drafts, setDrafts] = useState<ChatDraftAttachment[]>([]);
  const [menuOpen, setMenuOpen] = useState(false);
  const [editor, setEditor] = useState<EditorState | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (!prefill) return;
    setValue(prefill.text);
    if (prefill.attachments) setDrafts(prefill.attachments);
    textareaRef.current?.focus();
  }, [prefill]);

  // 内容に合わせて高さを伸ばす(上限を超えたら中でスクロール)
  useLayoutEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, MAX_TEXTAREA_HEIGHT)}px`;
  }, [value]);

  // メニューの外を押したら閉じる
  useEffect(() => {
    if (!menuOpen) return;
    const onPointerDown = (e: PointerEvent) => {
      if (!menuRef.current?.contains(e.target as Node)) setMenuOpen(false);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMenuOpen(false);
    };
    document.addEventListener('pointerdown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [menuOpen]);

  const trimmed = value.trim();
  const overLimit = value.length > CHAT_MAX_MESSAGE_CHARS;
  const draftsFull = drafts.length >= CHAT_MAX_ATTACHMENTS_PER_MESSAGE;
  // 資料だけを送るのも許す
  const canSend = !disabled && !overLimit && (trimmed.length > 0 || drafts.length > 0);

  const submit = () => {
    if (!canSend) return;
    onSend(trimmed, drafts);
    setValue('');
    setDrafts([]);
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // 日本語入力の変換確定のEnterでは送らない(isComposing / keyCode 229)
    if (event.nativeEvent.isComposing || event.keyCode === 229) return;
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      submit();
    }
  };

  // メッセージの上限を超える長さの貼り付けは、入力欄に入れずに資料の編集へ回す
  const onPaste = (event: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const pasted = event.clipboardData.getData('text');
    const el = event.currentTarget;
    const selected = el.selectionEnd - el.selectionStart;
    if (!pasted || value.length - selected + pasted.length <= CHAT_MAX_MESSAGE_CHARS || draftsFull) return;
    event.preventDefault();
    setEditor({ mode: 'new', value: { title: '', content: pasted }, fromPaste: true });
  };

  const openNewText = () => {
    setMenuOpen(false);
    setEditor({ mode: 'new', value: { title: '', content: '' }, fromPaste: false });
  };

  // 打ちすぎて上限を超えた本文を、そのまま資料にする
  const convertValueToDraft = () => {
    setEditor({ mode: 'new', value: { title: '', content: value }, fromPaste: true });
  };

  const saveEditor = (next: AttachmentEditorValue) => {
    if (!editor) return;
    if (editor.mode === 'edit') {
      setDrafts((prev) => prev.map((d) => (d.localId === editor.localId ? { ...d, ...next } : d)));
    } else {
      setDrafts((prev) => [...prev, { localId: newClientMessageId(), kind: 'text', ...next }]);
      // 入力欄から回した本文は、資料にしたので入力欄からは消す
      if (editor.fromPaste && editor.value.content === value) setValue('');
    }
    setEditor(null);
    textareaRef.current?.focus();
  };

  return (
    <form
      className="chat-composer"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
    >
      {(selectedText || lectureTitle || drafts.length > 0) && (
        <div className="chat-attachments">
          {drafts.map((draft) => (
            <span key={draft.localId} className="chat-attachment is-file">
              <button
                type="button"
                className="chat-attachment-open"
                onClick={() => setEditor({ mode: 'edit', localId: draft.localId, value: { title: draft.title, content: draft.content } })}
                title={draftLabel(draft)}
              >
                <Paperclip size={12} />
                <span className="chat-attachment-text">{draftLabel(draft)}</span>
                <span className="chat-attachment-meta">
                  {t('chatAttachmentChars', { count: formatNumber(draft.content.length) })}
                </span>
              </button>
              <button
                type="button"
                onClick={() => setDrafts((prev) => prev.filter((d) => d.localId !== draft.localId))}
                aria-label={t('chatRemoveAttachment')}
              >
                <X size={12} />
              </button>
            </span>
          ))}
          {selectedText && (
            <span className="chat-attachment is-quote" title={selectedText}>
              <Quote size={12} />
              <span className="chat-attachment-text">{selectedText}</span>
              {onClearSelectedText && (
                <button type="button" onClick={onClearSelectedText} aria-label={t('chatRemoveAttachment')}>
                  <X size={12} />
                </button>
              )}
            </span>
          )}
          {lectureTitle && (
            <span className="chat-attachment" title={lectureTitle}>
              <BookOpen size={12} />
              <span className="chat-attachment-text">{t('chatAttachedLecture', { title: lectureTitle })}</span>
              {onDetachLecture && (
                <button type="button" onClick={onDetachLecture} aria-label={t('chatRemoveAttachment')}>
                  <X size={12} />
                </button>
              )}
            </span>
          )}
        </div>
      )}

      <div className={`chat-input-row ${overLimit ? 'is-over' : ''}`}>
        <div className="chat-attach-wrap" ref={menuRef}>
          <button
            type="button"
            className={`chat-attach-btn ${menuOpen ? 'is-open' : ''}`}
            onClick={() => setMenuOpen((open) => !open)}
            aria-label={t('chatAttach')}
            aria-haspopup="menu"
            aria-expanded={menuOpen}
            title={t('chatAttach')}
          >
            <Plus size={18} />
          </button>
          {menuOpen && (
            <div className="chat-attach-menu" role="menu">
              <button type="button" role="menuitem" onClick={openNewText} disabled={draftsFull}>
                <FileText size={16} />
                <span className="chat-attach-menu-label">
                  <span>{t('chatAttachText')}</span>
                  <small>
                    {draftsFull
                      ? t('chatAttachmentLimitPerMessage', { max: CHAT_MAX_ATTACHMENTS_PER_MESSAGE })
                      : t('chatAttachTextHint')}
                  </small>
                </span>
              </button>
              <button type="button" role="menuitem" disabled>
                <ImageIcon size={16} />
                <span className="chat-attach-menu-label">
                  <span>{t('chatAttachImage')}</span>
                </span>
                <span className="chat-attach-soon">{t('chatComingSoon')}</span>
              </button>
              <button type="button" role="menuitem" disabled>
                <FileType size={16} />
                <span className="chat-attach-menu-label">
                  <span>{t('chatAttachPdf')}</span>
                </span>
                <span className="chat-attach-soon">{t('chatComingSoon')}</span>
              </button>
            </div>
          )}
        </div>
        <textarea
          id="chat-composer-input"
          ref={textareaRef}
          rows={1}
          value={value}
          placeholder={placeholder}
          onChange={(event) => setValue(event.target.value)}
          onKeyDown={onKeyDown}
          onPaste={onPaste}
          autoFocus={autoFocus}
          aria-label={placeholder}
        />
        <button type="submit" className="chat-send-btn" disabled={!canSend} aria-label={t('chatSend')}>
          <ArrowUp size={18} />
        </button>
      </div>

      {value.length > COUNTER_THRESHOLD && (
        <span className={`chat-counter ${overLimit ? 'is-over' : ''}`}>
          {overLimit ? (
            <>
              {t('chatErrorTooLong', { max: CHAT_MAX_MESSAGE_CHARS })}
              {!draftsFull && (
                <button type="button" className="chat-link-btn" onClick={convertValueToDraft}>
                  <Paperclip size={12} />
                  {t('chatAttachmentConvert')}
                </button>
              )}
            </>
          ) : (
            `${value.length} / ${CHAT_MAX_MESSAGE_CHARS}`
          )}
        </span>
      )}

      <AttachmentEditorModal
        initial={editor?.value ?? null}
        editing={editor?.mode === 'edit'}
        fromPaste={editor?.mode === 'new' && editor.fromPaste}
        onSave={saveEditor}
        onClose={() => setEditor(null)}
      />
    </form>
  );
};
