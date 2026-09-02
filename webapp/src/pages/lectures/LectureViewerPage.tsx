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
import { updateFunFactReaction } from '../../lib/content';
import { lectureDisplayTitle, DEAD_JOB_STATUSES } from '../../types/lecture';
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
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="chip-icon-svg">
                  <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
                  <path d="M13.73 21a2 2 0 0 1-3.46 0" />
                </svg>
                <span>{language === 'ja' ? 'お知らせ' : 'Announcements'}</span>
                <span className="chip-count-badge">{announcements.length}</span>
              </button>

              {/* 2. Keywords Chip */}
              <button
                type="button"
                className="lecture-highlight-chip"
                onClick={() => setActiveModal('keywords')}
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="chip-icon-svg">
                  <circle cx="7.5" cy="15.5" r="5.5" />
                  <path d="m21 2-9.6 9.6" />
                  <path d="m15.5 7.5 3 3L22 7l-3-3" />
                </svg>
                <span>{language === 'ja' ? 'キーワード' : 'Keywords'}</span>
                <span className="chip-count-badge">{keywords.length}</span>
              </button>

              {/* 3. Topics Chip */}
              <button
                type="button"
                className="lecture-highlight-chip"
                onClick={() => setActiveModal('topics')}
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="chip-icon-svg">
                  <circle cx="12" cy="12" r="10" />
                  <line x1="2" y1="12" x2="22" y2="12" />
                  <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
                </svg>
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
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="action-nav-svg">
                        <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
                        <line x1="8" y1="21" x2="16" y2="21" />
                        <line x1="12" y1="17" x2="12" y2="21" />
                      </svg>
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
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="action-nav-svg">
                        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                        <polyline points="14 2 14 8 20 8" />
                        <line x1="16" y1="13" x2="8" y2="13" />
                        <line x1="16" y1="17" x2="8" y2="17" />
                        <polyline points="10 9 9 9 8 9" />
                      </svg>
                    </div>
                    <span className="action-nav-title">{t('deepNotes')}</span>
                  </div>
                  <div className="action-nav-arrow" style={{ color: 'var(--gold)' }}>
                    →
                  </div>
                </Link>

                {/* 3. Transcript */}
                <Link to={`/lectures/${lectureId}/transcript`} className="action-nav-card">
                  <div className="action-nav-left">
                    <div
                      className="action-nav-icon-wrap"
                      style={{ backgroundColor: 'rgba(255, 179, 0, 0.15)', color: 'var(--gold)' }}
                    >
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="action-nav-svg">
                        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                      </svg>
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
                    {funFacts.map((fact) => {
                      const sources = fact.metadata?.sources && Array.isArray(fact.metadata.sources)
                        ? (fact.metadata.sources as string[])
                        : [];

                      return (
                        <article key={fact.id} className="fun-fact-card">
                          <h3 className="fun-fact-title" style={{ color: 'var(--gold)' }}>
                            {fact.title || t('funFact')}
                          </h3>

                          {fact.hook && <p className="fun-fact-hook">{fact.hook}</p>}

                          {fact.hook && fact.body && <div className="fun-fact-divider" />}

                          {fact.body && <p className="fun-fact-body">{fact.body}</p>}

                          {/* Sources Links */}
                          {sources.length > 0 && (
                            <div className="fun-fact-sources-wrap">
                              <span className="sources-label">{t('sources')}:</span>
                              <div className="sources-chips">
                                {sources.map((url, idx) => (
                                  <a
                                    key={idx}
                                    href={url}
                                    target="_blank"
                                    rel="noreferrer"
                                    className="fun-fact-source-chip"
                                    style={{ color: 'var(--gold)' }}
                                  >
                                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="source-link-icon">
                                      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
                                      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
                                    </svg>
                                    <span>{formatSourceHost(url)}</span>
                                  </a>
                                ))}
                              </div>
                            </div>
                          )}

                          <div className="fun-fact-card-footer">
                            <ReactionBar
                              reaction={fact.metadata?.reaction ?? null}
                              onChange={(reaction) => handleFunFactReaction(fact.id, reaction)}
                            />
                          </div>
                        </article>
                      );
                    })}
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
