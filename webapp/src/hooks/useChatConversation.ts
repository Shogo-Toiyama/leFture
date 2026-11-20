import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ChatSendError,
  getChatMessage,
  listChatAttachments,
  listChatMessages,
  newClientMessageId,
  removeChatAttachment,
  sendChatMessage,
  stopChatMessage,
  setChatAttachmentSelected,
} from '../lib/chat';
import type {
  ChatAttachment,
  ChatCitation,
  ChatAttachmentRef,
  ChatDraftAttachment,
  ChatSearchDetail,
  ChatMessage,
  ChatMessageContext,
  ChatStage,
  ChatStreamEvent,
} from '../types/chat';

/** 画面表示用のメッセージ。サーバーの行に、送信中・失敗などの画面専用の状態を足したもの。 */
export interface LocalChatMessage extends ChatMessage {
  /** 送信前チェックで弾かれたuserメッセージ(サーバーには保存されていない)。error_codeが入る。 */
  failedCode?: string;
  failedDetail?: Record<string, unknown>;
  /** 生成中の段階(assistantのみ) */
  stage?: ChatStage;
  /** 生成中の思考テキスト(assistantのみ。完了後は破棄される) */
  progressLabel?: string;
  /** stageがsearchingのとき、今の周で探しているもの。 */
  searchDetail?: ChatSearchDetail[];
  searchQuery?: string;
  searchTarget?: string;
  searchLayer?: string;
  searchHandle?: string;
  /** 生成中に届いた出典候補(assistantのみ。完了後は本文で使われたcitationsだけが残る) */
  pendingSources?: ChatCitation[];
  /** 受信中に通信が切れ、サーバー側で生成が終わるのを待っている */
  reconnecting?: boolean;
  /**
   * この送信で添付した資料の下書き(userのみ)。サーバーの資料一覧(attachments)が読み直されるまでの
   * 表示と、送れなかったときの再送に使う。
   */
  localAttachments?: ChatDraftAttachment[];
  /** この送信で指した既存の資料(userのみ。送れなかったときの再送に使う)。 */
  localReferences?: ChatAttachmentRef[];
  /** 停止を押して、サーバーが止めたところまでで確定するのを待っている(assistantのみ) */
  stopping?: boolean;
  /** 停止のリクエストが届かなかった(受信は続いている。もう一度押せる) */
  stopFailed?: boolean;
}

/** 送信のオプション(編集・作り直し)。 */
export interface SendOptions {
  /** このユーザーメッセージ自身と、それより後ろを消してから送る(編集・作り直し。一本道) */
  replaceFromMessageId?: string;
  /**
   * 送る前に弾かれた(残高不足など)。サーバーでは何も消えていないので、画面の会話は元に戻してある。
   * 呼び出し側は入力欄を編集中に戻すなどする。
   */
  onRejected?: (code: string, detail: Record<string, unknown>) => void;
}

interface Options {
  /** 新しいスレッドがサーバー側で作られた瞬間に呼ばれる(URLを /chat/:id に切り替える等)。 */
  onThreadCreated?: (threadId: string) => void;
}

/** 通信切断後に、サーバー側での生成完了をDBで待つ間隔と回数(約2分)。 */
const RECONNECT_POLL_INTERVAL_MS = 3000;
const RECONNECT_POLL_MAX_ATTEMPTS = 40;

const CHAT_PAGE_SIZE = 20;

/**
 * 1つの会話(スレッド)の表示と送信。threadIdがnullなら新しい会話として始め、
 * 最初の送信でサーバーがスレッドを作る。
 */
