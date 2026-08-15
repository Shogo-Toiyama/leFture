import React, { useEffect, useRef, useState } from 'react';
import { clamp01, subscribeScroll } from '../../lib/scrollBus';
import type { HomeTranslations } from '../../i18n/types';

/**
 * The "three things you do" section, pinned while you scroll through it.
 *
 * Scroll progress lights up each step in turn, fills the pipeline rail, and
 * slides the stage conveyor — so the ten minutes of AI work happening in the
 * background is something you physically scrub through.
 *
 * Below the `--pin-breakpoint` the pin is dropped in CSS and this degrades to a
 * plain stacked list; the progress variable simply goes unused.
 */
export const PipelineSection: React.FC<{ t: HomeTranslations['how'] }> = ({ t }) => {
  const wrapRef = useRef<HTMLDivElement>(null);
  const machineRef = useRef<HTMLDivElement>(null);
  const conveyorRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const [stage, setStage] = useState(0);

  // Measure and set the exact shift distance, dynamic gap, and padding so all chips scroll through fully
  useEffect(() => {
    const updateTrackShift = () => {
      const conveyor = conveyorRef.current;
      const track = trackRef.current;
      const wrap = wrapRef.current;
      if (!conveyor || !track || !wrap) return;

      const containerWidth = conveyor.clientWidth;
      const chips = Array.from(track.children) as HTMLElement[];
      const chipsCount = chips.length;
      if (chipsCount === 0) return;

      const gapsCount = Math.max(1, chipsCount - 1);

      // Pure total width of chips (excluding gap and padding)
      let pureChipsWidth = 0;
      chips.forEach((child) => {
        pureChipsWidth += child.offsetWidth;
      });

      const basePadding = 28;
      const baseGap = 10;
      const baseTotalWidth = pureChipsWidth + gapsCount * baseGap + basePadding * 2;

      // Target total length: 200% of container width (or baseTotalWidth if already larger)
      const targetTotalWidth = Math.max(baseTotalWidth, containerWidth * 2.0);
      const extraSpace = Math.max(0, targetTotalWidth - baseTotalWidth);

      // Dynamically expand gap (from 10px up to ~28px) based on available space and number of gaps
      const maxGapIncrease = 18;
      const idealGap = baseGap + Math.min(maxGapIncrease, (extraSpace * 0.35) / gapsCount);
      const gap = Math.max(baseGap, idealGap);

      // Allocate remaining space evenly to left/right padding
      const totalGapsWidth = gapsCount * gap;
      const remainingForPadding = Math.max(basePadding * 2, targetTotalWidth - (pureChipsWidth + totalGapsWidth));
      const padSide = Math.max(basePadding, remainingForPadding / 2);

      const finalTotalWidth = pureChipsWidth + totalGapsWidth + padSide * 2;
      const maxShift = Math.max(0, finalTotalWidth - containerWidth);

      wrap.style.setProperty('--track-gap', `${gap.toFixed(1)}px`);
      wrap.style.setProperty('--track-pad-left', `${padSide.toFixed(1)}px`);
      wrap.style.setProperty('--track-pad-right', `${padSide.toFixed(1)}px`);
      wrap.style.setProperty('--track-max-shift', `${maxShift.toFixed(1)}px`);
    };

    updateTrackShift();

    const ro = new ResizeObserver(updateTrackShift);
    if (conveyorRef.current) ro.observe(conveyorRef.current);
    if (trackRef.current) ro.observe(trackRef.current);

    window.addEventListener('resize', updateTrackShift);

    return () => {
      ro.disconnect();
      window.removeEventListener('resize', updateTrackShift);
    };
  }, [t.pipelineStages]);

  useEffect(() => {
    // Below this width the CSS drops the pin (see `--pin-breakpoint` note), so
    // there is barely any sticky range left to measure — reading progress the
    // pinned way made the rail shoot from empty to full in a third of a screen.
    const unpinned = window.matchMedia('(max-width: 780px)');
    let isUnpinned = unpinned.matches;
    const onMediaChange = (e: MediaQueryListEvent) => {
      isUnpinned = e.matches;
    };
    unpinned.addEventListener('change', onMediaChange);

    const stop = subscribeScroll(() => {
      const el = wrapRef.current;
      if (!el) return;

      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight;

      // Which step is lit follows the section as a whole, so each card lights
      // up around the time it comes into view.
      const stageProgress = isUnpinned
        ? clamp01((vh - rect.top) / Math.max(1, rect.height + vh * 0.2))
        : clamp01(-rect.top / Math.max(1, rect.height - vh));

      // The rail is anchored to the machine itself. Measuring it against the
      // section meant the rail was already ~80% full the moment it first
      // appeared at the bottom of a phone screen.
      const machine = machineRef.current;
      const railProgress =
        isUnpinned && machine
          ? clamp01((vh - machine.getBoundingClientRect().top) / Math.max(1, vh * 0.82))
          : stageProgress;

      el.style.setProperty('--pp', railProgress.toFixed(4));

      const next = stageProgress < 0.3 ? 0 : stageProgress < 0.62 ? 1 : 2;
      setStage((prev) => (prev === next ? prev : next));
    });

    return () => {
      unpinned.removeEventListener('change', onMediaChange);
      stop();
    };
  }, []);

  return (
    <section className="pipe-wrap" ref={wrapRef} id="how">
      <div className="pipe-pin">
        <div className="container">
          <header className="section-head reveal">
            <span className="eyebrow">
              <i className="eyebrow-bar" />
              {t.eyebrow}
            </span>
            <h2 className="section-title">{t.heading}</h2>
          </header>

          <ol className="pipe-steps">
            {t.steps.map((step, i) => (
              <li
                key={i}
                className={`pipe-step reveal${i <= stage ? ' is-lit' : ''}${
                  i === stage ? ' is-active' : ''
                }`}
                style={{ '--d': `${i * 90}ms` } as React.CSSProperties}
              >
                <span className="pipe-step-no">{String(i + 1).padStart(2, '0')}</span>
                <span className="pipe-step-when">{step.when}</span>
                <h3 className="pipe-step-title">{step.title}</h3>
                <p className="pipe-step-body">{step.body}</p>
              </li>
            ))}
          </ol>

          <div className="pipe-machine reveal" ref={machineRef}>
            <div className="pipe-machine-head">
              <span className="pipe-gear" aria-hidden="true">
                ⚙️
              </span>
              <span className="pipe-machine-label">{t.pipelineLabel}</span>
            </div>

            <div className="pipe-rail">
              <div className="pipe-rail-fill" />
              <div className="pipe-rail-comet" />
            </div>

            <div className="pipe-conveyor" aria-hidden="true" ref={conveyorRef}>
              <div className="pipe-conveyor-track" ref={trackRef}>
                {t.pipelineStages.map((label, i) => (
                  <span
                    key={i}
                    className="pipe-chip"
                    style={{ '--i': i } as React.CSSProperties}
                  >
                    {label}
                  </span>
                ))}
              </div>
            </div>

            <p className="pipe-note">{t.pipelineNote}</p>
          </div>

          <p className={`pipe-result${stage >= 2 ? ' is-shown' : ''}`}>{t.result}</p>
        </div>
      </div>
    </section>
  );
};
