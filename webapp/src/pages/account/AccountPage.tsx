import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useProfile } from '../../hooks/useProfile';
import { getCreditSummary } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { AvatarImage } from '../../components/AvatarImage';
import type { CreditSummary } from '../../types/billing';

export const AccountPage: React.FC = () => {
  const { profile, loading } = useProfile();
  const [summary, setSummary] = useState<CreditSummary | null>(null);

  useEffect(() => {
    getCreditSummary()
      .then(setSummary)
      .catch(() => setSummary(null));
  }, []);

  if (loading) return <p>Loading…</p>;

  return (
    <div>
      <h1>Account</h1>

      <div className="account-header">
        <AvatarImage avatarUrl={profile?.avatar_url ?? null} size={64} />
        <div>
          <strong>{profile?.username || 'Unnamed'}</strong>
        </div>
      </div>

      <Link to="/account/credits" className="course-list-item account-credit-tile">
        <span>Credits</span>
        <span>
          {summary ? `${toDisplayCredits(summary.credit_balance)} / ${toDisplayCredits(summary.monthly_allocation)}` : '—'}
        </span>
      </Link>

      <ul className="course-list">
        <li>
          <Link to="/account/profile" className="course-list-item">
            Profile & preferences
          </Link>
        </li>
        <li>
          <Link to="/account/plans" className="course-list-item">
            Plans
          </Link>
        </li>
        <li>
          <Link to="/account/contact" className="course-list-item">
            Contact us
          </Link>
        </li>
        <li>
          <Link to="/legal/privacy_policy" className="course-list-item">
            Privacy policy
          </Link>
        </li>
        <li>
          <Link to="/legal/terms_of_service" className="course-list-item">
            Terms of service
          </Link>
        </li>
      </ul>
    </div>
  );
};
