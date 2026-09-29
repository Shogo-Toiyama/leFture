import React, { useCallback, useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ChevronLeft, SquarePen } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { useChatThreads } from '../../hooks/useChatThreads';
import { getChatThread } from '../../lib/chat';
import { ChatConversation } from '../../components/chat/ChatConversation';
import { ChatThreadList } from '../../components/chat/ChatThreadList';

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

const ChatListView: React.FC = () => {
  const { t } = useLanguage();
  const navigate = useNavigate();
  const { threads, loading, error, refetch, rename, remove } = useChatThreads();

  return (
    <div className="chat-page">
      <div className="chat-page-head">
        <h1 className="chat-page-title">{t('chatTitle')}</h1>
        <Link to="/chat/new" className="chat-new-btn">
          <SquarePen size={16} />
          {t('chatNewConversation')}
        </Link>
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

  return (
    <div className="chat-page is-thread">
      <div className="chat-page-head">
        <Link to="/chat" className="chat-back-link" aria-label={t('chatHistory')}>
          <ChevronLeft size={18} />
          {t('chatHistory')}
        </Link>
        <span className="chat-page-thread-title">
          {title || (threadId ? t('chatThreadUntitled') : t('chatNewConversation'))}
        </span>
        {threadId && (
          <Link to="/chat/new" className="chat-icon-btn" aria-label={t('chatNewConversation')} title={t('chatNewConversation')}>
            <SquarePen size={16} />
          </Link>
        )}
      </div>
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
    </div>
  );
};
