import React, { useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ChevronRight, Sparkles } from 'lucide-react';
import { useDashboard } from '../../hooks/useDashboard';
import { useCourses } from '../../hooks/useCourses';
import { updateFunFactReaction, stripFunFactCitations } from '../../lib/content';
import { softDeleteLecture } from '../../lib/lectures';
import { GalaxyView } from '../../components/GalaxyView';
import { LectureTile } from '../../components/LectureTile';
import { LectureTileSkeleton } from '../../components/LectureTileSkeleton';
import { ReactionBar } from '../../components/ReactionBar';
import { PageState } from '../../components/PageState';
import {
  AnnouncementsModal,
  getAnnouncementTypeConfig,
} from '../../components/modals/AnnouncementsModal';
import { LectureEditModal } from '../../components/modals/LectureEditModal';
import { CourseIconGlyph, DEFAULT_COURSE_COLOR } from '../../lib/courseIcons';
import { useLanguage } from '../../i18n/LanguageContext';
import { useUploadModal } from '../../context/UploadModalContext';
import type { Announcement } from '../../types/content';
import type { Lecture } from '../../types/lecture';

/**
 * ワイド版ホーム("Command Center"): 銀河のワイドヒーロー + 3カラム
 * (お知らせ/コース | 最近の講義 | Fun Facts)。
 *
 * 1200px未満では中間幅の専用レイアウトは設けず、Flutter版 home_page.dart と
 * 同じ縦1カラムに畳む(お知らせバー → 銀河 → Fun Factsカルーセル → コース
 * 横並び → 講義リスト → 録音FAB)。パネルの配置はすべて grid-template-areas
 * 側で切り替えるので、DOMは共通のまま。
 */
