import React, { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useDashboard } from '../../hooks/useDashboard';
import { useCourses } from '../../hooks/useCourses';
import { updateFunFactReaction } from '../../lib/content';
import { GalaxyView } from '../../components/GalaxyView';
import { LectureTile } from '../../components/LectureTile';
import { ReactionBar } from '../../components/ReactionBar';
import { PageState } from '../../components/PageState';

/**
 * home_page.dart 準拠: ギャラクシー(固定高さ) → fun factsカルーセル →
 * "Courses ›" 見出し + 最近の講義リスト → 右下フローティングの録音(=アップロード)ボタン。
 */
export const HomePage: React.FC = () => {
  const { recentLectures, funFacts, loading } = useDashboard();
  const { courses } = useCourses();
  const [factIndex, setFactIndex] = useState(0);
  const [funFactsState, setFunFactsState] = useState(funFacts);
  const carouselRef = useRef<HTMLDivElement>(null);

  // useDashboardの結果が更新されたらローカルのreaction編集用stateも同期する
  useEffect(() => {
    setFunFactsState(funFacts);
  }, [funFacts]);

  const courseById = new Map(courses.map((course) => [course.id, course]));

  const handleReaction = async (factId: string, reaction: 'like' | 'dislike') => {
    const fact = funFactsState.find((f) => f.id === factId);
    if (!fact) return;
    const next = fact.metadata?.reaction === reaction ? null : reaction;
    setFunFactsState((prev) =>
      prev.map((f) => (f.id === factId ? { ...f, metadata: { ...f.metadata, reaction: next } } : f))
    );
    await updateFunFactReaction(factId, fact.metadata, reaction);
  };

  const scrollToSlide = (index: number) => {
    const el = carouselRef.current;
    if (!el) return;
    const slide = el.children[index] as HTMLElement | undefined;
    slide?.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
    setFactIndex(index);
  };

  return (
    <div className="home-page">
      <GalaxyView />

      {funFactsState.length > 0 && (
        <>
          <div
            className="fun-fact-carousel"
            ref={carouselRef}
            onScroll={(e) => {
              const el = e.currentTarget;
              const width = el.children[0]?.clientWidth || 1;
              setFactIndex(Math.round(el.scrollLeft / (width + 12)));
            }}
          >
            {funFactsState.map((fact) => (
              <div key={fact.id} className="fun-fact-slide">
                <article className="fun-fact-slide-card">
                  <h3 className="fun-fact-slide-title">{fact.title}</h3>
                  <p className="fun-fact-slide-body">
                    {fact.hook} {fact.body}
                  </p>
                  <div className="fun-fact-slide-foot">
                    <Link to={`/lectures/${fact.lecture_id}`}>Open lecture</Link>
                    <ReactionBar
                      reaction={fact.metadata?.reaction ?? null}
                      onChange={(reaction) => handleReaction(fact.id, reaction)}
                    />
                  </div>
                </article>
              </div>
            ))}
          </div>
          <div className="fun-fact-dots">
            {funFactsState.map((fact, i) => (
              <button
                key={fact.id}
                type="button"
                className={`fun-fact-dot ${i === factIndex ? 'is-active' : ''}`}
                onClick={() => scrollToSlide(i)}
                aria-label={`Fun fact ${i + 1}`}
              />
            ))}
          </div>
        </>
      )}

      <div className="home-section-header">
        <h2>Courses</h2>
        <Link to="/courses">All courses ›</Link>
      </div>

      {loading && <PageState kind="loading" />}

      {!loading && recentLectures.length === 0 && (
        <PageState
          kind="empty"
          title="Nothing here yet"
          message="Create a course and upload your first lecture recording to get started."
          action={
            <Link to="/courses">
              <button type="button">Create a course</button>
            </Link>
          }
        />
      )}

      {recentLectures.length > 0 && (
        <ul className="lecture-list">
          {recentLectures.map((lecture) => {
            const course = courseById.get(lecture.course_id);
            return (
              <li key={lecture.id}>
                <LectureTile
                  lecture={lecture}
                  courseCode={course?.course_code ?? course?.course_title}
                  courseColor={(course?.metadata?.color as string) ?? undefined}
                />
              </li>
            );
          })}
        </ul>
      )}

      <div className="record-fab-wrap">
        <Link to="/courses" className="record-fab">
          <button type="button" className="pill">
            ✦ Upload recording
          </button>
        </Link>
      </div>
    </div>
  );
};
