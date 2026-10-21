import React, { useEffect, useRef } from 'react';
import { ChatWorld } from './LaunchGateBackdrop';

interface ThinkingNebulaProps {
  world?: ChatWorld;
  size?: number;
  className?: string;
}

const TAU = Math.PI * 2;
const WHITE: [number, number, number] = [255, 255, 255];
const PAPER: [number, number, number] = [250, 245, 233];
const INK: [number, number, number] = [62, 50, 40];

const PALETTES = {
  universe: {
    gold: [255, 179, 0] as [number, number, number],
    blue: [66, 165, 245] as [number, number, number],
    lilac: [179, 157, 219] as [number, number, number],
    mint: [128, 222, 234] as [number, number, number],
    rose: [244, 143, 177] as [number, number, number],
  },
  paper: {
    gold: [204, 141, 0] as [number, number, number],
    blue: [30, 112, 196] as [number, number, number],
    lilac: [118, 86, 178] as [number, number, number],
    mint: [0, 137, 150] as [number, number, number],
    rose: [196, 78, 116] as [number, number, number],
  },
};

const rgba = (c: [number, number, number], a: number) =>
  `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`;

const mix = (
  a: [number, number, number],
  b: [number, number, number],
  t: number
): [number, number, number] => [
  a[0] + (b[0] - a[0]) * t,
  a[1] + (b[1] - a[1]) * t,
  a[2] + (b[2] - a[2]) * t,
];

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const ease = (t: number) =>
  t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

function glowDot(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  r: number,
  c: [number, number, number],
  a = 1
) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r * 3.6);
  g.addColorStop(0, rgba(c, a * 0.9));
  g.addColorStop(0.3, rgba(c, a * 0.35));
  g.addColorStop(1, rgba(c, 0));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(x, y, r * 3.6, 0, TAU);
  ctx.fill();
  ctx.fillStyle = rgba(mix(c, WHITE, 0.6), a);
  ctx.beginPath();
  ctx.arc(x, y, Math.max(0.6, r), 0, TAU);
  ctx.fill();
}

function inkDot(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  r: number,
  c: [number, number, number],
  a = 1
) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r * 2.6);
  g.addColorStop(0, rgba(c, a * 0.22));
  g.addColorStop(1, rgba(c, 0));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(x, y, r * 2.6, 0, TAU);
  ctx.fill();
  ctx.fillStyle = rgba(c, a);
  ctx.beginPath();
  ctx.arc(x, y, Math.max(0.7, r * 1.05), 0, TAU);
  ctx.fill();
}

const B_N = 200;
function shape(fn: (th: number) => number) {
  const r = new Float32Array(B_N);
  let max = 0;
  for (let i = 0; i < B_N; i++) {
    r[i] = fn((i / B_N) * TAU);
    max = Math.max(max, r[i]);
  }
  for (let i = 0; i < B_N; i++) r[i] /= max || 1;
  return r;
}

const lobes = (b: number, a: number, k: number, p: number) => (th: number) =>
  b + a * Math.pow(Math.abs(Math.cos((k * th) / 2)), p);

const SHAPES: Record<string, { name: string; r: Float32Array }> = {
  planet: { name: '惑星', r: shape(() => 1) },
  sparkle: { name: '光芒', r: shape(lobes(0.3, 0.7, 4, 9)) },
  flower: { name: '花', r: shape(lobes(0.6, 0.4, 6, 2.2)) },
  trefoil: { name: '三つ葉', r: shape(lobes(0.5, 0.5, 3, 1.3)) },
  star5: { name: '五芒星', r: shape(lobes(0.42, 0.58, 5, 2.6)) },
  rays8: { name: '八方の光', r: shape(lobes(0.28, 0.72, 8, 14)) },
  saturn: {
    name: '土星',
    r: shape((th) => {
      const phi = -0.35;
      const c = Math.cos(th - phi);
      const s = Math.sin(th - phi);
      return Math.max(1 / Math.sqrt(c * c + Math.pow(s / 0.3, 2)), 0.58);
    }),
  },
  binary: { name: '連星', r: shape(lobes(0.55, 0.45, 2, 1.6)) },
  corona: { name: '太陽のコロナ', r: shape(lobes(0.82, 0.18, 12, 1.2)) },
  comet: {
    name: '彗星',
    r: shape((th) => 0.5 + 0.5 * Math.pow((1 + Math.cos(th)) / 2, 4)),
  },
};

const SHAPE_KEYS = Object.keys(SHAPES);
const COLOR_KEYS = ['gold', 'blue', 'lilac', 'mint', 'rose'] as const;
type ColorKey = (typeof COLOR_KEYS)[number];

const SEG = 2.0;
const TRANS = 0.85;

function blobPath(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  R: number,
  rf: Float32Array,
  rt: Float32Array,
  m: number,
  rot: number
) {
  ctx.beginPath();
  for (let i = 0; i <= B_N; i++) {
    const j = i % B_N;
    const th = (j / B_N) * TAU + rot;
    const r = lerp(rf[j], rt[j], m) * R;
    const x = cx + Math.cos(th) * r;
    const y = cy + Math.sin(th) * r;
    if (i) ctx.lineTo(x, y);
    else ctx.moveTo(x, y);
  }
  ctx.closePath();
}

