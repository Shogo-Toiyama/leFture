import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { User, Sparkles, Flag, Languages, CreditCard, Mail, ShieldCheck, Gavel, UserX, ChevronRight } from 'lucide-react';
import { useProfile } from '../../hooks/useProfile';
import { getCreditSummary } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { AvatarImage } from '../../components/AvatarImage';
import { PageState } from '../../components/PageState';
import type { CreditSummary } from '../../types/billing';

/** my_account_page.dart 準拠: 単一列の積み重ねガラスカード。 */
export const AccountPage: React.FC = () => {
  const { profile, loading } = useProfile();
  const [summary, setSummary] = useState<CreditSummary | null>(null);

  useEffect(() => {
    getCreditSummary()
      .then(setSummary)
      .catch(() => setSummary(null));
  }, []);

  if (loading) return <PageState kind="loading" />;

  return (
    <div>
      <div className="account-header">
        <AvatarImage avatarUrl={profile?.avatar_url ?? null} size={72} />
        <div>
          <h1 style={{ margin: 0 }}>{profile?.username || 'Unnamed'}</h1>
        </div>
      </div>

      <Link to="/account/credits" className="glass-card" style={{ display: 'block', textDecoration: 'none' }}>
        <div className="credit-hero">
          <span className="credit-hero-value">{summary ? toDisplayCredits(summary.credit_balance) : '—'}</span>
          <div>
            <p className="muted" style={{ margin: 0 }}>
              of {summary ? toDisplayCredits(summary.monthly_allocation) : '—'} monthly credits
            </p>
          </div>
        </div>
      </Link>

      <p className="glass-section-label">Profile</p>
      <div className="glass-card">
        <Link to="/account/profile" className="glass-row">
          <span className="glass-row-icon"><User size={18} /></span>
          <span className="glass-row-text">
            <span className="glass-row-title">About you</span>
            <span className="glass-row-sub">{profile?.bio || 'Not set'}</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
        <Link to="/account/profile" className="glass-row">
          <span className="glass-row-icon"><Sparkles size={18} /></span>
          <span className="glass-row-text">
            <span className="glass-row-title">Interests</span>
            <span className="glass-row-sub">{profile?.interests || 'Not set'}</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
        <Link to="/account/profile" className="glass-row">
          <span className="glass-row-icon"><Flag size={18} /></span>
          <span className="glass-row-text">
            <span className="glass-row-title">Future goals</span>
            <span className="glass-row-sub">{profile?.future_goals || 'Not set'}</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
      </div>

      <p className="glass-section-label">Settings</p>
      <div className="glass-card">
        <Link to="/account/profile" className="glass-row">
          <span className="glass-row-icon"><Languages size={18} /></span>
          <span className="glass-row-text">
            <span className="glass-row-title">Language &amp; password</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
        <Link to="/account/plans" className="glass-row">
          <span className="glass-row-icon"><CreditCard size={18} /></span>
          <span className="glass-row-text">
            <span className="glass-row-title">Plans</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
      </div>

      <p className="glass-section-label">Legal &amp; support</p>
      <div className="glass-card">
        <Link to="/account/contact" className="glass-row">
          <span className="glass-row-icon"><Mail size={18} /></span>
          <span className="glass-row-text">
            <span className="glass-row-title">Contact us</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
        <Link to="/legal/privacy_policy" className="glass-row">
          <span className="glass-row-icon"><ShieldCheck size={18} /></span>
          <span className="glass-row-text">
            <span className="glass-row-title">Privacy policy</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
        <Link to="/legal/terms_of_service" className="glass-row">
          <span className="glass-row-icon"><Gavel size={18} /></span>
          <span className="glass-row-text">
            <span className="glass-row-title">Terms of service</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
      </div>

      <p className="glass-section-label">Danger zone</p>
      <div className="glass-card">
        <Link to="/account/profile" className="glass-row">
          <span className="glass-row-icon" style={{ background: 'rgba(229,57,53,0.16)', color: '#ff8b85' }}>
            <UserX size={18} />
          </span>
          <span className="glass-row-text">
            <span className="glass-row-title">Delete account</span>
          </span>
          <ChevronRight size={16} className="glass-row-chevron" />
        </Link>
      </div>
    </div>
  );
};
