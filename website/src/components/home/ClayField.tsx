import React, { useEffect, useRef } from 'react';
import { subscribeMouse } from '../../lib/mouseBus';

/**
 * The "cosmic toybox" from the app's intro slide: 3D clay assets that pop out
 * of the galaxy, drift in zero gravity, react to mouse movement with subtle depth parallax,
 * then scatter outward and fade as you scroll past the hero.
 */

interface Piece {
  src: string;
  /** Position within the hero, as CSS percentages. */
  x: string;
  y: string;
  size: number;
  /** Where the piece flies to as the hero scrolls away. */
  dx: number;
  dy: number;
  glow: string;
  tilt: number;
  /** Pop-in order, mirroring the app's staggered burst. */
  delay: number;
  /** Subtle mouse parallax intensity factors (different depths for 3D feel). */
  parallaxFactor: number;
}

const PIECES: Piece[] = [
  {
    src: '/img/clay/rocket.webp',
    x: '7%',
    y: '17%',
    size: 122,
    dx: -170,
    dy: -130,
    glow: '#FF8C42',
    tilt: -14,
    delay: 0,
    parallaxFactor: 14, // foreground subtle
  },
  {
    src: '/img/clay/earth.webp',
    x: '80%',
    y: '13%',
    size: 138,
    dx: 185,
    dy: -140,
    glow: '#5FD9C4',
    tilt: 10,
    delay: 0.09,
    parallaxFactor: -12, // mid-background subtle
  },
  {
    src: '/img/clay/books.webp',
    x: '5%',
    y: '62%',
    size: 116,
    dx: -195,
    dy: 150,
    glow: '#4DD0E1',
    tilt: 8,
    delay: 0.17,
    parallaxFactor: -15, // deeper subtle
  },
  {
    src: '/img/clay/headphones.webp',
    x: '82%',
    y: '61%',
    size: 118,
    dx: 205,
    dy: 160,
    glow: '#B388FF',
    tilt: -9,
    delay: 0.24,
    parallaxFactor: 13, // foreground subtle
  },
];

export const ClayField: React.FC = () => {
  const fieldRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    return subscribeMouse((mx, my) => {
      const el = fieldRef.current;
      if (!el) return;
      el.style.setProperty('--mouse-x', mx.toFixed(4));
      el.style.setProperty('--mouse-y', my.toFixed(4));
    });
  }, []);

  return (
    <div className="clay-field" ref={fieldRef} aria-hidden="true">
      {PIECES.map((piece) => (
        <div
          key={piece.src}
          className="clay"
          style={
            {
              '--x': piece.x,
              '--y': piece.y,
              '--size': `${piece.size}px`,
              '--dx': `${piece.dx}px`,
              '--dy': `${piece.dy}px`,
              '--glow': piece.glow,
              '--tilt': `${piece.tilt}deg`,
              '--delay': `${piece.delay}s`,
              '--pf': String(piece.parallaxFactor),
            } as React.CSSProperties
          }
        >
          <div className="clay-float">
            <img src={piece.src} alt="" loading="eager" decoding="async" />
          </div>
        </div>
      ))}
    </div>
  );
};
