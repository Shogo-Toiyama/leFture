import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ChevronRight, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { selfPortraitApi, shortDate, type AiMemory } from '../../lib/selfPortrait';

/**
 * AIチャット設定(チャットパネル右上のボタンから開くシート)。
 * 話し方の覚え書きと今の状況を見て消せる。AIのメモ(観察)と自分像のページへの入口を置く。
 * fixed=false ならパネルの中(position: absolute)、true なら画面全体(全画面のチャット)に重ねる。
 */
export const AiSettingsSheet: React.FC<{ open: boolean; onClose: () => void; fixed?: boolean; onNavigate?: () => void }> = ({
  open,
  onClose,
  fixed = false,
  onNavigate,
}) => {
  const { t, locale } = useLanguage();
  const [memory, setMemory] = useState<AiMemory | null>(null);
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
        <Link to="/account/ai-memory" className="ai-settings-link" onClick={onNavigate}>
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
