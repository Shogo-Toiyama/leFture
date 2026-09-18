import React, { useEffect } from 'react';
import { createPortal } from 'react-dom';
import { useNavigate } from 'react-router-dom';
import { PlanLockIllustration } from './PlanLockIllustration';
import { useLanguage } from '../i18n/LanguageContext';

export interface UpgradeRequiredDialogProps {
  requiredTierColor: string;
  title: string;
  message: string;
  onClose: () => void;
}

/**
 * 特定の機能がまだ現在のプランで使えない時に出す、Plansページへの誘導ダイアログ。
 * upgrade_required_dialog.dart の移植。
 */
export const UpgradeRequiredDialog: React.FC<UpgradeRequiredDialogProps> = ({
  requiredTierColor,
  title,
  message,
  onClose,
}) => {
  const navigate = useNavigate();
  const { t } = useLanguage();

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  // document.bodyへPortalで描画する。全画面ビューア(.pv-root系ページ)には
  // 「.pv-root > * の position:relative を強制するリセット」があり、それが
  // 後方のCSSルールとして本コンポーネントの position:fixed を上書きしてしまい、
  // ダイアログが画面中央ではなく通常のドキュメントフロー上(画面下端)に
  // 押し出される不具合が起きていた。Portalなら祖先のCSSの影響を一切受けない。
  return createPortal(
    <div className="upgrade-required-backdrop" onClick={onClose}>
      <div className="upgrade-required-card" onClick={(e) => e.stopPropagation()}>
        <PlanLockIllustration color={requiredTierColor} size={88} />
        <h3 className="upgrade-required-title">{title}</h3>
        <p className="upgrade-required-message">{message}</p>
        <div className="upgrade-required-actions">
          <button type="button" className="upgrade-required-cancel" onClick={onClose}>
            {t('upgradeRequiredCancelButton')}
          </button>
          <button
            type="button"
            className="upgrade-required-view-plans"
            style={{ background: requiredTierColor }}
            onClick={() => {
              onClose();
              navigate('/account/plans');
            }}
          >
            {t('upgradeRequiredViewPlansButton')}
          </button>
        </div>
      </div>
    </div>,
    document.body
  );
};
