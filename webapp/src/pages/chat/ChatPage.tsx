import React, { useCallback, useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ChevronLeft, Minimize2, SquarePen } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { useChatThreads } from '../../hooks/useChatThreads';
import { getChatThread } from '../../lib/chat';
import { ChatConversation } from '../../components/chat/ChatConversation';
import { ChatThreadList } from '../../components/chat/ChatThreadList';
import { ChatPlanNotice } from '../../components/chat/ChatPlanNotice';

/**
 * 会話の置き場(専用ページ)。
 *   /chat            会話の一覧
 *   /chat/new        新しい会話(最初の送信でスレッドができたら /chat/:id に置き換える)
 *   /chat/:threadId  会話
 * どの画面からでも開ける右側パネルの「全画面で開く」からもここに来る。
 */
export const ChatPage: React.FC = () => {
  const { threadId } = useParams<{ threadId?: string }>();
  if (!threadId) return <ChatListView />;
  // keyで作り直さない: /chat/new で最初に送ったあと /chat/:id へ置き換えた瞬間に
  // 作り直すと、受信中のストリームが切れてしまう。
  return <ChatThreadView threadId={threadId === 'new' ? null : threadId} />;
};

/**
 * チャット画面に入る前の元の画面(講義やコース等)に戻る。
 * チャット内で /chat/:id と /chat を行き来しても、チャット内部でループせず
 * 確実に「チャットの外」へ脱出できるようにする。
 */
function navigateOutOfChat(navigate: (to: string) => void) {
  const origin = sessionStorage.getItem('chat_origin_url');
  if (origin && !origin.startsWith('/chat')) {
    navigate(origin);
  } else {
    navigate('/');
  }
}

const ChatListView: React.FC = () => {
  const { t } = useLanguage();
  const navigate = useNavigate();
  const { threads, loading, error, refetch, rename, remove } = useChatThreads();

  const goBack = useCallback(() => {
    navigateOutOfChat(navigate);
  }, [navigate]);

  const handleMinimize = useCallback(() => {
    sessionStorage.setItem('open_chat_panel', 'history');
    navigateOutOfChat(navigate);
  }, [navigate]);

  return (
    <div className="chat-fullscreen is-paper">
      <header className="chat-fullscreen-topbar">
        <div className="chat-fullscreen-topbar-left">
          <button
            type="button"
            className="chat-fullscreen-back-btn"
            onClick={goBack}
            aria-label={t('back')}
            title={t('back')}
          >
            <ChevronLeft size={22} />
          </button>
        </div>

        <div className="chat-fullscreen-topbar-right">
          <Link to="/chat/new" className="chat-new-btn">
            <SquarePen size={16} />
            {t('chatNewConversation')}
          </Link>
          <button
            type="button"
            className="chat-icon-btn"
            onClick={handleMinimize}
            aria-label={t('chatExitFullScreen')}
            title={t('chatExitFullScreen')}
          >
            <Minimize2 size={18} />
          </button>
        </div>
      </header>

      <main className="chat-fullscreen-body">
        <div className="chat-fullscreen-container">
          <div className="chat-page-head">
            <h1 className="chat-page-title">{t('chatTitle')}</h1>
          </div>
          {error ? (
            <div className="chat-empty">
              <p>{t('chatErrorGeneric')}</p>
              <button type="button" className="chat-banner-btn is-primary" onClick={refetch}>
                {t('retry')}
              </button>
            </div>
          ) : (
            <ChatThreadList
              threads={threads}
              loading={loading}
              onSelect={(id) => navigate(`/chat/${id}`)}
              onRename={rename}
              onDelete={remove}
            />
          )}
        </div>
      </main>
    </div>
  );
};

const ChatThreadView: React.FC<{ threadId: string | null }> = ({ threadId }) => {
  const { t } = useLanguage();
  const navigate = useNavigate();
  const [title, setTitle] = useState<string | null>(null);

  const refreshTitle = useCallback(() => {
    if (!threadId) {
      setTitle(null);
      return;
    }
    getChatThread(threadId)
      .then((thread) => setTitle(thread?.title ?? null))
      .catch(() => {});
  }, [threadId]);
  useEffect(refreshTitle, [refreshTitle]);

  const handleMinimize = useCallback(() => {
    sessionStorage.setItem('open_chat_panel', threadId ?? 'null');
    navigateOutOfChat(navigate);
  }, [navigate, threadId]);

  return (
    <div className="chat-fullscreen is-thread is-paper">
      <header className="chat-fullscreen-topbar">
        <div className="chat-fullscreen-topbar-left">
          <Link to="/chat" className="chat-fullscreen-back-link" aria-label={t('chatHistory')}>
            <ChevronLeft size={20} />
            <span>{t('chatHistory')}</span>
          </Link>
        </div>

        <div className="chat-fullscreen-topbar-center">
          <span className="chat-fullscreen-thread-title">
            {title || (threadId ? t('chatThreadUntitled') : t('chatNewConversation'))}
          </span>
        </div>

        <div className="chat-fullscreen-topbar-right">
          {threadId && (
            <Link
              to="/chat/new"
              className="chat-icon-btn"
              aria-label={t('chatNewConversation')}
              title={t('chatNewConversation')}
            >
              <SquarePen size={18} />
            </Link>
          )}
          <button
            type="button"
            className="chat-icon-btn"
            onClick={handleMinimize}
            aria-label={t('chatExitFullScreen')}
            title={t('chatExitFullScreen')}
          >
            <Minimize2 size={18} />
          </button>
        </div>
      </header>
      <ChatPlanNotice />

      <main className="chat-fullscreen-thread-body">
        <ChatConversation
          threadId={threadId}
          onThreadCreated={(id) => navigate(`/chat/${id}`, { replace: true })}
          onTurnComplete={refreshTitle}
          lectureId={null}
          lectureTitle={null}
          selectedText={null}
          onOpenCitation={(route) => navigate(route)}
          variant="page"
        />
      </main>
    </div>
  );
};
