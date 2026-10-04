import { useCallback, useEffect, useState } from 'react';
import { selfPortraitApi, type SelfPortrait } from '../lib/selfPortrait';

/** 自分像ページのデータ。操作のたびに丸ごと取り直す(件数が小さいので部分更新はしない)。 */
export function useSelfPortrait() {
  const [data, setData] = useState<SelfPortrait | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    try {
      const fresh = await selfPortraitApi.get();
      setData(fresh);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { data, loading, error, refetch };
}
