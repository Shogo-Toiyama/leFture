import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

/** コース一覧カードに出す講義数。1クエリ取得してクライアント側で集計する。 */
export function useLectureCounts(): Map<string, number> {
  const [counts, setCounts] = useState<Map<string, number>>(new Map());

  useEffect(() => {
    let cancelled = false;
    supabase
      .from('lectures')
      .select('course_id')
      .is('deleted_at', null)
      .then(({ data }) => {
        if (cancelled || !data) return;
        const next = new Map<string, number>();
        for (const row of data as { course_id: string | null }[]) {
          if (!row.course_id) continue;
          next.set(row.course_id, (next.get(row.course_id) ?? 0) + 1);
        }
        setCounts(next);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return counts;
}
