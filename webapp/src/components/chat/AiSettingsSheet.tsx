import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ChevronRight, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { selfPortraitApi, shortDate, type AiMemory } from '../../lib/selfPortrait';
import { getChatThreadNotes } from '../../lib/chat';
import type { ChatThreadNotes } from '../../types/chat';

/**
 * AIチャット設定(チャットパネル右上のボタンから開くシート)。
 * チャット内メモ(この会話限定の合意・前提)と、話し方の覚え書き・今の状況(全会話共通)を見て消せる。
 * fixed=false ならパネルの中(position: absolute)、true なら画面全体(全画面のチャット)に重ねる。
 */
export const AiSettingsSheet: React.FC<{
  open: boolean;
  onClose: () => void;
  fixed?: boolean;
  onNavigate?: () => void;
  threadId?: string | null;
}> = ({
  open,
  onClose,
  fixed = false,
  onNavigate,
  threadId,
}) => {
  const { t, locale } = useLanguage();
  const [memory, setMemory] = useState<AiMemory | null>(null);
  const [threadNotes, setThreadNotes] = useState<ChatThreadNotes | null>(null);
  const [loadingNotes, setLoadingNotes] = useState(false);
  const [error, setError] = useState(false);

  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    setError(false);
    selfPortraitApi.aiMemory()
      .then((m) => { if (!cancelled) setMemory(m); })
      .catch(() => { if (!cancelled) setError(true); });
    return () => { cancelled = true; };
  }, [open]);

  useEffect(() => {
    if (!open || !threadId) {
      setThreadNotes(null);
      return;
    }
    let cancelled = false;
    setLoadingNotes(true);
    getChatThreadNotes(threadId)
      .then((notes) => {
        if (!cancelled) setThreadNotes(notes);
      })
      .catch(() => {
        if (!cancelled) setThreadNotes(null);
      })
      .finally(() => {
        if (!cancelled) setLoadingNotes(false);
      });
    return () => { cancelled = true; };
  }, [open, threadId]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); onClose(); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [open, onClose]);

  if (!open) return null;

  const removeMemo = async (id: string) => {
    setMemory((m) => (m ? { ...m, memos: m.memos.filter((x) => x.id !== id) } : m));
    try {
      await selfPortraitApi.deleteMemo(id);
    } catch {
      setError(true);
      selfPortraitApi.aiMemory().then(setMemory).catch(() => {});
    }
  };

  const styles = memory?.memos.filter((m) => m.kind === 'answer_style') ?? [];
  const situations = memory?.memos.filter((m) => m.kind === 'situation') ?? [];

  // チャット内メモの各カテゴリの平坦化
  const allChatNotes = [
    ...(threadNotes?.purpose.map((it) => ({ ...it, category: 'purpose' as const })) ?? []),
    ...(threadNotes?.style_preferences.map((it) => ({ ...it, category: 'style' as const })) ?? []),
    ...(threadNotes?.context.map((it) => ({ ...it, category: 'context' as const })) ?? []),
    ...(threadNotes?.unresolved.map((it) => ({ ...it, category: 'unresolved' as const })) ?? []),
  ];

  const getCategoryLabel = (cat: 'purpose' | 'style' | 'context' | 'unresolved') => {
    switch (cat) {
      case 'purpose':
        return t('chatNotesCategoryPurpose');
      case 'style':
        return t('chatNotesCategoryStyle');
      case 'context':
        return t('chatNotesCategoryContext');
      case 'unresolved':
        return t('chatNotesCategoryUnresolved');
    }
  };

  return (
    <div className={`ai-settings ${fixed ? 'is-fixed' : ''}`}>
      <button type="button" className="ai-settings-scrim" onClick={onClose} aria-label={t('close')} />
      <div className="ai-settings-sheet" role="dialog" aria-modal="true" aria-label={t('aiSettingsTitle')}>
        <div className="ai-settings-head">
          <h2 className="ai-settings-title">{t('aiSettingsTitle')}</h2>
          <button type="button" className="chat-icon-btn" onClick={onClose} aria-label={t('close')} title={t('close')}>
            <X size={18} />
          </button>
        </div>
        {error && <p className="auth-error">{t('spLoadError')}</p>}

        {/* 1. チャット内メモ (この会話を開いている時のみ表示) */}
        {Boolean(threadId) && (
          <>
            <div className="ai-settings-section">{t('chatNotesSection')}</div>
            {allChatNotes.length > 0 ? (
              <div className="chat-note-group">
                {allChatNotes.map((it, idx) => (
                  <div key={`${it.category}-${idx}`} className="chat-note-item">
                    <div className="chat-note-meta">
                      <span className={`chat-note-badge is-${it.category}`}>
                        {getCategoryLabel(it.category)}
                      </span>
                      {it.source_turn && (
                        <span className="chat-note-turn">turn {it.source_turn}</span>
                      )}
                    </div>
                    <div className="chat-note-text">{it.text}</div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="ai-memo-empty">
                {loadingNotes ? '…' : t('chatNotesEmpty')}
              </p>
            )}
          </>
        )}

        {/* 2. 全会話共通の覚え書き */}
        <div className="ai-settings-section">{t('aiMemoStyleSection')}</div>
        {styles.length ? styles.map((m) => (
          <div key={m.id} className="ai-memo-row">
            <span className="ai-memo-text">{m.content}</span>
            <button type="button" className="chat-icon-btn" onClick={() => removeMemo(m.id)} aria-label={t('aiMemoDelete')} title={t('aiMemoDelete')}>
              <X size={16} />
            </button>
          </div>
        )) : <p className="ai-memo-empty">{memory ? t('aiMemoEmpty') : '…'}</p>}

        <div className="ai-settings-section">{t('aiMemoSituationSection')}</div>
        {situations.length ? situations.map((m) => (
          <div key={m.id} className="ai-memo-row">
            <span className="ai-memo-text">
              {m.content}
              {m.expires_at && <span className="ai-memo-sub">{t('aiMemoUntil', { date: shortDate(m.expires_at, locale) })}</span>}
            </span>
            <button type="button" className="chat-icon-btn" onClick={() => removeMemo(m.id)} aria-label={t('aiMemoDelete')} title={t('aiMemoDelete')}>
              <X size={16} />
            </button>
          </div>
        )) : <p className="ai-memo-empty">{memory ? t('aiMemoEmpty') : '…'}</p>}
        <p className="ai-memo-note">{t('aiMemoOneTimeNote')}</p>

        <div className="ai-settings-section">{t('aiMoreSection')}</div>
        <Link to="/account/ai-notes" className="ai-settings-link" onClick={onNavigate}>
          <span>
            {t('aiNotesLink')}
            <span className="ai-memo-sub">{t('aiNotesLinkSub', { count: memory?.observation_count ?? 0 })}</span>
          </span>
          <ChevronRight size={18} />
        </Link>
        <Link to="/account/profile" className="ai-settings-link" onClick={onNavigate}>
          <span>
            {t('spPageTitle')}
            <span className="ai-memo-sub">{t('spLinkSub')}</span>
          </span>
          <ChevronRight size={18} />
        </Link>
      </div>
    </div>
  );
};

