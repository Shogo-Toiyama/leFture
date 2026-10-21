import React, { useEffect, useRef } from 'react';

export type ChatWorld = 'universe' | 'paper';

interface LaunchGateBackdropProps {
  world?: ChatWorld;
  className?: string;
}

const TAU = Math.PI * 2;
const WHITE: [number, number, number] = [255, 255, 255];
const INK: [number, number, number] = [62, 50, 40];
const PALETTES = {
  dark: {
    gold: [255, 179, 0] as [number, number, number],
    blue: [66, 165, 245] as [number, number, number],
  },
  paper: {
    gold: [255, 179, 0] as [number, number, number],
    deepGold: [204, 141, 0] as [number, number, number],
    sky: [92, 150, 214] as [number, number, number],
    lime: [168, 205, 96] as [number, number, number],
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

const ease = (t: number) =>
  t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

function rand(seed: number) {
  let s = seed | 0;
  return function () {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Star {
  x: number;
  y: number;
  r: number;
  sp: number;
  ph: number;
}

function makeStars(n: number, seed: number): Star[] {
  const r = rand(seed);
  const out: Star[] = [];
  for (let i = 0; i < n; i++) {
    out.push({
      x: r(),
      y: r(),
      r: 0.35 + r() * 1.05,
      sp: 0.6 + r() * 1.8,
      ph: r() * TAU,
    });
  }
  return out;
}

const GATE_STARS = makeStars(110, 11);

const DAWN_STARS: [number, number, number, number][] = [
  [0.14, 0.07, 1.5, 1.7],
  [0.36, 0.04, 1.1, 2.3],
  [0.6, 0.16, 1.3, 1.9],
  [0.9, 0.24, 1.05, 2.6],
];

function planetGeom(w: number, h: number) {
  const R = w * 1.25;
  const cx = w * 0.62;
  const cy = h * 0.4 + R;
  const fx = w * 0.4;
  const fy = cy - Math.sqrt(Math.max(0, R * R - (fx - cx) ** 2));
  return { R, cx, cy, fx, fy };
}

function shootingStar(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  t: number,
  color: [number, number, number]
) {
  const per = 4.6;
  const k = t % per;
  if (k >= 1) return;
  const th = (24 * Math.PI) / 180;
  const dx = Math.cos(th);
  const dy = Math.sin(th);
  const dist = Math.min((w * 0.5) / dx, (h * 0.34) / dy);
  const x0 = w * 0.25 + (w * 0.5 - dist * dx) / 2;
  const y0 = h * 0.04;
  const p = ease(k);
  const x = x0 + dx * dist * p;
  const y = y0 + dy * dist * p;
  const len = dist * 0.36 * Math.sin(Math.PI * k);
  const tx = x - dx * len;
  const ty = y - dy * len;
  const g = ctx.createLinearGradient(x, y, tx, ty);
  g.addColorStop(0, rgba(color, 0.95));
  g.addColorStop(1, rgba(color, 0));
  ctx.strokeStyle = g;
  ctx.lineWidth = 1.6;
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.lineTo(tx, ty);
  ctx.stroke();
}

function inkDot(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  r: number,
  c: [number, number, number],
  a = 1,
  bright = false
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
  if (bright) {
    ctx.strokeStyle = rgba(c, a * 0.55);
    ctx.lineWidth = Math.max(0.6, r * 0.35);
    ctx.beginPath();
    ctx.moveTo(x - r * 2.8, y);
    ctx.lineTo(x + r * 2.8, y);
    ctx.moveTo(x, y - r * 2.8);
    ctx.lineTo(x, y + r * 2.8);
    ctx.stroke();
  }
}

function drawGateNight(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  t: number
) {
  const gold = PALETTES.dark.gold;
  const blue = PALETTES.dark.blue;
  const bg = ctx.createLinearGradient(0, 0, 0, h);
  bg.addColorStop(0, '#0B0E1C');
  bg.addColorStop(1, '#141936');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, w, h);

  for (const st of GATE_STARS) {
    const a = 0.2 + 0.6 * (0.5 + 0.5 * Math.sin(t * st.sp + st.ph));
    ctx.fillStyle = `rgba(236,240,255,${a})`;
    ctx.beginPath();
    ctx.arc(st.x * w, st.y * h * 0.42, st.r, 0, TAU);
    ctx.fill();
  }

  shootingStar(ctx, w, h, t, WHITE);

  const { R, cx, cy, fx, fy } = planetGeom(w, h);
  const pulse = 0.72 + 0.28 * Math.sin(t * 1.1);
  const atm = ctx.createRadialGradient(cx, cy, R * 0.97, cx, cy, R * 1.13);
  atm.addColorStop(0, rgba(gold, 0));
  atm.addColorStop(0.22, rgba(gold, 0.3 * pulse));
  atm.addColorStop(0.55, rgba(blue, 0.13 * pulse));
  atm.addColorStop(1, rgba(blue, 0));
  ctx.fillStyle = atm;
  ctx.beginPath();
  ctx.arc(cx, cy, R * 1.13, 0, TAU);
  ctx.fill();

  const body = ctx.createLinearGradient(0, cy - R, 0, h);
  body.addColorStop(0, '#1C2550');
  body.addColorStop(0.12, '#0F1430');
  body.addColorStop(1, '#0B0E1D');
  ctx.fillStyle = body;
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, TAU);
  ctx.fill();

  const rim = ctx.createLinearGradient(0, 0, w, 0);
  rim.addColorStop(0, rgba(blue, 0.2));
  rim.addColorStop(0.42, rgba(gold, 0.95 * pulse));
  rim.addColorStop(1, rgba(blue, 0.25));
  ctx.strokeStyle = rim;
  ctx.lineWidth = 1.6;
  ctx.beginPath();
  ctx.arc(cx, cy, R, Math.PI * 1.2, Math.PI * 1.8);
  ctx.stroke();

  const fl = ctx.createRadialGradient(fx, fy, 0, fx, fy, w * 0.18);
  fl.addColorStop(0, `rgba(255,236,190,${0.9 * pulse})`);
  fl.addColorStop(0.2, rgba(gold, 0.35 * pulse));
  fl.addColorStop(1, rgba(gold, 0));
  ctx.fillStyle = fl;
  ctx.fillRect(fx - w * 0.2, fy - w * 0.2, w * 0.4, w * 0.4);
}

function drawGateDawn(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  t: number
) {
  const gold = PALETTES.paper.gold;
  const deepGold = PALETTES.paper.deepGold;
  const sky = PALETTES.paper.sky;
  const lime = PALETTES.paper.lime;

  const bg = ctx.createLinearGradient(0, 0, 0, h * 0.5);
  bg.addColorStop(0, '#FAF5E9');
  bg.addColorStop(0.55, '#FBF0DE');
  bg.addColorStop(1, '#FBE3C4');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, w, h);

  for (const st of GATE_STARS) {
    const y = st.y * h * 0.3;
    const fade = 1 - y / (h * 0.3);
    const a = (0.15 + 0.3 * (0.5 + 0.5 * Math.sin(t * st.sp + st.ph))) * fade;
    ctx.fillStyle = rgba(INK, a * 0.6);
    ctx.beginPath();
    ctx.arc(st.x * w, y, st.r * 0.7, 0, TAU);
    ctx.fill();
  }

  const { R, cx, cy, fx, fy } = planetGeom(w, h);
  const pulse = 0.75 + 0.25 * Math.sin(t * 1.1);
  const rise = 0.5 + 0.5 * Math.sin(t * 0.35);

  const glow = ctx.createRadialGradient(fx, fy, 0, fx, fy, w * 0.62);
  glow.addColorStop(0, rgba(gold, 0.5 * pulse));
  glow.addColorStop(0.35, rgba([255, 200, 120], 0.22 * pulse));
  glow.addColorStop(1, rgba([255, 220, 170], 0));
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, w, h);

  ctx.save();
  ctx.translate(fx, fy);
  ctx.rotate(t * 0.04);
  ctx.strokeStyle = rgba(deepGold, 0.16);
  ctx.lineWidth = 1;
  for (let k = 0; k < 36; k++) {
    const a = (k * TAU) / 36;
    ctx.beginPath();
    ctx.moveTo(Math.cos(a) * w * 0.1, Math.sin(a) * w * 0.1);
    ctx.lineTo(Math.cos(a) * w * 0.42, Math.sin(a) * w * 0.42);
    ctx.stroke();
  }
  ctx.restore();

  const sunR = w * 0.085;
  const sunY = fy + sunR * (0.55 - 0.25 * rise);
  const sun = ctx.createRadialGradient(fx, sunY, 0, fx, sunY, sunR);
  sun.addColorStop(0, 'rgba(255,246,220,1)');
  sun.addColorStop(0.6, 'rgba(255,205,90,1)');
  sun.addColorStop(1, 'rgba(255,179,0,.95)');
  ctx.fillStyle = sun;
  ctx.beginPath();
  ctx.arc(fx, sunY, sunR, 0, TAU);
  ctx.fill();

  ctx.fillStyle = '#FAF5E9';
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, TAU);
  ctx.fill();

  const edge = ctx.createRadialGradient(cx, cy, R * 0.86, cx, cy, R);
  edge.addColorStop(0, rgba(lime, 0));
  edge.addColorStop(0.38, rgba(lime, 0.13));
  edge.addColorStop(0.7, rgba(mix(lime, sky, 0.5), 0.24));
  edge.addColorStop(1, rgba(sky, 0.38));
  ctx.fillStyle = edge;
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, TAU);
  ctx.fill();

  const rimLine = ctx.createLinearGradient(0, 0, w, 0);
  rimLine.addColorStop(0, rgba(sky, 0.5));
  rimLine.addColorStop(0.4, rgba(deepGold, 0.9 * pulse));
  rimLine.addColorStop(1, rgba(sky, 0.55));
  ctx.strokeStyle = rimLine;
  ctx.lineWidth = 1.6;
  ctx.beginPath();
  ctx.arc(cx, cy, R, Math.PI * 1.2, Math.PI * 1.8);
  ctx.stroke();

  for (const [sx, sy, sr, sp] of DAWN_STARS) {
    const a = 0.55 + 0.35 * (0.5 + 0.5 * Math.sin(t * sp + sx * 9));
    inkDot(
      ctx,
      sx * w,
      sy * h,
      sr * (1 + 0.15 * Math.sin(t * sp * 1.3 + sy * 7)),
      INK,
      a,
      sr >= 1.4
    );
  }
  const vx = w * 0.8;
  const vy = h * 0.12;
  const vr = 2.2 * (1 + 0.25 * Math.sin(t * 2.3));
  inkDot(ctx, vx, vy, vr, deepGold, 1, true);
}

