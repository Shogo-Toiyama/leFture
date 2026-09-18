import React, { useEffect } from 'react';
import { createPortal } from 'react-dom';
import { useNavigate } from 'react-router-dom';
import { useLanguage } from '../i18n/LanguageContext';
import { CreditStarIcon } from './icons/CreditStarIcon';

export interface CreditRateTableDialogProps {
  onClose: () => void;
}

const RATE_ROWS: Array<{ durationKey: 'creditRateRow1Duration' | 'creditRateRow2Duration' | 'creditRateRow3Duration' | 'creditRateRow4Duration'; credits: number }> = [
  { durationKey: 'creditRateRow1Duration', credits: 60 },
  { durationKey: 'creditRateRow2Duration', credits: 80 },
  { durationKey: 'creditRateRow3Duration', credits: 100 },
  { durationKey: 'creditRateRow4Duration', credits: 120 },
];

/**
 * クレジット消費早見表(録音時間ごとの消費量)。credit_rate_table_dialog.dart の移植。
 * document.bodyへPortalで描画する(UpgradeRequiredDialogと同じ理由 — .pv-root系
 * ページの祖先CSSにposition:fixedを上書きされないため)。
 */
export const CreditRateTableDialog: React.FC<CreditRateTableDialogProps> = ({ onClose }) => {
  const { t } = useLanguage();
  const navigate = useNavigate();

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  return createPortal(
    <div className="credit-rate-backdrop" onClick={onClose}>
      <div className="credit-rate-card" onClick={(e) => e.stopPropagation()}>
        <div className="credit-rate-header">
          <span className="credit-rate-header-icon">
            <CreditStarIcon size={20} />
          </span>
          <h3 className="credit-rate-title">{t('creditRateModalTitle')}</h3>
          <button type="button" className="credit-rate-close-btn" onClick={onClose} aria-label="Close">
            ✕
          </button>
        </div>

        <p className="credit-rate-description">{t('creditRateModalDescription')}</p>

        <div className="credit-rate-table">
          <div className="credit-rate-table-header">
            <span>{t('creditRateTableDurationHeader')}</span>
            <span>{t('creditRateTableCreditsHeader')}</span>
          </div>
          {RATE_ROWS.map((row) => (
            <div key={row.durationKey} className="credit-rate-table-row">
              <span className="credit-rate-duration">{t(row.durationKey)}</span>
              <span className="credit-rate-credits">
                <CreditStarIcon size={15} />
                {row.credits}
              </span>
            </div>
          ))}
        </div>

        <div className="credit-rate-notice">
          <span className="material-symbols-outlined credit-rate-notice-icon">info</span>
          <span>{t('creditRateMaxDurationNotice')}</span>
        </div>

        <button
          type="button"
          className="credit-rate-buy-btn"
          onClick={() => {
            onClose();
            navigate('/account/credits/purchase');
          }}
        >
          <CreditStarIcon size={16} color="#FDE047" />
          {t('creditRateModalBuyCreditsButton')}
        </button>
      </div>
    </div>,
    document.body
  );
};
