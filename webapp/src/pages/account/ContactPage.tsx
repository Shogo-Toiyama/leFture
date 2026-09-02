import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { submitSupportTicket, type SupportCategory } from '../../lib/support';

const CATEGORIES: { value: SupportCategory; label: string }[] = [
  { value: 'bug', label: 'Bug report' },
  { value: 'feature_request', label: 'Feature request' },
  { value: 'account', label: 'Account issue' },
  { value: 'other', label: 'Other' },
];

export const ContactPage: React.FC = () => {
  const [category, setCategory] = useState<SupportCategory>('bug');
  const [message, setMessage] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ticketCode, setTicketCode] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      setTicketCode(await submitSupportTicket(category, message));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to submit');
    } finally {
      setSubmitting(false);
    }
  };

  if (ticketCode) {
    return (
      <div>
        <h1>Thanks!</h1>
        <p>Your ticket has been submitted. Reference code: {ticketCode}</p>
        <Link to="/account" className="back-link">
          ← Account
        </Link>
      </div>
    );
  }

  return (
    <div>
      <Link to="/account">← Account</Link>
      <h1>Contact us</h1>

      <form className="course-form" onSubmit={handleSubmit}>
        <label>
          Category
          <select value={category} onChange={(e) => setCategory(e.target.value as SupportCategory)}>
            {CATEGORIES.map((c) => (
              <option key={c.value} value={c.value}>
                {c.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          Message
          <textarea required rows={6} value={message} onChange={(e) => setMessage(e.target.value)} />
        </label>
        {error && <p className="auth-error">{error}</p>}
        <button type="submit" disabled={submitting || !message.trim()}>
          {submitting ? 'Sending…' : 'Send'}
        </button>
      </form>
    </div>
  );
};
