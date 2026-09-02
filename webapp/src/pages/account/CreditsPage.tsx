import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { useCreditSummary } from '../../hooks/useCreditSummary';
import { useCreditHistory } from '../../hooks/useCreditHistory';
import { usePlans } from '../../hooks/usePlans';
import { claimPlan } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { ApiError } from '../../lib/api';
import { PageState } from '../../components/PageState';

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

  if (loading) return <PageState kind="loading" />;
  if (error) return <PageState kind="error" message={error} />;
  if (!summary) return null;

  const balance = toDisplayCredits(summary.credit_balance);
  const allocation = toDisplayCredits(summary.monthly_allocation);
  const extra = toDisplayCredits(summary.extra_credit_balance);
  const progress = allocation > 0 ? Math.min(100, Math.round((balance / allocation) * 100)) : 0;

  return (
    <div>
      <Link to="/account" className="back-link">
        ← Account
      </Link>
      <h1>Credits</h1>

      {summary.has_active_plan ? (
        <section className="glass-card" style={{ padding: '1rem 1.1rem' }}>
          <div className="credit-hero">
            <span className="credit-hero-value">{balance}</span>
            <div>
              <p className="muted" style={{ margin: 0 }}>
                of {allocation} monthly credits
              </p>
              {extra > 0 && <p className="muted" style={{ margin: 0 }}>+{extra} bonus credits</p>}
            </div>
          </div>
          <div className="credit-progress-track">
            <div className="credit-progress-fill" style={{ width: `${progress}%` }} />
          </div>
          {summary.current_period_end && (
            <p className="muted" style={{ margin: 0 }}>
              Resets on {new Date(summary.current_period_end).toLocaleDateString()}
            </p>
          )}
        </section>
      ) : (
        <section className="glass-card" style={{ padding: '1rem 1.1rem' }}>
          <h2>Choose a plan</h2>
          <p className="muted">You don't have an active plan yet. Claim one below to start analysing lectures.</p>
          {claimError && <p className="notice notice-error">{claimError}</p>}
          {plansLoading && <PageState kind="loading" />}
          <ul className="plan-list">
            {plans.map((plan) => (
              <li key={plan.id} className="plan-row">
                <span className="plan-row-name">{plan.name}</span>
                <span className="muted">
                  {toDisplayCredits(plan.monthly_credit_amount)} credits/mo
                  {plan.price_usd != null && ` · $${plan.price_usd}`}
                </span>
                <button type="button" onClick={() => handleClaim(plan.id)} disabled={claimingId === plan.id}>
                  {claimingId === plan.id ? 'Claiming…' : 'Claim'}
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section>
        <h2>History</h2>
        {historyLoading && <PageState kind="loading" />}
        {!historyLoading && history.length === 0 && <p className="muted">No credit activity yet.</p>}
        <ul className="credit-history-list">
          {history
            .slice()
            .reverse()
            .map((item) => (
              <li key={item.id} className={item.is_positive ? 'credit-history-positive' : ''}>
                <span className="credit-history-time">{new Date(item.timestamp).toLocaleString()}</span>
                <span>{item.reason_summary}</span>
                <span className="credit-history-delta">{item.formatted_delta}</span>
              </li>
            ))}
        </ul>
      </section>
    </div>
  );
};
