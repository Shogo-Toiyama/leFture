import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Sparkles } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import { useChatConversation, type LocalChatMessage } from '../../hooks/useChatConversation';
import { CHAT_MAX_MESSAGE_CHARS, CHAT_MAX_SELECTED_TEXT_CHARS } from '../../types/chat';
import { ChatComposer } from './ChatComposer';
import { ChatMessageItem } from './ChatMessageItem';

interface ChatConversationProps {
  threadId: string | null;
  onThreadCreated: (threadId: string) => void;
  /** 1往復が終わったとき(スレッド名が付いた可能性があるので見出しを読み直す等)。 */
  onTurnComplete?: () => void;
  /** 話題にする講義。nullなら講義を指定しない。 */
  lectureId: string | null;
  lectureTitle: string | null;
  onDetachLecture?: () => void;
  selectedText: string | null;
  onClearSelectedText?: () => void;
  onOpenCitation: (route: string) => void;
  variant: 'panel' | 'page';
}

/** 送る前に止められたときの文言と、次にとれる行動。 */
function failureCopy(
  code: string,
  detail: Record<string, unknown>
): { key: TranslationKey; params?: Record<string, string | number>; action?: 'credits' } {
  switch (code) {
    case 'INSUFFICIENT_CREDITS':
      return {
        key: 'chatErrorInsufficientCredits',
        params: { min: typeof detail.min_credits === 'number' ? detail.min_credits : 5 },
        action: 'credits',
      };
    case 'CHAT_RATE_LIMITED':
      return { key: 'chatErrorRateLimited' };
    case 'CHAT_BLOCKED_COOLDOWN':
      return { key: 'chatErrorBlockedCooldown' };
    case 'MESSAGE_TOO_LONG':
      return { key: 'chatErrorTooLong', params: { max: CHAT_MAX_MESSAGE_CHARS } };
    case 'SELECTED_TEXT_TOO_LONG':
      return { key: 'chatErrorSelectedTooLong', params: { max: CHAT_MAX_SELECTED_TEXT_CHARS } };
    case 'THREAD_BUSY':
      return { key: 'chatErrorThreadBusy' };
    case 'THREAD_NOT_FOUND':
      return { key: 'chatErrorThreadNotFound' };
    case 'ACCOUNT_SUSPENDED':
      return { key: 'chatErrorSuspended' };
    case 'NETWORK':
      return { key: 'chatErrorNetwork' };
    default:
      return { key: 'chatErrorGeneric' };
  }
}

/** 下端からこの距離以内にいるときだけ、新しい文字に合わせて自動で下へ追従する。 */
const STICK_TO_BOTTOM_PX = 96;

