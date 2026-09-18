import { useCallback, useEffect, useState } from 'react';
import { listCreditHistory } from '../lib/billing';
import type { CreditHistoryItem } from '../types/billing';

export function useCreditHistory() {
  const [history, setHistory] = useState<CreditHistoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    try {
      const data = await listCreditHistory();
      setHistory(data);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load credit history');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { history, loading, error, refetch };
}
