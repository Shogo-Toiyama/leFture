import React, { useEffect, useRef } from 'react';

/**
 * Home画面の「ミニ銀河」。website/src/components/home/GalaxyCanvas.tsx をそのまま移植したもの
 * (ユーザー指定: 「あの銀河がウェブ用に完璧」)。生成アルゴリズム・パレット・投影計算は同一。
 *
 * marketing siteのGalaxyCanvasはページスクロールに連動してズーム/フェードするフルスクリーン
 * ヒーロー背景だったが、ここでは固定高さのパネル(モバイル版 galaxy_view.dart の
 * ミニギャラクシーと同じ用途)として使うため、scrollBus依存とスクロール連動のズーム/フェードは
 * 取り除き、常時オートローテーション + コンテナ内ポインター視差 + 流れ星のみを残した。
 */

const VOID_COLOR = '#111422';
const STAR_PALETTE = ['#FFFFFF', '#B7D8FF', '#FFE7B0', '#FFB7B7'];
const NEBULA_PALETTE = ['#FF5FA2', '#FF9A3D', '#B86BFF', '#4FA8FF'];
const SHOOTING_PALETTE = ['#FFB300', '#FFD166', '#FFFFFF', '#4AA8FF', '#B98BFF'];

const BASE_PITCH = 0.48;
const BASE_ROLL = -0.16;
const AUTO_SPIN = 0.06;
const FOV = 1.2;
const NEBULA_SCALE = 0.5;
const CORE_PINK_OPACITY = 0.8;
const CORE_PINK_SCALE = 0.8;
const CORE_BLUE_OPACITY = 0.8;
const CORE_BLUE_SCALE = 1.0;
const STAR_SCALE = 1.7;

function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

function clamp01(v: number): number {
  return Math.min(1, Math.max(0, v));
}

function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = clamp01((x - edge0) / (edge1 - edge0));
  return t * t * (3 - 2 * t);
}

interface Counts {
  bulge: number;
  disk: number;
  nebula: number;
  bg: number;
}

function pickCounts(width: number): Counts {
  if (width < 500) return { bulge: 900, disk: 2400, nebula: 7, bg: 260 };
  if (width < 900) return { bulge: 1300, disk: 3600, nebula: 10, bg: 400 };
  return { bulge: 1700, disk: 4800, nebula: 12, bg: 520 };
}

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Stars {
  x: Float32Array;
  y: Float32Array;
  z: Float32Array;
  size: Float32Array;
  bright: Float32Array;
  type: Uint8Array;
  count: number;
}

interface Nebula {
  x: Float32Array;
  y: Float32Array;
  z: Float32Array;
  radius: Float32Array;
  alpha: Float32Array;
  color: Uint8Array;
  count: number;
}

interface BgStars {
  x01: Float32Array;
  y01: Float32Array;
  r: Float32Array;
  alpha: Float32Array;
  phase: Float32Array;
  count: number;
}

