import { useEffect, useState } from 'react';
import { listCreditHistory } from '../lib/billing';
import type { CreditHistoryItem } from '../types/billing';

export function useCreditHistory() {
  const [history, setHistory] = useState<CreditHistoryItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    listCreditHistory()
      .then(setHistory)
      .finally(() => setLoading(false));
  }, []);

  return { history, loading };
}
