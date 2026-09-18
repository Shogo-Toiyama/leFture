import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Bookmark, ChevronDown, ChevronUp, LayoutGrid, Lock, X } from 'lucide-react';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useDeepNotes } from '../../hooks/useDeepNotes';
import { useCourse } from '../../hooks/useCourse';
import { useTopicImageUrls } from '../../hooks/useTopicImageUrls';
import { useLanguage } from '../../i18n/LanguageContext';
import { useMediaQuery, STACKED_PANELS_QUERY } from '../../hooks/useMediaQuery';
import { getLecture } from '../../lib/lectures';
import { updateDeepNoteReaction } from '../../lib/content';
import { readAnnotations, toggleSaved } from '../../lib/annotations';
import { readableAccent } from '../../lib/reviewCardTheme';
import { stripFigurePlaceholders, stripSidCitations } from '../../lib/sidCitation';
import type { ContentMetadata } from '../../types/content';
import type { Lecture } from '../../types/lecture';
import { AnnotatedMarkdown } from '../../components/annotations/AnnotatedMarkdown';
import { AnnotationLayer } from '../../components/annotations/AnnotationLayer';
import { ReactionBar } from '../../components/ReactionBar';
import {
  DeepNoteListDrawer,
  type DeepNoteEntry,
} from '../../components/deepNotes/DeepNoteListDrawer';
import { AdjacentTopicPreview } from '../../components/deepNotes/AdjacentTopicPreview';
import { DeepNotesDetailSkeleton } from '../../components/deepNotes/DeepNotesDetailSkeleton';
import { TranscriptSheet } from '../../components/transcript/TranscriptSheet';
import { UpgradeRequiredDialog } from '../../components/UpgradeRequiredDialog';
import { DEEP_NOTES_SKIPPED_PLAN_LIMIT, TIER_LITE } from '../../lib/planFeatures';
import { tierAccent } from '../../lib/planTheme';

/**
 * 詳細ノートビューア。deep_notes_detail_page.dart と同じ紙面(ライトテーマ)の
 * 全画面ビューアで、ヘッダーと一覧ドロワーは復習カードと同じ .pv-* を共有する。
 */
