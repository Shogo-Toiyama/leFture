import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Bookmark, ChevronLeft, ChevronRight, LayoutGrid, X } from 'lucide-react';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useReviewCards } from '../../hooks/useReviewCards';
import { useCourse } from '../../hooks/useCourse';
import { useTopicImageUrls } from '../../hooks/useTopicImageUrls';
import { useLanguage } from '../../i18n/LanguageContext';
import { useMediaQuery, STACKED_PANELS_QUERY } from '../../hooks/useMediaQuery';
import { useCardFlipGestures } from '../../hooks/useCardFlipGestures';
import { getLecture } from '../../lib/lectures';
import { updateReviewCardReaction } from '../../lib/content';
import { readAnnotations, toggleSaved } from '../../lib/annotations';
import { readableAccent } from '../../lib/reviewCardTheme';
import { REVIEW_CARD_TYPE_ORDER, type ContentMetadata, type ReviewCard } from '../../types/content';
import type { Lecture } from '../../types/lecture';
import type { TranslationKey } from '../../i18n/translations';
import { ReactionBar } from '../../components/ReactionBar';
import { AnnotationLayer } from '../../components/annotations/AnnotationLayer';
import { ReviewCardFace } from '../../components/reviewCards/ReviewCardFace';
import { ReviewCoverCard } from '../../components/reviewCards/ReviewCoverCard';
import { ReviewCardListDrawer } from '../../components/reviewCards/ReviewCardListDrawer';
import { TranscriptSheet } from '../../components/transcript/TranscriptSheet';
import type { ReviewFlatItem, ReviewTopicGroup } from '../../components/reviewCards/types';
import { ReviewCardsSkeleton } from '../../components/reviewCards/ReviewCardsSkeleton';

const TYPE_LABEL_KEY: Record<string, TranslationKey> = {
  hook: 'reviewCardTypeHook',
  core_why: 'reviewCardTypeCoreWhy',
  gotcha: 'reviewCardTypeGotcha',
  next_action: 'reviewCardTypeNextAction',
};

/**
 * 復習カードビューア。review_cards_viewer_page.dart と同じ紙面(ライトテーマ)の
 * 全画面ビューアで、アプリシェル(ダーク)の外側に自前で敷き直している。
 */
