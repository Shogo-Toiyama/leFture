import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { useCreditSummary } from '../../hooks/useCreditSummary';
import { useCreditHistory } from '../../hooks/useCreditHistory';
import { usePlans } from '../../hooks/usePlans';
import { claimPlan } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { ApiError } from '../../lib/api';

export const CreditsPage: React.FC = () => {
  const { summary, loading, error, refetch } = useCreditSummary(true);
  const { history, loading: historyLoading } = useCreditHistory();
  const { plans, loading: plansLoading } = usePlans();
  const [claimingId, setClaimingId] = useState<string | null>(null);
  const [claimError, setClaimError] = useState<string | null>(null);

  const handleClaim = async (planId: string) => {
    setClaimingId(planId);
    setClaimError(null);
    try {
      await claimPlan(planId);
      await refetch();
    } catch (err) {
      setClaimError(err instanceof ApiError ? err.message : 'Failed to claim plan');
    } finally {
      setClaimingId(null);
    }
  };

  if (loading) return <p>Loading…</p>;
  if (error) return <p className="auth-error">{error}</p>;
  if (!summary) return null;

  const balance = toDisplayCredits(summary.credit_balance);
  const allocation = toDisplayCredits(summary.monthly_allocation);
  const extra = toDisplayCredits(summary.extra_credit_balance);
  const progress = allocation > 0 ? Math.min(100, Math.round((balance / allocation) * 100)) : 0;

  return (
    <div>
      <Link to="/account">← Account</Link>
      <h1>Credits</h1>

      {summary.has_active_plan ? (
        <div className="status-banner">
          <strong>
            {balance} / {allocation} credits
          </strong>
          <div className="credit-progress-track">
            <div className="credit-progress-fill" style={{ width: `${progress}%` }} />
          </div>
          {extra > 0 && <p>+{extra} bonus credits</p>}
          {summary.current_period_end && (
            <p>Resets on {new Date(summary.current_period_end).toLocaleDateString()}</p>
          )}
        </div>
      ) : (
        <div>
          <p>You don't have an active plan yet. Claim one below to start analyzing lectures.</p>
          {claimError && <p className="auth-error">{claimError}</p>}
          {plansLoading && <p>Loading plans…</p>}
          <ul className="course-list">
            {plans.map((plan) => (
              <li key={plan.id} className="course-list-item">
                <span>
                  {plan.name} — {toDisplayCredits(plan.monthly_credit_amount)} credits/mo
                  {plan.price_usd != null && ` ($${plan.price_usd})`}
                </span>
                <button type="button" onClick={() => handleClaim(plan.id)} disabled={claimingId === plan.id}>
                  {claimingId === plan.id ? 'Claiming…' : 'Claim'}
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}

      <h2>History</h2>
      {historyLoading && <p>Loading…</p>}
      <ul className="credit-history-list">
        {history
          .slice()
          .reverse()
          .map((item) => (
            <li key={item.id} className={item.is_positive ? 'credit-history-positive' : ''}>
              <span>{new Date(item.timestamp).toLocaleString()}</span>
              <span>{item.reason_summary}</span>
              <span>{item.formatted_delta}</span>
            </li>
          ))}
      </ul>
      {!historyLoading && history.length === 0 && <p>No credit activity yet.</p>}
    </div>
  );
};
