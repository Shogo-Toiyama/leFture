import React from 'react';
import { AlertCircle } from 'lucide-react';
import { useLanguage } from '../i18n/LanguageContext';

/**
 * 停止中アカウント向けの注意書き。閲覧以外(録音・購入・プラン変更)の入口に出す。
 * 実際の拒否はバックエンド(403 ACCOUNT_SUSPENDED)が行うので、これは案内に過ぎない。
 */
export const AccountSuspendedNotice: React.FC<{ variant?: 'full' | 'plans' }> = ({ variant = 'full' }) => {
  const { t } = useLanguage();
  const text =
    variant === 'plans'
      ? t('accountSuspendedNoticePlans')
      : t('accountSuspendedNoticeFull');
  return (
    <div className="notice notice-error" role="alert" style={{ display: 'flex', gap: '0.6rem', alignItems: 'flex-start' }}>
      <AlertCircle size={18} style={{ flexShrink: 0, marginTop: 2 }} />
      <span>
        {text}{' '}
        <a href="https://lefture.com/contact" target="_blank" rel="noreferrer">
          {t('contactSupport')}
        </a>
      </span>
    </div>
  );
};
