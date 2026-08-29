import { useEffect, useState } from 'react';
import { listPlans } from '../lib/billing';
import type { PlanOption } from '../types/billing';

export function usePlans() {
  const [plans, setPlans] = useState<PlanOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listPlans()
      .then(setPlans)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load plans'))
      .finally(() => setLoading(false));
  }, []);

  return { plans, loading, error };
}
