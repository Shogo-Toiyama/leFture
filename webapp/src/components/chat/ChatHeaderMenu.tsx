import React, { useEffect, useRef, useState } from 'react';
import { MessageSquarePlus, MoreHorizontal, SlidersHorizontal } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';

interface ChatHeaderMenuProps {
  onNewConversation: () => void;
  onOpenSettings: () => void;
  iconSize?: number;
}

export const ChatHeaderMenu: React.FC<ChatHeaderMenuProps> = ({
  onNewConversation,
  onOpenSettings,
  iconSize = 16,
}) => {
  const { t } = useLanguage();
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [open]);

  return (
    <div className="chat-act-menu-anchor" ref={containerRef}>
      <button
        type="button"
        className={`chat-icon-btn ${open ? 'is-active' : ''}`}
        onClick={() => setOpen((v) => !v)}
        aria-label={t('chatActionMore')}
        title={t('chatActionMore')}
        aria-haspopup="menu"
        aria-expanded={open}
      >
        <MoreHorizontal size={iconSize} />
      </button>
      {open && (
        <div className="chat-header-menu" role="menu">
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onNewConversation();
            }}
          >
            <MessageSquarePlus size={16} />
            <span>{t('chatNewConversation')}</span>
          </button>
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onOpenSettings();
            }}
          >
            <SlidersHorizontal size={16} />
            <span>{t('aiSettingsButton')}</span>
          </button>
        </div>
      )}
    </div>
  );
};
