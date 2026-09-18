import React, { useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { useProcessingStatus } from '../../hooks/useProcessingStatus';
import { useCourse } from '../../hooks/useCourse';
import { useFunFacts } from '../../hooks/useFunFacts';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useAnnouncements } from '../../hooks/useAnnouncements';
import { useKeywords } from '../../hooks/useKeywords';
import { useLanguage } from '../../i18n/LanguageContext';
import { startAnalysis, InsufficientCreditsError } from '../../lib/upload';
import { updateFunFactReaction, stripFunFactCitations } from '../../lib/content';
import type { FunFact } from '../../types/content';
import { lectureDisplayTitle, lectureCreditsUsedDisplay, DEAD_JOB_STATUSES } from '../../types/lecture';
import { PipelineStepsList } from '../../components/PipelineStepsList';
import { ReactionBar } from '../../components/ReactionBar';
import { PageState } from '../../components/PageState';
import { LectureHeroView } from '../../components/lectures/LectureHeroView';
import { LectureViewerSkeleton } from '../../components/lectures/LectureViewerSkeleton';
import { AnnouncementsModal } from '../../components/modals/AnnouncementsModal';
import { KeywordsModal } from '../../components/modals/KeywordsModal';
import { TopicsModal } from '../../components/modals/TopicsModal';
import { LectureEditModal } from '../../components/modals/LectureEditModal';

