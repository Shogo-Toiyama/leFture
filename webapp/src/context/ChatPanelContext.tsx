import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import type { ChatScreenRef, ChatSelection } from '../types/chat';
import { useAiConsent } from './AiConsentContext';

/**
 * 横断チャットボットの「右側パネル(狭い画面ではボトムシート)」の状態。
 *
 * 会話の置き場は専用ページ(/chat)で、このパネルは「読んでいる画面を離れずに
 * 聞く」ための入口。どの画面からでも右下のボタンや、文章選択ツールバーの
 * 「Ask」から開ける。
 */
export interface ChatOpenRequest {
  /** 開く会話。未指定なら、パネルで直前に開いていた会話を続ける。 */
  threadId?: string | null;
  /** trueなら新しい会話として開く。 */
  newConversation?: boolean;
  /** 次の送信に添える選択(「Ask」)。 */
  selection?: ChatSelection;
}

interface ChatPanelContextValue {
  isOpen: boolean;
  view: 'conversation' | 'history';
  /** パネルで開いている会話。nullなら新しい会話。 */
  threadId: string | null;
  /** 次の送信に添える選択。1回送ったら外れる。 */
  selection: ChatSelection | null;
  /** 今いる画面が見せているページ(useChatScreenで各画面が登録する)。毎回の送信に添える。 */
  pageScreen: ChatScreenRef | null;
  /** 今いる画面の講義を文脈に使わない(ユーザーがチップを外した)。 */
  lectureDetached: boolean;
  open: (request?: ChatOpenRequest) => void;
  close: () => void;
  showHistory: () => void;
  showConversation: (threadId: string | null) => void;
  /** 新しい会話がサーバー側で作られたとき。 */
  adoptThread: (threadId: string) => void;
  clearSelection: () => void;
  setPageScreen: (screen: ChatScreenRef | null) => void;
  setLectureDetached: (detached: boolean) => void;
}

const ChatPanelContext = createContext<ChatPanelContextValue | undefined>(undefined);

export const ChatPanelProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [view, setView] = useState<'conversation' | 'history'>('conversation');
  const [threadId, setThreadId] = useState<string | null>(null);
  const [selection, setSelection] = useState<ChatSelection | null>(null);
  const [pageScreen, setPageScreen] = useState<ChatScreenRef | null>(null);
  const [lectureDetached, setLectureDetached] = useState(false);

  const { hasConsent, requestConsent } = useAiConsent();

  const doOpen = useCallback(
    (request: ChatOpenRequest = {}) => {
      if (request.newConversation) {
        setThreadId(null);
      } else if (request.threadId !== undefined) {
        setThreadId(request.threadId);
      } else if (request.selection && !isOpen) {
        // パネルを閉じた状態で文章を選んで「Ask」した: その文章についての新しい会話にする。
        // 既にパネルで会話中なら、その会話に選択テキストを添えて続ける。
        setThreadId(null);
      }
      if (request.selection !== undefined) setSelection(request.selection.text ? request.selection : null);
      setView('conversation');
      setIsOpen(true);
    },
    [isOpen]
  );

  // チャットで入力した内容・資料をAIサービスへ送ることへの同意(アカウント単位)。まだなら聞いてから開く
  const open = useCallback(
    (request: ChatOpenRequest = {}) => {
      if (hasConsent('chat')) {
        doOpen(request);
        return;
      }
      void requestConsent('chat').then((agreed) => {
        if (agreed) doOpen(request);
      });
    },
    [hasConsent, requestConsent, doOpen]
  );

  const close = useCallback(() => setIsOpen(false), []);
  const showHistory = useCallback(() => setView('history'), []);
  const showConversation = useCallback((id: string | null) => {
    setThreadId(id);
    setView('conversation');
  }, []);
  const adoptThread = useCallback((id: string) => setThreadId(id), []);
  const clearSelection = useCallback(() => setSelection(null), []);

  const value = useMemo(
    () => ({
      isOpen,
      view,
      threadId,
      selection,
      pageScreen,
      lectureDetached,
      open,
      close,
      showHistory,
      showConversation,
      adoptThread,
      clearSelection,
      setPageScreen,
      setLectureDetached,
    }),
    [isOpen, view, threadId, selection, pageScreen, lectureDetached, open, close, showHistory, showConversation, adoptThread, clearSelection]
  );

  return <ChatPanelContext.Provider value={value}>{children}</ChatPanelContext.Provider>;
};

/** チャットパネルの外(ログイン前の画面など)ではnullを返す。呼び出し側は「Ask」を出さない。 */
export function useChatPanel(): ChatPanelContextValue | null {
  return useContext(ChatPanelContext) ?? null;
}

/**
 * 今いる画面が見せているページをチャットに知らせる(画面を離れたら外れる)。
 * 送られるのはページの種類とIDだけで、本文はバックエンドがDBから読む。
 * nullなら何も知らせない(ロック中のページ・読み込み中など)。
 */
export function useChatScreen(screen: ChatScreenRef | null): void {
  const setPageScreen = useContext(ChatPanelContext)?.setPageScreen;
  // オブジェクトは毎回作り直されるので、中身が同じなら登録し直さない
  const key = screen ? JSON.stringify(screen) : null;
  useEffect(() => {
    if (!setPageScreen || !key) return;
    setPageScreen(JSON.parse(key) as ChatScreenRef);
    return () => setPageScreen(null);
  }, [setPageScreen, key]);
}
