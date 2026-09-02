import React from 'react';
import { Link } from 'react-router-dom';
import { usePlans } from '../../hooks/usePlans';
import { toDisplayCredits } from '../../types/billing';
import { PageState } from '../../components/PageState';

/**
 * mobile版のplans_page.dartは実データではなく固定文言のマーケティング表示だが
 * (research: 価格は全てハードコード、claim-planは呼ばれない)、Webでは古い固定値を
 * 見せるより実際のGET /billing/plansをそのまま閲覧専用で見せる方が誠実。
 * 実際にクレジットを得るclaim操作は/account/creditsで行う。
 */
export const PlansPage: React.FC = () => {
  const { plans, loading, error } = usePlans();

  return (
    <div>
      <Link to="/account" className="back-link">
        ← Account
      </Link>
      <h1>Plans</h1>

      {loading && <PageState kind="loading" />}
      {error && <PageState kind="error" message={error} />}

      <ul className="plan-list">
        {plans.map((plan) => (
          <li key={plan.id} className="plan-row">
            <span className="plan-row-name">{plan.name}</span>
            <span className="muted">
              {toDisplayCredits(plan.monthly_credit_amount)} credits / {plan.billing_interval_months}mo
              {plan.price_usd != null && ` · $${plan.price_usd}`}
            </span>
          </li>
        ))}
      </ul>

      <p style={{ marginTop: '1.25rem' }}>
        <Link to="/account/credits">Go claim a plan →</Link>
      </p>
    </div>
  );
};
