import React from 'react';
import { AlertCircle } from 'lucide-react';
import { useLanguage } from '../i18n/LanguageContext';

/**
 * 停止中アカウント向けの注意書き。閲覧以外(録音・購入・プラン変更)の入口に出す。
 * 実際の拒否はバックエンド(403 ACCOUNT_SUSPENDED)が行うので、これは案内に過ぎない。
 */
export const AccountSuspendedNotice: React.FC<{ variant?: 'full' | 'plans' }> = ({ variant = 'full' }) => {
  const isJa = useLanguage().language === 'ja';
  const text =
    variant === 'plans'
      ? isJa
        ? 'アカウントが停止中です。サブスクリプションの解約は可能ですが、その他のプラン変更はご利用いただけません。'
        : 'Your account is suspended. You can cancel your subscription here, but other plan changes are unavailable.'
      : isJa
        ? '利用規約違反のため、このアカウントは停止されています。既存の講義やノートの閲覧は引き続き可能ですが、録音・分析・クレジット購入・プラン変更はご利用いただけません。'
        : 'This account has been suspended due to a violation of our Terms of Service. You can still view your existing lectures and notes, but recording, analysis, credit purchases, and plan changes are unavailable.';
  return (
    <div className="notice notice-error" role="alert" style={{ display: 'flex', gap: '0.6rem', alignItems: 'flex-start' }}>
      <AlertCircle size={18} style={{ flexShrink: 0, marginTop: 2 }} />
      <span>
        {text}{' '}
        <a href="https://lefture.com/contact" target="_blank" rel="noreferrer">
          {isJa ? 'サポートに連絡' : 'Contact support'}
        </a>
      </span>
    </div>
  );
};
