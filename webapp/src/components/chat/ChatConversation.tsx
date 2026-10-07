import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Sparkles, Upload } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import { useChatConversation, type LocalChatMessage } from '../../hooks/useChatConversation';
import {
  CHAT_MAX_ATTACHMENT_CHARS,
  CHAT_MAX_ATTACHMENTS_PER_MESSAGE,
  CHAT_MAX_ATTACHMENTS_PER_THREAD,
  CHAT_MAX_MESSAGE_CHARS,
  CHAT_MAX_SELECTED_TEXT_CHARS,
  type ChatAttachment,
  type ChatDraftAttachment,
  type ChatMessageContext,
  type ChatScreenRef,
  type ChatSelection,
} from '../../types/chat';
import { AttachmentListModal } from './AttachmentListModal';
import { AttachmentViewerModal, viewableFromAttachment, type ViewableAttachment } from './AttachmentViewerModal';
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
  /** 「Ask」で添える選択。1回の送信にだけ添える。 */
  selection: ChatSelection | null;
  onClearSelection?: () => void;
  /** 今いる画面のページ。毎回の送信に添える(本文はバックエンドが読む)。 */
  screen: ChatScreenRef | null;
  onOpenCitation: (route: string) => void;
  variant: 'panel' | 'page';
  /** この会話の資料の一覧を開いているか(ボタンはヘッダー側にある)。 */
  attachmentListOpen?: boolean;
  onAttachmentListClose?: () => void;
  /** 一覧に出す資料の数が変わったとき(ヘッダーのボタンの表示と件数に使う)。 */
  onAttachmentCountChange?: (count: number) => void;
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
    case 'EMPTY_ATTACHMENT':
      return { key: 'chatErrorEmptyAttachment' };
    case 'ATTACHMENT_TOO_LONG':
      return { key: 'chatErrorAttachmentTooLong', params: { max: CHAT_MAX_ATTACHMENT_CHARS } };
    case 'TOO_MANY_ATTACHMENTS':
      return { key: 'chatErrorTooManyAttachments', params: { max: CHAT_MAX_ATTACHMENTS_PER_MESSAGE } };
    case 'THREAD_ATTACHMENT_LIMIT':
      return { key: 'chatErrorThreadAttachmentLimit', params: { max: CHAT_MAX_ATTACHMENTS_PER_THREAD } };
    case 'ATTACHMENT_NOT_FOUND':
    case 'ATTACHMENT_NOT_READY':
      return { key: 'chatErrorAttachmentNotReady' };
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
  selection,
  onClearSelection,
  screen,
  onOpenCitation,
  variant,
  attachmentListOpen = false,
  onAttachmentListClose,
  onAttachmentCountChange,
}) => {
  const { t } = useLanguage();
  const {
    messages,
    attachments,
    selectAttachment,
    loading,
    loadError,
    sending,
    send,
    retry,
    discard,
    reload,
    removeAttachment,
  } = useChatConversation(threadId, { onThreadCreated });
  // 資料の一覧は、ヘッダーのクリップのボタン(親が開く)と、＋メニューの「既存の資料を選ぶ」(ここで開く)の両方から開く
  const [localListOpen, setLocalListOpen] = useState(false);
  const listOpen = attachmentListOpen || localListOpen;
  const closeList = useCallback(() => {
    setLocalListOpen(false);
    onAttachmentListClose?.();
  }, [onAttachmentListClose]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const stickToBottomRef = useRef(true);
  const [prefill, setPrefill] = useState<{ text: string; attachments?: ChatDraftAttachment[]; nonce: number } | null>(
    null
  );
  /** 会話の上にドロップされたファイル(入力欄が添付する)。 */
  const [droppedFiles, setDroppedFiles] = useState<{ files: File[]; nonce: number } | null>(null);
  const [dragging, setDragging] = useState(false);
  // 子要素への出入りでもdragenter/dragleaveが来るので、数えて「外に出た」を判定する
  const dragDepthRef = useRef(0);
  /** 読んでいる資料(送った資料ならidがあり、外せる)。 */
  const [viewing, setViewing] = useState<{ attachment: ViewableAttachment; id?: string } | null>(null);

  // 一覧に出す資料: 使えるもの(ready)と確認中のもの。断った・失敗した資料はメッセージの上のチップにだけ出す
  const listedAttachments = useMemo(
    () => attachments.filter((a) => a.status === 'ready' || a.status === 'processing'),
    [attachments]
  );
  useEffect(() => {
    onAttachmentCountChange?.(listedAttachments.length);
  }, [listedAttachments.length, onAttachmentCountChange]);

  // 送ったメッセージごとの資料(会話の中でチップとして見せる)
  const attachmentsByMessage = useMemo(() => {
    const map = new Map<string, ChatAttachment[]>();
    for (const a of attachments) {
      if (!a.message_id) continue;
      map.set(a.message_id, [...(map.get(a.message_id) ?? []), a]);
    }
    return map;
  }, [attachments]);

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

  const selectedText = selection?.text ?? null;
  const selectedTooLong = (selectedText?.length ?? 0) > CHAT_MAX_SELECTED_TEXT_CHARS;

  const handleSend = useCallback(
    (content: string, drafts: ChatDraftAttachment[] = []) => {
      stickToBottomRef.current = true;
      const context: ChatMessageContext = {};
      if (lectureId) context.lecture_id = lectureId;
      // 選んだページ(「Ask」)を優先し、無ければ今いる画面のページ
      const screenRef = selection?.screen ?? screen;
      if (screenRef) context.screen = screenRef;
      if (selection) {
        context.selected_text = selection.text;
        if (selection.before) context.selection_before = selection.before;
        if (selection.after) context.selection_after = selection.after;
      }
      void send(content, context, drafts);
      // 選択テキストは1回の質問にだけ添える
      if (selection) onClearSelection?.();
    },
    [lectureId, selection, screen, send, onClearSelection]
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
              setPrefill({ text: message.content, attachments: message.localAttachments, nonce: Date.now() });
            }}
          >
            {t('chatDismiss')}
          </button>
        </div>
      </div>
    );
  };

  const hasFiles = (e: React.DragEvent) => Array.from(e.dataTransfer.types).includes('Files');
  const dropHandlers = {
    onDragEnter: (e: React.DragEvent) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      dragDepthRef.current += 1;
      setDragging(true);
    },
    onDragOver: (e: React.DragEvent) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
    },
    onDragLeave: (e: React.DragEvent) => {
      if (!hasFiles(e)) return;
      dragDepthRef.current = Math.max(0, dragDepthRef.current - 1);
      if (dragDepthRef.current === 0) setDragging(false);
    },
    onDrop: (e: React.DragEvent) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      dragDepthRef.current = 0;
      setDragging(false);
      const files = Array.from(e.dataTransfer.files);
      if (files.length) setDroppedFiles({ files, nonce: Date.now() });
    },
  };

  return (
    <div className={`chat-convo is-${variant} ${dragging ? 'is-dragging' : ''}`} {...dropHandlers}>
      {dragging && (
        <div className="chat-drop-overlay" aria-hidden="true">
          <div className="chat-drop-card">
            <Upload size={22} />
            <strong>{t('chatFileDropTitle')}</strong>
            <span>{t('chatFileDropHint', { max: CHAT_MAX_ATTACHMENTS_PER_MESSAGE })}</span>
          </div>
        </div>
      )}
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
                  attachments={attachmentsByMessage.get(message.id)}
                  onOpenAttachment={(attachment, id) => setViewing({ attachment, id })}
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
          onClearSelectedText={onClearSelection}
          lectureTitle={lectureTitle}
          onDetachLecture={onDetachLecture}
          selectedAttachments={listedAttachments.filter((a) => a.selected)}
          onUnselectAttachment={(id) => void selectAttachment(id, false).catch(() => {})}
          hasAttachments={listedAttachments.some((a) => a.status === 'ready')}
          onOpenAttachmentList={() => setLocalListOpen(true)}
          prefill={prefill}
          droppedFiles={droppedFiles}
          autoFocus={variant === 'page'}
        />
        <p className="chat-disclaimer">{t('chatAiDisclaimer')}</p>
      </div>

      <AttachmentListModal
        open={listOpen && !viewing}
        attachments={listedAttachments}
        onOpen={(a) => setViewing({ attachment: viewableFromAttachment(a), id: a.id })}
        onToggleSelected={selectAttachment}
        onClose={closeList}
      />
      <AttachmentViewerModal
        attachment={viewing?.attachment ?? null}
        onRemove={
          viewing?.id && attachments.some((a) => a.id === viewing.id && a.status === 'ready')
            ? () => removeAttachment(viewing.id!)
            : undefined
        }
        onClose={() => setViewing(null)}
      />
    </div>
  );
};