function buildStars(counts: Counts, seed = 42): Stars {
  const total = counts.bulge + counts.disk;
  const x = new Float32Array(total);
  const y = new Float32Array(total);
  const z = new Float32Array(total);
  const size = new Float32Array(total);
  const bright = new Float32Array(total);
  const type = new Uint8Array(total);

  const rnd = mulberry32(seed);
  const randNorm = () => {
    const u1 = Math.max(rnd(), 1e-9);
    const u2 = rnd();
    return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  };

  const radius = 1.0;
  const thickness = 0.05;
  const bulgeRadiusNorm = 0.2;
  const innerDiskHoleNorm = 0.14;
  const arms = 3;
  const spiralTightness = 5.0;

  let i = 0;

  for (let n = 0; n < counts.bulge; n++, i++) {
    const uOuter = 0.75 * (1 - Math.pow(rnd(), 2.6));
    const uInner = Math.pow(rnd(), 1.7);
    const u = rnd() < 0.28 ? uInner : uOuter;

    const maxR = radius * bulgeRadiusNorm;
    const r = u * maxR;
    const theta = rnd() * Math.PI * 2;
    const phi = Math.acos(2 * rnd() - 1) - Math.PI / 2;

    x[i] = r * Math.cos(phi) * Math.cos(theta);
    y[i] = r * Math.sin(phi) * 0.45;
    z[i] = r * Math.cos(phi) * Math.sin(theta);

    const distNorm = r / maxR;
    size[i] = (0.7 + Math.pow(1 - distNorm, 1.4) * 1.8 + rnd() * 0.6) * 2;
    bright[i] = 0.55 + Math.pow(1 - distNorm, 1.2) * 0.45;

    const p = rnd();
    type[i] = p < 0.32 ? 0 : p < 0.68 ? 2 : p < 0.88 ? 1 : 3;
  }

  for (let n = 0; n < counts.disk; n++, i++) {
    const u = Math.pow(rnd(), 1.4);
    const minR = radius * innerDiskHoleNorm;
    const r = minR + u * (radius - minR);

    const armIndex = Math.floor(rnd() * arms);
    const armOffset = (armIndex * 2 * Math.PI) / arms;
    const thetaSpiral = spiralTightness * Math.log(Math.max(r / minR, 1e-4)) + armOffset;

    const spreadFactor = 0.1 + (r / radius) * 0.14;
    const thetaOffset = randNorm() * spreadFactor;
    const theta = thetaSpiral + thetaOffset;

    const rWander = r + randNorm() * 0.035 * (r / radius);

    x[i] = rWander * Math.cos(theta);
    y[i] = randNorm() * thickness * (0.35 + 0.65 * (r / radius));
    z[i] = rWander * Math.sin(theta);

    const distNorm = r / radius;
    size[i] = (0.38 + (1 - distNorm) * 1.3 + Math.pow(rnd(), 3) * 1.4) * 2;
    bright[i] = 0.35 + (1 - distNorm) * 0.45 + rnd() * 0.2;

    const p = rnd();
    type[i] = p < 0.32 ? 1 : p < 0.65 ? 0 : p < 0.88 ? 2 : 3;
  }

  return { x, y, z, size, bright, type, count: total };
}

function buildNebula(count: number, seed = 77): Nebula {
  const x = new Float32Array(count);
  const y = new Float32Array(count);
  const z = new Float32Array(count);
  const radius = new Float32Array(count);
  const alpha = new Float32Array(count);
  const color = new Uint8Array(count);

  const rnd = mulberry32(seed + 999);
  const randNorm = () => {
    const u1 = Math.max(rnd(), 1e-9);
    const u2 = rnd();
    return Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math.PI * u2);
  };

  const arms = 3;
  const spiralTightness = 5.0;
  const innerStartNorm = 0.1;
  const galaxyRadius = 0.9;
  const thickness = 0.05;

  for (let i = 0; i < count; i++) {
    const t = rnd();
    const rNormRaw = Math.pow(t, 0.55);
    const rNorm = innerStartNorm + (1 - innerStartNorm) * rNormRaw;
    const r = galaxyRadius * rNorm;

    const armIndex = Math.floor(rnd() * arms);
    const baseAngle = (armIndex / arms) * 2.0 * Math.PI;

    const angleNoise = 0.12 + 0.4 * rNorm;
    const angle = baseAngle + r * spiralTightness + randNorm() * angleNoise;

    const posNoise = 0.015 + 0.06 * rNorm;
    x[i] = r * Math.cos(angle) + randNorm() * posNoise;
    y[i] = randNorm() * thickness * (0.4 + 0.8 * (1 - rNorm));
    z[i] = r * Math.sin(angle) + randNorm() * posNoise;

    radius[i] = (0.18 + 0.29 * rNorm) * (0.8 + rnd() * 0.8);
    alpha[i] = Math.max(0.1, Math.min(0.5, 0.18 + 0.3 * (1 - rNorm) + rnd() * 0.1));

    const p = rnd();
    color[i] = p < 0.45 ? 0 : p < 0.75 ? 1 : p < 0.92 ? 2 : 3;
  }

  return { x, y, z, radius, alpha, color, count };
}

