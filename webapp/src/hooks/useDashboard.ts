import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { listRecentAnnouncements } from '../lib/content';
import type { Lecture } from '../types/lecture';
import type { Announcement, FunFact } from '../types/content';

export interface DashboardData {
  recentLectures: Lecture[];
  setRecentLectures: React.Dispatch<React.SetStateAction<Lecture[]>>;
  funFacts: FunFact[];
  announcements: Announcement[];
  setAnnouncements: React.Dispatch<React.SetStateAction<Announcement[]>>;
  /** 講義の総数(最近の講義6件とは別に、ヒーローの統計表示で使う)。 */
  lectureCount: number;
  loading: boolean;
}

/** ホーム画面用のまとめ取得(最近の講義 + 最新のfun facts + お知らせ)。 */
export function useDashboard(): DashboardData {
  const [recentLectures, setRecentLectures] = useState<Lecture[]>([]);
  const [funFacts, setFunFacts] = useState<FunFact[]>([]);
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [lectureCount, setLectureCount] = useState(0);
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
      // ここだけthrowしうるので、失敗してもダッシュボード全体がロード中で止まらないようにする
      listRecentAnnouncements(20).catch(() => [] as Announcement[]),
      supabase
        .from('lectures')
        .select('id', { count: 'exact', head: true })
        .is('deleted_at', null),
    ]).then(([lectureRes, factRes, announcementList, countRes]) => {
      if (cancelled) return;
      setRecentLectures((lectureRes.data as Lecture[]) ?? []);
      setFunFacts((factRes.data as FunFact[]) ?? []);
      setAnnouncements(announcementList);
      setLectureCount(countRes.count ?? 0);
      setLoading(false);
    });

    return () => {
      cancelled = true;
    };
  }, []);

  return {
    recentLectures,
    setRecentLectures,
    funFacts,
    announcements,
    setAnnouncements,
    lectureCount,
    loading,
  };
}
