import React, { useEffect, useRef } from 'react';

// --- Palette (mirrors GalaxyCanvas.tsx) --------------------
const VOID_COLOR = '#111422';
const STAR_PALETTE = ['#FFFFFF', '#B7D8FF', '#FFE7B0', '#FFB7B7'];
const NEBULA_PALETTE = ['#FF5FA2', '#FF9A3D', '#B86BFF', '#4FA8FF'];

// --- Camera Defaults ---------------------------------------
const DEFAULT_PITCH = 0.45;
const DEFAULT_YAW = 0.6;
const DEFAULT_ZOOM = 1.8;
const FOV = 1.2;

// ★ ネビュラ（星雲ガス）の大きさ倍率
const NEBULA_SCALE = 0.5;

// ★ 銀河中心のピンク発光の調整（ここを変えるだけで調整できます）
const CORE_PINK_OPACITY = 1.0; // 明るさ・透明度倍率 (例: 0.5 で半分, 1.5 で明るく, 0.0 で非表示)
const CORE_PINK_SCALE = 0.8;   // 大きさ倍率 (例: 0.8 で小さく, 1.3 で大きく)

// ★ 星の大きさ倍率（ここを変えるだけで調整できます）
const STAR_SCALE = 1.8;        // 銀河の星（バルジ・渦状腕）の大きさ倍率 (例: 1.3 で30%大きく)
const BG_STAR_SCALE = 1.0;     // 背景の遠い星の大きさ倍率 (例: 1.3 で30%大きく)

interface Counts {
  bulge: number;
  disk: number;
  nebula: number;
  bg: number;
}

