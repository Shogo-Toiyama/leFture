import React from 'react';
import { Link } from 'react-router-dom';
import { usePlans } from '../../hooks/usePlans';
import { toDisplayCredits } from '../../types/billing';

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
      <Link to="/account">← Account</Link>
      <h1>Plans</h1>

      {loading && <p>Loading…</p>}
      {error && <p className="auth-error">{error}</p>}

      <ul className="course-list">
        {plans.map((plan) => (
          <li key={plan.id} className="course-list-item">
            <span>
              {plan.name} — {toDisplayCredits(plan.monthly_credit_amount)} credits / {plan.billing_interval_months}
              mo
              {plan.price_usd != null && ` · $${plan.price_usd}`}
            </span>
          </li>
        ))}
      </ul>

      <p>
        <Link to="/account/credits">Go claim a plan →</Link>
      </p>
    </div>
  );
};