export const LectureViewerPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const location = useLocation();
  const blockedReason = (location.state as { analysisBlockedReason?: string } | null)?.analysisBlockedReason;

  const { t, language } = useLanguage();
  const { lecture, job, tasks, loading, error, refetch } = useProcessingStatus(lectureId);
  const { course } = useCourse(lecture?.course_id);
  const { topics } = useLectureTopics(lectureId);
  const { funFacts, setFunFacts } = useFunFacts(lectureId);
  const { announcements, setAnnouncements } = useAnnouncements(lectureId);
  const { keywords, setKeywords } = useKeywords(lectureId);

  const [activeModal, setActiveModal] = useState<'announcements' | 'keywords' | 'topics' | 'edit' | null>(null);
  const [starting, setStarting] = useState(false);
  const [startError, setStartError] = useState<string | null>(blockedReason ?? null);

  const handleStart = async (force: boolean) => {
    if (!lectureId) return;
    setStarting(true);
    setStartError(null);
    try {
      await startAnalysis(lectureId, force);
      await refetch();
    } catch (err) {
      setStartError(err instanceof InsufficientCreditsError ? err.message : 'Failed to start analysis.');
    } finally {
      setStarting(false);
    }
  };

  const handleFunFactReaction = async (factId: string, reaction: 'like' | 'dislike') => {
    const fact = funFacts.find((f) => f.id === factId);
    if (!fact) return;
    const next = fact.metadata?.reaction === reaction ? null : reaction;
    setFunFacts((prev) => prev.map((f) => (f.id === factId ? { ...f, metadata: { ...f.metadata, reaction: next } } : f)));
    await updateFunFactReaction(factId, fact.metadata, reaction);
  };

  if (loading) return <LectureViewerSkeleton />;
  if (error) return <PageState kind="error" message={error} />;
  if (!lecture) return <PageState kind="empty" title="Lecture not found" />;

  const failed = job ? DEAD_JOB_STATUSES.includes(job.status) : false;
  const ready = job?.status === 'COMPLETED';
  const hasAnythingReady = topics.length > 0;
  const showOverlay = !ready && !hasAnythingReady;
  const completedTasks = tasks.filter((t) => t.status === 'COMPLETED').length;
  const courseColor = (course?.metadata?.color as string) || '#FFB300';

  const formatSourceHost = (url: string) => {
    try {
      const host = new URL(url).hostname;
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch {
      return url;
    }
  };

  return (
    <div
      className="lecture-viewer-root"
      style={{
        ['--course-accent' as string]: courseColor,
        background: '#111422',
      }}
    >
      {/* 1. Full Viewport Hero View */}
      <LectureHeroView
        course={course}
        lectureTitle={lectureDisplayTitle(lecture)}
        lectureDatetime={lecture.lecture_datetime}
        topics={topics}
        summary={lecture.summary}
        creditsUsed={lectureCreditsUsedDisplay(lecture)}
        onEdit={() => setActiveModal('edit')}
      />

      {/* 2. Main Body Content (Below Hero) */}
      <div className="lecture-body-container">
        {startError && (
          <div className="app-error-box" style={{ marginBottom: '2rem' }}>
            <span>{startError}</span>
          </div>
        )}

        {showOverlay ? (
          <div className="lecture-overlay-backdrop">
            <div className={`lecture-overlay-card ${failed ? 'is-error' : ''}`}>
              <div className="lecture-overlay-icon">{failed ? '!' : job ? '◐' : '✦'}</div>
              {!job && (
                <>
                  <h2>{t('readyToAnalyse')}</h2>
                  <p className="muted">{t('notAnalysedYet')}</p>
                  <button type="button" className="auth-submit-btn" onClick={() => handleStart(false)} disabled={starting}>
                    {starting ? t('starting') : t('startAnalysis')}
                  </button>
                </>
              )}
              {job && !failed && (
                <>
                  <h2>{t('analysingLecture')}</h2>
                  <p className="muted">
                    {t('stepsCompleted', { completed: String(completedTasks), total: String(tasks.length) })}
                  </p>
                  <PipelineStepsList tasks={tasks} onRetried={refetch} />
                </>
              )}
              {failed && (
                <>
                  <h2>{t('analysisStopped')}</h2>
                  <p className="muted">{t('retryOrStartOver')}</p>
                  <PipelineStepsList tasks={tasks} onRetried={refetch} />
                  <button type="button" className="auth-submit-btn" onClick={() => handleStart(true)} disabled={starting}>
                    {starting ? t('starting') : t('startOver')}
                  </button>
                </>
              )}
            </div>
          </div>
        ) : (
          <div className="lecture-content-flow">
            {!ready && (
              <div className="pipeline-progress-banner">
                <span>{failed ? t('analysisStopped') : t('analysingLecture')}</span>
                <span className="muted">
                  {completedTasks}/{tasks.length}
                </span>
              </div>
            )}

            {/* Top Row: Highlights Chips (Announcements, Keywords, Topics) */}
            <div className="lecture-highlights-row">
              {/* 1. Announcements Chip */}
              <button
                type="button"
                className="lecture-highlight-chip"
                onClick={() => setActiveModal('announcements')}
              >
                <span className="material-symbols-outlined chip-icon-glyph">campaign</span>
                <span>{language === 'ja' ? 'お知らせ' : 'Announcements'}</span>
                <span className="chip-count-badge">{announcements.length}</span>
              </button>

              {/* 2. Keywords Chip */}
              <button
                type="button"
                className="lecture-highlight-chip"
                onClick={() => setActiveModal('keywords')}
              >
                <span className="material-symbols-outlined chip-icon-glyph">vpn_key</span>
                <span>{language === 'ja' ? 'キーワード' : 'Keywords'}</span>
                <span className="chip-count-badge">{keywords.length}</span>
              </button>

              {/* 3. Topics Chip */}
              <button
                type="button"
                className="lecture-highlight-chip"
                onClick={() => setActiveModal('topics')}
              >
                <span className="material-symbols-outlined chip-icon-glyph">hub</span>
                <span>{language === 'ja' ? 'トピック' : 'Topics'}</span>
                <span className="chip-count-badge">{topics.length}</span>
              </button>
            </div>

            {/* Clean 2-Column Split Layout */}
            <div className="lecture-split-layout">
              {/* Left Column: Action Navigation Cards */}
              <div className="action-nav-stack">
                {/* 1. Review Cards */}
                <Link to={`/lectures/${lectureId}/review-cards`} className="action-nav-card">
                  <div className="action-nav-left">
                    <div
                      className="action-nav-icon-wrap"
                      style={{ backgroundColor: 'rgba(255, 179, 0, 0.15)', color: 'var(--gold)' }}
                    >
                      <span className="material-symbols-outlined action-nav-glyph action-nav-glyph-review">style</span>
                    </div>
                    <span className="action-nav-title">{t('reviewCards')}</span>
                  </div>
                  <div className="action-nav-arrow" style={{ color: 'var(--gold)' }}>
                    →
                  </div>
                </Link>

                {/* 2. Deep Notes */}
                <Link to={`/lectures/${lectureId}/deep-notes`} className="action-nav-card">
                  <div className="action-nav-left">
                    <div
                      className="action-nav-icon-wrap"
                      style={{ backgroundColor: 'rgba(255, 179, 0, 0.15)', color: 'var(--gold)' }}
                    >
                      <span className="material-symbols-outlined action-nav-glyph action-nav-glyph-notes">description</span>
                    </div>
                    <span className="action-nav-title">{t('deepNotes')}</span>
                  </div>
                  <div className="action-nav-arrow" style={{ color: 'var(--gold)' }}>
                    →
                  </div>
                </Link>

                {/* 3. Transcript & Audio */}
                <Link to={`/lectures/${lectureId}/transcript`} className="action-nav-card">
                  <div className="action-nav-left">
                    <div
                      className="action-nav-icon-wrap"
                      style={{ backgroundColor: 'rgba(255, 179, 0, 0.15)', color: 'var(--gold)' }}
                    >
                      <span className="material-symbols-outlined action-nav-glyph">receipt_long</span>
                    </div>
                    <span className="action-nav-title">{t('transcript')}</span>
                  </div>
                  <div className="action-nav-arrow" style={{ color: 'var(--gold)' }}>
                    →
                  </div>
                </Link>
              </div>

              {/* Right Column: Fun Facts Section */}
              <div className="lecture-funfacts-column">
                {funFacts.length > 0 ? (
                  <div className="fun-fact-stack">
                    {funFacts.map((fact) => (
                      <ViewerFunFactCard
                        key={fact.id}
                        fact={fact}
                        formatSourceHost={formatSourceHost}
                        onReactionChange={(reaction) => handleFunFactReaction(fact.id, reaction)}
                      />
                    ))}
                  </div>
                ) : (
                  <div className="fun-fact-empty-card">
                    <p className="muted">{t('funFact')}</p>
                  </div>
                )}
              </div>
            </div>

            <p className="ai-disclaimer">{t('aiDisclaimer')}</p>
          </div>
        )}
      </div>

      {/* Pop-up Modals (Modularized Components) */}
      {activeModal === 'announcements' && (
        <AnnouncementsModal
          announcements={announcements}
          onClose={() => setActiveModal(null)}
          onAnnouncementToggled={(updated) => {
            setAnnouncements((prev) => prev.map((a) => (a.id === updated.id ? updated : a)));
          }}
        />
      )}
      {activeModal === 'keywords' && (
        <KeywordsModal
          keywords={keywords}
          topics={topics}
          onClose={() => setActiveModal(null)}
          onKeywordUpdated={(updated) => {
            setKeywords((prev) => prev.map((k) => (k.id === updated.id ? updated : k)));
          }}
        />
      )}
      {activeModal === 'topics' && lectureId && (
        <TopicsModal
          lectureId={lectureId}
          courseId={lecture.course_id}
          topics={topics}
          onClose={() => setActiveModal(null)}
        />
      )}
      {activeModal === 'edit' && lecture && (
        <LectureEditModal
          lecture={lecture}
          onClose={() => setActiveModal(null)}
          onLectureUpdated={() => {
            refetch();
          }}
        />
      )}
    </div>
  );
};

