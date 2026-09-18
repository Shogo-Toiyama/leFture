/** すべてマイクロクレジット単位 (表示時は1,000,000で割る)。credit_summary.dart / plan_option.dart 準拠。 */
export interface CreditSummary {
  credit_balance: number;
  monthly_allocation: number | null;
  extra_credit_balance: number;
  has_active_plan: boolean;
  current_period_end: string | null;
  /** 次回更新日に切り替わる予定の別プランのid(Apple同一サブスクグループの予約)。予約が無ければnull。 */
  pending_plan_id: string | null;
  credits_per_usd: number;
  /** 0=Free, 1=Lite, 2=Core, 3=Max。 */
  tier_level: number;
  /** kill-switch(実機テスト用許可リスト含む)。trueならhasFeature()は常にtrueを返す。 */
  gating_disabled: boolean;
}

export interface PlanOption {
  id: string;
  name: string;
  monthly_credit_amount: number;
  price_usd: number | null;
  billing_interval_months: number;
  claim_mode: 'self_serve' | 'store_purchase';
  store_product_id: string | null;
  stripe_price_id: string | null;
  tier_level: number;
}

export interface CreditPackOption {
  id: string;
  name: string;
  credit_amount: number;
  price_usd: number | null;
  store_product_id: string | null;
  stripe_price_id: string | null;
}

/**
 * GET /billing/history の1件。kind: 'transaction'は付与/消費(消費は1時間単位の
 * バケツにまとめ済み)、'reset'はプラン更新/切り替えで残高がリセットされた区切り
 * (数字を見せると誤解を招くため、reset_reasonだけを持つ)。credit_usage_item.dart 準拠。
 */
export interface CreditHistoryItem {
  id: string;
  kind: 'transaction' | 'reset';
  timestamp: string;
  /** サーバーがユーザーのローカル日時から作った表示用ラベル ("Today" / "Yesterday" / "Jul 23")。 */
  date_label: string;
  /** サーバーがユーザーのローカル日時から作った表示用ラベル ("1 PM" 等)。 */
  time_label: string;
  /** kind === 'transaction' のときだけ意味を持つ。 */
  delta_credits?: number;
  formatted_delta?: string;
  is_positive?: boolean;
  /** kind === 'reset' のときだけ意味を持つ: "renewed" | "plan_changed" | "expired"。 */
  reset_reason?: string;
}

const MICRO_CREDITS_PER_CREDIT = 1_000_000;

export function toDisplayCredits(micro: number | null | undefined): number {
  if (micro == null) return 0;
  return Math.trunc(micro / MICRO_CREDITS_PER_CREDIT);
}