function paintBlob(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  s: number,
  col: [number, number, number],
  rf: Float32Array,
  rt: Float32Array,
  m: number,
  m2: number,
  t: number,
  satellites: boolean,
  paper: boolean
) {
  const R = s * 0.72 * (1 + 0.035 * Math.sin((t * TAU) / 3));
  const rot = t * 0.25;

  const halo = ctx.createRadialGradient(cx, cy, 0, cx, cy, s);
  halo.addColorStop(0, rgba(col, paper ? 0.13 : 0.24));
  halo.addColorStop(1, rgba(col, 0));
  ctx.fillStyle = halo;
  ctx.fillRect(cx - s, cy - s, s * 2, s * 2);

  const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, R);
  if (paper) {
    g.addColorStop(0, rgba(mix(col, PAPER, 0.78), 0.95));
    g.addColorStop(0.55, rgba(mix(col, PAPER, 0.4), 0.9));
    g.addColorStop(1, rgba(col, 0.88));
  } else {
    g.addColorStop(0, 'rgba(255,255,255,.95)');
    g.addColorStop(0.35, rgba(mix(col, WHITE, 0.45), 0.92));
    g.addColorStop(1, rgba(col, 0.5));
  }
  blobPath(ctx, cx, cy, R, rf, rt, m, rot);
  ctx.fillStyle = g;
  ctx.fill();

  if (paper) {
    ctx.strokeStyle = rgba(mix(col, INK, 0.35), 0.5);
    ctx.lineWidth = Math.max(0.7, s * 0.012);
    ctx.stroke();
  }

  blobPath(ctx, cx, cy, R * 0.48, rf, rt, m2, -rot * 1.6);
  ctx.fillStyle = paper ? 'rgba(255,255,255,.5)' : 'rgba(255,255,255,.3)';
  ctx.fill();

  if (!satellites) return;
  for (let k = 0; k < 3; k++) {
    const a = t * (0.8 + k * 0.25) + (k * TAU) / 3;
    const x = cx + Math.cos(a) * s * 0.9;
    const y = cy + Math.sin(a) * s * 0.9 * 0.85;
    if (paper) {
      inkDot(ctx, x, y, s * 0.028, mix(col, INK, 0.25), 0.9);
    } else {
      glowDot(ctx, x, y, s * 0.03, mix(col, WHITE, 0.3), 0.9);
    }
  }
}

export const ThinkingNebula: React.FC<ThinkingNebulaProps> = ({
  world = 'universe',
  size = 34,
  className = '',
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  // コンポーネントごとに独立したランダムシーケンスを生成・保持
  const seqRef = useRef<{
    shapes: string[];
    colors: ColorKey[];
    seed: number;
  }>({
    shapes: [],
    colors: [],
    seed: Math.floor(Math.random() * 1e9),
  });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animId: number;
    const reduceMotion = window.matchMedia(
      '(prefers-reduced-motion: reduce)'
    ).matches;
    const speed = reduceMotion ? 0.25 : 1;
    const startTime = performance.now();

    const seq = seqRef.current;
    const ensure = (n: number) => {
      while (seq.shapes.length <= n) {
        const ps = seq.shapes[seq.shapes.length - 1];
        const pc = seq.colors[seq.colors.length - 1];
        let s: string;
        let c: ColorKey;
        do {
          s = SHAPE_KEYS[Math.floor(Math.random() * SHAPE_KEYS.length)];
        } while (s === ps);
        do {
          c = COLOR_KEYS[Math.floor(Math.random() * COLOR_KEYS.length)];
        } while (c === pc);
        seq.shapes.push(s);
        seq.colors.push(c);
      }
    };
    ensure(3);

    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(size * dpr);
    canvas.height = Math.round(size * dpr);

    const render = (now: number) => {
      const elapsed = ((now - startTime) / 1000) * speed;
      const tt = Math.max(0, elapsed) + SEG;
      const n = Math.floor(tt / SEG);
      const sec = tt - n * SEG;
      ensure(n + 1);

      const m = ease(clamp(sec / TRANS));
      const m2 = ease(clamp((sec - 0.2) / TRANS));

      const isPaper = world === 'paper';
      const P = isPaper ? PALETTES.paper : PALETTES.universe;
      const colFrom = P[seq.colors[n - 1]];
      const colTo = P[seq.colors[n]];
      const col = mix(colFrom, colTo, m);

      const rf = SHAPES[seq.shapes[n - 1]].r;
      const rt = SHAPES[seq.shapes[n]].r;

      ctx.save();
      ctx.scale(dpr, dpr);
      ctx.clearRect(0, 0, size, size);

      paintBlob(
        ctx,
        size / 2,
        size / 2,
        size / 2,
        col,
        rf,
        rt,
        m,
        m2,
        elapsed,
        true,
        isPaper
      );

      ctx.restore();
      animId = requestAnimationFrame(render);
    };

    animId = requestAnimationFrame(render);

    return () => {
      cancelAnimationFrame(animId);
    };
  }, [world, size]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width: size, height: size }}
      className={`chat-thinking-nebula ${className}`}
      aria-hidden="true"
    />
  );
};
