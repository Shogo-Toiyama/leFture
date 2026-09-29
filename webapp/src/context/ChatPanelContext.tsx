import React, { createContext, useCallback, useContext, useMemo, useState } from 'react';

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
  /** 次の送信に添える選択テキスト。 */
  selectedText?: string;
}

interface ChatPanelContextValue {
  isOpen: boolean;
  view: 'conversation' | 'history';
  /** パネルで開いている会話。nullなら新しい会話。 */
  threadId: string | null;
  /** 次の送信に添える選択テキスト。1回送ったら外れる。 */
  selectedText: string | null;
  /** 今いる画面の講義を文脈に使わない(ユーザーがチップを外した)。 */
  lectureDetached: boolean;
  open: (request?: ChatOpenRequest) => void;
  close: () => void;
  showHistory: () => void;
  showConversation: (threadId: string | null) => void;
  /** 新しい会話がサーバー側で作られたとき。 */
  adoptThread: (threadId: string) => void;
  clearSelectedText: () => void;
  setLectureDetached: (detached: boolean) => void;
}

const ChatPanelContext = createContext<ChatPanelContextValue | undefined>(undefined);

export const ChatPanelProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [view, setView] = useState<'conversation' | 'history'>('conversation');
  const [threadId, setThreadId] = useState<string | null>(null);
  const [selectedText, setSelectedText] = useState<string | null>(null);
  const [lectureDetached, setLectureDetached] = useState(false);

  const open = useCallback(
    (request: ChatOpenRequest = {}) => {
      if (request.newConversation) {
        setThreadId(null);
      } else if (request.threadId !== undefined) {
        setThreadId(request.threadId);
      } else if (request.selectedText && !isOpen) {
        // パネルを閉じた状態で文章を選んで「Ask」した: その文章についての新しい会話にする。
        // 既にパネルで会話中なら、その会話に選択テキストを添えて続ける。
        setThreadId(null);
      }
      if (request.selectedText !== undefined) setSelectedText(request.selectedText || null);
      setView('conversation');
      setIsOpen(true);
    },
    [isOpen]
  );

  const close = useCallback(() => setIsOpen(false), []);
  const showHistory = useCallback(() => setView('history'), []);
  const showConversation = useCallback((id: string | null) => {
    setThreadId(id);
    setView('conversation');
  }, []);
  const adoptThread = useCallback((id: string) => setThreadId(id), []);
  const clearSelectedText = useCallback(() => setSelectedText(null), []);

  const value = useMemo(
    () => ({
      isOpen,
      view,
      threadId,
      selectedText,
      lectureDetached,
      open,
      close,
      showHistory,
      showConversation,
      adoptThread,
      clearSelectedText,
      setLectureDetached,
    }),
    [isOpen, view, threadId, selectedText, lectureDetached, open, close, showHistory, showConversation, adoptThread, clearSelectedText]
  );

  return <ChatPanelContext.Provider value={value}>{children}</ChatPanelContext.Provider>;
};

/** チャットパネルの外(ログイン前の画面など)ではnullを返す。呼び出し側は「Ask」を出さない。 */
export function useChatPanel(): ChatPanelContextValue | null {
  return useContext(ChatPanelContext) ?? null;
}
