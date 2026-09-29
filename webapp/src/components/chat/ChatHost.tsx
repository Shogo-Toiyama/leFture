import React, { Suspense, lazy, useEffect } from 'react';
import { Outlet, useLocation } from 'react-router-dom';
import { MessageCircle } from 'lucide-react';
import { ChatPanelProvider, useChatPanel } from '../../context/ChatPanelContext';
import { useLanguage } from '../../i18n/LanguageContext';
import { useMediaQuery, STACKED_PANELS_QUERY } from '../../hooks/useMediaQuery';

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
 */
export const ChatHost: React.FC = () => (
  <ChatPanelProvider>
    <Outlet />
    <ChatDock />
  </ChatPanelProvider>
);

/** 今はパネル幅を固定。将来ドラッグで変えられるようにする。 */
const CHAT_DOCK_WIDTH_PX = 460;
/** 右下のボタン(56px)+間隔。index.cssの .chat-fab と揃える。 */
const CHAT_FAB_CLEARANCE_PX = 68;

const ChatDock: React.FC = () => {
  const { t } = useLanguage();
  const panel = useChatPanel()!;
  const location = useLocation();
  const stacked = useMediaQuery(STACKED_PANELS_QUERY);
  const onChatPage = location.pathname === '/chat' || location.pathname.startsWith('/chat/');
  const docked = panel.isOpen && !stacked && !onChatPage;

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
    if (docked) root.style.setProperty('--chat-dock-width', `${CHAT_DOCK_WIDTH_PX}px`);
    else root.style.removeProperty('--chat-dock-width');
    return () => {
      root.style.removeProperty('--chat-dock-width');
    };
  }, [docked]);

  // 専用ページでは会話がページそのものなので、パネルは閉じてボタンも出さない
  useEffect(() => {
    if (onChatPage && panel.isOpen) panel.close();
  }, [onChatPage, panel]);

  if (onChatPage) return null;

  return (
    <>
      {!panel.isOpen && (
        <button type="button" className="chat-fab" onClick={() => panel.open()} aria-label={t('chatOpen')} title={t('chatOpen')}>
          <MessageCircle size={24} />
        </button>
      )}
      {panel.isOpen && (
        <Suspense fallback={<aside className={`chat-panel ${stacked ? 'is-sheet' : 'is-docked'}`} aria-busy="true" />}>
          <ChatPanel stacked={stacked} />
        </Suspense>
      )}
    </>
  );
};
