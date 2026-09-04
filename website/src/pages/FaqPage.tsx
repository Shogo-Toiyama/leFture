import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from '../i18n/LanguageContext';
import { usePageMeta } from '../lib/usePageMeta';
import {
  HelpCircle,
  ChevronDown,
  ExternalLink,
  ShieldAlert,
  MessageSquare,
  ArrowRight,
} from 'lucide-react';

export const FaqPage: React.FC = () => {
  const { t, locale } = useTranslation();

  usePageMeta({
    title: locale === 'ja' ? 'よくある質問 (FAQ) | leFture' : 'FAQ | leFture',
    description:
      locale === 'ja'
        ? 'leFtureに関するよくあるご質問と回答。アカウントの削除方法やプライバシー保護、機能についてご案内します。'
        : 'Frequently asked questions about leFture, account deletion, privacy, and features.',
    canonicalPath: '/faq',
  });

  // 'account-deletion' を初期状態で開いておくことで、Google Play審査や利用者が即座に確認可能
  const [openIds, setOpenIds] = useState<string[]>(['account-deletion']);

  const toggleItem = (id: string) => {
    setOpenIds((prev) =>
      prev.includes(id) ? prev.filter((item) => item !== id) : [...prev, id]
    );
  };

  return (
    <div className="container animate-fade-in" style={{ maxWidth: '820px' }}>
      <div
        className="glass-card"
        style={{
          padding: 'clamp(20px, 5vw, 40px)',
          marginTop: '12px',
          marginBottom: '40px',
        }}
      >
        {/* Header */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '16px',
            paddingBottom: '20px',
            borderBottom: '1px solid var(--glass-border)',
            marginBottom: '28px',
          }}
        >
          <div
            style={{
              width: '48px',
              height: '48px',
              borderRadius: '14px',
              background: 'rgba(255, 179, 0, 0.12)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'var(--color-star-gold)',
              flexShrink: 0,
            }}
          >
            <HelpCircle size={26} />
          </div>
          <div>
            <h1
              style={{
                fontSize: 'clamp(1.5rem, 4vw, 2rem)',
                marginBottom: '4px',
                color: 'var(--text-starlight)',
              }}
            >
              {t.faq.title}
            </h1>
            <p style={{ color: 'var(--text-comet)', fontSize: '0.875rem' }}>
              {t.faq.subtitle}
            </p>
          </div>
        </div>

        {/* FAQ Accordion List */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
          {t.faq.items.map((item) => {
            const isOpen = openIds.includes(item.id);
            const isAccountDeletion = item.id === 'account-deletion';

            return (
              <div
                key={item.id}
                style={{
                  borderRadius: '14px',
                  background: isAccountDeletion
                    ? 'rgba(255, 255, 255, 0.04)'
                    : 'rgba(255, 255, 255, 0.02)',
                  border: isOpen
                    ? isAccountDeletion
                      ? '1px solid rgba(229, 57, 53, 0.4)'
                      : '1px solid var(--glass-border-hover)'
                    : '1px solid var(--glass-border)',
                  overflow: 'hidden',
                  transition: 'all 0.25s ease',
                }}
              >
                {/* Accordion Trigger */}
                <button
                  type="button"
                  onClick={() => toggleItem(item.id)}
                  style={{
                    width: '100%',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '18px 20px',
                    background: 'transparent',
                    color: 'var(--text-starlight)',
                    textAlign: 'left',
                    fontSize: '1rem',
                    fontWeight: 600,
                    gap: '16px',
                  }}
                  aria-expanded={isOpen}
                >
                  <span
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: '10px',
                      color: isAccountDeletion && isOpen ? '#ff8b85' : 'inherit',
                    }}
                  >
                    {isAccountDeletion && (
                      <ShieldAlert
                        size={18}
                        color={isOpen ? '#ff8b85' : 'var(--color-correction-red)'}
                        style={{ flexShrink: 0 }}
                      />
                    )}
                    {item.question}
                  </span>
                  <ChevronDown
                    size={20}
                    style={{
                      transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)',
                      transition: 'transform 0.25s ease',
                      color: 'var(--text-comet)',
                      flexShrink: 0,
                    }}
                  />
                </button>

                {/* Accordion Content */}
                {isOpen && (
                  <div
                    style={{
                      padding: '0 20px 22px',
                      color: 'var(--text-comet)',
                      fontSize: '0.9375rem',
                      lineHeight: 1.7,
                      borderTop: '1px solid rgba(255, 255, 255, 0.05)',
                    }}
                  >
                    <p style={{ marginTop: '14px', marginBottom: item.action ? '16px' : '0', whiteSpace: 'pre-line' }}>
                      {item.answer}
                    </p>

                    {/* Action Button (e.g. app.lefture.com or /privacy) */}
                    {item.action && (
                      <div style={{ marginTop: '16px', marginBottom: item.note ? '16px' : '0' }}>
                        {item.action.url.startsWith('http') ? (
                          <a
                            href={item.action.url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="btn-primary"
                            style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '8px',
                              padding: '10px 22px',
                              fontSize: '0.9rem',
                              fontWeight: 600,
                              borderRadius: '10px',
                              textDecoration: 'none',
                            }}
                          >
                            <span>{item.action.label}</span>
                            <ExternalLink size={16} />
                          </a>
                        ) : (
                          <Link
                            to={item.action.url}
                            className="btn-secondary"
                            style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '8px',
                              padding: '10px 22px',
                              fontSize: '0.9rem',
                              fontWeight: 600,
                              borderRadius: '10px',
                              textDecoration: 'none',
                              color: 'var(--text-starlight)',
                              border: '1px solid var(--glass-border)',
                            }}
                          >
                            <span>{item.action.label}</span>
                            <ArrowRight size={16} />
                          </Link>
                        )}
                      </div>
                    )}

                    {/* Additional Warning / Note */}
                    {item.note && (
                      <div
                        style={{
                          padding: '12px 14px',
                          borderRadius: '10px',
                          background: 'rgba(229, 57, 53, 0.08)',
                          border: '1px solid rgba(229, 57, 53, 0.25)',
                          color: '#ff8b85',
                          fontSize: '0.8125rem',
                          lineHeight: 1.5,
                        }}
                      >
                        {item.note}
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        {/* Contact Footer Box */}
        <div
          style={{
            marginTop: '36px',
            padding: '20px 24px',
            borderRadius: '14px',
            background: 'rgba(255, 255, 255, 0.03)',
            border: '1px solid var(--glass-border)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            flexWrap: 'wrap',
            gap: '14px',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <MessageSquare size={20} color="var(--color-star-gold)" />
            <span style={{ fontSize: '0.875rem', color: 'var(--text-comet)' }}>
              {t.faq.stillHaveQuestions}
            </span>
          </div>
          <Link
            to="/contact"
            className="btn-secondary"
            style={{
              fontSize: '0.85rem',
              padding: '8px 18px',
              borderRadius: '8px',
              color: 'var(--text-starlight)',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '6px',
            }}
          >
            <span>{t.faq.contactLink}</span>
          </Link>
        </div>
      </div>
    </div>
  );
};