function buildBgStars(count: number, seed = 123): BgStars {
  const rnd = mulberry32(seed);
  const x01 = new Float32Array(count);
  const y01 = new Float32Array(count);
  const r = new Float32Array(count);
  const alpha = new Float32Array(count);
  const phase = new Float32Array(count);

  for (let i = 0; i < count; i++) {
    x01[i] = rnd();
    y01[i] = rnd();
    r[i] = 0.5 + Math.pow(rnd(), 2.5) * 1.6;
    alpha[i] = 0.35 + Math.pow(rnd(), 2.0) * 0.65;
    phase[i] = rnd() * Math.PI * 2;
  }

  return { x01, y01, r, alpha, phase, count };
}

function hexToRgba(hex: string, alpha: number): string {
  const v = hex.replace('#', '');
  const r = parseInt(v.slice(0, 2), 16);
  const g = parseInt(v.slice(2, 4), 16);
  const b = parseInt(v.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function makeSprite(color: string, size = 40): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const g = c.getContext('2d')!;
  const half = size / 2;
  const grad = g.createRadialGradient(half, half, 0, half, half, half);
  grad.addColorStop(0, color);
  grad.addColorStop(0.28, color);
  grad.addColorStop(0.55, hexToRgba(color, 0.32));
  grad.addColorStop(1, hexToRgba(color, 0));
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  return c;
}

function makeNebulaSprite(color: string, size = 192): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const g = c.getContext('2d')!;
  const half = size / 2;
  const grad = g.createRadialGradient(half, half, 0, half, half, half);
  grad.addColorStop(0, hexToRgba(color, 1.0));
  grad.addColorStop(0.2, hexToRgba(color, 0.75));
  grad.addColorStop(0.45, hexToRgba(color, 0.35));
  grad.addColorStop(0.72, hexToRgba(color, 0.1));
  grad.addColorStop(1, hexToRgba(color, 0));
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  return c;
}

interface ShootingStar {
  x: number;
  y: number;
  vx: number;
  vy: number;
  length: number;
  width: number;
  color: string;
  life: number;
  maxLife: number;
}

interface GalaxyViewProps {
  className?: string;
}

