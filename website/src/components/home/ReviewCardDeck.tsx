import React, { useCallback, useEffect, useRef, useState } from 'react';

export interface DeckCard {
  kind: string;
  emoji: string;
  title: string;
  body: string;
}

/** Accent per card type, matching the four-card rhythm used in the app. */
const ACCENTS = ['#FFB300', '#42A5F5', '#FF9A3D', '#B98BFF'];

/**
 * A live stack of the app's four review cards — Hook, Core Why, Gotcha, Next
 * Action. It advances on its own so the section is never static, and clicking
 * the front card (or the labels underneath) takes over manually.
 */
export const ReviewCardDeck: React.FC<{ cards: DeckCard[]; hint: string }> = ({
  cards,
  hint,
}) => {
  const [index, setIndex] = useState(0);
  const [paused, setPaused] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  // Only cycle while the deck is actually on screen.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([entry]) => setVisible(entry.isIntersecting),
      { threshold: 0.35 }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    if (paused || !visible) return;
    const id = window.setInterval(
      () => setIndex((i) => (i + 1) % cards.length),
      5200
    );
    return () => window.clearInterval(id);
  }, [paused, visible, cards.length]);

  const advance = useCallback(() => {
    setPaused(true);
    setIndex((i) => (i + 1) % cards.length);
  }, [cards.length]);

  return (
    <div className="deck-wrap" ref={containerRef}>
      <div className="deck">
        {cards.map((card, i) => {
          const offset = (i - index + cards.length) % cards.length;
          return (
            <article
              key={i}
              className="deck-card"
              data-pos={offset}
              aria-hidden={offset !== 0}
              style={{ '--accent': ACCENTS[i % ACCENTS.length] } as React.CSSProperties}
            >
              <div className="deck-card-head">
                <span className="deck-kind">{card.kind}</span>
                <span className="deck-emoji">{card.emoji}</span>
              </div>
              <h4 className="deck-title">{card.title}</h4>
              <p className="deck-body">{card.body}</p>
              <div className="deck-rail" />
            </article>
          );
        })}

        <button type="button" className="deck-hit" onClick={advance}>
          <span className="deck-hint">{hint}</span>
        </button>
      </div>

      <div className="deck-tabs" role="tablist">
        {cards.map((card, i) => (
          <button
            key={i}
            type="button"
            role="tab"
            aria-selected={i === index}
            className={`deck-tab${i === index ? ' is-active' : ''}`}
            style={{ '--accent': ACCENTS[i % ACCENTS.length] } as React.CSSProperties}
            onClick={() => {
              setPaused(true);
              setIndex(i);
            }}
          >
            {card.kind}
          </button>
        ))}
      </div>
    </div>
  );
};