export const HomePage: React.FC = () => {
  const { language } = useLanguage();
  const isJa = language === 'ja';
  const { openUploadModal } = useUploadModal();
  const navigate = useNavigate();
  const {
    recentLectures,
    setRecentLectures,
    funFacts,
    announcements,
    setAnnouncements,
    lectureCount,
    loading,
  } = useDashboard();
  const { courses } = useCourses();
  const [factIndex, setFactIndex] = useState(0);
  const [funFactsState, setFunFactsState] = useState(funFacts);
  const [announcementsOpen, setAnnouncementsOpen] = useState(false);
  const [editingLecture, setEditingLecture] = useState<Lecture | null>(null);
  const carouselRef = useRef<HTMLDivElement>(null);

  // useDashboardの結果が更新されたらローカルのreaction編集用stateも同期する
  useEffect(() => {
    setFunFactsState(funFacts);
  }, [funFacts]);

  const courseById = new Map(courses.map((course) => [course.id, course]));
  const activeAnnouncements = announcements.filter((a) => !a.completed_at);
  const latestAnnouncement = activeAnnouncements[0] ?? null;

  const handleReaction = async (factId: string, reaction: 'like' | 'dislike') => {
    const fact = funFactsState.find((f) => f.id === factId);
    if (!fact) return;
    const next = fact.metadata?.reaction === reaction ? null : reaction;
    setFunFactsState((prev) =>
      prev.map((f) => (f.id === factId ? { ...f, metadata: { ...f.metadata, reaction: next } } : f))
    );
    await updateFunFactReaction(factId, fact.metadata, reaction);
  };

  const handleAnnouncementToggled = (updated: Announcement) => {
    setAnnouncements((prev) => prev.map((a) => (a.id === updated.id ? updated : a)));
  };

  const handleDeleteLecture = async (lecture: Lecture) => {
    const msg = isJa ? '講義を削除しますか？' : 'Delete this lecture?';
    if (!window.confirm(msg)) return;
    try {
      await softDeleteLecture(lecture.id);
      setRecentLectures((prev) => prev.filter((l) => l.id !== lecture.id));
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to delete lecture');
    }
  };

  const scrollToSlide = (index: number) => {
    const el = carouselRef.current;
    if (!el) return;
    const slide = el.children[index] as HTMLElement | undefined;
    slide?.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
    setFactIndex(index);
  };

  const announcementSummary = (item: Announcement) =>
    item.title?.trim() || item.description?.trim() || (isJa ? 'お知らせ' : 'Announcement');
  const noAnnouncementsText = isJa ? 'お知らせはありません' : 'No announcements';
  const seeAllLabel = isJa ? 'すべて見る' : 'See all';

  const heroStat = isJa
    ? `${courses.length}コース · ${lectureCount}件の講義`
    : `${courses.length} ${courses.length === 1 ? 'course' : 'courses'} · ${lectureCount} ${
        lectureCount === 1 ? 'lecture' : 'lectures'
      }`;

  return (
    <div className="home-page">
      {/* お知らせ+コースは1つのflex縦積みラッパーにまとめ、gridの行トラック計算を
          main/facts側から独立させる(そうしないと main が2行分の高さを要求した時に
          announce/courses側の行トラックまで引き伸ばされ、コースが不自然に下がる)。
          900px未満だけ display:contents で解除し、Flutter版と同じ個別配置に戻す。 */}
      <div className="home-sidebar">
      {/* お知らせ: モバイルでは銀河の上の1行バー、ワイドでは左カラムのパネル */}
      <section className="home-announce" aria-label={isJa ? 'お知らせ' : 'Announcements'}>
        <button
          type="button"
          className="home-announce-bar"
          onClick={() => setAnnouncementsOpen(true)}
        >
          <span
            className="home-announce-icon"
            style={{
              color: latestAnnouncement
                ? getAnnouncementTypeConfig(latestAnnouncement.type).color
                : 'var(--gold)',
              background: latestAnnouncement
                ? getAnnouncementTypeConfig(latestAnnouncement.type).bg
                : 'rgba(255, 179, 0, 0.14)',
            }}
          >
            <span className="material-symbols-outlined">
              {latestAnnouncement ? getAnnouncementTypeConfig(latestAnnouncement.type).icon : 'star'}
            </span>
          </span>
          <span className="home-announce-bar-text">
            {latestAnnouncement ? announcementSummary(latestAnnouncement) : noAnnouncementsText}
          </span>
          {activeAnnouncements.length > 0 && (
            <span className="home-announce-count">{activeAnnouncements.length}</span>
          )}
          <ChevronRight size={15} className="home-announce-chevron" />
        </button>

        <div className="home-announce-panel">
          <div className="home-panel-head">
            <div className="home-panel-head-left">
              <h2>{isJa ? 'お知らせ' : 'Announcements'}</h2>
              {activeAnnouncements.length > 0 && (
                <span className="home-announce-count">{activeAnnouncements.length}</span>
              )}
            </div>
            <button
              type="button"
              className="home-panel-more"
              onClick={() => setAnnouncementsOpen(true)}
            >
              {seeAllLabel}
              <ChevronRight size={14} />
            </button>
          </div>

          {activeAnnouncements.length === 0 ? (
            <p className="home-panel-empty">{noAnnouncementsText}</p>
          ) : (
            <ul className="home-announce-list">
              {activeAnnouncements.slice(0, 4).map((item) => {
                const config = getAnnouncementTypeConfig(item.type);
                const title = announcementSummary(item);
                const description = item.title?.trim() ? item.description?.trim() : null;
                return (
                  <li key={item.id}>
                    <button
                      type="button"
                      className="home-announce-item"
                      onClick={() => setAnnouncementsOpen(true)}
                    >
                      <span
                        className="home-announce-icon"
                        style={{ color: config.color, background: config.bg }}
                      >
                        <span className="material-symbols-outlined">{config.icon}</span>
                      </span>
                      <span className="home-announce-item-text">
                        <span className="home-announce-item-title">{title}</span>
                        {description && (
                          <span className="home-announce-item-desc">{description}</span>
                        )}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </section>

      {/* コース: モバイルは横スクロールのチップ、ワイドでは左カラムの縦リスト */}
      <section className="home-courses">
        <div className="home-panel-head">
          <h2>{isJa ? 'コース' : 'Courses'}</h2>
          <Link to="/courses" className="home-panel-more">
            {isJa ? 'すべてのコース' : 'All courses'}
            <ChevronRight size={14} />
          </Link>
        </div>

        {courses.length > 0 && (
          <ul className="home-course-list">
            {courses.slice(0, 6).map((course) => {
              const accent = course.metadata?.color || DEFAULT_COURSE_COLOR;
              return (
                <li key={course.id}>
                  <Link
                    to={`/courses/${course.id}`}
                    className="home-course-row"
                    style={{ ['--course-accent' as string]: accent }}
                  >
                    <span className="home-course-icon">
                      <CourseIconGlyph icon={course.metadata?.icon} size={17} />
                    </span>
                    <span className="home-course-text">
                      {course.course_code?.trim() && (
                        <span className="home-course-code">{course.course_code.trim()}</span>
                      )}
                      <span className="home-course-title">{course.course_title}</span>
                    </span>
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </section>
      </div>

      {/* 銀河ヒーロー(ワイドでは横長バナー + 録音CTA、モバイルでは画面端まで + 下部FAB) */}
      <section className="home-hero">
        <GalaxyView />
        <div className="home-hero-caption">
          <span className="home-hero-eyebrow">{isJa ? 'あなたの銀河' : 'Your galaxy'}</span>
          <strong className="home-hero-stat">{heroStat}</strong>
        </div>
        <button type="button" className="home-upload-cta" onClick={() => openUploadModal()}>
          <Sparkles size={17} strokeWidth={2.2} />
          <span>{isJa ? '録音をアップロード' : 'Upload recording'}</span>
        </button>
      </section>

      {/* Fun Facts: モバイルは横スクロールのカルーセル、ワイドでは右カラムの縦積み */}
      {funFactsState.length > 0 && (
        <section className="home-facts">
          <div className="home-panel-head">
            <h2>{isJa ? '最新のファンファクト' : 'Latest fun facts'}</h2>
          </div>

          <div
            className="home-facts-scroller"
            ref={carouselRef}
            onScroll={(e) => {
              const el = e.currentTarget;
              const width = el.children[0]?.clientWidth || 1;
              setFactIndex(Math.round(el.scrollLeft / (width + 12)));
            }}
          >
            {funFactsState.map((fact) => (
              <div key={fact.id} className="home-fact-rainbow-wrapper">
                <article
                  className="home-fact-card"
                  role="link"
                  tabIndex={0}
                  onClick={() => navigate(`/lectures/${fact.lecture_id}`)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      navigate(`/lectures/${fact.lecture_id}`);
                    }
                  }}
                >
                  <h3 className="home-fact-title">{fact.title}</h3>
                  <p className="home-fact-body">
                    {stripFunFactCitations(fact.hook)} {stripFunFactCitations(fact.body)}
                  </p>
                  <div className="home-fact-foot">
                    <span className="home-fact-open-hint">
                      {isJa ? '講義を開く' : 'Open lecture'}
                    </span>
                    {/* カード全体のクリックに巻き込まれないよう伝播を止める */}
                    <span onClick={(e) => e.stopPropagation()}>
                      <ReactionBar
                        reaction={fact.metadata?.reaction ?? null}
                        onChange={(reaction) => handleReaction(fact.id, reaction)}
                      />
                    </span>
                  </div>
                </article>
              </div>
            ))}
          </div>

          <div className="home-fact-dots">
            {funFactsState.map((fact, i) => (
              <button
                key={fact.id}
                type="button"
                className={`home-fact-dot ${i === factIndex ? 'is-active' : ''}`}
                onClick={() => scrollToSlide(i)}
                aria-label={`Fun fact ${i + 1}`}
              />
            ))}
          </div>
        </section>
      )}

      {/* 最近の講義 */}
      <section className="home-main">
        <div className="home-panel-head">
          <h2>{isJa ? '最近の講義' : 'Recent lectures'}</h2>
        </div>

        {loading && (
          <ul className="home-lecture-grid">
            {[0, 1, 2, 3].map((i) => (
              <li key={i}>
                <LectureTileSkeleton />
              </li>
            ))}
          </ul>
        )}

        {!loading && recentLectures.length === 0 && (
          <PageState
            kind="empty"
            title={isJa ? 'まだ何もありません' : 'Nothing here yet'}
            message={
              isJa
                ? 'コースを作成して、最初の講義録音をアップロードしましょう。'
                : 'Create a course and upload your first lecture recording to get started.'
            }
            action={
              <Link to="/courses">
                <button type="button">{isJa ? 'コースを作成' : 'Create a course'}</button>
              </Link>
            }
          />
        )}

        {!loading && recentLectures.length > 0 && (
          <ul className="home-lecture-grid">
            {recentLectures.map((lecture) => {
              const course = courseById.get(lecture.course_id);
              return (
                <li key={lecture.id}>
                  <LectureTile
                    lecture={lecture}
                    courseCode={course?.course_code ?? course?.course_title}
                    courseColor={(course?.metadata?.color as string) ?? undefined}
                    onEdit={() => setEditingLecture(lecture)}
                    onDelete={() => handleDeleteLecture(lecture)}
                  />
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {announcementsOpen && (
        <AnnouncementsModal
          announcements={announcements}
          lectures={recentLectures}
          onClose={() => setAnnouncementsOpen(false)}
          onAnnouncementToggled={handleAnnouncementToggled}
        />
      )}

      {editingLecture && (
        <LectureEditModal
          lecture={editingLecture}
          onClose={() => setEditingLecture(null)}
          onLectureUpdated={(updated) => {
            setRecentLectures((prev) => prev.map((l) => (l.id === updated.id ? updated : l)));
            setEditingLecture(null);
          }}
        />
      )}
    </div>
  );
};
