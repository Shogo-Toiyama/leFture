import { apiFetch } from './api';
import type { CreditSummary, PlanOption, CreditPackOption, CreditHistoryItem } from '../types/billing';

export const getCreditSummary = () => apiFetch<CreditSummary>('/billing/summary');

export const listPlans = () => apiFetch<{ plans: PlanOption[] }>('/billing/plans').then((r) => r.plans);

export const claimPlan = (planId: string) =>
  apiFetch('/billing/claim-plan', { method: 'POST', body: JSON.stringify({ plan_id: planId }) });

export const listCreditHistory = () =>
  apiFetch<{ history: CreditHistoryItem[] }>('/billing/history').then((r) => r.history);

export const listCreditPacks = () =>
  apiFetch<{ packs: CreditPackOption[] }>('/billing/credit-packs').then((r) => r.packs);

export const createCreditPackPayment = (creditPackId: string) =>
  apiFetch<{ client_secret: string }>('/billing/stripe/create-credit-pack-payment', {
    method: 'POST',
    body: JSON.stringify({ credit_pack_id: creditPackId }),
  });

/**
 * 既に何らかのプラン(Free/Apple/Stripe)を持つユーザーが別プランに切り替える時の
 * 統一エンドポイント。client_secretが返ってくれば決済フォームで確定させる必要が
 * あり(新規Stripeサブスク作成)、statusだけ返ってくればサーバー側で完結している
 * (claim/即時アップグレード/次回更新時の予約のいずれか)。
 */
export type SwitchPlanResult =
  | { client_secret: string; subscription_id: string }
  | { status: 'claimed' | 'switched' | 'scheduled_downgrade' | 'scheduled_cancel' | 'already_current' };

export const switchPlan = (planId: string) =>
  apiFetch<SwitchPlanResult>('/billing/stripe/switch-plan', {
    method: 'POST',
    body: JSON.stringify({ plan_id: planId }),
  });
