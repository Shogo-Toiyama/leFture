import React, { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowLeft, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { ConfirmModal } from '../../components/modals/ConfirmModal';
import { ProfileSkeleton } from '../../components/account/ProfileSkeleton';
import { selfPortraitApi, shortDate, type AiMemory } from '../../lib/selfPortrait';

/**
 * AIメモ一覧(ページ版):
 * 会話の中でAIが気づいた観察メモ(observations)を会話ごとに一覧表示し、
 * 個別削除や全消去、該当チャットを開く操作ができる。
 */
export const AiNotesPage: React.FC = () => {
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

  return (
    <div className="account-page sp-page">
      <div className="profile-detail-top-nav">
        <Link to="/account/ai-memory" className="back-link" style={{ margin: 0 }}>
          <ArrowLeft size={18} />
          <span>{t('aiSettingsPageTitle')}</span>
        </Link>
      </div>
      <div className="profile-detail-title-row">
        <h1 style={{ margin: '0.5rem 0 0.25rem', fontSize: '1.8rem' }}>{t('aiNotesLink')}</h1>
        <p className="muted" style={{ margin: 0, fontSize: '0.9rem' }}>{t('aiMemoryIntro')}</p>
      </div>
      {error && <p className="auth-error" style={{ marginTop: '1rem' }}>{t('spLoadError')}</p>}

      {memory && memory.observation_groups.length === 0 && (
        <p className="sp-empty" style={{ marginTop: '2rem' }}>{t('aiMemoryEmpty')}</p>
      )}

      <div className="ai-obs-groups" style={{ marginTop: '1.5rem' }}>
        {memory?.observation_groups.map((g) => (
          <div key={g.thread_id} className="glass-card">
            <div className="ai-obs-head">
              <span>{g.thread_title || t('chatThreadUntitled')} · {shortDate(g.last_observed_at, locale)}</span>
              <Link to={`/chat/${g.thread_id}`}>{t('spOpenChat')}</Link>
            </div>
            {g.observations.map((o) => (
              <div key={o.id} className="ai-page-row">
                <span className="ai-memo-text">{o.note}</span>
                <button
                  type="button"
                  className="chat-icon-btn"
                  onClick={() => removeObservation(o.id)}
                  aria-label={t('aiMemoryDeleteNote')}
                  title={t('aiMemoryDeleteNote')}
                >
                  <X size={16} />
                </button>
              </div>
            ))}
          </div>
        ))}
      </div>

      {memory && memory.observation_count > 0 && (
        <div className="glass-card ai-forget-card" style={{ marginTop: '1.5rem' }}>
          <button type="button" className="ai-forget-btn" onClick={() => setConfirmForget(true)}>
            {t('aiMemoryForgetAll')}
          </button>
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
