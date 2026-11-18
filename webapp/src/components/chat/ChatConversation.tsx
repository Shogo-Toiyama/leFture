import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { ArrowDown, Upload } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import { useChatConversation, type LocalChatMessage } from '../../hooks/useChatConversation';
import { useChatScroll } from '../../hooks/useChatScroll';
import {
  CHAT_MAX_ATTACHMENT_CHARS,
  CHAT_MAX_ATTACHMENTS_PER_MESSAGE,
  CHAT_MAX_ATTACHMENTS_PER_THREAD,
  CHAT_MAX_MENTIONS_PER_MESSAGE,
  CHAT_MAX_MESSAGE_CHARS,
  CHAT_MAX_SELECTED_TEXT_CHARS,
  type ChatAttachment,
  type ChatAttachmentRef,
  type ChatDraftAttachment,
  type ChatMessageContext,
  type ChatScreenRef,
  type ChatSelection,
} from '../../types/chat';
import { AttachmentListModal } from './AttachmentListModal';
import { AttachmentViewerModal, viewableFromAttachment, type ViewableAttachment } from './AttachmentViewerModal';
import { ChatComposer, type ChatInsertRequest } from './ChatComposer';
import { ChatMessageItem } from './ChatMessageItem';
import { LaunchGateBackdrop, type ChatWorld } from './LaunchGateBackdrop';

interface ChatConversationProps {
  threadId: string | null;
  world?: ChatWorld;
  onThreadCreated: (threadId: string) => void;
  /** 1往復が終わったとき(スレッド名が付いた可能性があるので見出しを読み直す等)。 */
  onTurnComplete?: () => void;
  /** 話題にする講義。nullなら講義を指定しない。 */
  lectureId: string | null;
  lectureTitle: string | null;
  /** 話題にするコース(コースの画面から開いたとき。講義があるときは講義を優先して送らない)。 */
  courseId?: string | null;
  courseTitle?: string | null;
  /** 講義・コースのチップを外す。 */
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
    case 'TOO_MANY_MENTIONS':
      return { key: 'chatErrorTooManyMentions', params: { max: CHAT_MAX_MENTIONS_PER_MESSAGE } };
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
export const ChatConversation: React.FC<ChatConversationProps> = ({
  threadId,
  world,
  onThreadCreated,
  onTurnComplete,
  lectureId,
  lectureTitle,
  courseId = null,
  courseTitle = null,
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
    hasMore,
    loadingOlder,
    loadOlder,
    send,
    stop,
    stopping,
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
  const showGate = messages.length === 0 && !loading && !loadError;
  const isGenerating = !loading && messages.some((message) =>
    message.role === 'assistant' && message.status === 'streaming');
  const {
    scrollRef, threadRef, showJumpToBottom, jumpToBottom, preservePositionOnSend,
    captureBeforePrepend, onScroll, onWheel, onKeyDown, onPointerDown, onTouchStart, onTouchEnd,
  } = useChatScroll(messages, loading, showGate, isGenerating);

  const location = useLocation();
  // 親に .is-paper があるか、もしくは world prop で paper/universe を判定
  const [domIsPaper, setDomIsPaper] = useState(false);
  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const check = () => setDomIsPaper(Boolean(el.closest('.is-paper')));
    check();
    const observer = new MutationObserver(check);
    const host = el.closest('.chat-panel') || el.closest('.chat-fullscreen') || document.body;
    observer.observe(host, { attributes: true, attributeFilter: ['class'] });
    return () => observer.disconnect();
  }, [location.pathname]);
  const resolvedWorld: ChatWorld = world ?? (domIsPaper ? 'paper' : 'universe');
  const [prefill, setPrefill] = useState<{
    text: string;
    attachments?: ChatDraftAttachment[];
    references?: ChatAttachmentRef[];
    nonce: number;
  } | null>(null);
  /** 資料の一覧の「全文で添付」「メンション」で入力欄に入れる資料 */
  const [insertRequest, setInsertRequest] = useState<ChatInsertRequest | null>(null);
  /** 入力欄で指している既存の資料(資料の一覧に「添付する予定」として見せる) */
  const [pendingRefs, setPendingRefs] = useState<ChatAttachmentRef[]>([]);
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
  // 本文の中のチップ・外した知らせに名前を出すため(外した資料も含む)
  const attachmentsById = useMemo(() => new Map(attachments.map((a) => [a.id, a])), [attachments]);
  const readyAttachments = useMemo(() => listedAttachments.filter((a) => a.status === 'ready'), [listedAttachments]);

