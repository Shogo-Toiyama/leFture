import React from 'react';
import { useNavigate } from 'react-router-dom';
import { AuthLayout } from '../../components/auth/AuthLayout';
import { useLanguage } from '../../i18n/LanguageContext';

export const AccountDeletedPage: React.FC = () => {
  const { t } = useLanguage();
  const navigate = useNavigate();

  return (
    <AuthLayout
      title={t('accountDeletedTitle')}
      subtitle="leFture"
      icon="sparkles"
    >
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1.5rem', textAlign: 'center', padding: '1rem 0' }}>
        {/* Success checkmark badge */}
        <div
          style={{
            width: '64px',
            height: '64px',
            borderRadius: '50%',
            background: 'rgba(76, 175, 80, 0.12)',
            border: '1px solid rgba(76, 175, 80, 0.3)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: '#81c784',
          }}
        >
          <svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="20 6 9 17 4 12" />
          </svg>
        </div>

        <p style={{ margin: 0, color: 'var(--text-comet)', fontSize: '0.9375rem', lineHeight: 1.6 }}>
          {t('accountDeletedMessage')}
        </p>

        <button
          type="button"
          className="auth-submit-btn"
          style={{ width: '100%', marginTop: '0.5rem' }}
          onClick={() => navigate('/sign-in', { replace: true })}
        >
          {t('backToSignIn')}
        </button>
      </div>
    </AuthLayout>
  );
};