export function useChatConversation(threadId: string | null, options: Options = {}) {
  const [messages, setMessages] = useState<LocalChatMessage[]>([]);
  const [loading, setLoading] = useState(Boolean(threadId));
  const [loadError, setLoadError] = useState<unknown>(null);
  const [sending, setSending] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  /** 停止を押してから、止まった行が返るまで */
  const [stopping, setStopping] = useState(false);
  /** このスレッドの資料(外したものを除く、添付順)。 */
  const [attachments, setAttachments] = useState<ChatAttachment[]>([]);

  // 送信中にサーバーが作ったスレッドid。onThreadCreatedでURLが変わっても
  // (=threadId propが同じ値に変わっても)、会話を読み直して表示中の
  // ストリームを消さないために使う。
  const activeThreadIdRef = useRef<string | null>(threadId);
  const mountedRef = useRef(true);
  const abortRef = useRef<AbortController | null>(null);
  /**
   * 今受信している返答。返答のIDはmetaイベントで届くので、それより前に停止を押したら
   * stopRequestedを立てておき、metaが届いた瞬間に止める。
   */
  const streamRef = useRef<{ assistantId: string | null; controller: AbortController; stopRequested: boolean } | null>(
    null
  );
  const onThreadCreatedRef = useRef(options.onThreadCreated);
  onThreadCreatedRef.current = options.onThreadCreated;

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      // 画面を離れたら受信だけ止める(サーバー側の生成・保存・課金は最後まで走る)
      abortRef.current?.abort();
    };
  }, []);

  const patchMessage = useCallback((id: string, patch: Partial<LocalChatMessage>) => {
    if (!mountedRef.current) return;
    setMessages((prev) => prev.map((m) => (m.id === id ? { ...m, ...patch } : m)));
  }, []);

  /**
   * 停止のリクエストを送り、サーバーが止めたところまでで確定した行に差し替える。受信もここで止める
   * (止めた後はサーバーも流さない)。確定した行が返るので、完了をDBで待つ必要は無い。
   */
  const performStop = useCallback(async (assistantId: string, controller: AbortController) => {
    patchMessage(assistantId, { stopping: true, stopFailed: false });
    try {
      const row = await stopChatMessage(assistantId);
      controller.abort();
      if (!mountedRef.current) return;
      setMessages((prev) =>
        prev.map((m) =>
          m.id === assistantId
            ? { ...m, ...row, stopping: false, stage: undefined, pendingSources: undefined, reconnecting: false }
            : m
        )
      );
    } catch {
      patchMessage(assistantId, { stopping: false, stopFailed: true });
    } finally {
      if (mountedRef.current) setStopping(false);
    }
  }, [patchMessage]);

  /** 生成中の返答を止める。止めても送ったメッセージは残り、そのまま次を送れる。 */
  const stop = useCallback(() => {
    const current = streamRef.current;
    if (!current || stopping) return;
    setStopping(true);
    if (!current.assistantId) {
      current.stopRequested = true;
      return;
    }
    void performStop(current.assistantId, current.controller);
  }, [stopping, performStop]);

  /** サーバー側の生成が終わるまでDBを見に行き、終わったら差し替える。 */
  const waitForServerCompletion = useCallback(
    async (messageId: string) => {
      patchMessage(messageId, { reconnecting: true });
      for (let attempt = 0; attempt < RECONNECT_POLL_MAX_ATTEMPTS; attempt++) {
        await new Promise((resolve) => setTimeout(resolve, RECONNECT_POLL_INTERVAL_MS));
        if (!mountedRef.current) return;
        try {
          const row = await getChatMessage(messageId);
          if (row && row.status !== 'streaming') {
            patchMessage(messageId, {
              ...row,
              reconnecting: false,
              stage: undefined,
              pendingSources: undefined,
            });
            return;
          }
        } catch {
          // 一時的な読み取り失敗は次の試行に任せる
        }
      }
      patchMessage(messageId, { reconnecting: false, status: 'error', stage: undefined });
    },
    [patchMessage]
  );

  /** 資料の一覧を読み直す。読めなくても会話は使えるので、失敗は今の一覧のままにする。 */
  const refreshAttachments = useCallback(async (id: string | null) => {
    if (!id) {
      setAttachments([]);
      return;
    }
    try {
      const rows = await listChatAttachments(id);
      if (mountedRef.current && activeThreadIdRef.current === id) setAttachments(rows);
    } catch {
      // 次の往復の後にもう一度読む
    }
  }, []);

  const load = useCallback(
    async (id: string) => {
      setLoading(true);
      setLoadError(null);
      void refreshAttachments(id);
      try {
        const { messages: rows, hasMore: more } = await listChatMessages(id, { limit: CHAT_PAGE_SIZE + 1 });
        if (!mountedRef.current) return;
        setMessages(rows);
        setHasMore(more);
        // 生成中にページを再読み込みした等: まだstreamingの返答は完了を待つ
        rows
          .filter((m) => m.role === 'assistant' && m.status === 'streaming')
          .forEach((m) => void waitForServerCompletion(m.id));
      } catch (e) {
        if (mountedRef.current) setLoadError(e);
      } finally {
        if (mountedRef.current) setLoading(false);
      }
    },
    [waitForServerCompletion, refreshAttachments]
  );

  const loadOlder = useCallback(
    async (onBeforePrepend?: () => void) => {
      const id = activeThreadIdRef.current;
      if (!id || !hasMore || loadingOlder || loading) return;
      const oldest = messages.find((m) => !m.id.startsWith('local-'));
      if (!oldest) return;

      setLoadingOlder(true);
      try {
        const { messages: rows, hasMore: more } = await listChatMessages(id, {
          limit: CHAT_PAGE_SIZE + 1,
          before: oldest.created_at,
        });
        if (!mountedRef.current) return;
        onBeforePrepend?.();
        setMessages((prev) => [...rows, ...prev]);
        setHasMore(more);
      } catch {
        // 再試行できるよう状態のみ戻す
      } finally {
        if (mountedRef.current) setLoadingOlder(false);
      }
    },
    [hasMore, loadingOlder, loading, messages]
  );

  useEffect(() => {
    if (threadId && threadId === activeThreadIdRef.current && messages.length > 0) {
      // 自分が送信して作ったスレッドへURLが追従しただけ。読み直さない。
      return;
    }
    // 別の会話へ切り替えた: 前の会話の受信だけ止める(サーバー側の生成は続き、
    // その会話を開き直せばDBから読める)。止めないと送信中の状態が残り、
    // 切り替え先で入力欄が使えないままになる。
    abortRef.current?.abort();
    activeThreadIdRef.current = threadId;
    // 前の会話の資料を、切り替え先の会話で一瞬でも見せない
    setAttachments([]);
    if (threadId) {
      void load(threadId);
    } else {
      setMessages([]);
      setAttachments([]);
      setHasMore(false);
      setLoadingOlder(false);
      setLoading(false);
      setLoadError(null);
    }
    // messagesは「読み直すべきか」の判定にだけ使うので依存に入れない
  }, [threadId, load]);

  const send = useCallback(
    async (
      rawContent: string,
      context?: ChatMessageContext,
      drafts?: ChatDraftAttachment[],
      references?: ChatAttachmentRef[],
      sendOptions: SendOptions = {}
    ) => {
      const content = rawContent.trim();
      const replaceFrom = sendOptions.replaceFromMessageId;
      const localAttachments = drafts?.length ? drafts : undefined;
      const localReferences = references?.length ? references : undefined;
      // 資料だけを送るのは許す
      if ((!content && !localAttachments && !localReferences) || sending) return;
      // 画面のチップ用に、添付・指した資料と渡し方を残す(サーバーも同じものを保存する)
      const sentContext: ChatMessageContext = {
        ...(context ?? {}),
        ...(localAttachments || localReferences
          ? {
              attachments: [
                ...(localReferences ?? []).map((r) => ({ id: r.attachment_id, mode: r.mode })),
                ...(localAttachments ?? []).map((d) => ({
                  id: d.kind === 'file' ? (d.attachmentId ?? d.localId) : d.localId,
                  mode: 'full' as const,
                })),
              ],
            }
          : {}),
      };

      const clientMessageId = newClientMessageId();
      const now = new Date().toISOString();
      let userId = `local-user-${clientMessageId}`;
      let assistantId = `local-assistant-${clientMessageId}`;
      let receivedMeta = false;
      const baseThreadId = activeThreadIdRef.current ?? '';

      // 編集・作り直し: そのメッセージから後ろを画面から外す(送る前に弾かれたら戻す)
      let removed: LocalChatMessage[] = [];
      setMessages((prev) => {
        const cut = replaceFrom ? prev.findIndex((m) => m.id === replaceFrom) : -1;
        const kept = cut >= 0 ? prev.slice(0, cut) : prev;
        removed = cut >= 0 ? prev.slice(cut) : [];
        return [
          ...kept,
          {
            id: userId,
            thread_id: baseThreadId,
            role: 'user',
            content,
            status: 'complete',
            citations: [],
            context: sentContext,
            credits_charged_micro: null,
            created_at: now,
            localAttachments,
            localReferences,
          },
          {
            id: assistantId,
            thread_id: baseThreadId,
            role: 'assistant',
            content: '',
            status: 'streaming',
            citations: [],
            context: {},
            credits_charged_micro: null,
            created_at: now,
            stage: 'thinking',
          },
        ];
      });
      setSending(true);

      const controller = new AbortController();
      abortRef.current = controller;
      const stream = { assistantId: null as string | null, controller, stopRequested: false };
      streamRef.current = stream;

      const onEvent = (event: ChatStreamEvent) => {
        if (!mountedRef.current) return;
        switch (event.type) {
          case 'meta': {
            receivedMeta = true;
            const isNewThread = activeThreadIdRef.current !== event.thread_id;
            activeThreadIdRef.current = event.thread_id;
            const oldUserId = userId;
            const oldAssistantId = assistantId;
            userId = event.user_message_id;
            assistantId = event.assistant_message_id;
            setMessages((prev) =>
              prev.map((m) => {
                if (m.id === oldUserId) return { ...m, id: userId, thread_id: event.thread_id };
                if (m.id === oldAssistantId) return { ...m, id: assistantId, thread_id: event.thread_id };
                return m;
              })
            );
            if (isNewThread) onThreadCreatedRef.current?.(event.thread_id);
            stream.assistantId = assistantId;
            // 返答のIDが届く前に停止が押されていた
            if (stream.stopRequested) void performStop(assistantId, controller);
            break;
          }
          case 'status':
            patchMessage(assistantId, {
              stage: event.stage,
              searchDetail: event.detail,
              searchQuery: event.query,
              searchTarget: event.target,
              searchLayer: event.layer,
              searchHandle: event.handle,
              progressLabel: event.progress_label,
            });
            break;
          case 'sources':
            patchMessage(assistantId, { pendingSources: event.sources });
            break;
          case 'attachments':
            // 全文で読む枠を超えて外した資料など(返答の下に知らせる。資料の一覧も読み直す)
            patchMessage(assistantId, {
              context: { attachment_notice: { unpinned: event.unpinned, too_long: event.too_long } },
            });
            void refreshAttachments(activeThreadIdRef.current);
            break;
          case 'delta':
            setMessages((prev) =>
              prev.map((m) => (m.id === assistantId ? { ...m, content: m.content + event.text } : m))
            );
            break;
          case 'replace':
            patchMessage(assistantId, { content: event.text });
            break;
          case 'done':
            patchMessage(assistantId, {
              status: event.status,
              citations: event.citations ?? [],
              credits_charged_micro: Math.round((event.credits_charged ?? 0) * 1_000_000),
              stage: undefined,
              progressLabel: undefined,
              pendingSources: undefined,
            });
            break;
          case 'error':
            patchMessage(assistantId, {
              status: 'error',
              stage: undefined,
              progressLabel: undefined,
              pendingSources: undefined,
            });
            break;
        }
      };

      try {
        await sendChatMessage(
          {
            threadId: activeThreadIdRef.current,
            clientMessageId,
            content,
            context,
            attachments: localAttachments,
            references: localReferences,
            replaceFromMessageId: replaceFrom,
          },
          onEvent,
          controller.signal
        );
      } catch (e) {
        if ((e as Error)?.name === 'AbortError' || !mountedRef.current) return;
        const code = e instanceof ChatSendError ? e.code : 'NETWORK';
        if (code === 'NETWORK' && receivedMeta) {
          // 受信中に切れた。サーバー側では生成が続いているので、DBで完了を待つ。
          void waitForServerCompletion(assistantId);
        } else {
          // ストリームが始まる前に弾かれた(残高不足・送信頻度など)か、送信自体が
          // 届かなかった。userメッセージはサーバーに保存されていないので、
          // 返答の枠を消して「送れなかった」表示にする。
          const detail = e instanceof ChatSendError ? e.detail : {};
          if (replaceFrom) {
            // 編集は送る前に弾かれた: サーバーでは何も消えていないので、会話を元に戻す
            setMessages((prev) => [...prev.filter((m) => m.id !== userId && m.id !== assistantId), ...removed]);
            sendOptions.onRejected?.(code, detail);
            return;
          }
          setMessages((prev) =>
            prev
              .filter((m) => m.id !== assistantId)
              .map((m) => (m.id === userId ? { ...m, failedCode: code, failedDetail: detail } : m))
          );
        }
      } finally {
        if (abortRef.current === controller) abortRef.current = null;
        if (streamRef.current === stream) streamRef.current = null;
        if (mountedRef.current) {
          setSending(false);
          // 返答のIDが届く前に終わった(送れなかった等)ので、待っていた停止は要らない
          if (stream.stopRequested && !stream.assistantId) setStopping(false);
        }
        // 添付した資料の状態(確認済み・断った)と、AIが付けた名前を読み直す
        if ((localAttachments || localReferences) && receivedMeta) void refreshAttachments(activeThreadIdRef.current);
      }
    },
    [sending, patchMessage, waitForServerCompletion, refreshAttachments, performStop]
  );

  /** 送れなかったuserメッセージを取り除き、同じ内容でもう一度送る。 */
  const retry = useCallback(
    (failedMessageId: string) => {
      const target = messages.find((m) => m.id === failedMessageId);
      if (!target || !target.failedCode || sending) return;
      setMessages((prev) => prev.filter((m) => m.id !== failedMessageId));
      void send(target.content, target.context, target.localAttachments, target.localReferences);
    },
    [messages, sending, send]
  );

  /** 送れなかったuserメッセージを画面から消す(入力欄に戻す等は呼び出し側で)。 */
  const discard = useCallback((failedMessageId: string) => {
    setMessages((prev) => prev.filter((m) => m.id !== failedMessageId));
  }, []);

  const reload = useCallback(() => {
    if (activeThreadIdRef.current) void load(activeThreadIdRef.current);
  }, [load]);

  /** 資料を外す。外したらAIにはもう渡らない(会話の中の「添付した」印は残る)。 */
  const removeAttachment = useCallback(
    async (attachmentId: string) => {
      await removeChatAttachment(attachmentId);
      setAttachments((prev) => prev.filter((a) => a.id !== attachmentId));
    },
    []
  );

  /** 資料を全文で読ませる/外す。断られたら(上限など)元に戻して例外を投げる。 */
  const selectAttachment = useCallback(async (attachmentId: string, selected: boolean) => {
    setAttachments((prev) => prev.map((a) => (a.id === attachmentId ? { ...a, selected } : a)));
    try {
      await setChatAttachmentSelected(attachmentId, selected);
    } catch (e) {
      setAttachments((prev) => prev.map((a) => (a.id === attachmentId ? { ...a, selected: !selected } : a)));
      throw e;
    }
  }, []);

  return {
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
  };
}