  const attachmentsByMessage = useMemo(() => {
    const map = new Map<string, ChatAttachment[]>();
    for (const a of attachments) {
      if (!a.message_id) continue;
      map.set(a.message_id, [...(map.get(a.message_id) ?? []), a]);
    }
    return map;
  }, [attachments]);

  // ---- 編集・作り直し(一本道。ロードマップ2-12) ----
  /** 下の入力欄で直しているユーザーメッセージ。送ると、そのメッセージ自身と後ろが消えて、そこからやり直す */
  const [editingId, setEditingId] = useState<string | null>(null);
  /** 編集・作り直しが送る前に弾かれた(残高不足など)。会話は元のまま */
  const [editError, setEditError] = useState<{ code: string; detail: Record<string, unknown> } | null>(null);
  /** 後ろで添付した資料も消えるときだけ、送る前に確かめる */
  const [pendingEdit, setPendingEdit] = useState<{
    content: string;
    drafts: ChatDraftAttachment[];
    references: ChatAttachmentRef[];
    context: ChatMessageContext;
  } | null>(null);
  useEffect(() => {
    setEditingId(null);
    setEditError(null);
    setPendingEdit(null);
  }, [threadId]);

  const editInfo = useMemo(() => {
    if (!editingId) return null;
    const index = messages.findIndex((m) => m.id === editingId);
    if (index < 0) return null;
    const later = messages.slice(index + 1);
    const laterIds = new Set(later.map((m) => m.id));
    return {
      laterIds,
      turns: later.filter((m) => m.role === 'user').length,
      doomedAttachments: attachments.filter(
        (a) => a.message_id && laterIds.has(a.message_id) && (a.status === 'ready' || a.status === 'processing')
      ),
    };
  }, [editingId, messages, attachments]);

  /** 送るときに一緒に指す資料(このメッセージで添付・指した資料のうち、今も使えるもの) */
  const referencesOf = useCallback(
    (message: LocalChatMessage): ChatAttachmentRef[] =>
      (message.context.attachments ?? [])
        .filter((a) => attachmentsById.get(a.id)?.status === 'ready')
        .map((a) => ({ attachment_id: a.id, mode: a.mode })),
    [attachmentsById]
  );

  // 1往復が終わった(sending: true → false)ことを親に知らせる
  const wasSendingRef = useRef(false);
  useEffect(() => {
    if (wasSendingRef.current && !sending) onTurnComplete?.();
    wasSendingRef.current = sending;
  }, [sending, onTurnComplete]);

  const handleScroll = () => {
    onScroll();
    const el = scrollRef.current;
    if (!el) return;
    if (el.scrollTop <= 150 && hasMore && !loadingOlder && !loading) {
      void loadOlder(captureBeforePrepend);
    }
  };

  // 会話の中のAIの回答を選んで「返信」したときの引用。パネルの「Ask」(selection)とは別に持ち、
  // どちらかがあれば次の送信に添える(新しい「Ask」が来たら、そちらを優先して返信の引用は外す)
  const [replySelection, setReplySelection] = useState<ChatSelection | null>(null);
  useEffect(() => {
    if (selection) setReplySelection(null);
  }, [selection]);
  useEffect(() => {
    setReplySelection(null);
  }, [threadId]);
  const activeSelection = replySelection ?? selection;
  const clearSelection = useCallback(() => {
    setReplySelection(null);
    onClearSelection?.();
  }, [onClearSelection]);

  const selectedText = activeSelection?.text ?? null;
  const selectedTooLong = (selectedText?.length ?? 0) > CHAT_MAX_SELECTED_TEXT_CHARS;

  /** 送ったときの文脈から、入力欄の引用(選択・返信)を戻す */
  const restoreQuote = (context: ChatMessageContext) =>
    setReplySelection(
      context.selected_text
        ? { text: context.selected_text, screen: context.screen, replyToMessageId: context.reply_to_message_id }
        : null
    );

