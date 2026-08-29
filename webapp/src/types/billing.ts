/** すべてマイクロクレジット単位 (表示時は1,000,000で割る)。credit_summary.dart / plan_option.dart 準拠。 */
export interface CreditSummary {
  credit_balance: number;
  monthly_allocation: number | null;
  extra_credit_balance: number;
  has_active_plan: boolean;
  current_period_end: string | null;
  credits_per_usd: number;
}

export interface PlanOption {
  id: string;
  name: string;
  monthly_credit_amount: number;
  price_usd: number | null;
  billing_interval_months: number;
}

export interface CreditHistoryItem {
  id: string;
  timestamp: string;
  delta_credits: number;
  formatted_delta: string;
  is_positive: boolean;
  reason_summary: string;
}

const MICRO_CREDITS_PER_CREDIT = 1_000_000;

export function toDisplayCredits(micro: number | null | undefined): number {
  if (micro == null) return 0;
  return Math.trunc(micro / MICRO_CREDITS_PER_CREDIT);
}
