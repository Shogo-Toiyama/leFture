import React, { useMemo } from 'react';

/**
 * The gold equaliser from the app's recording screen, rebuilt in CSS.
 *
 * Bar heights follow the same shape the Flutter painter uses: a sine envelope
 * that peaks in the middle, plus a deterministic jitter so it reads as real
 * audio rather than a smooth curve. Each bar animates on its own delay, so the
 * band is never still.
 */

const BAR_COUNT = 33;

function buildLevels(count: number): number[] {
  // Fixed pseudo-random jitter — same shape on every render, no hydration drift.
  let seed = 12;
  const rand = () => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed / 2147483648;
  };

  return Array.from({ length: count }, (_, i) => {
    const centered = 1 - Math.abs(i - count / 2) / (count / 2);
    const envelope = Math.sin(Math.max(0, centered) * (Math.PI / 2));
    return Math.min(1, Math.max(0.12, (0.24 + envelope * 0.62 + rand() * 0.18) * envelope));
  });
}

export const Waveform: React.FC<{ className?: string }> = ({ className }) => {
  const levels = useMemo(() => buildLevels(BAR_COUNT), []);

  return (
    <div className={`waveform ${className ?? ''}`} aria-hidden="true">
      {levels.map((level, i) => (
        <span
          key={i}
          className="waveform-bar"
          style={
            {
              '--level': level.toFixed(3),
              '--delay': `${(i * 0.062).toFixed(3)}s`,
              '--dur': `${(1.5 + (i % 5) * 0.14).toFixed(2)}s`,
            } as React.CSSProperties
          }
        />
      ))}
    </div>
  );
};