export const ChatConversation: React.FC<ChatConversationProps> = ({
  threadId,
  onThreadCreated,
  onTurnComplete,
  lectureId,
  lectureTitle,
  onDetachLecture,
  selectedText,
  onClearSelectedText,
  onOpenCitation,
  variant,
}) => {
  const { t } = useLanguage();
  const { messages, loading, loadError, sending, send, retry, discard, reload } = useChatConversation(threadId, {
    onThreadCreated,
  });
  const scrollRef = useRef<HTMLDivElement>(null);
  const stickToBottomRef = useRef(true);
  const [prefill, setPrefill] = useState<{ text: string; nonce: number } | null>(null);

  // 1往復が終わった(sending: true → false)ことを親に知らせる
  const wasSendingRef = useRef(false);
  useEffect(() => {
    if (wasSendingRef.current && !sending) onTurnComplete?.();
    wasSendingRef.current = sending;
  }, [sending, onTurnComplete]);

  const onScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    stickToBottomRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < STICK_TO_BOTTOM_PX;
  };

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (el && stickToBottomRef.current) el.scrollTop = el.scrollHeight;
  }, [messages]);

  const selectedTooLong = (selectedText?.length ?? 0) > CHAT_MAX_SELECTED_TEXT_CHARS;

  const handleSend = useCallback(
    (content: string) => {
      stickToBottomRef.current = true;
      const context: { lecture_id?: string; selected_text?: string } = {};
      if (lectureId) context.lecture_id = lectureId;
      if (selectedText) context.selected_text = selectedText;
      void send(content, context);
      // 選択テキストは1回の質問にだけ添える
      if (selectedText) onClearSelectedText?.();
    },
    [lectureId, selectedText, send, onClearSelectedText]
  );

  /** 返答に失敗したassistantメッセージの直前のuserメッセージを、もう一度送る。 */
  const resendFor = useCallback(
    (assistantIndex: number) => {
      const previousUser = [...messages.slice(0, assistantIndex)].reverse().find((m) => m.role === 'user');
      if (!previousUser) return undefined;
      return () => {
        stickToBottomRef.current = true;
        void send(previousUser.content, previousUser.context);
      };
    },
    [messages, send]
  );

  const suggestions = useMemo(() => {
    if (selectedText) return [t('chatSuggestionSelection')];
    if (lectureId) return [t('chatSuggestionThisLecture'), t('chatSuggestionQuiz')];
    return [t('chatSuggestionLatest'), t('chatSuggestionQuiz'), t('chatSuggestionGoals')];
  }, [selectedText, lectureId, t]);

  const renderFailure = (message: LocalChatMessage) => {
    if (!message.failedCode) return null;
    const copy = failureCopy(message.failedCode, message.failedDetail ?? {});
    return (
      <div className="chat-banner" role="alert" key={`${message.id}-banner`}>
        <span>{t(copy.key, copy.params)}</span>
        <div className="chat-banner-actions">
          {copy.action === 'credits' ? (
            <Link to="/account/credits/purchase" className="chat-banner-btn is-primary">
              {t('chatBuyCredits')}
            </Link>
          ) : (
            copy.key !== 'chatErrorBlockedCooldown' &&
            copy.key !== 'chatErrorSuspended' &&
            copy.key !== 'chatErrorThreadNotFound' && (
              <button type="button" className="chat-banner-btn is-primary" onClick={() => retry(message.id)}>
                {t('chatResend')}
              </button>
            )
          )}
          <button
            type="button"
            className="chat-banner-btn"
            onClick={() => {
              discard(message.id);
              setPrefill({ text: message.content, nonce: Date.now() });
            }}
          >
            {t('chatDismiss')}
          </button>
        </div>
      </div>
    );
  };

  return (
    <div className={`chat-convo is-${variant}`}>
      <div className="chat-scroll" ref={scrollRef} onScroll={onScroll}>
        <div className="chat-thread">
          {loading ? (
            <div className="chat-loading" aria-busy="true">
              <span className="chat-skeleton is-user" />
              <span className="chat-skeleton" />
              <span className="chat-skeleton is-short" />
            </div>
          ) : loadError ? (
            <div className="chat-empty">
              <p>{t('chatLoadFailed')}</p>
              <button type="button" className="chat-banner-btn is-primary" onClick={reload}>
                {t('retry')}
              </button>
            </div>
          ) : messages.length === 0 ? (
            <div className="chat-empty">
              <span className="chat-empty-mark" aria-hidden="true">
                <Sparkles size={20} />
              </span>
              <h2 className="chat-empty-title">{t('chatEmptyTitle')}</h2>
              <p className="chat-empty-sub">{t('chatEmptySubtitle')}</p>
              <div className="chat-suggestions">
                {suggestions.map((text) => (
                  <button
                    key={text}
                    type="button"
                    className="chat-suggestion"
                    onClick={() => setPrefill({ text, nonce: Date.now() })}
                  >
                    {text}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            messages.map((message, index) => (
              <React.Fragment key={message.id}>
                <ChatMessageItem
                  message={message}
                  onOpenCitation={onOpenCitation}
                  onResend={message.status === 'error' && !sending ? resendFor(index) : undefined}
                />
                {renderFailure(message)}
              </React.Fragment>
            ))
          )}
        </div>
      </div>

      <div className="chat-footer">
        {selectedTooLong && (
          <p className="chat-footer-warning">{t('chatErrorSelectedTooLong', { max: CHAT_MAX_SELECTED_TEXT_CHARS })}</p>
        )}
        <ChatComposer
          disabled={sending || selectedTooLong}
          placeholder={messages.length > 0 ? t('chatInputPlaceholderFollowUp') : t('chatInputPlaceholder')}
          onSend={handleSend}
          selectedText={selectedText}
          onClearSelectedText={onClearSelectedText}
          lectureTitle={lectureTitle}
          onDetachLecture={onDetachLecture}
          prefill={prefill}
          autoFocus={variant === 'page'}
        />
        <p className="chat-disclaimer">{t('chatAiDisclaimer')}</p>
      </div>
    </div>
  );
};