interface ViewerFunFactCardProps {
  fact: FunFact;
  formatSourceHost: (url: string) => string;
  onReactionChange: (reaction: 'like' | 'dislike') => void;
}

const ViewerFunFactCard: React.FC<ViewerFunFactCardProps> = ({
  fact,
  formatSourceHost,
  onReactionChange,
}) => {
  const { t, language } = useLanguage();
  const [sourcesOpen, setSourcesOpen] = useState(false);

  const cleanHook = stripFunFactCitations(fact.hook);
  const cleanBody = stripFunFactCitations(fact.body);
  const sources =
    fact.metadata?.sources && Array.isArray(fact.metadata.sources)
      ? (fact.metadata.sources as string[])
      : [];

  return (
    <div className="fun-fact-rainbow-wrapper">
      <article className="fun-fact-card">
        <h3 className="fun-fact-title" style={{ color: 'var(--gold)' }}>
          {fact.title || t('funFact')}
        </h3>

        {cleanHook && <p className="fun-fact-hook">{cleanHook}</p>}

        {cleanHook && cleanBody && <div className="fun-fact-divider" />}

        {cleanBody && <p className="fun-fact-body">{cleanBody}</p>}

        {/* Card Footer: Sources Accordion Button on Left, Reaction on Right */}
        <div className="fun-fact-card-footer">
          {sources.length > 0 ? (
            <button
              type="button"
              className={`fun-fact-sources-toggle ${sourcesOpen ? 'is-open' : ''}`}
              onClick={() => setSourcesOpen(!sourcesOpen)}
              aria-expanded={sourcesOpen}
            >
              <span className="material-symbols-outlined sources-toggle-icon">link</span>
              <span>{language === 'ja' ? 'ソース' : 'Sources'}</span>
              <span className="sources-toggle-count">({sources.length})</span>
              <span className="material-symbols-outlined sources-toggle-chevron">
                {sourcesOpen ? 'keyboard_arrow_up' : 'keyboard_arrow_down'}
              </span>
            </button>
          ) : (
            <div />
          )}

          <ReactionBar
            reaction={fact.metadata?.reaction ?? null}
            onChange={onReactionChange}
          />
        </div>

        {/* Expandable Sources Accordion Body */}
        {sources.length > 0 && sourcesOpen && (
          <div className="fun-fact-sources-accordion-panel">
            {sources.map((url, idx) => (
              <a
                key={idx}
                href={url}
                target="_blank"
                rel="noreferrer"
                className="fun-fact-accordion-source-item"
                title={url}
              >
                <span className="material-symbols-outlined source-item-link-icon">open_in_new</span>
                <span className="source-item-host">{formatSourceHost(url)}</span>
              </a>
            ))}
          </div>
        )}
      </article>
    </div>
  );
};
