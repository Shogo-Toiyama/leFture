import { useCallback, useEffect, useState } from 'react';
import { getCreditSummary } from '../lib/billing';
import type { CreditSummary } from '../types/billing';

const POLL_INTERVAL_MS = 5000;

/** credit_detail_page.dart同様、ジョブ処理中はクレジット残高が動くのでポーリングする。 */
export function useCreditSummary(pollWhileActive: boolean) {
  const [summary, setSummary] = useState<CreditSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    try {
      setSummary(await getCreditSummary());
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load credit summary');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refetch();
  }, [refetch]);

  useEffect(() => {
    if (!pollWhileActive) return;
    const interval = setInterval(refetch, POLL_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [pollWhileActive, refetch]);

  return { summary, loading, error, refetch };
}
