import { useEffect, useState } from 'react';
import { listCreditPacks } from '../lib/billing';
import type { CreditPackOption } from '../types/billing';

export function useCreditPacks() {
  const [packs, setPacks] = useState<CreditPackOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listCreditPacks()
      .then(setPacks)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load credit packs'))
      .finally(() => setLoading(false));
  }, []);

  return { packs, loading, error };
}
