import React, { useEffect, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { getLegalDocument, LegalDocument } from '../lib/supabase';
import { useTranslation } from '../i18n/LanguageContext';
import { FileText, Loader2, AlertCircle, RefreshCw, Calendar } from 'lucide-react';
import { usePageMeta } from '../lib/usePageMeta';

export const TermsPage: React.FC = () => {
  const { locale, t } = useTranslation();

  usePageMeta({
    title: 'Terms of Service | leFture',
    description: 'Read the Terms of Service for leFture, the AI-powered lecture companion.',
    canonicalPath: '/terms',
  });

  const [doc, setDoc] = useState<LegalDocument | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const fetchDocument = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getLegalDocument('terms_of_service', locale);
      setDoc(data);
    } catch (err: any) {
      console.error('Failed to load terms document:', err);
      setError(err.message || 'Failed to fetch legal document');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDocument();
  }, [locale]);

  return (
    <div className="container animate-fade-in" style={{ maxWidth: '820px' }}>
      <div className="glass-card" style={{ padding: 'clamp(20px, 5vw, 40px)', marginTop: '12px' }}>
        {/* Header Section */}
        <div style={{
          display: 'flex',
          alignItems: 'flex-start',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: '16px',
          paddingBottom: '20px',
          borderBottom: '1px solid var(--glass-border)',
          marginBottom: '24px'
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
            <div style={{
              width: '44px',
              height: '44px',
              borderRadius: '12px',
              background: 'rgba(255, 179, 0, 0.12)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'var(--color-star-gold)',
              flexShrink: 0
            }}>
              <FileText size={24} />
            </div>
            <div>
              <h1 style={{ fontSize: 'clamp(1.4rem, 4vw, 1.85rem)', marginBottom: '2px' }}>
                {doc?.title || t.terms.title}
              </h1>
              <p style={{ color: 'var(--text-comet)', fontSize: '0.85rem' }}>
                {t.terms.subtitle}
              </p>
            </div>
          </div>

          {doc?.effectiveDate && (
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              fontSize: '0.825rem',
              color: 'var(--text-dim)',
            }}>
              <Calendar size={14} />
              <span>
                {t.terms.effectiveDate}: {new Date(doc.effectiveDate).toLocaleDateString(locale === 'ja' ? 'ja-JP' : 'en-US')}
              </span>
            </div>
          )}
        </div>

        {/* Content Body */}
        {loading ? (
          <div style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '12px',
            color: 'var(--text-comet)',
            padding: '60px 0'
          }}>
            <Loader2 size={28} className="animate-spin" color="var(--color-star-gold)" />
            <span style={{ fontSize: '0.95rem' }}>{t.terms.loading}</span>
          </div>
        ) : error ? (
          <div style={{
            textAlign: 'center',
            padding: '48px 20px',
            backgroundColor: 'rgba(229, 57, 53, 0.08)',
            border: '1px solid rgba(229, 57, 53, 0.25)',
            borderRadius: '12px'
          }}>
            <AlertCircle size={40} color="var(--color-correction-red)" style={{ margin: '0 auto 12px' }} />
            <h3 style={{ fontSize: '1.15rem', marginBottom: '6px' }}>{t.terms.errorTitle}</h3>
            <p style={{ color: 'var(--text-comet)', fontSize: '0.9rem', marginBottom: '20px' }}>
              {t.terms.errorDesc}
            </p>
            <button
              onClick={fetchDocument}
              className="btn-secondary"
              style={{ fontSize: '0.875rem', padding: '8px 18px' }}
            >
              <RefreshCw size={15} />
              <span>{t.terms.retry}</span>
            </button>
          </div>
        ) : doc ? (
          <div className="markdown-body" style={{
            color: 'var(--text-starlight)',
            lineHeight: 1.8,
            fontSize: '0.95rem'
          }}>
            <ReactMarkdown
              components={{
                h1: ({ children }) => <h2 style={{ fontSize: '1.4rem', margin: '28px 0 14px', color: '#fff', borderBottom: '1px solid rgba(255,255,255,0.08)', paddingBottom: '8px' }}>{children}</h2>,
                h2: ({ children }) => <h3 style={{ fontSize: '1.2rem', margin: '22px 0 10px', color: '#fff' }}>{children}</h3>,
                h3: ({ children }) => <h4 style={{ fontSize: '1.05rem', margin: '18px 0 8px', color: 'var(--color-star-gold)' }}>{children}</h4>,
                p: ({ children }) => <p style={{ marginBottom: '14px', color: 'var(--text-starlight)' }}>{children}</p>,
                ul: ({ children }) => <ul style={{ paddingLeft: '20px', marginBottom: '14px' }}>{children}</ul>,
                ol: ({ children }) => <ol style={{ paddingLeft: '20px', marginBottom: '14px' }}>{children}</ol>,
                li: ({ children }) => <li style={{ marginBottom: '6px' }}>{children}</li>,
              }}
            >
              {doc.contentMarkdown}
            </ReactMarkdown>
          </div>
        ) : null}
      </div>
    </div>
  );
};