  /** 編集を送る。送る前に弾かれたら、会話は元のままなので入力欄を編集中に戻す */
  const sendEdit = (
    targetId: string,
    content: string,
    drafts: ChatDraftAttachment[],
    references: ChatAttachmentRef[],
    context: ChatMessageContext
  ) => {
    preservePositionOnSend();
    setEditingId(null);
    setEditError(null);
    void send(content, context, drafts, references, {
      replaceFromMessageId: targetId,
      onRejected: (code, detail) => {
        setEditingId(targetId);
        setEditError({ code, detail });
        setPrefill({ text: content, attachments: drafts, references, nonce: Date.now() });
        restoreQuote(context);
      },
    });
  };

  /** 自分のメッセージを編集する: 本文・資料・引用を下の入力欄に読み込む */
  const startEdit = (message: LocalChatMessage) => {
    if (sending) return;
    setEditingId(message.id);
    setEditError(null);
    setPrefill({ text: message.content, attachments: [], references: referencesOf(message), nonce: Date.now() });
    restoreQuote(message.context);
  };

  const cancelEdit = () => {
    setEditingId(null);
    setEditError(null);
    setReplySelection(null);
    setPrefill({ text: '', attachments: [], references: [], nonce: Date.now() });
  };

  const handleSend = useCallback(
    (content: string, drafts: ChatDraftAttachment[] = [], references: ChatAttachmentRef[] = []) => {
      const context: ChatMessageContext = {};
      if (lectureId) context.lecture_id = lectureId;
      else if (courseId) context.course_id = courseId;
      // 選んだページ(「Ask」)を優先し、無ければ今いる画面のページ
      const screenRef = activeSelection?.screen ?? screen;
      if (screenRef) context.screen = screenRef;
      if (activeSelection) {
        context.selected_text = activeSelection.text;
        if (activeSelection.before) context.selection_before = activeSelection.before;
        if (activeSelection.after) context.selection_after = activeSelection.after;
        if (activeSelection.replyToMessageId) context.reply_to_message_id = activeSelection.replyToMessageId;
      }
      // 選択テキストは1回の質問にだけ添える
      if (activeSelection) clearSelection();
      if (editingId) {
        // 後ろで添付した資料も消えるときだけ、送る前に確かめる(往復が消えることはバーに出ている)
        if (editInfo && editInfo.doomedAttachments.length > 0) {
          setPendingEdit({ content, drafts, references, context });
          return;
        }
        sendEdit(editingId, content, drafts, references, context);
        return;
      }
      preservePositionOnSend();
      void send(content, context, drafts, references);
    },
    [lectureId, courseId, activeSelection, screen, send, clearSelection, editingId, editInfo, preservePositionOnSend]
  );