export const DeepNotesDetailPage: React.FC = () => {
  const { lectureId, topicIndex } = useParams<{ lectureId: string; topicIndex?: string }>();
  const navigate = useNavigate();
  const { t } = useLanguage();

  const { topics } = useLectureTopics(lectureId);
  const { notes, loading, error, setNotes } = useDeepNotes(lectureId);
  const [lecture, setLecture] = useState<Lecture | null>(null);
  const { course } = useCourse(lecture?.course_id);
  // 一覧は常に本文へ覆いかぶさるオーバーレイ(モーダル)。出典シートとは違い、
  // 開いている間に本文や出典を同時に操作できる必要はない。
  const [listOpen, setListOpen] = useState(false);
  /** 出典シートで強調するSID。null ならシートは閉じている。 */
  const [sourceSids, setSourceSids] = useState<string[] | null>(null);
  // 出典シートは広い画面では本文の横に並ぶが、狭い画面ではボトムシートに
  // なって重なる。そのときだけ「外側をタップで閉じる」幕を出す。
  const stackedPanels = useMediaQuery(STACKED_PANELS_QUERY);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [lockDialogOpen, setLockDialogOpen] = useState(false);
  const deepNotesLockColor = tierAccent(TIER_LITE).accent;

  useEffect(() => {
    if (!lectureId) return;
    let cancelled = false;
    getLecture(lectureId)
      .then((data) => {
        if (!cancelled) setLecture(data);
      })
      .catch(() => {
        /* コースカラーが取れないだけなので既定色で続行する */
      });
    return () => {
      cancelled = true;
    };
  }, [lectureId]);

  const accent = readableAccent((course?.metadata?.color as string | undefined) ?? null);

  const entries = useMemo(
    () =>
      topics
        .map((topic) => ({ topic, note: notes.find((n) => n.topic_number === topic.index) }))
        .filter((entry): entry is { topic: (typeof topics)[number]; note: NonNullable<typeof entry.note> } =>
          Boolean(entry.note)
        ),
    [topics, notes]
  );

  const imageUrls = useTopicImageUrls(
    useMemo(() => entries.map((e) => e.topic.image_path), [entries])
  );

  const position = topicIndex != null
    ? entries.findIndex((e) => e.topic.index === Number(topicIndex))
    : (entries.length > 0 ? 0 : -1);
  const current = position >= 0 ? entries[position] : undefined;
  const prev = position > 0 ? entries[position - 1] : undefined;
  const next = position >= 0 && position < entries.length - 1 ? entries[position + 1] : undefined;

  const go = useCallback(
    (targetTopicIndex: number) => navigate(`/lectures/${lectureId}/deep-notes/${targetTopicIndex}`),
    [navigate, lectureId]
  );

  const close = useCallback(() => navigate(`/lectures/${lectureId}`), [navigate, lectureId]);

  // ノートを切り替えたら先頭から読ませる。
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0 });
  }, [topicIndex]);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === 'TEXTAREA' || target.tagName === 'INPUT')) return;
      if (event.key === 'ArrowRight' && next) go(next.topic.index);
      if (event.key === 'ArrowLeft' && prev) go(prev.topic.index);
      // Escapeは開いているパネルを、上に乗っている方から順に畳むだけ。
      // ビューアそのものは閉じない。
      if (event.key === 'Escape') {
        if (listOpen) setListOpen(false);
        else if (sourceSids) setSourceSids(null);
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [next, prev, go, listOpen, sourceSids]);

  const patchNote = useCallback(
    (noteId: string, metadata: ContentMetadata) => {
      setNotes((list) => list.map((n) => (n.id === noteId ? { ...n, metadata } : n)));
    },
    [setNotes]
  );

  const drawerEntries: DeepNoteEntry[] = entries.map((entry) => ({
    topic: entry.topic,
    summary: entry.topic.summary ? stripSidCitations(entry.topic.summary) : '',
    isLocked: entry.note.note_contents === DEEP_NOTES_SKIPPED_PLAN_LIMIT,
  }));

  const rootStyle = { ['--pv-accent' as string]: accent } as React.CSSProperties;

  if (loading) {
    return <DeepNotesDetailSkeleton />;
  }

  if (error || !current) {
    return (
      <div className="pv-root" style={rootStyle}>
        <div className="pv-top">
          <div className="pv-top-row">
            <button type="button" className="pv-icon-btn" onClick={close} aria-label={t('close')}>
              <X size={20} />
            </button>
            <span className="pv-title">{t('deepNotes')}</span>
            <span style={{ width: 36 }} />
          </div>
        </div>
        <div className="pv-center">{error ?? t('deepNotesEmpty')}</div>
      </div>
    );
  }

  const { topic, note } = current;
  const heroUrl = topic.image_path ? imageUrls[topic.image_path] ?? null : null;
  const isLocked = note.note_contents === DEEP_NOTES_SKIPPED_PLAN_LIMIT;
  const cleaned = stripSidCitations(stripFigurePlaceholders(note.note_contents));

  const handleReaction = async (reaction: 'like' | 'dislike') => {
    const value = note.metadata?.reaction === reaction ? null : reaction;
    patchNote(note.id, { ...note.metadata, reaction: value });
    await updateDeepNoteReaction(note.id, note.metadata, reaction);
  };

  const handleSave = async () => {
    patchNote(note.id, { ...note.metadata, saved: !note.metadata?.saved });
    await toggleSaved('deep_notes', note.id, note.metadata);
  };

  return (
    <div className="pv-root" style={rootStyle}>
      <div className="pv-split">
        {sourceSids && (
          <TranscriptSheet lectureId={lectureId!} sids={sourceSids} onClose={() => setSourceSids(null)} />
        )}

        <div className="pv-column">
      <header className="pv-top">
        <div className="pv-top-row">
          <button type="button" className="pv-icon-btn" onClick={close} aria-label={t('close')}>
            <X size={20} />
          </button>
          <span className="pv-title">{topic.topic_title}</span>
          <span style={{ width: 36 }} />
        </div>

        <div className="pv-tool-row">
          <button
            type="button"
            className={`pv-icon-btn ${listOpen ? 'is-active' : ''}`}
            onClick={() => setListOpen((v) => !v)}
            aria-label={t('deepNotesViewList')}
            title={t('deepNotesViewList')}
          >
            <LayoutGrid size={19} />
          </button>
          <span className="pv-divider" />
          <button
            type="button"
            className={`pv-icon-btn pv-save-btn ${note.metadata?.saved ? 'is-saved' : ''}`}
            onClick={handleSave}
            aria-pressed={Boolean(note.metadata?.saved)}
            aria-label={t('save')}
            title={t('save')}
          >
            <Bookmark size={18} fill={note.metadata?.saved ? 'currentColor' : 'none'} />
          </button>
          <ReactionBar reaction={note.metadata?.reaction ?? null} onChange={handleReaction} />

          <span className="pv-tool-spacer" />
          <span className="pv-counter">
            {position + 1} / {entries.length}
          </span>
        </div>
      </header>

      <div className="dnv-scroll" ref={scrollRef}>
        <div className="dnv-sheet">
          {prev && (
            <>
              <AdjacentTopicPreview
                title={prev.topic.topic_title}
                imageUrl={prev.topic.image_path ? imageUrls[prev.topic.image_path] ?? null : null}
                direction="prev"
                onClick={() => go(prev.topic.index)}
              />
              <p className="dnv-adjacent-hint is-top">
                <ChevronUp size={14} className="dnv-adjacent-chevron" />
                {t('deepNotesPrevHint')}
              </p>
            </>
          )}

          {heroUrl && (
            <div className="dnv-hero">
              <img src={heroUrl} alt="" />
            </div>
          )}

          <h1 className="dnv-title">{topic.topic_title}</h1>
          {topic.summary && <p className="dnv-summary">{stripSidCitations(topic.summary)}</p>}

          {isLocked ? (
            <div
              className="locked-content-placeholder"
              role="button"
              tabIndex={0}
              onClick={() => setLockDialogOpen(true)}
            >
              <div className="locked-content-blur">{topic.summary ? stripSidCitations(topic.summary) : ''}</div>
              <span className="locked-content-caption" style={{ color: deepNotesLockColor }}>
                <Lock size={13} />
                {t('deepNotesLockedCaption')}
              </span>
            </div>
          ) : (
            <AnnotationLayer
              key={note.id}
              table="deep_notes"
              rowId={note.id}
              metadata={note.metadata}
              onMetadataChange={(metadata) => patchNote(note.id, metadata)}
              lectureId={lectureId!}
              onOpenSource={setSourceSids}
            >
              <AnnotatedMarkdown
                className="dnv-prose"
                markdown={cleaned}
                rawMarkdown={note.note_contents}
                annotations={readAnnotations(note.metadata)}
                blockIdx={null}
              />
            </AnnotationLayer>
          )}

          <p className="dnv-disclaimer">{t('aiDisclaimer')}</p>

          {next && (
            <>
              <p className="dnv-adjacent-hint">
                {t('deepNotesNextHint')}
                <ChevronDown size={14} className="dnv-adjacent-chevron" />
              </p>
              <AdjacentTopicPreview
                title={next.topic.topic_title}
                imageUrl={next.topic.image_path ? imageUrls[next.topic.image_path] ?? null : null}
                direction="next"
                onClick={() => go(next.topic.index)}
              />
            </>
          )}
        </div>
      </div>

        </div>

        {sourceSids && stackedPanels && (
          <button
            type="button"
            className="pv-scrim"
            onClick={() => setSourceSids(null)}
            aria-label={t('close')}
          />
        )}
      </div>

      {listOpen && (
        <>
          <button
            type="button"
            className="pv-list-scrim"
            onClick={() => setListOpen(false)}
            aria-label={t('close')}
          />
          <DeepNoteListDrawer
            title={t('deepNotesListTitle')}
            entries={drawerEntries}
            currentIndex={position}
            closeLabel={t('close')}
            onSelect={(i) => {
              go(entries[i].topic.index);
              setListOpen(false);
            }}
            onClose={() => setListOpen(false)}
          />
        </>
      )}

      {lockDialogOpen && (
        <UpgradeRequiredDialog
          requiredTierColor={deepNotesLockColor}
          title={t('deepNotesLockedDialogTitle')}
          message={t('deepNotesLockedDialogMessage')}
          onClose={() => setLockDialogOpen(false)}
        />
      )}
    </div>
  );
};
