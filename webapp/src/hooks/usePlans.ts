import { useEffect, useState } from 'react';
import { listPlans } from '../lib/billing';
import type { PlanOption } from '../types/billing';
import { useLanguage } from '../i18n/LanguageContext';

export function usePlans() {
  const { t } = useLanguage();
  const [plans, setPlans] = useState<PlanOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listPlans()
      .then(setPlans)
      .catch((err) => setError(err instanceof Error ? err.message : t('failedToLoadPlans')))
      .finally(() => setLoading(false));
  }, [t]);

  return { plans, loading, error };
}