export const ReviewCardsPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const navigate = useNavigate();
  const { t } = useLanguage();

  const { topics } = useLectureTopics(lectureId);
  const { cards, loading, error, setCards } = useReviewCards(lectureId);
  const [lecture, setLecture] = useState<Lecture | null>(null);
  const { course } = useCourse(lecture?.course_id);

  const [index, setIndex] = useState(0);
  // 一覧は常に本文へ覆いかぶさるオーバーレイ(モーダル)。出典シートとは違い、
  // 開いている間に本文や出典を同時に操作できる必要はない。
  const [listOpen, setListOpen] = useState(false);
  /** 出典シートで強調するSID。null ならシートは閉じている。 */
  const [sourceSids, setSourceSids] = useState<string[] | null>(null);
  // 出典シートは広い画面では本文の横に並ぶが、狭い画面ではボトムシートに
  // なって重なる。そのときだけ「外側をタップで閉じる」幕を出す。
  const stackedPanels = useMediaQuery(STACKED_PANELS_QUERY);
  // めくりアニメーション。dir は「どちら向きにめくったか」で、leaving は
  // まだ退場アニメーション中の一つ前のカード。
  const [dir, setDir] = useState<'next' | 'prev'>('next');
  const [leaving, setLeaving] = useState<number | null>(null);
  const indexRef = useRef(0);

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

  const { groups, flat } = useMemo(() => {
    const byTopic = new Map<number, ReviewCard[]>();
    for (const card of cards) {
      const list = byTopic.get(card.topic_number);
      if (list) list.push(card);
      else byTopic.set(card.topic_number, [card]);
    }

    const nextGroups: ReviewTopicGroup[] = [];
    const nextFlat: ReviewFlatItem[] = [];
    for (const topic of topics) {
      const topicCards = (byTopic.get(topic.index) ?? [])
        .slice()
        .sort(
          (a, b) =>
            REVIEW_CARD_TYPE_ORDER.indexOf(a.card_type) - REVIEW_CARD_TYPE_ORDER.indexOf(b.card_type)
        );
      if (topicCards.length === 0) continue;

      const groupIndex = nextGroups.length;
      const startIndex = nextFlat.length;
      nextGroups.push({ topic, cards: topicCards, startIndex });
      nextFlat.push({ groupIndex, card: null });
      for (const card of topicCards) nextFlat.push({ groupIndex, card });
    }
    return { groups: nextGroups, flat: nextFlat };
  }, [cards, topics]);

  const imageUrls = useTopicImageUrls(useMemo(() => groups.map((g) => g.topic.image_path), [groups]));

  useEffect(() => {
    indexRef.current = index;
  }, [index]);

  useEffect(() => {
    if (flat.length > 0 && index >= flat.length) {
      setLeaving(null);
      setIndex(0);
    }
  }, [flat.length, index]);

  const goTo = useCallback(
    (next: number) => {
      if (flat.length === 0) return;
      const clamped = Math.min(Math.max(next, 0), flat.length - 1);
      const current = indexRef.current;
      if (clamped === current) return;
      indexRef.current = clamped;
      setDir(clamped > current ? 'next' : 'prev');
      setLeaving(current);
      setIndex(clamped);
    },
    [flat.length]
  );

  // 退場アニメーションが終わったら、裏で残していたカードを片付ける。
  useEffect(() => {
    if (leaving === null) return;
    const timer = window.setTimeout(() => setLeaving(null), 420);
    return () => window.clearTimeout(timer);
  }, [leaving, index]);

  const close = useCallback(() => navigate(`/lectures/${lectureId}`), [navigate, lectureId]);

  // スマホはスワイプとタップでめくる(左右の矢印はカードの上に重ねて残す)。
  const flipGestures = useCardFlipGestures({
    onPrevious: () => goTo(indexRef.current - 1),
    onNext: () => goTo(indexRef.current + 1),
  });

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === 'TEXTAREA' || target.tagName === 'INPUT')) return;
      if (event.key === 'ArrowRight') goTo(index + 1);
      if (event.key === 'ArrowLeft') goTo(index - 1);
      // Escapeは開いているパネルを、上に乗っている方から順に畳むだけ。
      // ビューアそのものは閉じない。
      if (event.key === 'Escape') {
        if (listOpen) setListOpen(false);
        else if (sourceSids) setSourceSids(null);
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [goTo, index, listOpen, sourceSids]);

  const patchCard = useCallback(
    (cardId: string, metadata: ContentMetadata) => {
      setCards((prev) => prev.map((c) => (c.id === cardId ? { ...c, metadata } : c)));
    },
    [setCards]
  );

  const typeLabel = useCallback(
    (cardType: string) => (TYPE_LABEL_KEY[cardType] ? t(TYPE_LABEL_KEY[cardType]) : cardType),
    [t]
  );

  const rootStyle = { ['--pv-accent' as string]: accent } as React.CSSProperties;

  if (loading) {
    return <ReviewCardsSkeleton />;
  }

  if (error || flat.length === 0) {
    return (
      <div className="pv-root" style={rootStyle}>
        <div className="pv-top">
          <div className="pv-top-row">
            <button type="button" className="pv-icon-btn" onClick={close} aria-label={t('close')}>
              <X size={20} />
            </button>
            <span className="pv-title">{t('reviewCards')}</span>
            <span style={{ width: 36 }} />
          </div>
        </div>
        <div className="pv-center">{error ?? t('reviewCardsEmpty')}</div>
      </div>
    );
  }

  const item = flat[index];
  const group = groups[item.groupIndex];
  const card = item.card;

  /**
   * flatリストの1件をカードとして描く。めくり中は前後2枚が同時に存在するため、
   * 操作を受け付けるのは表側([interactive])だけにする。
   */
  const renderFace = (target: ReviewFlatItem, interactive: boolean) => {
    const targetGroup = groups[target.groupIndex];
    const targetImage = targetGroup.topic.image_path
      ? imageUrls[targetGroup.topic.image_path] ?? null
      : null;

    if (!target.card) {
      return (
        <ReviewCoverCard
          title={targetGroup.topic.topic_title}
          kicker={`Topic ${target.groupIndex + 1}`}
          imageUrl={targetImage}
        />
      );
    }

    const face = (
      <ReviewCardFace
        card={target.card}
        annotations={readAnnotations(target.card.metadata)}
        imageUrl={targetImage}
        typeLabel={typeLabel(target.card.card_type)}
      />
    );

    // 退場中のカードは見た目だけの残像なので、選択メニューは載せない。
    if (!interactive) return face;

    const activeCard = target.card;
    return (
      <AnnotationLayer
        table="review_cards"
        rowId={activeCard.id}
        metadata={activeCard.metadata}
        onMetadataChange={(metadata) => patchCard(activeCard.id, metadata)}
        lectureId={lectureId!}
        onOpenSource={setSourceSids}
      >
        {face}
      </AnnotationLayer>
    );
  };

  const handleReaction = async (reaction: 'like' | 'dislike') => {
    if (!card) return;
    const next = card.metadata?.reaction === reaction ? null : reaction;
    patchCard(card.id, { ...card.metadata, reaction: next });
    await updateReviewCardReaction(card.id, card.metadata, reaction);
  };

  const handleSave = async () => {
    if (!card) return;
    patchCard(card.id, { ...card.metadata, saved: !card.metadata?.saved });
    await toggleSaved('review_cards', card.id, card.metadata);
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
          <span className="pv-title">{group.topic.topic_title}</span>
          <span style={{ width: 36 }} />
        </div>

        <div className="pv-tool-row">
          <button
            type="button"
            className={`pv-icon-btn ${listOpen ? 'is-active' : ''}`}
            onClick={() => setListOpen((v) => !v)}
            aria-label={t('reviewCardsViewList')}
            title={t('reviewCardsViewList')}
          >
            <LayoutGrid size={19} />
          </button>

          {card && (
            <>
              <span className="pv-divider" />
              <button
                type="button"
                className={`pv-icon-btn pv-save-btn ${card.metadata?.saved ? 'is-saved' : ''}`}
                onClick={handleSave}
                aria-pressed={Boolean(card.metadata?.saved)}
                aria-label={t('save')}
                title={t('save')}
              >
                <Bookmark size={18} fill={card.metadata?.saved ? 'currentColor' : 'none'} />
              </button>
              <ReactionBar reaction={card.metadata?.reaction ?? null} onChange={handleReaction} />
            </>
          )}

          <span className="pv-tool-spacer" />
          <span className="pv-counter">
            {index + 1} / {flat.length}
          </span>
        </div>

        <div className="rcv-progress">
          {groups.map((g, gi) => (
            <div className="rcv-progress-group" key={g.topic.id}>
              {Array.from({ length: g.cards.length + 1 }, (_, segIdx) => {
                const flatIndex = g.startIndex + segIdx;
                return (
                  <button
                    key={flatIndex}
                    type="button"
                    className={`rcv-seg ${flatIndex < index ? 'is-done' : ''} ${
                      flatIndex === index ? 'is-current' : ''
                    }`}
                    onClick={() => goTo(flatIndex)}
                    aria-label={`${gi + 1}-${segIdx + 1}`}
                  />
                );
              })}
            </div>
          ))}
        </div>
      </header>

          <div className="rcv-stage" {...flipGestures}>
        <button
          type="button"
          className="pv-nav-btn"
          onClick={() => goTo(index - 1)}
          disabled={index === 0}
          aria-label={t('previous')}
        >
          <ChevronLeft size={22} />
        </button>

        <div className="rcv-stack" data-dir={dir}>
          {leaving !== null && flat[leaving] && (
            <div className="rcv-layer is-leaving" key={`out-${leaving}`} aria-hidden="true">
              {renderFace(flat[leaving], false)}
            </div>
          )}
          <div className="rcv-layer is-entering" key={`in-${index}`}>
            {renderFace(item, true)}
          </div>
        </div>

        <button
          type="button"
          className="pv-nav-btn"
          onClick={() => goTo(index + 1)}
          disabled={index === flat.length - 1}
          aria-label={t('next')}
        >
          <ChevronRight size={22} />
        </button>
      </div>

      <p className="pv-hint">
        {stackedPanels ? t('reviewCardsNavHintTouch') : t('reviewCardsNavHint')}
      </p>
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
          <ReviewCardListDrawer
            title={t('reviewCardsListTitle')}
            groups={groups}
            imageUrls={imageUrls}
            currentIndex={index}
            typeLabel={typeLabel}
            onSelect={(flatIndex) => {
              goTo(flatIndex);
              setListOpen(false);
            }}
            onClose={() => setListOpen(false)}
          />
        </>
      )}
    </div>
  );
};
