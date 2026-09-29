import React, { useLayoutEffect, useRef, useState } from 'react';
import { ArrowUp, BookOpen, Quote, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { CHAT_MAX_MESSAGE_CHARS } from '../../types/chat';

interface ChatComposerProps {
  disabled: boolean;
  placeholder: string;
  onSend: (content: string) => void;
  /** 次の送信に添える選択テキスト(チップとして見せ、外せる)。 */
  selectedText: string | null;
  onClearSelectedText?: () => void;
  /** 話題にしている講義名(チップとして見せ、外せる)。 */
  lectureTitle: string | null;
  onDetachLecture?: () => void;
  /** 候補の質問を押したときなどに、外から入力欄を埋める。 */
  prefill?: { text: string; nonce: number } | null;
  autoFocus?: boolean;
}

/** 入力欄が伸びる上限(行数ではなく高さで止める)。 */
const MAX_TEXTAREA_HEIGHT = 168;
/** 文字数の残りを出し始める目安。 */
const COUNTER_THRESHOLD = CHAT_MAX_MESSAGE_CHARS - 500;

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
  const { t } = useLanguage();
  const [value, setValue] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useLayoutEffect(() => {
    if (!prefill) return;
    setValue(prefill.text);
    textareaRef.current?.focus();
  }, [prefill]);

  // 内容に合わせて高さを伸ばす(上限を超えたら中でスクロール)
  useLayoutEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, MAX_TEXTAREA_HEIGHT)}px`;
  }, [value]);

  const trimmed = value.trim();
  const overLimit = value.length > CHAT_MAX_MESSAGE_CHARS;
  const canSend = !disabled && trimmed.length > 0 && !overLimit;

  const submit = () => {
    if (!canSend) return;
    onSend(trimmed);
    setValue('');
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // 日本語入力の変換確定のEnterでは送らない(isComposing / keyCode 229)
    if (event.nativeEvent.isComposing || event.keyCode === 229) return;
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      submit();
    }
  };

  return (
    <form
      className="chat-composer"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
    >
      {(selectedText || lectureTitle) && (
        <div className="chat-attachments">
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
        <textarea
          id="chat-composer-input"
          ref={textareaRef}
          rows={1}
          value={value}
          placeholder={placeholder}
          onChange={(event) => setValue(event.target.value)}
          onKeyDown={onKeyDown}
          autoFocus={autoFocus}
          aria-label={placeholder}
        />
        <button type="submit" className="chat-send-btn" disabled={!canSend} aria-label={t('chatSend')}>
          <ArrowUp size={18} />
        </button>
      </div>

      {value.length > COUNTER_THRESHOLD && (
        <span className={`chat-counter ${overLimit ? 'is-over' : ''}`}>
          {overLimit
            ? t('chatErrorTooLong', { max: CHAT_MAX_MESSAGE_CHARS })
            : `${value.length} / ${CHAT_MAX_MESSAGE_CHARS}`}
        </span>
      )}
    </form>
  );
};
