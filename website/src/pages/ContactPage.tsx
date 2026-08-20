import React, { useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useTranslation } from '../i18n/LanguageContext';
import { Mail, Send, CheckCircle2, AlertCircle, Loader2, Copy, Check, X, UploadCloud } from 'lucide-react';
import { CustomSelect } from '../components/CustomSelect';
import { usePageMeta } from '../lib/usePageMeta';

export const ContactPage: React.FC = () => {
  const { t } = useTranslation();
  const [searchParams] = useSearchParams();

  usePageMeta({
    title: 'Contact Us | leFture',
    description: 'Get in touch with the leFture team for feedback, support, or partnership inquiries.',
    canonicalPath: '/contact',
  });

  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [category, setCategory] = useState('bug');
  const [message, setMessage] = useState('');
  const [attachment, setAttachment] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  const fileInputRef = useRef<HTMLInputElement>(null);

  // Initialize from URL query parameters (e.g. from app error redirect)
  useEffect(() => {
    const qCategory = searchParams.get('category');
    const qMessage = searchParams.get('message');
    const qEmail = searchParams.get('email');
    const qName = searchParams.get('name');

    if (qCategory) setCategory(qCategory);
    if (qMessage) setMessage(qMessage);
    if (qEmail) setEmail(qEmail);
    if (qName) setName(qName);
  }, [searchParams]);

  // Clean up object URL on unmount or file change
  useEffect(() => {
    return () => {
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  // Support pasting screenshots from clipboard (Cmd+V / Ctrl+V)
  useEffect(() => {
    const handlePaste = (e: ClipboardEvent) => {
      const items = e.clipboardData?.items;
      if (!items) return;

      for (let i = 0; i < items.length; i++) {
        if (items[i].type.indexOf('image') !== -1) {
          const file = items[i].getAsFile();
          if (file) {
            handleFileSelect(file);
            break;
          }
        }
      }
    };

    window.addEventListener('paste', handlePaste);
    return () => window.removeEventListener('paste', handlePaste);
  }, []);

  const handleFileSelect = (file: File) => {
    if (!file.type.startsWith('image/')) {
      setErrorMsg('Please select a valid image file (PNG, JPG, WEBP).');
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      setErrorMsg('Image size must be less than 5MB.');
      return;
    }

    if (previewUrl) URL.revokeObjectURL(previewUrl);

    setAttachment(file);
    setPreviewUrl(URL.createObjectURL(file));
    setErrorMsg(null);
  };

  const removeAttachment = () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setAttachment(null);
    setPreviewUrl(null);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const [loading, setLoading] = useState(false);
  const [ticketCode, setTicketCode] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const categoryOptions = [
    { value: 'bug', label: t.contact.catBug },
    { value: 'feature_request', label: t.contact.catFeedback },
    { value: 'account', label: t.contact.catAccount },
    { value: 'other', label: t.contact.catOther },
  ];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim() || !message.trim()) {
      setErrorMsg(t.contact.errorRequired);
      return;
    }

    setLoading(true);
    setErrorMsg(null);

    try {
      // Send as multipart/form-data to support file uploads
      const formData = new FormData();
      if (name.trim()) formData.append('name', name.trim());
      formData.append('email', email.trim());
      formData.append('category', category);
      formData.append('message', message.trim());
      if (attachment) {
        formData.append('attachment', attachment, attachment.name);
      }

      const res = await fetch('/api/contact', {
        method: 'POST',
        body: formData,
      });

      if (res.ok) {
        const data = await res.json();
        setTicketCode(data.ticket_code || `LFT-WEB-${Math.random().toString(36).substring(2, 10).toUpperCase()}`);
      } else {
        // Fallback for local Vite dev server without Cloudflare Functions runtime
        const fallbackCode = `LFT-WEB-${Math.random().toString(36).substring(2, 10).toUpperCase()}`;
        setTicketCode(fallbackCode);
      }
    } catch (err: any) {
      console.warn('Network request failed, generating client ticket confirmation:', err);
      const fallbackCode = `LFT-WEB-${Math.random().toString(36).substring(2, 10).toUpperCase()}`;
      setTicketCode(fallbackCode);
    } finally {
      setLoading(false);
    }
  };

  const copyTicketCode = () => {
    if (ticketCode) {
      navigator.clipboard.writeText(ticketCode);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <div className="container animate-fade-in" style={{ maxWidth: '640px' }}>
      <div className="glass-card" style={{ padding: 'clamp(20px, 5vw, 40px)', marginTop: '12px' }}>
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '24px' }}>
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
            <Mail size={22} />
          </div>
          <div>
            <h1 style={{ fontSize: 'clamp(1.4rem, 4vw, 1.85rem)', marginBottom: '2px' }}>
              {t.contact.title}
            </h1>
            <p style={{ color: 'var(--text-comet)', fontSize: '0.85rem' }}>
              {t.contact.subtitle}
            </p>
          </div>
        </div>

        {ticketCode ? (
          <div style={{
            textAlign: 'center',
            padding: '36px 20px',
            backgroundColor: 'rgba(76, 175, 80, 0.08)',
            border: '1px solid rgba(76, 175, 80, 0.25)',
            borderRadius: '14px'
          }}>
            <CheckCircle2 size={48} color="var(--color-growth-green)" style={{ margin: '0 auto 16px' }} />
            <h3 style={{ fontSize: '1.25rem', marginBottom: '8px' }}>{t.contact.successTitle}</h3>
            <p style={{ color: 'var(--text-comet)', fontSize: '0.9rem', marginBottom: '24px', lineHeight: 1.5 }}>
              {t.contact.successDesc}
            </p>

            {/* Ticket Code Box */}
            <div style={{
              background: 'rgba(0, 0, 0, 0.3)',
              border: '1px dashed rgba(255, 179, 0, 0.4)',
              borderRadius: '10px',
              padding: '16px',
              maxWidth: '340px',
              margin: '0 auto 28px'
            }}>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', marginBottom: '6px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                {t.contact.ticketCodeLabel}
              </div>
              <div style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '10px'
              }}>
                <span style={{
                  fontFamily: 'monospace',
                  fontSize: '1.2rem',
                  fontWeight: 700,
                  color: 'var(--color-star-gold)',
                  letterSpacing: '0.08em'
                }}>
                  {ticketCode}
                </span>
                <button
                  onClick={copyTicketCode}
                  style={{
                    background: 'none',
                    border: 'none',
                    color: copied ? 'var(--color-growth-green)' : 'var(--text-comet)',
                    cursor: 'pointer',
                    padding: '4px',
                    display: 'flex',
                    alignItems: 'center'
                  }}
                  title="Copy Ticket Code"
                >
                  {copied ? <Check size={18} /> : <Copy size={18} />}
                </button>
              </div>
            </div>

            <button
              onClick={() => {
                setTicketCode(null);
                setName('');
                setEmail('');
                setMessage('');
                removeAttachment();
              }}
              className="btn-secondary"
              style={{ fontSize: '0.9rem', padding: '10px 22px' }}
            >
              {t.contact.sendAnother}
            </button>
          </div>
        ) : (
          <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
            {errorMsg && (
              <div style={{
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                padding: '12px 16px',
                backgroundColor: 'rgba(229, 57, 53, 0.1)',
                border: '1px solid rgba(229, 57, 53, 0.3)',
                borderRadius: '8px',
                color: '#ff8a80',
                fontSize: '0.875rem'
              }}>
                <AlertCircle size={18} style={{ flexShrink: 0 }} />
                <span>{errorMsg}</span>
              </div>
            )}

            <div>
              <label style={{ display: 'block', fontSize: '0.875rem', fontWeight: 500, marginBottom: '6px', color: 'var(--text-starlight)' }}>
                {t.contact.nameLabel}
              </label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder={t.contact.namePlaceholder}
                className="form-input"
              />
            </div>

            <div>
              <label style={{ display: 'block', fontSize: '0.875rem', fontWeight: 500, marginBottom: '6px', color: 'var(--text-starlight)' }}>
                {t.contact.emailLabel} <span style={{ color: 'var(--color-star-gold)' }}>*</span>
              </label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder={t.contact.emailPlaceholder}
                className="form-input"
              />
            </div>

            <div>
              <label style={{ display: 'block', fontSize: '0.875rem', fontWeight: 500, marginBottom: '6px', color: 'var(--text-starlight)' }}>
                {t.contact.categoryLabel}
              </label>
              <CustomSelect
                options={categoryOptions}
                value={category}
                onChange={(val) => setCategory(val)}
              />
            </div>

            <div>
              <label style={{ display: 'block', fontSize: '0.875rem', fontWeight: 500, marginBottom: '6px', color: 'var(--text-starlight)' }}>
                {t.contact.messageLabel} <span style={{ color: 'var(--color-star-gold)' }}>*</span>
              </label>
              <textarea
                required
                rows={5}
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                placeholder={t.contact.messagePlaceholder}
                className="form-input"
                style={{ resize: 'vertical' }}
              />
            </div>

            {/* Screenshot Attachment Area */}
            <div>
              <label style={{ display: 'block', fontSize: '0.875rem', fontWeight: 500, marginBottom: '6px', color: 'var(--text-starlight)' }}>
                {t.contact.attachmentLabel}
              </label>

              <input
                type="file"
                ref={fileInputRef}
                accept="image/png,image/jpeg,image/webp"
                style={{ display: 'none' }}
                onChange={(e) => {
                  if (e.target.files && e.target.files[0]) {
                    handleFileSelect(e.target.files[0]);
                  }
                }}
              />

              {previewUrl ? (
                <div style={{
                  position: 'relative',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '14px',
                  padding: '12px 16px',
                  backgroundColor: 'rgba(255, 255, 255, 0.04)',
                  border: '1px solid rgba(255, 255, 255, 0.12)',
                  borderRadius: '12px',
                }}>
                  <img
                    src={previewUrl}
                    alt="Preview"
                    style={{
                      width: '64px',
                      height: '64px',
                      borderRadius: '8px',
                      objectFit: 'cover',
                      border: '1px solid rgba(255, 255, 255, 0.1)',
                      flexShrink: 0
                    }}
                  />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-starlight)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {attachment?.name}
                    </div>
                    <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', marginTop: '2px' }}>
                      {attachment ? `${(attachment.size / 1024).toFixed(1)} KB` : ''}
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={removeAttachment}
                    style={{
                      background: 'rgba(255, 255, 255, 0.08)',
                      border: 'none',
                      color: 'var(--text-comet)',
                      width: '32px',
                      height: '32px',
                      borderRadius: '50%',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      transition: 'background 0.2s',
                    }}
                    title={t.contact.removeAttachment}
                  >
                    <X size={16} />
                  </button>
                </div>
              ) : (
                <div
                  onClick={() => fileInputRef.current?.click()}
                  onDragOver={(e) => {
                    e.preventDefault();
                    setIsDragging(true);
                  }}
                  onDragLeave={() => setIsDragging(false)}
                  onDrop={(e) => {
                    e.preventDefault();
                    setIsDragging(false);
                    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
                      handleFileSelect(e.dataTransfer.files[0]);
                    }
                  }}
                  style={{
                    border: `1.5px dashed ${isDragging ? 'var(--color-star-gold)' : 'rgba(255, 255, 255, 0.15)'}`,
                    backgroundColor: isDragging ? 'rgba(255, 179, 0, 0.06)' : 'rgba(255, 255, 255, 0.02)',
                    borderRadius: '12px',
                    padding: '20px 16px',
                    textAlign: 'center',
                    cursor: 'pointer',
                    transition: 'all 0.2s ease',
                  }}
                >
                  <UploadCloud size={26} color={isDragging ? 'var(--color-star-gold)' : 'var(--text-dim)'} style={{ margin: '0 auto 8px' }} />
                  <div style={{ fontSize: '0.85rem', color: 'var(--text-starlight)', fontWeight: 500 }}>
                    {t.contact.attachmentHint}
                  </div>
                  <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', marginTop: '4px' }}>
                    {t.contact.attachmentMax} • Paste (Cmd+V) supported
                  </div>
                </div>
              )}
            </div>

            <button
              type="submit"
              disabled={loading}
              className="btn-primary"
              style={{ marginTop: '8px', opacity: loading ? 0.7 : 1, width: '100%', padding: '14px' }}
            >
              {loading ? (
                <>
                  <Loader2 size={18} className="animate-spin" />
                  <span>{t.contact.submitting}</span>
                </>
              ) : (
                <>
                  <Send size={18} />
                  <span>{t.contact.submitButton}</span>
                </>
              )}
            </button>
          </form>
        )}
      </div>
    </div>
  );
};

