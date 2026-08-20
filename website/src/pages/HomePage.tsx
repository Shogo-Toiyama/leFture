import React, { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, Quote, Sparkles } from 'lucide-react';
import { useTranslation } from '../i18n/LanguageContext';
import { clamp01, subscribeScroll } from '../lib/scrollBus';
import { subscribeMouse } from '../lib/mouseBus';
import { APP_STORE_URL } from '../lib/links';
import { AppleLogo } from '../components/AppleLogo';
import { GalaxyCanvas } from '../components/home/GalaxyCanvas';
import { ClayField } from '../components/home/ClayField';
import { Waveform } from '../components/home/Waveform';
import { ReviewCardDeck } from '../components/home/ReviewCardDeck';
import { PipelineSection } from '../components/home/PipelineSection';
import { usePageMeta } from '../lib/usePageMeta';
import './home.css';

/** Accent colours, straight from the app's Universe palette. */
const ACCENT_CARDS = '#FFB300';
const ACCENT_NOTES = '#42A5F5';
const ACCENT_FACTS = '#B98BFF';
const ROAD_ACCENTS = ['#FFB300', '#42A5F5', '#B98BFF'];
const WHY_ACCENTS = ['#42A5F5', '#B98BFF'];

/**
 * Reveals every `.reveal` descendant once as it enters the viewport. One
 * observer for the whole page rather than a hook per element.
 *
 * The marker is a `data-in` attribute rather than a class: several revealed
 * elements also carry React-controlled classNames (the pipeline steps toggle
 * `is-lit`/`is-active`), and React rewrites `className` wholesale on re-render,
 * which would silently strip a class we added imperatively.
 */
function useRevealAll(rootRef: React.RefObject<HTMLElement | null>, locale: string) {
  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;

    // Re-scan on locale change: React re-renders the translated lists, and any
    // node it recreates comes back without the marker below.
    const elements = Array.from(root.querySelectorAll<HTMLElement>('.reveal')).filter(
      (el) => !el.hasAttribute('data-in')
    );

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      elements.forEach((el) => el.setAttribute('data-in', ''));
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.setAttribute('data-in', '');
            observer.unobserve(entry.target);
          }
        }
      },
      { threshold: 0.12, rootMargin: '0px 0px -6% 0px' }
    );

    elements.forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, [rootRef, locale]);
}

/** Cycles the highlighted persona so the Fun Facts card is never static. */
const FactRotator: React.FC<{
  personas: { emoji: string; who: string; angle: string }[];
}> = ({ personas }) => {
  const [active, setActive] = useState(0);

  useEffect(() => {
    const id = window.setInterval(
      () => setActive((i) => (i + 1) % personas.length),
      2800
    );
    return () => window.clearInterval(id);
  }, [personas.length]);

  return (
    <ul className="fact-personas">
      {personas.map((persona, i) => (
        <li key={i} className={`fact-persona${i === active ? ' is-on' : ''}`}>
          <span className="fact-persona-emoji" aria-hidden="true">
            {persona.emoji}
          </span>
          <span>
            <span className="fact-persona-who">{persona.who}</span>
            <span className="fact-persona-angle">{persona.angle}</span>
          </span>
        </li>
      ))}
    </ul>
  );
};

