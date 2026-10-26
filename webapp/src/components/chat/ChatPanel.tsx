import React, { useCallback, useEffect, useState } from 'react';
import { matchPath, useLocation, useNavigate } from 'react-router-dom';
import { ChevronLeft, Maximize2, MessagesSquare, SlidersHorizontal, SquarePen, X } from 'lucide-react';
import { useChatPanel } from '../../context/ChatPanelContext';
import { useLanguage } from '../../i18n/LanguageContext';
import { useChatThreads } from '../../hooks/useChatThreads';
import { getChatThread } from '../../lib/chat';
import { getLecture } from '../../lib/lectures';
import { lectureDisplayTitle } from '../../types/lecture';
import { AiSettingsSheet } from './AiSettingsSheet';
import { ChatConversation } from './ChatConversation';
import { ChatPlanNotice } from './ChatPlanNotice';
import { ChatThreadList } from './ChatThreadList';

/**
 * チャットの右側パネル(狭い画面ではボトムシート)の中身。
 * Markdown表示(react-markdown等)を含んで重いので、ChatHostから遅延読み込みする
 * (常に全画面に出るChatHostに直接含めると、メインのチャンクが約190kB増えるため)。
 */
export const ChatPanel: React.FC<{ stacked: boolean }> = ({ stacked }) => {
  const { t } = useLanguage();
  const panel = useChatPanel()!;
  const navigate = useNavigate();
  const location = useLocation();

  // 今いる画面の講義(/lectures/:lectureId/...)を話題として添える。
  const routeLectureId =
    matchPath('/lectures/:lectureId/*', location.pathname)?.params.lectureId ??
    matchPath('/lectures/:lectureId', location.pathname)?.params.lectureId ??
    null;
  const lectureId = panel.lectureDetached ? null : routeLectureId;
  const lectureTitle = useLectureTitle(lectureId);

  // 講義が変わったら、外していた講義のチップは元に戻す
  const { setLectureDetached } = panel;
  useEffect(() => {
    setLectureDetached(false);
  }, [routeLectureId, setLectureDetached]);

  const [threadTitle, setThreadTitle] = useState<string | null>(null);
  const [attachmentListOpen, setAttachmentListOpen] = useState(false);
  // AIチャット設定(覚え書き・AIのメモ・自分像への入口)のシート
  const [aiSettingsOpen, setAiSettingsOpen] = useState(false);
  useEffect(() => setAttachmentListOpen(false), [panel.threadId, panel.view]);
  const refreshThreadTitle = useCallback(() => {
    if (!panel.threadId) {
      setThreadTitle(null);
      return;
    }
    getChatThread(panel.threadId)
      .then((thread) => setThreadTitle(thread?.title ?? null))
      .catch(() => {});
  }, [panel.threadId]);
  useEffect(refreshThreadTitle, [refreshThreadTitle]);

  // 会話の中だけでEscapeを効かせる(読み物の画面にも独自のEscapeがあるため)
  const onKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === 'Escape') panel.close();
  };

  const openCitation = (route: string) => {
    if (stacked) panel.close();
    navigate(route);
  };

  const isHistory = panel.view === 'history';
  const isNewConversation = !isHistory && !panel.threadId;
  const isWide = !stacked;
  const isPaper = Boolean(
    location.pathname.includes('/review-cards') ||
    location.pathname.includes('/deep-notes') ||
    location.pathname.includes('/transcript')
  );

  return (
    <>
      {stacked && <button type="button" className="chat-sheet-scrim" onClick={panel.close} aria-label={t('close')} />}
      <aside
        className={`chat-panel ${stacked ? 'is-sheet' : 'is-docked'} ${isPaper ? 'is-paper' : ''}`}
        role="complementary"
        aria-label={t('chatTitle')}
        onKeyDown={onKeyDown}
      >
        <header className="chat-panel-head">
          {isHistory ? (
            <button
              type="button"
              className="chat-icon-btn"
              onClick={() => panel.showConversation(panel.threadId)}
              aria-label={t('back')}
              title={t('back')}
            >
              <ChevronLeft size={18} />
            </button>
          ) : (
            <button
              type="button"
              className="chat-icon-btn"
              onClick={panel.showHistory}
              aria-label={t('chatHistory')}
              title={t('chatHistory')}
            >
              <MessagesSquare size={18} />
            </button>
          )}
          <span className="chat-panel-title">
            {isHistory ? t('chatHistory') : threadTitle || (panel.threadId ? t('chatThreadUntitled') : t('chatNewConversation'))}
          </span>
          {isHistory ? (
            <>
              <button
                type="button"
                className={`chat-icon-btn ${aiSettingsOpen ? 'is-active' : ''}`}
                onClick={() => setAiSettingsOpen((v) => !v)}
                aria-label={t('aiSettingsButton')}
                aria-expanded={aiSettingsOpen}
                title={t('aiSettingsButton')}
              >
                <SlidersHorizontal size={16} />
              </button>
              <button
                type="button"
                className="chat-icon-btn"
                onClick={() => navigate(panel.threadId ? `/chat/${panel.threadId}` : '/chat/new')}
                aria-label={t('chatOpenFullScreen')}
                title={t('chatOpenFullScreen')}
              >
                <Maximize2 size={16} />
              </button>
            </>
          ) : isNewConversation ? (
            <>
              <button
                type="button"
                className={`chat-icon-btn ${aiSettingsOpen ? 'is-active' : ''}`}
                onClick={() => setAiSettingsOpen((v) => !v)}
                aria-label={t('aiSettingsButton')}
                aria-expanded={aiSettingsOpen}
                title={t('aiSettingsButton')}
              >
                <SlidersHorizontal size={16} />
              </button>
              <button
                type="button"
                className="chat-icon-btn"
                onClick={() => navigate('/chat/new')}
                aria-label={t('chatOpenFullScreen')}
                title={t('chatOpenFullScreen')}
              >
                <Maximize2 size={16} />
              </button>
            </>
          ) : (
            <>
              {isWide && (
                <button
                  type="button"
                  className={`chat-icon-btn ${aiSettingsOpen ? 'is-active' : ''}`}
                  onClick={() => setAiSettingsOpen((v) => !v)}
                  aria-label={t('aiSettingsButton')}
                  aria-expanded={aiSettingsOpen}
                  title={t('aiSettingsButton')}
                >
                  <SlidersHorizontal size={16} />
                </button>
              )}
              <button
                type="button"
                className="chat-icon-btn"
                onClick={() => panel.showConversation(null)}
                aria-label={t('chatNewConversation')}
                title={t('chatNewConversation')}
              >
                <SquarePen size={16} />
              </button>
              <button
                type="button"
                className="chat-icon-btn"
                onClick={() => navigate(panel.threadId ? `/chat/${panel.threadId}` : '/chat/new')}
                aria-label={t('chatOpenFullScreen')}
                title={t('chatOpenFullScreen')}
              >
                <Maximize2 size={16} />
              </button>
            </>
          )}
          <button type="button" className="chat-icon-btn" onClick={panel.close} aria-label={t('close')} title={t('close')}>
            <X size={18} />
          </button>
        </header>
        {!isHistory && <ChatPlanNotice />}

        {isHistory ? (
          <PanelHistory />
        ) : (
          <ChatConversation
            // keyで作り直さない: 新しい会話にスレッドidが付いた瞬間(adoptThread)に
            // 作り直すと、受信中のストリームが切れてしまう。会話の切り替えは
            // useChatConversationがthreadIdの変化として扱う。
            threadId={panel.threadId}
            world={isPaper ? 'paper' : 'universe'}
            onThreadCreated={panel.adoptThread}
            onTurnComplete={refreshThreadTitle}
            lectureId={lectureId}
            lectureTitle={lectureTitle}
            onDetachLecture={() => panel.setLectureDetached(true)}
            selection={panel.selection}
            onClearSelection={panel.clearSelection}
            // 講義のチップを外したら、その講義のページも添えない
            screen={panel.lectureDetached ? null : panel.pageScreen}
            onOpenCitation={openCitation}
            variant="panel"
            attachmentListOpen={attachmentListOpen}
            onAttachmentListClose={() => setAttachmentListOpen(false)}
          />
        )}
        <AiSettingsSheet
          open={aiSettingsOpen}
          onClose={() => setAiSettingsOpen(false)}
          threadId={panel.threadId}
          onNavigate={() => {
            setAiSettingsOpen(false);
            if (stacked) panel.close();
          }}
        />
      </aside>
    </>
  );
};

const PanelHistory: React.FC = () => {
  const panel = useChatPanel()!;
  const { threads, loading, rename, remove } = useChatThreads();
  return (
    <div className="chat-panel-history">
      <ChatThreadList
        threads={threads}
        loading={loading}
        activeThreadId={panel.threadId}
        onSelect={(id) => panel.showConversation(id)}
        onNewConversation={() => panel.showConversation(null)}
        onRename={rename}
        onDelete={async (id) => {
          await remove(id);
          if (id === panel.threadId) panel.showConversation(null);
          else panel.showHistory();
        }}
      />
    </div>
  );
};

/** 講義名(チップ表示用)。取れなければnull。 */
function useLectureTitle(lectureId: string | null): string | null {
  const { t } = useLanguage();
  const [title, setTitle] = useState<string | null>(null);
  useEffect(() => {
    if (!lectureId) {
      setTitle(null);
      return;
    }
    let cancelled = false;
    getLecture(lectureId)
      .then((lecture) => {
        if (!cancelled) setTitle(lectureDisplayTitle(lecture, t('lectureUntitled')));
      })
      .catch(() => {
        if (!cancelled) setTitle(null);
      });
    return () => {
      cancelled = true;
    };
  }, [lectureId, t]);
  return title;
}
