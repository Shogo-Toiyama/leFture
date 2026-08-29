import React, { useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useLectureTopics } from '../../hooks/useLectureTopics';
import { useReviewCards } from '../../hooks/useReviewCards';
import { updateReviewCardReaction } from '../../lib/content';
import { REVIEW_CARD_TYPE_ORDER } from '../../types/content';
import { ReviewCardBlockView } from '../../components/ReviewCardBlockView';
import { ReactionButtons } from '../../components/ReactionButtons';

const CARD_TYPE_LABEL: Record<string, string> = {
  hook: 'Hook',
  core_why: 'Why it matters',
  gotcha: 'Watch out',
  next_action: 'Next step',
};

export const ReviewCardsPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const { topics } = useLectureTopics(lectureId);
  const { cards, loading, error, setCards } = useReviewCards(lectureId);
  const [index, setIndex] = useState(0);

  const orderedCards = useMemo(() => {
    const topicOrder = new Map(topics.map((t, i) => [t.index, i]));
    return [...cards].sort((a, b) => {
      const topicDiff = (topicOrder.get(a.topic_number) ?? 0) - (topicOrder.get(b.topic_number) ?? 0);
      if (topicDiff !== 0) return topicDiff;
      return REVIEW_CARD_TYPE_ORDER.indexOf(a.card_type) - REVIEW_CARD_TYPE_ORDER.indexOf(b.card_type);
    });
  }, [cards, topics]);

  useEffect(() => {
    if (index >= orderedCards.length) setIndex(0);
  }, [orderedCards, index]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') setIndex((i) => Math.min(i + 1, orderedCards.length - 1));
      if (e.key === 'ArrowLeft') setIndex((i) => Math.max(i - 1, 0));
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [orderedCards.length]);

  if (loading) return <p>Loading…</p>;
  if (error) return <p className="auth-error">{error}</p>;
  if (orderedCards.length === 0) return <p>No review cards yet.</p>;

  const card = orderedCards[index];
  const topic = topics.find((t) => t.index === card.topic_number);

  const handleReaction = async (reaction: 'like' | 'dislike') => {
    await updateReviewCardReaction(card.id, card.metadata, reaction);
    setCards((prev) =>
      prev.map((c) =>
        c.id === card.id
          ? { ...c, metadata: { ...c.metadata, reaction: c.metadata?.reaction === reaction ? null : reaction } }
          : c
      )
    );
  };

  return (
    <div>
      <Link to={`/lectures/${lectureId}`}>← Back to lecture</Link>
      <div className="page-header">
        <h1>Review cards</h1>
        <span>
          {index + 1} / {orderedCards.length}
        </span>
      </div>

      <div className="review-card">
        {topic && <p className="review-card-topic">{topic.topic_title}</p>}
        <div className="review-card-header">
          <span className="review-card-emoji">{card.hero_emoji}</span>
          <div>
            <span className="review-card-type">{CARD_TYPE_LABEL[card.card_type] ?? card.card_type}</span>
            {card.title && <h2>{card.title}</h2>}
          </div>
        </div>

        {card.card_content.map((block, i) => (
          <ReviewCardBlockView key={i} block={block} lectureId={lectureId!} />
        ))}

        <ReactionButtons reaction={card.metadata?.reaction ?? null} onChange={handleReaction} />
      </div>

      <div className="review-card-nav">
        <button type="button" onClick={() => setIndex((i) => Math.max(i - 1, 0))} disabled={index === 0}>
          ← Prev
        </button>
        <button
          type="button"
          onClick={() => setIndex((i) => Math.min(i + 1, orderedCards.length - 1))}
          disabled={index === orderedCards.length - 1}
        >
          Next →
        </button>
      </div>
    </div>
  );
};
