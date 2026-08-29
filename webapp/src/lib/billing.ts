import { apiFetch } from './api';
import type { CreditSummary, PlanOption, CreditHistoryItem } from '../types/billing';

export const getCreditSummary = () => apiFetch<CreditSummary>('/billing/summary');

export const listPlans = () => apiFetch<{ plans: PlanOption[] }>('/billing/plans').then((r) => r.plans);

export const claimPlan = (planId: string) =>
  apiFetch('/billing/claim-plan', { method: 'POST', body: JSON.stringify({ plan_id: planId }) });

export const listCreditHistory = () =>
  apiFetch<{ history: CreditHistoryItem[] }>('/billing/history').then((r) => r.history);
