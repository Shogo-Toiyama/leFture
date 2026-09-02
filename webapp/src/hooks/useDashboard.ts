import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import type { Lecture } from '../types/lecture';
import type { FunFact } from '../types/content';

export interface DashboardData {
  recentLectures: Lecture[];
  funFacts: FunFact[];
  loading: boolean;
}

/** ホーム画面用のまとめ取得(最近の講義 + 最新のfun facts)。 */
export function useDashboard(): DashboardData {
  const [recentLectures, setRecentLectures] = useState<Lecture[]>([]);
  const [funFacts, setFunFacts] = useState<FunFact[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    Promise.all([
      supabase
        .from('lectures')
        .select('*')
        .is('deleted_at', null)
        .order('lecture_datetime', { ascending: false })
        .limit(6),
      supabase
        .from('fun_facts')
        .select('*')
        .is('deleted_at', null)
        .order('created_at', { ascending: false })
        .limit(6),
    ]).then(([lectureRes, factRes]) => {
      if (cancelled) return;
      setRecentLectures((lectureRes.data as Lecture[]) ?? []);
      setFunFacts((factRes.data as FunFact[]) ?? []);
      setLoading(false);
    });

    return () => {
      cancelled = true;
    };
  }, []);

  return { recentLectures, funFacts, loading };
}