  /**
   * 最後の回答を作り直す: 直前の質問を、同じ内容で編集して送る(その質問と回答を消して、新しい往復を書く)。
   * 作り直せるのは最後の回答だけ(途中の回答を作り直すと後ろの会話の前提が崩れるので、それは質問の編集で行う)。
   */
  const regenerateFor = (assistantIndex: number) => {
    if (sending || editingId || assistantIndex !== messages.length - 1) return undefined;
    const target = messages[assistantIndex];
    if (!['complete', 'stopped', 'error'].includes(target.status)) return undefined;
    const previousUser = [...messages.slice(0, assistantIndex)].reverse().find((m) => m.role === 'user');
    if (!previousUser || previousUser.id.startsWith('local-')) return undefined;
    return () => {
      preservePositionOnSend();
      setEditError(null);
      void send(previousUser.content, previousUser.context, [], referencesOf(previousUser), {
        replaceFromMessageId: previousUser.id,
        onRejected: (code, detail) => setEditError({ code, detail }),
      });
    };
  };

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
              <button
                type="button"
                className="chat-banner-btn is-primary"
                onClick={() => {
                  preservePositionOnSend();
                  retry(message.id);
                }}
              >
                {t('chatResend')}
              </button>
            )
          )}
          <button
            type="button"
            className="chat-banner-btn"
            onClick={() => {
              discard(message.id);
              setPrefill({
                text: message.content,
                attachments: message.localAttachments,
                references: message.localReferences,
                nonce: Date.now(),
              });
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
      <div
        className="chat-scroll"
        ref={scrollRef}
        role="region"
        aria-label={t('chatMessages')}
        tabIndex={0}
        onScroll={handleScroll}
        onWheelCapture={onWheel}
        onKeyDown={onKeyDown}
        onPointerDownCapture={onPointerDown}
        onTouchStartCapture={onTouchStart}
        onTouchEnd={onTouchEnd}
        onTouchCancel={onTouchEnd}
      >
        {showGate ? (
          <div className="chat-empty-gate">
            <LaunchGateBackdrop world={resolvedWorld} />
            <div className="chat-gate-content">
              <p
                className="chat-gate-eyebrow rise"
                style={{ '--d': '0.15s' } as React.CSSProperties}
              >
                AI CHAT
              </p>
              <h2
                className="chat-gate-title rise"
                style={{ '--d': '0.25s' } as React.CSSProperties}
              >
                {t('chatEmptyTitle')}
              </h2>
              <p
                className="chat-gate-sub rise"
                style={{ '--d': '0.35s' } as React.CSSProperties}
              >
                {t('chatEmptySubtitle')}
              </p>
              <div className="chat-gate-chips">
                {suggestions.map((text, i) => (
                  <button
                    key={text}
                    type="button"
                    className="chat-gate-chip rise"
                    style={{ '--d': `${0.5 + i * 0.08}s` } as React.CSSProperties}
                    onClick={() => setPrefill({ text, nonce: Date.now() })}
                  >
                    {text}
                  </button>
                ))}
              </div>
            </div>
          </div>
        ) : (
          <div className="chat-thread" ref={threadRef}>
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
            ) : (
              <>
                {loadingOlder && (
                  <div className="chat-older-loading" aria-live="polite">
                    <span className="chat-older-spinner" />
                  </div>
                )}
                {messages.map((message, index) => (
                  <React.Fragment key={message.id}>
                  <ChatMessageItem
                    message={message}
                    world={resolvedWorld}
                    attachments={attachmentsByMessage.get(message.id)}
                    attachmentsById={attachmentsById}
                    onOpenAttachment={(attachment, id) => setViewing({ attachment, id })}
                    onOpenCitation={onOpenCitation}
                    onResend={message.status === 'error' ? regenerateFor(index) : undefined}
                    onRegenerate={message.role === 'assistant' ? regenerateFor(index) : undefined}
                    onEdit={
                      message.role === 'user' && !sending && !message.failedCode && !message.id.startsWith('local-')
                        ? () => startEdit(message)
                        : undefined
                    }
                    editState={
                      message.id === editingId ? 'target' : editInfo?.laterIds.has(message.id) ? 'doomed' : undefined
                    }
                    onReplyToSelection={setReplySelection}
                    question={
                      message.role === 'assistant'
                        ? [...messages.slice(0, index)].reverse().find((m) => m.role === 'user')?.content
                        : undefined
                    }
                  />
                  {renderFailure(message)}
                </React.Fragment>
              ))}
            </>
          )}
          </div>
        )}
      </div>

      <div className="chat-footer">
        {showJumpToBottom && messages.length > 0 && !loading && (
          <button
            type="button"
            className="chat-jump-to-bottom"
            aria-label={t('chatJumpToBottom')}
            title={t('chatJumpToBottom')}
            onClick={() => {
              scrollRef.current?.focus({ preventScroll: true });
              jumpToBottom();
            }}
          >
            <ArrowDown size={18} aria-hidden="true" />
          </button>
        )}
        {editError && (
          <div className="chat-banner" role="alert">
            <span>{t(failureCopy(editError.code, editError.detail).key, failureCopy(editError.code, editError.detail).params)}</span>
            <div className="chat-banner-actions">
              <button type="button" className="chat-banner-btn" onClick={() => setEditError(null)}>
                {t('chatDismiss')}
              </button>
            </div>
          </div>
        )}
        {selectedTooLong && (
          <p className="chat-footer-warning">{t('chatErrorSelectedTooLong', { max: CHAT_MAX_SELECTED_TEXT_CHARS })}</p>
        )}
        <ChatComposer
          // パネル ⇄ 全画面の切り替えで、入力中の中身をこの名前で預けて戻す
          draftKey={threadId ?? 'new'}
          disabled={sending || selectedTooLong}
          onStop={sending ? stop : undefined}
          stopping={stopping}
          editingLabel={
            editInfo
              ? editInfo.turns === 0
                ? t('chatEditingLast')
                : editInfo.doomedAttachments.length > 0
                  ? t('chatEditingWithAttachments', { turns: editInfo.turns, count: editInfo.doomedAttachments.length })
                  : t('chatEditing', { turns: editInfo.turns })
              : null
          }
          onCancelEdit={cancelEdit}
          placeholder={messages.length > 0 ? t('chatInputPlaceholderFollowUp') : t('chatInputPlaceholder')}
          onSend={handleSend}
          selectedText={selectedText}
          onClearSelectedText={clearSelection}
          lectureTitle={lectureTitle}
          courseTitle={lectureId ? null : courseTitle}
          onDetachLecture={onDetachLecture}
          selectedAttachments={listedAttachments.filter((a) => a.selected && a.kind !== 'image')}
          onUnselectAttachment={(id) => void selectAttachment(id, false).catch(() => {})}
          // 編集中は、送ると消える資料を指せないようにする
          mentionables={
            editInfo
              ? readyAttachments.filter((a) => !(a.message_id && editInfo.laterIds.has(a.message_id)))
              : readyAttachments
          }
          onOpenAttachmentList={() => setLocalListOpen(true)}
          prefill={prefill}
          droppedFiles={droppedFiles}
          insertRequest={insertRequest}
          onPendingChange={setPendingRefs}
          onViewAttachment={(id) => {
            const a = attachmentsById.get(id);
            if (a) setViewing({ attachment: viewableFromAttachment(a), id: a.id });
          }}
          autoFocus={variant === 'page'}
        />
        <p className="chat-disclaimer">{t('chatAiDisclaimer')}</p>
      </div>

      <AttachmentListModal
        open={listOpen && !viewing}
        attachments={listedAttachments}
        onView={(a) => setViewing({ attachment: viewableFromAttachment(a), id: a.id })}
        pendingRefs={pendingRefs}
        // 一覧は開いたまま(続けていくつも選べるように)。入力欄には裏で「@名前」が入る
        onAttach={(a, mode) => setInsertRequest({ attachment: a, mode, nonce: Date.now() })}
        onPin={(a) => selectAttachment(a.id, true)}
        onUnpin={(a) => selectAttachment(a.id, false)}
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
      {pendingEdit && editingId && (
        <div className="citation-modal-backdrop" onClick={() => undefined}>
          <div className="citation-modal-card chat-confirm-card" role="dialog" aria-label={t('chatEditConfirmTitle')}>
            <div className="citation-modal-header">
              <div className="citation-modal-title-group">
                <h3 className="citation-modal-title">{t('chatEditConfirmTitle')}</h3>
              </div>
            </div>
            <div className="chat-confirm-body">
              <p>
                {t('chatEditConfirmBody', {
                  turns: editInfo?.turns ?? 0,
                  titles: (editInfo?.doomedAttachments ?? [])
                    .map((a) => `「${a.title || a.file_name || t('chatAttachmentUntitled')}」`)
                    .join(''),
                })}
              </p>
              <div className="chat-confirm-actions">
                <button
                  type="button"
                  className="chat-banner-btn"
                  onClick={() => {
                    // 入力欄は送ったときに空になっているので、書いたものを戻す
                    setPrefill({
                      text: pendingEdit.content,
                      attachments: pendingEdit.drafts,
                      references: pendingEdit.references,
                      nonce: Date.now(),
                    });
                    restoreQuote(pendingEdit.context);
                    setPendingEdit(null);
                  }}
                >
                  {t('cancel')}
                </button>
                <button
                  type="button"
                  className="chat-banner-btn is-danger"
                  onClick={() => {
                    const edit = pendingEdit;
                    setPendingEdit(null);
                    sendEdit(editingId, edit.content, edit.drafts, edit.references, edit.context);
                  }}
                >
                  {t('chatEditConfirmSend')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
