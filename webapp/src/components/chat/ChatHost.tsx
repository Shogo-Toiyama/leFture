import React, { Suspense, lazy, useCallback, useEffect, useState } from 'react';
import { Outlet, useLocation } from 'react-router-dom';
import { MessageCircle } from 'lucide-react';
import { AiConsentProvider } from '../../context/AiConsentContext';
import { ChatPanelProvider, useChatPanel } from '../../context/ChatPanelContext';
import { useLanguage } from '../../i18n/LanguageContext';
import { useMediaQuery, STACKED_PANELS_QUERY } from '../../hooks/useMediaQuery';
import {
  CHAT_DOCK_DEFAULT_PX,
  clampDockWidth,
  loadDockWidth,
  saveDockWidth,
} from '../../lib/chatDockWidth';
import { ChatDockResizer } from './ChatDockResizer';
import { useUploadModal } from '../../context/UploadModalContext';
import { UploadModal } from '../modals/UploadModal';

// パネルの中身は重い(Markdown表示を含む)ので、初めて開いたときに読み込む
const ChatPanel = lazy(() => import('./ChatPanel').then((m) => ({ default: m.ChatPanel })));

/**
 * ログイン後の全画面を包むルート要素。右下のチャットボタンと、右側パネル
 * (狭い画面ではボトムシート)をどの画面にも出す。アプリの枠(Layout)の外に
 * ある全画面の読み物(Deep Notes等)も含めるため、Layoutではなくここに置く。
 *
 * 広い画面ではパネルを右側に固定し、--chat-dock-width の分だけページ側を
 * 縮める(index.cssの .app-shell / .pv-root 等がこの変数を見ている)。
 * これまで左側のパネル(出典シート等)を使い、右側を空けてきたのはこのため。
 * パネルの幅は左端のつかみ部分(ChatDockResizer)で変えられ、端末ごとに覚える(lib/chatDockWidth)。
 */
export const ChatHost: React.FC = () => (
  <AiConsentProvider>
    <ChatPanelProvider>
      <Outlet />
      <ChatDock />
      <GlobalUploadModal />
    </ChatPanelProvider>
  </AiConsentProvider>
);

/**
 * 「Upload a Recording」。Layoutの外のページ(チャット・Deep Notes等)のヘッダーにある
 * 録音中のタイマー(RecordingChip)からも開き直せるよう、Layoutではなくここに置く。
 */
const GlobalUploadModal: React.FC = () => {
  const { isOpen, targetCourseId, closeUploadModal } = useUploadModal();
  return <UploadModal open={isOpen} onClose={closeUploadModal} initialCourseId={targetCourseId} />;
};

/** 画面(ウィンドウ)の幅。パネルの幅を、画面に収まるよう丸めるのに使う。 */
function useViewportWidth(): number {
  const [width, setWidth] = useState(() => window.innerWidth);
  useEffect(() => {
    const onResize = () => setWidth(window.innerWidth);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);
  return width;
}

/** 右下のボタン(56px)+間隔。index.cssの .chat-fab と揃える。 */
const CHAT_FAB_CLEARANCE_PX = 68;

const ChatDock: React.FC = () => {
  const { t } = useLanguage();
  const panel = useChatPanel()!;
  const location = useLocation();
  const stacked = useMediaQuery(STACKED_PANELS_QUERY);
  const onChatPage = location.pathname === '/chat' || location.pathname.startsWith('/chat/');
  const docked = panel.isOpen && !stacked && !onChatPage;

  // 好みの幅(保存する値)と、いま画面に収まる幅。画面が狭い間は丸めて使い、広がったら好みの幅に戻る
  const [preferredWidth, setPreferredWidth] = useState(loadDockWidth);
  const viewportWidth = useViewportWidth();
  const dockWidth = clampDockWidth(preferredWidth, viewportWidth);

  // 右下のボタンが出ている間は、既存の右下のボタン(コース画面)をその左へずらす
  const fabVisible = !panel.isOpen && !onChatPage;
  useEffect(() => {
    const root = document.documentElement;
    if (fabVisible) root.style.setProperty('--chat-fab-clearance', `${CHAT_FAB_CLEARANCE_PX}px`);
    else root.style.removeProperty('--chat-fab-clearance');
    return () => {
      root.style.removeProperty('--chat-fab-clearance');
    };
  }, [fabVisible]);

  useEffect(() => {
    const root = document.documentElement;
    if (docked) root.style.setProperty('--chat-dock-width', `${dockWidth}px`);
    else root.style.removeProperty('--chat-dock-width');
    return () => {
      root.style.removeProperty('--chat-dock-width');
    };
  }, [docked, dockWidth]);

  // ドラッグ中: Reactを通さず変数だけを動かして、ページをその場で追従させる。
  // 注釈の位置などはwindowのresizeで測り直すので、動かすたびに知らせる。
  const onLiveWidth = useCallback((px: number) => {
    document.documentElement.style.setProperty('--chat-dock-width', `${px}px`);
    window.dispatchEvent(new Event('resize'));
  }, []);
  const onCommitWidth = useCallback((px: number) => {
    setPreferredWidth(px);
    saveDockWidth(px);
  }, []);
  const onResetWidth = useCallback(() => {
    setPreferredWidth(CHAT_DOCK_DEFAULT_PX);
    saveDockWidth(null);
  }, []);

  // チャット画面以外の直前のURLを常に記録（全画面チャットから元の画面へ脱出するため）
  useEffect(() => {
    if (!onChatPage) {
      sessionStorage.setItem('chat_origin_url', location.pathname + location.search + location.hash);
    }
  }, [location, onChatPage]);

  // 専用ページでは会話がページそのものなので、パネルは閉じてボタンも出さない
  useEffect(() => {
    if (onChatPage && panel.isOpen) panel.close();
  }, [onChatPage, panel]);

  // 全画面チャットの「縮小」ボタンから戻ってきた場合、パネルを開く
  useEffect(() => {
    if (!onChatPage) {
      const pendingOpen = sessionStorage.getItem('open_chat_panel');
      if (pendingOpen !== null) {
        sessionStorage.removeItem('open_chat_panel');
        if (pendingOpen === 'history') {
          panel.open();
          panel.showHistory();
        } else {
          panel.open({
            threadId: pendingOpen === 'null' || pendingOpen === 'true' ? null : pendingOpen,
          });
        }
      }
    }
  }, [onChatPage, panel]);

  if (onChatPage) return null;

  return (
    <>
      {!panel.isOpen && (
        <button type="button" className="chat-fab" onClick={() => panel.open()} aria-label={t('chatOpen')} title={t('chatOpen')}>
          <MessageCircle size={24} />
        </button>
      )}
      {docked && (
        <ChatDockResizer
          width={dockWidth}
          viewportWidth={viewportWidth}
          label={t('chatPanelResize')}
          onLive={onLiveWidth}
          onCommit={onCommitWidth}
          onReset={onResetWidth}
        />
      )}
      {panel.isOpen && (
        <Suspense fallback={<aside className={`chat-panel ${stacked ? 'is-sheet' : 'is-docked'}`} aria-busy="true" />}>
          <ChatPanel stacked={stacked} />
        </Suspense>
      )}
    </>
  );
};
