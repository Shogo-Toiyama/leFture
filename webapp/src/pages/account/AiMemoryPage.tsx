import React, { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowLeft, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { ConfirmModal } from '../../components/modals/ConfirmModal';
import { ProfileSkeleton } from '../../components/account/ProfileSkeleton';
import { selfPortraitApi, shortDate, type AiMemory } from '../../lib/selfPortrait';

/**
 * AIチャット設定(ページ版): 話し方の覚え書き・今の状況と、AIのメモ(観察)を会話ごとに。
 * アカウントページとチャットのシートから来る。仮説(AIが次に聞いてみたいこと)は見せない。
 */
export const AiMemoryPage: React.FC = () => {
  const { t, locale } = useLanguage();
  const [memory, setMemory] = useState<AiMemory | null>(null);
  const [error, setError] = useState(false);
  const [confirmForget, setConfirmForget] = useState(false);

  const load = useCallback(async () => {
    try {
      setMemory(await selfPortraitApi.aiMemory());
      setError(false);
    } catch {
      setError(true);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const act = async (fn: () => Promise<unknown>, optimistic: (m: AiMemory) => AiMemory) => {
    setMemory((m) => (m ? optimistic(m) : m));
    try {
      await fn();
    } catch {
      setError(true);
      void load();
    }
  };

  const removeMemo = (id: string) =>
    act(() => selfPortraitApi.deleteMemo(id), (m) => ({ ...m, memos: m.memos.filter((x) => x.id !== id) }));

  const removeObservation = (id: string) =>
    act(() => selfPortraitApi.deleteObservation(id), (m) => ({
      ...m,
      observation_count: m.observation_count - 1,
      observation_groups: m.observation_groups
        .map((g) => ({ ...g, observations: g.observations.filter((o) => o.id !== id) }))
        .filter((g) => g.observations.length > 0),
    }));

  const forgetAll = () =>
    act(() => selfPortraitApi.forgetAiNotes(), (m) => ({ ...m, observation_groups: [], observation_count: 0 }));

  if (!memory && !error) return <ProfileSkeleton />;

  const styles = memory?.memos.filter((m) => m.kind === 'answer_style') ?? [];
  const situations = memory?.memos.filter((m) => m.kind === 'situation') ?? [];

  return (
    <div className="account-page sp-page">
      <div className="profile-detail-top-nav">
        <Link to="/account" className="back-link" style={{ margin: 0 }}>
          <ArrowLeft size={18} />
          <span>Account</span>
        </Link>
      </div>
      <div className="profile-detail-title-row">
        <h1 style={{ margin: '0.5rem 0 0.25rem', fontSize: '1.8rem' }}>{t('aiSettingsPageTitle')}</h1>
        <p className="muted" style={{ margin: 0, fontSize: '0.9rem' }}>{t('aiSettingsPageIntro')}</p>
      </div>
      {error && <p className="auth-error" style={{ marginTop: '1rem' }}>{t('spLoadError')}</p>}

      <p className="glass-section-label">{t('aiMemoStyleSection')}</p>
      <div className="glass-card">
        {styles.length ? styles.map((m) => (
          <div key={m.id} className="ai-page-row">
            <span className="ai-memo-text">{m.content}</span>
            <button type="button" className="chat-icon-btn" onClick={() => removeMemo(m.id)} aria-label={t('aiMemoDelete')} title={t('aiMemoDelete')}>
              <X size={16} />
            </button>
          </div>
        )) : <p className="ai-memo-empty ai-page-empty">{t('aiMemoEmpty')}</p>}
      </div>

      <p className="glass-section-label">{t('aiMemoSituationSection')}</p>
      <div className="glass-card">
        {situations.length ? situations.map((m) => (
          <div key={m.id} className="ai-page-row">
            <span className="ai-memo-text">
              {m.content}
              {m.expires_at && <span className="ai-memo-sub">{t('aiMemoUntil', { date: shortDate(m.expires_at, locale) })}</span>}
            </span>
            <button type="button" className="chat-icon-btn" onClick={() => removeMemo(m.id)} aria-label={t('aiMemoDelete')} title={t('aiMemoDelete')}>
              <X size={16} />
            </button>
          </div>
        )) : <p className="ai-memo-empty ai-page-empty">{t('aiMemoEmpty')}</p>}
      </div>
      <p className="ai-memo-note">{t('aiMemoOneTimeNote')}</p>

      <p className="glass-section-label">{t('aiNotesLink')}</p>
      <p className="ai-memo-note" style={{ marginTop: 0 }}>{t('aiMemoryIntro')}</p>
      {memory && memory.observation_groups.length === 0 && <p className="sp-empty">{t('aiMemoryEmpty')}</p>}
      <div className="ai-obs-groups">
        {memory?.observation_groups.map((g) => (
          <div key={g.thread_id} className="glass-card">
            <div className="ai-obs-head">
              <span>{g.thread_title || t('chatThreadUntitled')} · {shortDate(g.last_observed_at, locale)}</span>
              <Link to={`/chat/${g.thread_id}`}>{t('spOpenChat')}</Link>
            </div>
            {g.observations.map((o) => (
              <div key={o.id} className="ai-page-row">
                <span className="ai-memo-text">{o.note}</span>
                <button type="button" className="chat-icon-btn" onClick={() => removeObservation(o.id)} aria-label={t('aiMemoryDeleteNote')} title={t('aiMemoryDeleteNote')}>
                  <X size={16} />
                </button>
              </div>
            ))}
          </div>
        ))}
      </div>

      {memory && memory.observation_count > 0 && (
        <div className="glass-card ai-forget-card">
          <button type="button" className="ai-forget-btn" onClick={() => setConfirmForget(true)}>{t('aiMemoryForgetAll')}</button>
          <p className="ai-memo-note" style={{ margin: 0 }}>{t('aiMemoryForgetAllNote')}</p>
        </div>
      )}

      <ConfirmModal
        open={confirmForget}
        onClose={() => setConfirmForget(false)}
        onConfirm={() => { setConfirmForget(false); void forgetAll(); }}
        title={t('aiMemoryForgetAll')}
        message={t('aiMemoryForgetConfirmMessage', { count: memory?.observation_count ?? 0 })}
        confirmLabel={t('delete')}
        cancelLabel={t('cancel')}
        isDanger
      />
    </div>
  );
};
