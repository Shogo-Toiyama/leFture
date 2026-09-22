import { apiFetch } from './api';
import { listCourses, createCourse } from './courses';
import type { Language } from '../i18n/translations';

/**
 * default_course_service.dart同等。全ユーザーが持つ「既定コース」
 * (チュートリアル講義の置き場所、および一発ものの録音の受け皿)を確保する。
 */
const DEFAULT_COURSE_TEXT: Record<Language, { title: string; summary: string }> = {
  ja: {
    title: '使い方・メモ',
    summary: 'leFtureの使い方や、コースを作るまでもない一発ものの録音をまとめておく場所です。',
  },
  en: {
    title: 'Guide & Notes',
    summary: "Where the app tour lives, plus a home for one-off recordings that don't need their own course.",
  },
};

async function ensureDefaultCourse(displayLanguage: Language): Promise<string> {
  const courses = await listCourses();
  const existing = courses.find((c) => c.metadata?.is_default === true);
  if (existing) return existing.id;

  const text = DEFAULT_COURSE_TEXT[displayLanguage] ?? DEFAULT_COURSE_TEXT.en;
  const created = await createCourse({
    courseTitle: text.title,
    courseCode: '',
    summary: text.summary,
    year: '',
    term: '',
    professor: '',
    school: '',
    subject: '',
    metadata: { is_default: true },
  });
  return created.id;
}

interface SeedTutorialResponse {
  lecture_id: string;
  created: boolean;
}

/**
 * onboarding_page.dart / tutorial_lecture_seed_provider.dart相当。既定コースを
 * 確保したうえで`/seed-tutorial`を叩き、新規ユーザーにチュートリアル講義一式
 * (固定文言、LLM/クレジット不使用)を投入する。バックエンド側で
 * user_idごとに冪等(既にあれば何もせず既存IDを返す)なので、重複呼び出しは安全。
 */
export async function seedTutorial(displayLanguage: Language): Promise<string> {
  const courseId = await ensureDefaultCourse(displayLanguage);
  const { lecture_id } = await apiFetch<SeedTutorialResponse>('/seed-tutorial', {
    method: 'POST',
    body: JSON.stringify({
      course_id: courseId,
      display_language: displayLanguage,
      lecture_datetime: new Date().toISOString(),
    }),
  });
  return lecture_id;
}
