import React, { useEffect, useState } from 'react';
import { Bot } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import type { AiConsentKind } from '../../lib/aiConsent';

export interface AiConsentModalProps {
  kind: AiConsentKind;
  /** 前の版に同意した人にもう一度聞くとき、その理由を先頭に出す(録音)。 */
  updated: boolean;
  /** 同意を記録して進む。失敗したら投げる(モーダルは開いたまま、やり直せる)。 */
  onAgree: () => Promise<void>;
  onCancel: () => void;
}

/**
 * AIサービスへのデータ送信への同意(アプリと同じ形・同じ文言)。
 * 短い説明と「詳しく見る」(送るデータと送り先の一覧)、プライバシーポリシーとお問い合わせへのリンク、
 * 「キャンセル」と「同意して続ける」。録音の同意とチャットの同意は文言を変えて別々に出す。
 */
export const AiConsentModal: React.FC<AiConsentModalProps> = ({ kind, updated, onAgree, onCancel }) => {
  const { t } = useLanguage();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !busy) onCancel();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [busy, onCancel]);

  const title = kind === 'chat' ? t('aiConsentChatTitle') : t('aiConsentRecordingTitle');
  const message = kind === 'chat' ? t('aiConsentChatMessage') : t('aiConsentRecordingMessage');
  const details = kind === 'chat' ? t('aiConsentChatDetails') : t('aiConsentRecordingDetails');

  const agree = async () => {
    setBusy(true);
    setError(null);
    try {
      await onAgree();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setBusy(false);
    }
  };

  return (
    <div
      className="lecture-modal-backdrop"
      style={{ zIndex: 1200, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }}
      onClick={() => {
        if (!busy) onCancel();
      }}
    >
      <div
        className="lecture-modal-card"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        style={{
          maxWidth: 480,
          width: '100%',
          maxHeight: '90vh',
          display: 'flex',
          flexDirection: 'column',
          background: '#13131c',
          border: '1px solid var(--glass-border)',
          borderRadius: 20,
          boxShadow: '0 20px 48px rgba(0, 0, 0, 0.7)',
          overflow: 'hidden',
          animation: 'sheet-fade-in 0.2s ease-out',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', padding: '1.25rem 1.4rem 0.75rem' }}>
          <span
            style={{
              display: 'inline-flex',
              padding: 8,
              borderRadius: 10,
              background: 'rgba(255, 179, 0, 0.15)',
              color: 'var(--gold)',
            }}
          >
            <Bot size={22} />
          </span>
          <h3 style={{ margin: 0, fontSize: '1.1rem', color: '#fff', fontWeight: 700 }}>{title}</h3>
        </div>

        <div style={{ padding: '0.25rem 1.4rem 0.5rem', overflowY: 'auto', color: 'var(--starlight)', fontSize: '0.9rem', lineHeight: 1.6 }}>
          {updated && (
            <p
              style={{
                margin: '0 0 0.75rem',
                padding: '0.6rem 0.75rem',
                borderRadius: 10,
                background: 'rgba(255, 179, 0, 0.12)',
                color: 'var(--gold)',
                fontSize: '0.85rem',
              }}
            >
              {t('aiConsentRecordingUpdated')}
            </p>
          )}
          <p style={{ margin: 0 }}>{message}</p>
          <details style={{ marginTop: '0.5rem' }}>
            <summary style={{ cursor: 'pointer', color: 'var(--gold)', fontWeight: 700, fontSize: '0.85rem' }}>
              {t('aiConsentDetailsToggle')}
            </summary>
            <p style={{ margin: '0.5rem 0 0', whiteSpace: 'pre-line', fontSize: '0.82rem', lineHeight: 1.7 }}>{details}</p>
          </details>
          <p style={{ margin: '0.75rem 0 0', display: 'flex', gap: '1rem', flexWrap: 'wrap', fontSize: '0.85rem' }}>
            <a href="https://lefture.com/privacy" target="_blank" rel="noopener noreferrer" style={{ color: 'var(--gold)' }}>
              {t('privacyPolicyLink')}
            </a>
            <a href="https://lefture.com/contact" target="_blank" rel="noopener noreferrer" style={{ color: 'var(--gold)' }}>
              {t('contactUs')}
            </a>
          </p>
          {error && (
            <p role="alert" style={{ margin: '0.75rem 0 0', color: 'var(--correction-red, #ff5252)', fontSize: '0.85rem' }}>
              {error}
            </p>
          )}
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem', padding: '0.9rem 1.4rem 1.25rem' }}>
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            style={{
              fontSize: '0.88rem',
              background: 'transparent',
              color: 'var(--comet, #c3c8d6)',
              border: 'none',
              borderRadius: 8,
              padding: '0.55rem 1.15rem',
              cursor: busy ? 'default' : 'pointer',
              fontWeight: 600,
            }}
          >
            {t('cancel')}
          </button>
          <button
            type="button"
            onClick={agree}
            disabled={busy}
            style={{
              fontSize: '0.88rem',
              background: 'var(--gold)',
              color: '#241a00',
              border: '1px solid transparent',
              borderRadius: 10,
              padding: '0.55rem 1.15rem',
              cursor: busy ? 'default' : 'pointer',
              fontWeight: 700,
              opacity: busy ? 0.7 : 1,
            }}
          >
            {t('aiConsentAgree')}
          </button>
        </div>
      </div>
    </div>
  );
};
