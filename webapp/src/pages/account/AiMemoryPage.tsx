import React, { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowLeft, ChevronRight, Sparkles, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { ConfirmModal } from '../../components/modals/ConfirmModal';
import { ProfileSkeleton } from '../../components/account/ProfileSkeleton';
import { selfPortraitApi, type AiMemory } from '../../lib/selfPortrait';

/**
 * AIチャット設定(ページ版):
 * 話し方の覚え書き(Style)の管理と、AIのメモ(AI Notes)のサマリー・一括消去・詳細ページへのリンク。
 * 今の状況(Right Now)は一時的な文脈のためチャット内シート限定とし、ここからは除外。
 */
export const AiMemoryPage: React.FC = () => {
  const { t } = useLanguage();
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

  const forgetAll = () =>
    act(() => selfPortraitApi.forgetAiNotes(), (m) => ({ ...m, observation_groups: [], observation_count: 0 }));

  if (!memory && !error) return <ProfileSkeleton />;

  const styles = memory?.memos.filter((m) => m.kind === 'answer_style') ?? [];
  const observationCount = memory?.observation_count ?? 0;

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

      {/* 1. 話し方の覚え書き */}
      <p className="glass-section-label">{t('aiMemoStyleSection')}</p>
      <div className="glass-card">
        {styles.length ? styles.map((m) => (
          <div key={m.id} className="ai-page-row">
            <span className="ai-memo-text">{m.content}</span>
            <button
              type="button"
              className="chat-icon-btn"
              onClick={() => removeMemo(m.id)}
              aria-label={t('aiMemoDelete')}
              title={t('aiMemoDelete')}
            >
              <X size={16} />
            </button>
          </div>
        )) : <p className="ai-memo-empty ai-page-empty">{t('aiMemoEmpty')}</p>}
      </div>
      <p className="ai-memo-note">{t('aiMemoOneTimeNote')}</p>

      {/* 2. AIのメモ (サマリーカード) */}
      <p className="glass-section-label" style={{ marginTop: '2rem' }}>{t('aiNotesLink')}</p>
      <div className="glass-card" style={{ padding: '1.25rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
          <Sparkles size={17} style={{ color: 'var(--comet, #8E99A6)' }} />
          <span style={{ fontWeight: 600, fontSize: '0.95rem', color: 'var(--white, #fff)' }}>
            {t('aiNotesCount', { count: observationCount })}
          </span>
        </div>
        <p className="ai-memo-note" style={{ margin: '0 0 1rem 0' }}>
          {t('aiMemoryIntro')}
        </p>

        <Link
          to="/account/ai-notes"
          className="glass-row"
          style={{
            background: 'rgba(255, 255, 255, 0.04)',
            borderRadius: '8px',
            border: '1px solid rgba(255, 255, 255, 0.08)',
            padding: '0.65rem 0.85rem',
            marginBottom: observationCount > 0 ? '1rem' : 0,
          }}
        >
          <span className="glass-row-text">
            <span className="glass-row-title" style={{ fontSize: '0.9rem' }}>{t('aiNotesViewAll')}</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>

        {observationCount > 0 && (
          <div style={{ borderTop: '1px solid rgba(255, 255, 255, 0.08)', paddingTop: '0.85rem' }}>
            <button
              type="button"
              className="ai-forget-btn"
              onClick={() => setConfirmForget(true)}
              style={{ padding: '0.25rem 0', background: 'transparent', border: 'none' }}
            >
              {t('aiMemoryForgetAll')}
            </button>
            <p className="ai-memo-note" style={{ margin: '0.25rem 0 0 0', fontSize: '0.8rem' }}>
              {t('aiMemoryForgetAllNote')}
            </p>
          </div>
        )}
      </div>

      <ConfirmModal
        open={confirmForget}
        onClose={() => setConfirmForget(false)}
        onConfirm={() => { setConfirmForget(false); void forgetAll(); }}
        title={t('aiMemoryForgetAll')}
        message={t('aiMemoryForgetConfirmMessage', { count: observationCount })}
        confirmLabel={t('delete')}
        cancelLabel={t('cancel')}
        isDanger
      />
    </div>
  );
};