export const LaunchGateBackdrop: React.FC<LaunchGateBackdropProps> = ({
  world = 'universe',
  className = '',
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

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

    const drawFrame = (now: number) => {
      const elapsed = ((now - startTime) / 1000) * speed;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = canvas.width / dpr;
      const h = canvas.height / dpr;

      if (w > 0 && h > 0) {
        // 横幅が広がるにつれて透明度を少し上げて（opacityを下げて）背景の主張を抑える
        // 440px以下: 1.0 (標準) / 960px以上: 0.65 (広い画面向けに控えめ)
        const targetOpacity = Math.max(
          0.65,
          Math.min(1.0, 1.0 - Math.max(0, (w - 440) / 520) * 0.35)
        );
        canvas.style.opacity = targetOpacity.toFixed(3);

        ctx.save();
        ctx.scale(dpr, dpr);
        ctx.clearRect(0, 0, w, h);
        if (world === 'paper') {
          drawGateDawn(ctx, w, h, elapsed);
        } else {
          drawGateNight(ctx, w, h, elapsed);
        }
        ctx.restore();
      }
    };

    const resizeAndDraw = () => {
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = Math.round(rect.width * dpr);
      const h = Math.round(rect.height * dpr);
      if (w <= 0 || h <= 0) return;

      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
      }
      // リサイズ時も即座に描画することで、スライダー操作中の背景の消失やチラつきを防ぐ
      drawFrame(performance.now());
    };

    resizeAndDraw();
    const observer = new ResizeObserver(() => resizeAndDraw());
    observer.observe(canvas);

    const render = (now: number) => {
      // 毎フレームの描画前にサイズずれを検知
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = Math.round(rect.width * dpr);
      const h = Math.round(rect.height * dpr);
      if (w > 0 && h > 0 && (canvas.width !== w || canvas.height !== h)) {
        canvas.width = w;
        canvas.height = h;
      }

      drawFrame(now);
      animId = requestAnimationFrame(render);
    };

    animId = requestAnimationFrame(render);

    return () => {
      cancelAnimationFrame(animId);
      observer.disconnect();
    };
  }, [world]);

  return (
    <canvas
      ref={canvasRef}
      className={`chat-launch-gate-canvas ${className}`}
      aria-hidden="true"
    />
  );
};
