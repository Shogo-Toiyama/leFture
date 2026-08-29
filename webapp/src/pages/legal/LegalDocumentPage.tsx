import React, { useEffect, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { Link, useParams } from 'react-router-dom';
import { getLegalDocument, type LegalDocument } from '../../lib/legal';

export const LegalDocumentPage: React.FC = () => {
  const { slug } = useParams<{ slug: string }>();
  const [doc, setDoc] = useState<LegalDocument | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!slug) return;
    setLoading(true);
    const locale = (navigator.language || 'en').split('-')[0];
    getLegalDocument(slug, locale)
      .then(setDoc)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load document'))
      .finally(() => setLoading(false));
  }, [slug]);

  return (
    <div>
      <Link to="/account">← Account</Link>
      {loading && <p>Loading…</p>}
      {error && <p className="auth-error">{error}</p>}
      {doc && (
        <div className="deep-note-body">
          <h1>{doc.title}</h1>
          <p>Effective {new Date(doc.effectiveDate).toLocaleDateString()}</p>
          <ReactMarkdown>{doc.contentMarkdown}</ReactMarkdown>
        </div>
      )}
    </div>
  );
};