export const HomePage: React.FC = () => {
  const { t, locale } = useTranslation();
  const home = t.home;

  usePageMeta({
    title: 'leFture | Turn Any Lecture into Knowledge for Your Future',
    description:
      'leFture transforms raw lecture audio into interactive review cards, deep notes, and personalized fun facts. Just tap record, set your phone down, and focus on the lecture.',
    canonicalPath: '/',
  });

  const rootRef = useRef<HTMLDivElement>(null);
  const heroRef = useRef<HTMLElement>(null);

  useRevealAll(rootRef, locale);

  // Publish hero scroll progress once per frame. Everything inside the hero —
  // copy, waveform, clay pieces, scroll cue — reads it as an inherited CSS
  // variable, so the whole choreography runs without a single re-render.
  useEffect(
    () =>
      subscribeScroll((y, vh) => {
        const el = heroRef.current;
        if (!el) return;
        el.style.setProperty('--sp', clamp01(y / Math.max(1, vh * 0.85)).toFixed(4));
      }),
    []
  );

  // Publish mouse parallax to root for CTA clay objects and other elements
  useEffect(
    () =>
      subscribeMouse((mx, my) => {
        const el = rootRef.current;
        if (!el) return;
        el.style.setProperty('--mouse-x', mx.toFixed(4));
        el.style.setProperty('--mouse-y', my.toFixed(4));
      }),
    []
  );

  return (
    <div className="home" ref={rootRef}>
      <GalaxyCanvas />

      {/* ---------------------------------------------------------------- Hero */}
      <section className="hero" ref={heroRef}>
        <ClayField />

        <div className="hero-inner">
          <span className="hero-eyebrow">
            <i className="hero-eyebrow-rule" />
            <span className="hero-eyebrow-text">{home.hero.eyebrow}</span>
            <i className="hero-eyebrow-rule" />
          </span>

          <h1 className="hero-title">
            <span className="line-1">{home.hero.titleTop}</span>
            <span className="line-2 gold-text">{home.hero.titleGlow}</span>
          </h1>

          <p className="hero-sub">{home.hero.subtitle}</p>

          <div className="hero-actions">
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-primary"
            >
              <AppleLogo size={18} />
              <span>{home.hero.primaryCta}</span>
            </a>
            <a href="#how" className="btn-secondary">
              <span>{home.hero.secondaryCta}</span>
              <ArrowRight size={16} />
            </a>
          </div>

          <div className="hero-wave">
            <Waveform />
          </div>
        </div>

        <div className="hero-scroll">
          <span>{home.hero.scrollHint}</span>
          <i />
        </div>
      </section>

      {/* ----------------------------------------------------------------- Why */}
      <section className="section" id="why">
        <div className="container">
          <header className="section-head reveal">
            <span className="eyebrow">
              <i className="eyebrow-bar" />
              {home.why.eyebrow}
            </span>
            <h2 className="section-title">{home.why.heading}</h2>
            <p className="section-lead">{home.why.lead}</p>
          </header>

          <div className="why-grid">
            {home.why.problems.map((problem, i) => (
              <article
                key={i}
                className="why-card reveal"
                style={
                  {
                    '--accent': WHY_ACCENTS[i % WHY_ACCENTS.length],
                    '--d': `${i * 120}ms`,
                  } as React.CSSProperties
                }
              >
                <div className="why-no">{problem.no}</div>
                <h3>{problem.title}</h3>
                <p>{problem.body}</p>
              </article>
            ))}
          </div>

          <p className="why-closing reveal">{home.why.closing}</p>
        </div>
      </section>

      {/* ------------------------------------------------------- How (pinned) */}
      <PipelineSection t={home.how} />

      {/* ----------------------------------------------------------- What you get */}
      <section className="section" id="features">
        <div className="container">
          <header className="section-head section-head--center reveal">
            <span className="eyebrow">
              <i className="eyebrow-bar" />
              {home.what.eyebrow}
            </span>
            <h2 className="section-title">{home.what.heading}</h2>
            <p className="section-lead">{home.what.lead}</p>
          </header>

          {/* Review Cards */}
          <div className="feature" style={{ '--accent': ACCENT_CARDS } as React.CSSProperties}>
            <div className="feature-copy reveal">
              <span className="feature-tag">{home.what.cards.tag}</span>
              <h3 className="feature-title">{home.what.cards.title}</h3>
              <p className="feature-subtitle">{home.what.cards.subtitle}</p>
              <p className="feature-body">{home.what.cards.body}</p>
            </div>
            <div className="feature-media reveal" style={{ '--d': '120ms' } as React.CSSProperties}>
              <ReviewCardDeck cards={home.what.cards.deck} hint={home.what.cards.deckHint} />
            </div>
          </div>

          {/* Deep Notes */}
          <div
            className="feature feature--flip"
            style={{ '--accent': ACCENT_NOTES } as React.CSSProperties}
          >
            <div className="feature-copy reveal">
              <span className="feature-tag">{home.what.notes.tag}</span>
              <h3 className="feature-title">{home.what.notes.title}</h3>
              <p className="feature-subtitle">{home.what.notes.subtitle}</p>
              <p className="feature-body">{home.what.notes.body}</p>
              <div className="feature-callout">
                <h4>
                  <Quote size={15} />
                  {home.what.notes.citationTitle}
                </h4>
                <p>{home.what.notes.citationBody}</p>
              </div>
            </div>

            <div className="feature-media">
              <div className="note-mock reveal">
                <div className="note-paper">
                  <h5>{home.what.notes.sampleHeading}</h5>
                  <p>
                    <mark className="note-sel">{home.what.notes.sampleLine}</mark>
                  </p>
                  <div className="note-toolbar">
                    <span>{home.what.notes.sampleAction}</span>
                  </div>
                </div>

                <div className="note-cite">
                  <div className="note-cite-time">
                    <Quote size={12} />
                    {home.what.notes.sampleTimestamp}
                  </div>
                  <p>{home.what.notes.sampleQuote}</p>
                </div>
              </div>
            </div>
          </div>

          {/* Fun Facts */}
          <div className="feature" style={{ '--accent': ACCENT_FACTS } as React.CSSProperties}>
            <div className="feature-copy reveal">
              <span className="feature-tag">{home.what.facts.tag}</span>
              <h3 className="feature-title">{home.what.facts.title}</h3>
              <p className="feature-subtitle">{home.what.facts.subtitle}</p>
              <p className="feature-body">{home.what.facts.body}</p>
              <ul className="feature-list">
                {home.what.facts.ingredients.map((item, i) => (
                  <li key={i}>{item}</li>
                ))}
              </ul>
            </div>

            <div className="feature-media reveal" style={{ '--d': '120ms' } as React.CSSProperties}>
              <div className="fact-mock">
                <div className="fact-aurora" aria-hidden="true" />
                <div className="fact-inner">
                  <span className="fact-lecture">{home.what.facts.lecture}</span>
                  <FactRotator personas={home.what.facts.personas} />
                  <span className="fact-aha">
                    <Sparkles size={13} />
                    {home.what.facts.ahaLabel}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* --------------------------------------------------------------- Tools */}
      <section className="section" id="tools">
        <div className="container">
          <header className="section-head reveal">
            <span className="eyebrow">
              <i className="eyebrow-bar" />
              {home.tools.eyebrow}
            </span>
            <h2 className="section-title">{home.tools.heading}</h2>
            <p className="section-lead">{home.tools.lead}</p>
          </header>

          <div className="tools-grid">
            {home.tools.items.map((item, i) => (
              <article
                key={i}
                className="tool-card reveal"
                style={{ '--d': `${i * 80}ms` } as React.CSSProperties}
              >
                <span className="tool-emoji" aria-hidden="true">
                  {item.emoji}
                </span>
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* ------------------------------------------------------------- Roadmap */}
      <section className="section" id="roadmap">
        <div className="container">
          <header className="section-head reveal">
            <span className="eyebrow">
              <i className="eyebrow-bar" />
              {home.road.eyebrow}
            </span>
            <h2 className="section-title">{home.road.heading}</h2>
            <p className="section-lead">{home.road.lead}</p>
          </header>

          <div className="road-layout">
            <ol className="road-list">
              {home.road.stages.map((stage, i) => (
                <li
                  key={i}
                  className="road-item reveal"
                  style={
                    {
                      '--accent': ROAD_ACCENTS[i % ROAD_ACCENTS.length],
                      '--d': `${i * 110}ms`,
                    } as React.CSSProperties
                  }
                >
                  <div className="road-head">
                    <span className="road-term">
                      {stage.emoji} {stage.term}
                    </span>
                    <span className="road-status">{stage.status}</span>
                  </div>
                  <h3>{stage.title}</h3>
                  <p>{stage.body}</p>
                </li>
              ))}
            </ol>

            <figure className="road-media reveal" style={{ '--d': '140ms' } as React.CSSProperties}>
              <img
                src="/img/scene/galaxy-dome.webp"
                alt=""
                loading="lazy"
                decoding="async"
              />
              <figcaption className="road-media-caption">
                {home.road.stages[home.road.stages.length - 1]?.title}
              </figcaption>
            </figure>
          </div>
        </div>
      </section>

      {/* ------------------------------------------------------------- Final CTA */}
      <section className="cta-section" id="download">
        <div className="container">
          <div className="cta-panel reveal">
            <div className="cta-glow" aria-hidden="true" />

            <span className="cta-clay cta-clay--left" aria-hidden="true">
              <img src="/img/clay/unicorn.webp" alt="" loading="lazy" decoding="async" />
            </span>
            <span className="cta-clay cta-clay--right" aria-hidden="true">
              <img src="/img/clay/owl.webp" alt="" loading="lazy" decoding="async" />
            </span>

            <div className="cta-inner">
              <h2 className="cta-title">{home.cta.heading}</h2>
              <p className="cta-sub">{home.cta.sub}</p>

              <div className="cta-actions">
                <a
                  href={APP_STORE_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-primary"
                  style={{ padding: '14px 30px' }}
                >
                  <AppleLogo size={19} />
                  <span>{home.cta.button}</span>
                </a>
                <Link to="/contact" className="btn-secondary" style={{ padding: '14px 26px' }}>
                  <span>{home.cta.secondary}</span>
                </Link>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
};
