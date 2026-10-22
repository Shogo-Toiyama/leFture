import React, { useState } from 'react';
import { Check, MessageSquareText, Pencil, Plus, Trash2, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { ConfirmModal } from '../modals/ConfirmModal';
import type { ChatThread } from '../../types/chat';

interface ChatThreadListProps {
  threads: ChatThread[];
  loading: boolean;
  activeThreadId?: string | null;
  onSelect: (threadId: string) => void;
  onNewConversation?: () => void;
  onRename: (threadId: string, title: string) => Promise<void>;
  onDelete: (threadId: string) => Promise<void>;
}

export const ChatThreadList: React.FC<ChatThreadListProps> = ({
  threads,
  loading,
  activeThreadId,
  onSelect,
  onNewConversation,
  onRename,
  onDelete,
}) => {
  const { t, formatDate } = useLanguage();
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draftTitle, setDraftTitle] = useState('');
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const relativeTime = (iso: string) => {
    const date = new Date(iso);
    const today = new Date();
    const sameDay = date.toDateString() === today.toDateString();
    return sameDay
      ? formatDate(date, { hour: 'numeric', minute: '2-digit' })
      : formatDate(date, { month: 'short', day: 'numeric' });
  };

  const commitRename = async (threadId: string) => {
    const title = draftTitle.trim();
    if (!title) {
      setEditingId(null);
      return;
    }
    setBusy(true);
    try {
      await onRename(threadId, title);
      setEditingId(null);
    } finally {
      setBusy(false);
    }
  };

  if (loading) {
    return (
      <div className="chat-threads" aria-busy="true">
        {[0, 1, 2].map((i) => (
          <span key={i} className="chat-thread-skeleton" />
        ))}
      </div>
    );
  }

  const newButton = onNewConversation ? (
    <button
      type="button"
      className="chat-thread-new-btn"
      onClick={onNewConversation}
    >
      <Plus size={18} />
      <span>{t('chatNewConversation')}</span>
    </button>
  ) : null;

  if (threads.length === 0) {
    return (
      <>
        {newButton}
        <p className="chat-threads-empty">{t('chatThreadsEmpty')}</p>
      </>
    );
  }

  return (
    <>
      {newButton}
      <ul className="chat-threads">
        {threads.map((thread) => {
          const title = thread.title || t('chatThreadUntitled');
          const isEditing = editingId === thread.id;
          return (
            <li key={thread.id} className={`chat-thread-row ${thread.id === activeThreadId ? 'is-active' : ''}`}>
              {isEditing ? (
                <form
                  className="chat-thread-edit"
                  onSubmit={(event) => {
                    event.preventDefault();
                    void commitRename(thread.id);
                  }}
                >
                  <input
                    id={`chat-thread-title-${thread.id}`}
                    value={draftTitle}
                    maxLength={100}
                    autoFocus
                    onChange={(event) => setDraftTitle(event.target.value)}
                    onKeyDown={(event) => event.key === 'Escape' && setEditingId(null)}
                    aria-label={t('chatRename')}
                  />
                  <button type="submit" disabled={busy} aria-label={t('save')}>
                    <Check size={16} />
                  </button>
                  <button type="button" onClick={() => setEditingId(null)} aria-label={t('cancel')}>
                    <X size={16} />
                  </button>
                </form>
              ) : (
                <>
                  <button type="button" className="chat-thread-main" onClick={() => onSelect(thread.id)}>
                    <MessageSquareText size={16} className="chat-thread-icon" />
                    <span className="chat-thread-text">
                      <span className="chat-thread-title">{title}</span>
                      <span className="chat-thread-time">{relativeTime(thread.last_message_at)}</span>
                    </span>
                  </button>
                  <span className="chat-thread-actions">
                    <button
                      type="button"
                      onClick={() => {
                        setDraftTitle(thread.title ?? '');
                        setEditingId(thread.id);
                      }}
                      aria-label={t('chatRename')}
                      title={t('chatRename')}
                    >
                      <Pencil size={14} />
                    </button>
                    <button
                      type="button"
                      onClick={() => setDeletingId(thread.id)}
                      aria-label={t('chatDelete')}
                      title={t('chatDelete')}
                    >
                      <Trash2 size={14} />
                    </button>
                  </span>
                </>
              )}
            </li>
          );
        })}
      </ul>

      <ConfirmModal
        open={deletingId !== null}
        onClose={() => setDeletingId(null)}
        onConfirm={() => {
          if (!deletingId) return;
          const id = deletingId;
          setDeletingId(null);
          void onDelete(id);
        }}
        title={t('chatDeleteConfirmTitle')}
        message={t('chatDeleteConfirmMessage')}
        confirmLabel={t('chatDelete')}
        cancelLabel={t('cancel')}
        isDanger
      />
    </>
  );
};