export const GalaxyView: React.FC<GalaxyViewProps> = ({ className }) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    const canvas = canvasRef.current;
    if (!container || !canvas) return;

    const ctx = canvas.getContext('2d', { alpha: false });
    if (!ctx) return;

    const reduced = prefersReducedMotion();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);

    let width = container.clientWidth;
    let height = container.clientHeight;

    const counts = pickCounts(width);
    const stars = buildStars(counts);
    const nebula = buildNebula(counts.nebula);
    const bgStars = buildBgStars(counts.bg);

    const starSprites = STAR_PALETTE.map((c) => makeSprite(c, 40));
    const nebulaSprites = NEBULA_PALETTE.map((c) => makeNebulaSprite(c, 192));
    const whiteSprite = starSprites[0];

    let yaw = 0.6;
    let introT = 0;
    let pointerX = 0;
    let pointerY = 0;
    let targetPointerX = 0;
    let targetPointerY = 0;

    const shooting: ShootingStar[] = [];
    let shootingCooldown = 1.2;
    let elapsed = 0;

    function handlePointerMove(e: PointerEvent) {
      const rect = container!.getBoundingClientRect();
      targetPointerX = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      targetPointerY = ((e.clientY - rect.top) / rect.height) * 2 - 1;
    }
    function handlePointerLeave() {
      targetPointerX = 0;
      targetPointerY = 0;
    }
    if (!reduced && window.matchMedia('(hover: hover)').matches) {
      container.addEventListener('pointermove', handlePointerMove, { passive: true });
      container.addEventListener('pointerleave', handlePointerLeave);
    }

    let resizeRaf = 0;
    function resize() {
      width = container!.clientWidth;
      height = container!.clientHeight;
      const nextW = Math.round(width * dpr);
      const nextH = Math.round(height * dpr);
      if (canvas!.width === nextW && canvas!.height === nextH) return;
      canvas!.width = nextW;
      canvas!.height = nextH;
      canvas!.style.width = `${width}px`;
      canvas!.style.height = `${height}px`;
      render(0);
    }
    function onResize() {
      if (resizeRaf) cancelAnimationFrame(resizeRaf);
      resizeRaf = requestAnimationFrame(resize);
    }
    const resizeObserver = new ResizeObserver(onResize);
    resizeObserver.observe(container);
    resize();

    function spawnShootingStar() {
      const rightToLeft = Math.random() < 0.75;
      const angle = rightToLeft
        ? Math.PI * 0.75 + (Math.random() - 0.5) * 0.2
        : Math.PI * 0.25 + (Math.random() - 0.5) * 0.2;
      const speed = Math.random() * 260 + 420;
      shooting.push({
        x: rightToLeft ? width * (0.3 + Math.random() * 0.8) : width * (-0.1 + Math.random() * 0.5),
        y: Math.random() * height * 0.5,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        length: Math.random() * 110 + 90,
        width: Math.random() * 1.2 + 1.3,
        color: SHOOTING_PALETTE[Math.floor(Math.random() * SHOOTING_PALETTE.length)],
        life: 0,
        maxLife: Math.random() * 0.5 + 0.8,
      });
    }

    function render(dt: number) {
      elapsed += dt;
      pointerX += (targetPointerX - pointerX) * 0.08;
      pointerY += (targetPointerY - pointerY) * 0.08;

      introT = Math.min(1, introT + dt / 2.6);
      const introEase = 1 - Math.pow(1 - introT, 4);
      const zoom = 1.15 + introEase * 0.72;

      if (!reduced) yaw += AUTO_SPIN * dt;

      const viewYaw = yaw - pointerX * 0.36;
      const pitch = BASE_PITCH + pointerY * 0.2;

      const cy = Math.cos(viewYaw);
      const sy = Math.sin(viewYaw);
      const cp = Math.cos(pitch);
      const sp = Math.sin(pitch);
      const cr = Math.cos(BASE_ROLL);
      const sr = Math.sin(BASE_ROLL);

      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx!.globalAlpha = 1;
      ctx!.globalCompositeOperation = 'source-over';
      ctx!.fillStyle = VOID_COLOR;
      ctx!.fillRect(0, 0, width, height);

      const centerX = width * 0.5 - pointerX * 24;
      const centerY = height * 0.4 - pointerY * 18;
      const scale = Math.max(width, height) * 0.7 * zoom;
      const densityScale = Math.min(2.4, Math.max(1, scale / 800));
      const z01 = clamp01((zoom - 1) / 7);

      ctx!.globalCompositeOperation = 'lighter';

      const avoidR = Math.min(width, height) * 0.14;
      const bgScale = Math.min(1.4, Math.max(1.0, Math.min(width, height) / 400));
      const bgShiftX = -pointerX * 32;
      const bgShiftY = -pointerY * 26;
      for (let i = 0; i < bgStars.count; i++) {
        const x = bgStars.x01[i] * width + bgShiftX;
        const y = bgStars.y01[i] * height + bgShiftY;
        const dx = x - centerX;
        const dy = y - centerY;
        const avoid = Math.min(1, Math.max(0.55, (dx * dx + dy * dy) / (avoidR * avoidR)));
        const twinkle = reduced ? 1 : 0.55 + 0.45 * Math.sin(elapsed * 1.8 + bgStars.phase[i]);
        const a = Math.min(0.68, bgStars.alpha[i] * avoid * twinkle);
        if (a < 0.02) continue;
        const r = bgStars.r[i] * 1.45 * bgScale;
        ctx!.globalAlpha = a;
        ctx!.drawImage(whiteSprite, x - r, y - r, r * 2, r * 2);
      }

      const tilt = Math.abs(sp);
      const haze = 1.35 - 0.55 * z01;
      const coreRadius = scale * 0.33 * haze;

      ctx!.globalAlpha = 1;
      ctx!.globalCompositeOperation = 'screen';

      ctx!.save();
      ctx!.translate(centerX, centerY);
      ctx!.rotate(Math.atan2(sr, cr));
      ctx!.scale(1, 0.35 + 0.65 * tilt);
      const blueRadius = coreRadius * CORE_BLUE_SCALE;
      const outerGlow = ctx!.createRadialGradient(0, 0, 0, 0, 0, blueRadius);
      outerGlow.addColorStop(0, `rgba(224, 246, 255, ${0.72 * CORE_BLUE_OPACITY})`);
      outerGlow.addColorStop(0.32, `rgba(115, 210, 255, ${0.36 * CORE_BLUE_OPACITY})`);
      outerGlow.addColorStop(0.82, 'rgba(30, 27, 46, 0)');
      ctx!.fillStyle = outerGlow;
      ctx!.beginPath();
      ctx!.arc(0, 0, blueRadius, 0, Math.PI * 2);
      ctx!.fill();
      ctx!.restore();

      ctx!.save();
      ctx!.translate(centerX, centerY);
      ctx!.rotate(Math.atan2(sr, cr));
      ctx!.scale(1, 0.75 + 0.25 * tilt);
      const pinkRadius = coreRadius * 0.52 * CORE_PINK_SCALE;
      const innerCore = ctx!.createRadialGradient(0, 0, 0, 0, 0, pinkRadius);
      innerCore.addColorStop(0, `rgba(255, 190, 120, ${0.45 * CORE_PINK_OPACITY})`);
      innerCore.addColorStop(0.48, `rgba(255, 88, 170, ${0.25 * CORE_PINK_OPACITY})`);
      innerCore.addColorStop(1, 'rgba(255, 88, 170, 0)');
      ctx!.fillStyle = innerCore;
      ctx!.beginPath();
      ctx!.arc(0, 0, pinkRadius, 0, Math.PI * 2);
      ctx!.fill();
      ctx!.restore();

      const zoomFade = Math.max(0.65, Math.min(1.2, 0.65 + 0.35 * Math.sqrt(z01)));
      const sizeFade = 0.6 + 0.4 * z01;

      ctx!.globalCompositeOperation = 'screen';
      for (let i = 0; i < nebula.count; i++) {
        const px = nebula.x[i];
        const py = nebula.y[i];
        const pz = nebula.z[i];

        const rx = px * cy + pz * sy;
        const rz0 = -px * sy + pz * cy;
        const ry = py * cp - rz0 * sp;
        const rz = py * sp + rz0 * cp;

        const depth = rz + 2.5;
        if (depth <= 0.2) continue;

        const sx = (rx / (depth * FOV)) * scale;
        const sy2 = (ry / (depth * FOV)) * scale;
        const x = centerX + sx * cr - sy2 * sr;
        const y = centerY + sx * sr + sy2 * cr;

        if (x < -220 || x > width + 220 || y < -220 || y > height + 220) continue;

        const rPx = ((nebula.radius[i] * scale) / (depth * FOV)) * sizeFade * NEBULA_SCALE;
        const a = clamp01(nebula.alpha[i] * zoomFade);
        if (a < 0.01) continue;

        ctx!.globalAlpha = a;
        ctx!.drawImage(nebulaSprites[nebula.color[i]], x - rPx, y - rPx, rPx * 2, rPx * 2);
      }

      ctx!.globalCompositeOperation = 'lighter';
      const zoomT = clamp01((zoom - 0.6) / 2.4);
      const zoomBoost = 0.55 + 0.9 * Math.pow(zoomT, 2.2);
      const baseAlphaFactor = 0.6 + 0.5 * z01;

      for (let i = 0; i < stars.count; i++) {
        const px = stars.x[i];
        const py = stars.y[i];
        const pz = stars.z[i];

        const rx = px * cy + pz * sy;
        const rz0 = -px * sy + pz * cy;
        const ry = py * cp - rz0 * sp;
        const rz = py * sp + rz0 * cp;

        const depth = rz + 2.5;
        if (depth <= 0.2) continue;

        const sx = (rx / (depth * FOV)) * scale;
        const sy2 = (ry / (depth * FOV)) * scale;
        const x = centerX + sx * cr - sy2 * sr;
        const y = centerY + sx * sr + sy2 * cr;

        if (x < -24 || x > width + 24 || y < -24 || y > height + 24) continue;

        const distFromCenter = Math.hypot(x - centerX, y - centerY);
        const coreFade = smoothstep(coreRadius * 0.1, coreRadius * 0.65, distFromCenter);

        const sizePx = (stars.size[i] / depth) * zoomBoost * densityScale * STAR_SCALE;
        if (sizePx < 0.22) continue;

        const a =
          Math.min(0.85, Math.max(0.2, (stars.bright[i] / Math.pow(depth, 0.85)) * baseAlphaFactor)) *
          (0.35 + 0.65 * coreFade);

        const r = sizePx * 1.4 * (0.7 + 0.3 * coreFade);
        ctx!.globalAlpha = a;
        ctx!.drawImage(starSprites[stars.type[i]], x - r, y - r, r * 2, r * 2);
      }

      if (!reduced) {
        shootingCooldown -= dt;
        if (shootingCooldown <= 0 && shooting.length < 3) {
          spawnShootingStar();
          shootingCooldown = 1.4 + Math.random() * 2.4;
        }

        for (let i = shooting.length - 1; i >= 0; i--) {
          const s = shooting[i];
          s.x += s.vx * dt;
          s.y += s.vy * dt;
          s.life += dt;

          const progress = s.life / s.maxLife;
          if (progress >= 1 || s.x < -260 || s.x > width + 260 || s.y > height + 260) {
            shooting.splice(i, 1);
            continue;
          }

          const fade = progress < 0.25 ? progress / 0.25 : progress > 0.85 ? (1 - progress) / 0.15 : 1;
          const opacity = clamp01(fade);
          if (opacity <= 0.01) continue;

          const speed = Math.hypot(s.vx, s.vy) || 1;
          const tailX = s.x - (s.vx / speed) * s.length;
          const tailY = s.y - (s.vy / speed) * s.length;

          const grad = ctx!.createLinearGradient(tailX, tailY, s.x, s.y);
          grad.addColorStop(0, hexToRgba(s.color, 0));
          grad.addColorStop(1, hexToRgba(s.color, opacity * 0.9));

          ctx!.globalAlpha = 1;
          ctx!.strokeStyle = grad;
          ctx!.lineWidth = s.width;
          ctx!.lineCap = 'round';
          ctx!.beginPath();
          ctx!.moveTo(tailX, tailY);
          ctx!.lineTo(s.x, s.y);
          ctx!.stroke();

          ctx!.globalAlpha = opacity;
          const headR = s.width * 3.2;
          ctx!.drawImage(whiteSprite, s.x - headR, s.y - headR, headR * 2, headR * 2);
        }
      }

      ctx!.globalAlpha = 1;
      ctx!.globalCompositeOperation = 'source-over';
    }

    let rafId = 0;
    let lastTime = performance.now();
    let accumulator = 0;

    if (reduced) {
      render(0);
    } else {
      const frame = (now: number) => {
        rafId = requestAnimationFrame(frame);
        const dt = Math.min(0.05, (now - lastTime) / 1000);
        lastTime = now;
        accumulator += dt;
        if (accumulator < 1 / 40) return;
        const step = accumulator;
        accumulator = 0;
        render(step);
      };
      rafId = requestAnimationFrame(frame);
    }

    function onVisibilityChange() {
      if (reduced) return;
      if (document.hidden) {
        cancelAnimationFrame(rafId);
      } else {
        lastTime = performance.now();
        accumulator = 0;
        rafId = requestAnimationFrame((now) => {
          lastTime = now;
        });
      }
    }
    document.addEventListener('visibilitychange', onVisibilityChange);

    return () => {
      cancelAnimationFrame(rafId);
      cancelAnimationFrame(resizeRaf);
      resizeObserver.disconnect();
      document.removeEventListener('visibilitychange', onVisibilityChange);
      container!.removeEventListener('pointermove', handlePointerMove);
      container!.removeEventListener('pointerleave', handlePointerLeave);
    };
  }, []);

  return (
    <div ref={containerRef} className={`galaxy-view ${className ?? ''}`} aria-hidden="true">
      <canvas ref={canvasRef} />
      <div className="galaxy-view-vignette" />
    </div>
  );
};
