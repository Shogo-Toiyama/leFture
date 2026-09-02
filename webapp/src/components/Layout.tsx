import React, { useEffect, useState } from 'react';
import { Link, Outlet } from 'react-router-dom';
import { useProfile } from '../hooks/useProfile';
import { getCreditSummary } from '../lib/billing';
import { toDisplayCredits } from '../types/billing';
import { AvatarImage } from './AvatarImage';
import { LanguageHeaderButton } from './auth/LanguageHeaderButton';
import { supabase } from '../lib/supabase';

const RING_RADIUS = 15;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;

export const Layout: React.FC = () => {
  const { profile } = useProfile();
  const [ratio, setRatio] = useState<number | null>(null);

  useEffect(() => {
    getCreditSummary()
      .then((summary) => {
        const balance = toDisplayCredits(summary.credit_balance);
        const allocation = toDisplayCredits(summary.monthly_allocation);
        setRatio(allocation > 0 ? Math.min(1, balance / allocation) : 0);
      })
      .catch(() => setRatio(null));
  }, []);

  return (
    <div className="app-shell">
      <header className="app-topbar">
        <Link to="/" className="app-topbar-home">
          <span className="app-topbar-mark">le</span>
        </Link>

        <div className="app-topbar-account">
          <LanguageHeaderButton />
          <button type="button" className="app-topbar-signout" onClick={() => supabase.auth.signOut()}>
            Sign out
          </button>
          <Link to="/account" className="credit-gauge" aria-label="Account">
            {ratio !== null && (
              <svg width="34" height="34" viewBox="0 0 34 34">
                <circle className="credit-gauge-track" cx="17" cy="17" r={RING_RADIUS} strokeWidth="2.5" />
                <circle
                  className="credit-gauge-fill"
                  cx="17"
                  cy="17"
                  r={RING_RADIUS}
                  strokeWidth="2.5"
                  strokeDasharray={RING_CIRCUMFERENCE}
                  strokeDashoffset={RING_CIRCUMFERENCE * (1 - ratio)}
                />
              </svg>
            )}
            <AvatarImage avatarUrl={profile?.avatar_url ?? null} size={25} />
          </Link>
        </div>
      </header>

      <main className="app-main">
        <Outlet />
      </main>
    </div>
  );
};