function pickCounts(width: number): Counts {
  if (width < 700) return { bulge: 1100, disk: 3000, nebula: 8, bg: 340 };
  if (width < 1200) return { bulge: 1700, disk: 4800, nebula: 12, bg: 520 };
  return { bulge: 2400, disk: 7000, nebula: 15, bg: 800 };
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
  const innerStartNorm = 0.10;
  const galaxyRadius = 0.7;
  const thickness = 0.05;

  for (let i = 0; i < count; i++) {
    const t = rnd();
    const rNormRaw = Math.pow(t, 0.55);
    const rNorm = innerStartNorm + (1 - innerStartNorm) * rNormRaw;
    const r = galaxyRadius * rNorm;

    const armIndex = Math.floor(rnd() * arms);
    const baseAngle = (armIndex / arms) * 2.0 * Math.PI;

    const angleNoise = 0.12 + 0.40 * rNorm;
    const angle = baseAngle + r * spiralTightness + randNorm() * angleNoise;

    const posNoise = 0.015 + 0.06 * rNorm;
    x[i] = r * Math.cos(angle) + randNorm() * posNoise;
    y[i] = randNorm() * thickness * (0.4 + 0.8 * (1 - rNorm));
    z[i] = r * Math.sin(angle) + randNorm() * posNoise;

    // Larger nebula puffs (1.3x increased radius)
    radius[i] = (0.18 + 0.29 * rNorm) * (0.8 + rnd() * 0.8);
    // Outer fade with solid presence
    alpha[i] = Math.max(0.10, Math.min(0.50, 0.18 + 0.30 * (1 - rNorm) + rnd() * 0.10));

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

function makeSprite(color: string, size = 48): HTMLCanvasElement {
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

/** Soft cloud-like falloff with solid core density so it stays visible when small */
function makeNebulaSprite(color: string, size = 192): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const g = c.getContext('2d')!;
  const half = size / 2;
  const grad = g.createRadialGradient(half, half, 0, half, half, half);
  // Richer core density (1.0 -> 0.7 -> 0.35 -> 0.1 -> 0) so it doesn't wash out at distance
  grad.addColorStop(0, hexToRgba(color, 1.0));
  grad.addColorStop(0.20, hexToRgba(color, 0.75));
  grad.addColorStop(0.45, hexToRgba(color, 0.35));
  grad.addColorStop(0.72, hexToRgba(color, 0.10));
  grad.addColorStop(1, hexToRgba(color, 0));
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  return c;
}

function clamp(val: number, min: number, max: number): number {
  return Math.min(Math.max(val, min), max);
}

function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

export const GalaxyScreenshotPage: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container) return;

    const ctx = canvas.getContext('2d', { alpha: false });
    if (!ctx) return;

    const dpr = Math.min(window.devicePixelRatio || 1, 2);

    let width = window.innerWidth;
    let height = window.innerHeight;

    const counts = pickCounts(width);
    const stars = buildStars(counts);
    const nebula = buildNebula(counts.nebula);
    const bgStars = buildBgStars(counts.bg);

    const starSprites = STAR_PALETTE.map((c) => makeSprite(c, 40));
    const nebulaSprites = NEBULA_PALETTE.map((c) => makeNebulaSprite(c, 192));
    const whiteSprite = starSprites[0];

    // --- Interactive camera state ---
    let yaw = DEFAULT_YAW;
    let pitch = DEFAULT_PITCH;
    let zoom = DEFAULT_ZOOM;
    let elapsed = 0;

    // --- Drag & Wheel Interaction ---
    let isDragging = false;
    let startX = 0;
    let startY = 0;
    let startYaw = yaw;
    let startPitch = pitch;

    const onPointerDown = (e: PointerEvent) => {
      isDragging = true;
      startX = e.clientX;
      startY = e.clientY;
      startYaw = yaw;
      startPitch = pitch;
      container.style.cursor = 'grabbing';
      canvas.setPointerCapture(e.pointerId);
    };

    const onPointerMove = (e: PointerEvent) => {
      if (!isDragging) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;

      // Sensitivity: horizontal drag changes yaw, vertical drag changes pitch
      const sensitivity = 0.005;
      yaw = startYaw + dx * sensitivity;
      pitch = clamp(startPitch + dy * sensitivity, -Math.PI / 2 + 0.05, Math.PI / 2 - 0.05);
    };

    const onPointerUp = (e: PointerEvent) => {
      if (!isDragging) return;
      isDragging = false;
      container.style.cursor = 'grab';
      try {
        canvas.releasePointerCapture(e.pointerId);
      } catch {
        // ignore
      }
    };

    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      // Smooth zoom scaling
      const zoomFactor = Math.exp(-e.deltaY * 0.0015);
      zoom = clamp(zoom * zoomFactor, 0.4, 15.0);
    };

    canvas.addEventListener('pointerdown', onPointerDown);
    canvas.addEventListener('pointermove', onPointerMove);
    canvas.addEventListener('pointerup', onPointerUp);
    canvas.addEventListener('pointercancel', onPointerUp);
    canvas.addEventListener('wheel', onWheel, { passive: false });

    // --- Resize ---
    let resizeRaf = 0;
    function resize() {
      width = window.innerWidth;
      height = window.innerHeight;
      const nextW = Math.round(width * dpr);
      const nextH = Math.round(height * dpr);
      if (canvas!.width === nextW && canvas!.height === nextH) return;
      canvas!.width = nextW;
      canvas!.height = nextH;
      canvas!.style.width = `${width}px`;
      canvas!.style.height = `${height}px`;
    }

    function onResize() {
      if (resizeRaf) cancelAnimationFrame(resizeRaf);
      resizeRaf = requestAnimationFrame(resize);
    }
    resize();
    window.addEventListener('resize', onResize);

    // --- Render Loop ---
    function render(dt: number) {
      elapsed += dt;

      const viewYaw = yaw;
      const viewPitch = pitch;

      const cy = Math.cos(viewYaw);
      const sy = Math.sin(viewYaw);
      const cp = Math.cos(viewPitch);
      const sp = Math.sin(viewPitch);
      const roll = 0;
      const cr = Math.cos(roll);
      const sr = Math.sin(roll);

      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx!.globalAlpha = 1;
      ctx!.globalCompositeOperation = 'source-over';
      ctx!.fillStyle = VOID_COLOR;
      ctx!.fillRect(0, 0, width, height);

      // Centered precisely on screen
      const centerX = width * 0.5;
      const centerY = height * 0.5;
      const screenMin = Math.min(width, height);
      const scale = Math.max(width, height) * 0.70 * zoom;
      const densityScale = Math.min(2.4, Math.max(1, scale / 800));
      const z01 = clamp((zoom - 1) / 7, 0, 1);

      ctx!.globalCompositeOperation = 'lighter';

      // 1. Background stars
      const avoidR = screenMin * 0.14;
      const bgScale = Math.min(1.4, Math.max(1.0, screenMin / 400));
      for (let i = 0; i < bgStars.count; i++) {
        const x = bgStars.x01[i] * width;
        const y = bgStars.y01[i] * height;
        const dx = x - centerX;
        const dy = y - centerY;
        const avoid = Math.min(1, Math.max(0.55, (dx * dx + dy * dy) / (avoidR * avoidR)));
        const twinkle = 0.55 + 0.45 * Math.sin(elapsed * 1.8 + bgStars.phase[i]);
        const a = Math.min(0.68, bgStars.alpha[i] * avoid * twinkle);
        if (a < 0.02) continue;
        const r = bgStars.r[i] * 1.45 * bgScale * BG_STAR_SCALE;
        ctx!.globalAlpha = a;
        ctx!.drawImage(whiteSprite, x - r, y - r, r * 2, r * 2);
      }

      // 2. Core glow
      const tilt = Math.abs(sp);
      const haze = 1.35 - 0.55 * z01;
      const coreRadius = scale * 0.33 * haze;

      ctx!.globalAlpha = 1;
      ctx!.globalCompositeOperation = 'screen';

      ctx!.save();
      ctx!.translate(centerX, centerY);
      ctx!.scale(1, 0.35 + 0.65 * tilt);
      const outerGlow = ctx!.createRadialGradient(0, 0, 0, 0, 0, coreRadius);
      outerGlow.addColorStop(0, 'rgba(224, 246, 255, 0.72)');
      outerGlow.addColorStop(0.32, 'rgba(115, 210, 255, 0.36)');
      outerGlow.addColorStop(0.82, 'rgba(30, 27, 46, 0)');
      ctx!.fillStyle = outerGlow;
      ctx!.beginPath();
      ctx!.arc(0, 0, coreRadius, 0, Math.PI * 2);
      ctx!.fill();
      ctx!.restore();

      ctx!.save();
      ctx!.translate(centerX, centerY);
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

      // Maintain solid visibility across zoom levels
      const zoomFade = Math.max(0.65, Math.min(1.2, 0.65 + 0.35 * Math.sqrt(z01)));
      const sizeFade = 0.60 + 0.40 * z01;

      // 3. Nebula puffs
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
        // Keep solid presence even at distance
        const a = clamp(nebula.alpha[i] * zoomFade, 0.08, 1.0);

        ctx!.globalAlpha = a;
        ctx!.drawImage(nebulaSprites[nebula.color[i]], x - rPx, y - rPx, rPx * 2, rPx * 2);
      }

      // 4. Stars
      ctx!.globalCompositeOperation = 'lighter';
      const zoomT = clamp((zoom - 0.6) / 2.4, 0, 1);
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

        const sizePx = (stars.size[i] / depth) * zoomBoost * densityScale;
        if (sizePx < 0.22) continue;

        const a = Math.min(
          0.85,
          Math.max(0.2, (stars.bright[i] / Math.pow(depth, 0.85)) * baseAlphaFactor)
        ) * (0.35 + 0.65 * coreFade);

        const r = sizePx * 1.4 * (0.7 + 0.3 * coreFade) * STAR_SCALE;
        ctx!.globalAlpha = a;
        ctx!.drawImage(starSprites[stars.type[i]], x - r, y - r, r * 2, r * 2);
      }

      // 5. Shooting stars (Disabled for clean screenshot capture)
      // ctx!.globalAlpha = 1;
      ctx!.globalCompositeOperation = 'source-over';
    }

    let rafId = 0;
    let lastTime = performance.now();
    let accumulator = 0;

    function frame(now: number) {
      rafId = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (now - lastTime) / 1000);
      lastTime = now;

      accumulator += dt;
      if (accumulator < 1 / 60) return;
      const step = accumulator;
      accumulator = 0;
      render(step);
    }

    rafId = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(rafId);
      cancelAnimationFrame(resizeRaf);
      window.removeEventListener('resize', onResize);
      canvas.removeEventListener('pointerdown', onPointerDown);
      canvas.removeEventListener('pointermove', onPointerMove);
      canvas.removeEventListener('pointerup', onPointerUp);
      canvas.removeEventListener('pointercancel', onPointerUp);
      canvas.removeEventListener('wheel', onWheel);
    };
  }, []);

  return (
    <div
      ref={containerRef}
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        width: '100vw',
        height: '100vh',
        backgroundColor: VOID_COLOR,
        overflow: 'hidden',
        cursor: 'grab',
        userSelect: 'none',
        touchAction: 'none',
      }}
    >
      <canvas
        ref={canvasRef}
        style={{
          display: 'block',
          width: '100%',
          height: '100%',
        }}
      />
    </div>
  );
};
