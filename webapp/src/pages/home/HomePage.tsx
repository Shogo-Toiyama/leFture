import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { apiFetch, ApiError } from '../../lib/api';

interface BillingSummary {
  credit_balance: number;
  monthly_allocation: number;
  extra_credit_balance: number;
  has_active_plan: boolean;
  current_period_end: string | null;
  credits_per_usd: number;
}

export const HomePage: React.FC = () => {
  const [summary, setSummary] = useState<BillingSummary | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiFetch<BillingSummary>('/billing/summary')
      .then(setSummary)
      .catch((err: unknown) => {
        setError(err instanceof ApiError ? err.message : 'Failed to reach backend');
      });
  }, []);

  return (
    <div>
      <h1>Home</h1>
      <p>
        <Link to="/courses">Go to your courses →</Link>
      </p>
      {error && <p className="auth-error">Backend check failed: {error}</p>}
      {summary && <p>Credit balance: {summary.credit_balance}</p>}
    </div>
  );
};
