import React, { useCallback, useEffect, useRef, useState } from 'react';

export interface DeckCard {
  kind: string;
  emoji: string;
  title: string;
  body: string;
  highlight?: string;
  imageUrl?: string;
}

/** Accent per card type, matching the four-card rhythm used in the app. */
const ACCENTS: Record<string, string> = {
  Hook: '#FFB300',
  'Core Why': '#42A5F5',
  Gotcha: '#FF9A3D',
  'Next Action': '#B98BFF',
};

const DEFAULT_ACCENTS = ['#FFB300', '#42A5F5', '#FF9A3D', '#B98BFF'];

/**
 * A live stack of the app's four review cards — Hook, Core Why, Gotcha, Next Action.
 * Modeled directly after the real web app's ReviewCardFace:
 *   Topic image border (10px padding) -> Cream/White paper -> Hero Emoji ->
 *   Card title -> Body prose -> Bottom type label banner with gradient fade.
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

  const handleCardClick = useCallback(
    (cardIndex: number, offset: number) => {
      setPaused(true);
      if (offset === 0) {
        setIndex((i) => (i + 1) % cards.length);
      } else {
        setIndex(cardIndex);
      }
    },
    [cards.length]
  );

  return (
    <div className="deck-wrap" ref={containerRef}>
      <div className="deck">
        {cards.map((card, i) => {
          const offset = (i - index + cards.length) % cards.length;
          const typeAccent = ACCENTS[card.kind] ?? DEFAULT_ACCENTS[i % DEFAULT_ACCENTS.length];
          const bgImg = card.imageUrl || `/img/topics/topic_${(i % 4) + 1}.jpg`;

          return (
            <article
              key={i}
              className="deck-card rcv-card"
              data-pos={offset}
              aria-hidden={offset !== 0}
              style={
                {
                  ['--pv-type' as string]: typeAccent,
                  backgroundImage: `url(${bgImg})`,
                } as React.CSSProperties
              }
              onClick={() => handleCardClick(i, offset)}
            >
              <div className="rcv-paper">
                <div className="rcv-scroll">
                  <div className="rcv-hero-emoji" aria-hidden="true">
                    {card.emoji}
                  </div>
                  <h4 className="rcv-card-title">{card.title}</h4>
                  <div className="rcv-blocks">
                    <p className="rcv-body-p">{card.body}</p>
                    {card.highlight && (
                      <div className="rcv-callout">
                        <span className="rcv-callout-icon" aria-hidden="true">
                          ✨
                        </span>
                        <p>{card.highlight}</p>
                      </div>
                    )}
                  </div>
                </div>

                <div className="rcv-foot">
                  <span className="rcv-type-label">{card.kind}</span>
                </div>
              </div>
            </article>
          );
        })}

        <button
          type="button"
          className="deck-hit"
          onClick={advance}
          aria-label={hint}
        >
          <span className="deck-hint">{hint}</span>
        </button>
      </div>

      <div className="deck-tabs" role="tablist">
        {cards.map((card, i) => {
          const typeAccent = ACCENTS[card.kind] ?? DEFAULT_ACCENTS[i % DEFAULT_ACCENTS.length];
          return (
            <button
              key={i}
              type="button"
              role="tab"
              aria-selected={i === index}
              className={`deck-tab${i === index ? ' is-active' : ''}`}
              style={{ '--accent': typeAccent } as React.CSSProperties}
              onClick={() => {
                setPaused(true);
                setIndex(i);
              }}
            >
              {card.kind}
            </button>
          );
        })}
      </div>
    </div>
  );
};

