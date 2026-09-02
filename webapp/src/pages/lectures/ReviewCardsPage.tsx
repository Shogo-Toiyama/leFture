import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useReviewCards } from '../../hooks/useReviewCards';
import { updateReviewCardReaction } from '../../lib/content';
import { readAnnotations, toggleSaved } from '../../lib/annotations';
import { blockRawMarkdownSource } from '../../lib/reviewCardBlocks';
import { REVIEW_CARD_TYPE_ORDER, type ContentMetadata, type ReviewCard } from '../../types/content';
import { ReviewCardBlockView } from '../../components/ReviewCardBlockView';
import { ReactionBar } from '../../components/ReactionBar';
import { CitationLink } from '../../components/CitationLink';
import { AnnotationLayer } from '../../components/annotations/AnnotationLayer';
import { PageState } from '../../components/PageState';

const CARD_TYPE_LABEL: Record<string, string> = {
  hook: 'Hook',
  core_why: 'Why it matters',
  gotcha: 'Watch out',
  next_action: 'Next step',
};

/** review_cards_viewer_page.dart 準拠: 紙面全画面カード + トピック毎のセグメント進捗バー。 */
export const ReviewCardsPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const navigate = useNavigate();
  const { topics } = useLectureTopics(lectureId);
  const { cards, loading, error, setCards } = useReviewCards(lectureId);
  const [index, setIndex] = useState(0);

  const grouped = useMemo(() => {
    const topicOrder = new Map(topics.map((t, i) => [t.index, i]));
    const sorted = [...cards].sort((a, b) => {
      const topicDiff = (topicOrder.get(a.topic_number) ?? 0) - (topicOrder.get(b.topic_number) ?? 0);
      if (topicDiff !== 0) return topicDiff;
      return REVIEW_CARD_TYPE_ORDER.indexOf(a.card_type) - REVIEW_CARD_TYPE_ORDER.indexOf(b.card_type);
    });
    const byTopic: ReviewCard[][] = [];
    for (const card of sorted) {
      const arr = byTopic[byTopic.length - 1];
      if (arr && cards.find((c) => c.id === arr[0].id)?.topic_number === card.topic_number) {
        arr.push(card);
      } else {
        byTopic.push([card]);
      }
    }
    return { flat: sorted, byTopic };
  }, [cards, topics]);

  const orderedCards = grouped.flat;

  useEffect(() => {
    if (index >= orderedCards.length) setIndex(0);
  }, [orderedCards, index]);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === 'TEXTAREA' || target.tagName === 'INPUT')) return;
      if (event.key === 'ArrowRight') setIndex((i) => Math.min(i + 1, orderedCards.length - 1));
      if (event.key === 'ArrowLeft') setIndex((i) => Math.max(i - 1, 0));
      if (event.key === 'Escape') navigate(`/lectures/${lectureId}`);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [orderedCards.length, navigate, lectureId]);

  const patchCard = useCallback(
    (cardId: string, metadata: ContentMetadata) => {
      setCards((prev) => prev.map((c) => (c.id === cardId ? { ...c, metadata } : c)));
    },
    [setCards]
  );

  if (loading) return <PageState kind="loading" />;
  if (error) return <PageState kind="error" message={error} />;
  if (orderedCards.length === 0) {
    return (
      <div className="rc-page">
        <PageState kind="empty" title="No review cards yet" message="They'll appear once processing finishes." />
      </div>
    );
  }

  const card = orderedCards[index];
  const topic = topics.find((t) => t.index === card.topic_number);
  const annotations = readAnnotations(card.metadata);
  const rawCardText = card.card_content.map(blockRawMarkdownSource).join('\n\n');

  const handleReaction = async (reaction: 'like' | 'dislike') => {
    const next = card.metadata?.reaction === reaction ? null : reaction;
    patchCard(card.id, { ...card.metadata, reaction: next });
    await updateReviewCardReaction(card.id, card.metadata, reaction);
  };

  const handleSave = async () => {
    patchCard(card.id, { ...card.metadata, saved: !card.metadata?.saved });
    await toggleSaved('review_cards', card.id, card.metadata);
  };

  let seenSoFar = 0;

  return (
    <div className="rc-page">
      <header className="rc-header">
        <div className="rc-header-row">
          <button type="button" className="rc-icon-button" onClick={() => navigate(`/lectures/${lectureId}`)} aria-label="Close">
            ✕
          </button>
          <span className="rc-header-title">{topic?.topic_title ?? 'Review cards'}</span>
          <span style={{ width: 36 }} />
        </div>
        <div className="rc-toolbar-row">
          <div className="rc-toolbar">
            <button
              type="button"
              className={`icon-button ${card.metadata?.saved ? 'is-active' : ''}`}
              onClick={handleSave}
              aria-label="Save"
              title="Save"
            >
              {card.metadata?.saved ? '★' : '☆'}
            </button>
            <ReactionBar reaction={card.metadata?.reaction ?? null} onChange={handleReaction} />
          </div>
          <span className="rc-counter">
            {index + 1} / {orderedCards.length}
          </span>
        </div>

        <div className="rc-progress">
          {grouped.byTopic.map((group, gi) => (
            <div className="rc-progress-group" key={gi}>
              {group.map((c) => {
                const cardGlobalIndex = seenSoFar;
                seenSoFar += 1;
                return (
                  <button
                    key={c.id}
                    type="button"
                    className={`rc-progress-seg ${cardGlobalIndex < index ? 'is-done' : ''} ${
                      cardGlobalIndex === index ? 'is-current' : ''
                    }`}
                    onClick={() => setIndex(cardGlobalIndex)}
                    aria-label={`Card ${cardGlobalIndex + 1}`}
                  />
                );
              })}
            </div>
          ))}
        </div>
      </header>

      <div className="rc-card-area">
        <AnnotationLayer
          key={card.id}
          table="review_cards"
          rowId={card.id}
          metadata={card.metadata}
          onMetadataChange={(metadata) => patchCard(card.id, metadata)}
          lectureId={lectureId!}
        >
          <article className="rc-card">
            {topic && <p className="rc-topic-label">{topic.topic_title}</p>}
            <div className="review-card-head">
              {card.hero_emoji && <span className="review-card-emoji">{card.hero_emoji}</span>}
              <div>
                <span className="review-card-type">{CARD_TYPE_LABEL[card.card_type] ?? card.card_type}</span>
                {card.title && <h1>{card.title}</h1>}
              </div>
            </div>

            <div className="review-card-body">
              {card.card_content.map((block, i) => (
                <ReviewCardBlockView key={i} block={block} blockIdx={i} annotations={annotations} />
              ))}
            </div>

            <footer className="review-card-foot">
              <CitationLink lectureId={lectureId!} rawText={rawCardText} />
            </footer>
          </article>
        </AnnotationLayer>
      </div>

      <div className="review-card-nav">
        <button type="button" className="ghost" onClick={() => setIndex((i) => Math.max(i - 1, 0))} disabled={index === 0}>
          ← Previous
        </button>
        <button
          type="button"
          className="ghost"
          onClick={() => setIndex((i) => Math.min(i + 1, orderedCards.length - 1))}
          disabled={index === orderedCards.length - 1}
        >
          Next →
        </button>
      </div>
      <p className="rc-nav-hint">Use ← → keys, or drag the progress bar above</p>
    </div>
  );
};
