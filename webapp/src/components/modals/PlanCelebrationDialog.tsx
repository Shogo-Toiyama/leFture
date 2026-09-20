import React, { useEffect, useRef } from 'react';
import { tierAccent, planIconAsset } from '../../lib/planTheme';
import type { PlanOption } from '../../types/billing';

/**
 * アップグレード(または初回購入)成立時に表示するお祝いダイアログ。
 * plan_change_dialogs.dart の showUpgradeCelebrationDialog(紙吹雪ではなく、
 * プランカラーの光る星屑がアイコンから放射状に開花する演出)をCanvasで移植したもの。
 * Flutterのshowdowngradeダイアログと同様、対象はアップグレード成立時のみ
 * (Freeプランのclaimや、変更なしのalready_currentでは出さない)。
 */

const DURATION_MS = 2800;
const PARTICLE_COUNT = 90;

interface Particle {
  originOffsetX: number;
  originOffsetY: number;
  angle: number;
  spreadRadius: number;
  color: [number, number, number];
  size: number;
  rotationSpeed: number;
  delay: number;
  gravity: number;
  twinkleFrequency: number;
  twinklePhase: number;
}

function hexToRgb(hex: string): [number, number, number] {
  const n = parseInt(hex.replace('#', ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function mixWithWhite([r, g, b]: [number, number, number], amount: number): [number, number, number] {
  const mix = (c: number) => Math.round(c + (255 - c) * amount);
  return [mix(r), mix(g), mix(b)];
}

function generateParticles(accentHex: string): Particle[] {
  const accent = hexToRgb(accentHex);
  // 白 〜 プラン色の洗練されたスターパレット(Dart版の_generateParticles準拠)。
  const palette: [number, number, number][] = [
    [255, 255, 255],
    [248, 250, 252],
    [226, 232, 240],
    [224, 231, 255],
    mixWithWhite(accent, 0.55),
    mixWithWhite(accent, 0.3),
    accent,
  ];

  return Array.from({ length: PARTICLE_COUNT }, () => ({
    originOffsetX: (Math.random() - 0.5) * 16,
    originOffsetY: (Math.random() - 0.5) * 16,
    angle: Math.random() * Math.PI * 2,
    spreadRadius: 80 + Math.random() * 120,
    color: palette[Math.floor(Math.random() * palette.length)],
    size: 2.2 + Math.random() * 2.6,
    rotationSpeed: (Math.random() - 0.5) * 5,
    delay: Math.random() * 0.04,
    gravity: 80 + Math.random() * 50,
    twinkleFrequency: 7 + Math.random() * 12,
    twinklePhase: Math.random() * Math.PI * 2,
  }));
}

function drawParticle(ctx: CanvasRenderingContext2D, p: Particle, originX: number, originY: number, t: number) {
  const localT = Math.min(1, Math.max(0, (t - p.delay) / (1 - p.delay)));
  if (localT <= 0) return;

  // 物理的に滑らかな空気抵抗(指数関数的減衰)。
  const dragProgress = 1 - Math.exp(-9 * localT);

  const startX = originX + p.originOffsetX;
  const startY = originY + p.originOffsetY;
  const currentRadius = p.spreadRadius * dragProgress;
  const dx = startX + Math.cos(p.angle) * currentRadius;
  const dy = startY + Math.sin(p.angle) * (currentRadius * 0.78) + 0.5 * p.gravity * localT * localT;

  const baseFade = localT < 0.65 ? 1 : Math.min(1, Math.max(0, 1 - (localT - 0.65) / 0.35));
  if (baseFade <= 0) return;

  const twinkle = 0.2 + 0.8 * Math.abs(Math.sin(localT * p.twinkleFrequency * Math.PI + p.twinklePhase));
  const opacity = Math.min(0.65, Math.max(0, baseFade * twinkle));
  if (opacity <= 0.015) return;

  const [r, g, b] = p.color;

  ctx.save();
  ctx.translate(dx, dy);
  ctx.rotate(p.rotationSpeed * localT * Math.PI);

  const rayLength = p.size;
  ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${opacity * 0.6})`;
  ctx.lineWidth = 0.5;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(-rayLength, 0);
  ctx.lineTo(rayLength, 0);
  ctx.moveTo(0, -rayLength);
  ctx.lineTo(0, rayLength);
  ctx.stroke();

  // やや大きい星には繊細な斜め光条を追加(8方向スターバースト)。
  if (p.size > 3.6) {
    const diag = rayLength * 0.45;
    ctx.beginPath();
    ctx.moveTo(-diag, -diag);
    ctx.lineTo(diag, diag);
    ctx.moveTo(-diag, diag);
    ctx.lineTo(diag, -diag);
    ctx.stroke();
  }

  ctx.fillStyle = `rgba(255, 255, 255, ${opacity * 0.9})`;
  ctx.beginPath();
  ctx.arc(0, 0, 0.55, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}

export const PlanCelebrationDialog: React.FC<{
  plan: PlanOption;
  isJa: boolean;
  onClose: () => void;
}> = ({ plan, isJa, onClose }) => {
  const { accent } = tierAccent(plan.tier_level);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const iconRef = useRef<HTMLDivElement>(null);
  const particlesRef = useRef<Particle[]>(generateParticles(accent));

  useEffect(() => {
    const canvas = canvasRef.current;
    const iconEl = iconRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !iconEl || !ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const resize = () => {
      canvas.width = window.innerWidth * dpr;
      canvas.height = window.innerHeight * dpr;
      canvas.style.width = `${window.innerWidth}px`;
      canvas.style.height = `${window.innerHeight}px`;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    window.addEventListener('resize', resize);

    // 中央の惑星アイコン位置から放射状に開花させる(Dart版準拠)。
    const iconRect = iconEl.getBoundingClientRect();
    const originX = iconRect.left + iconRect.width / 2;
    const originY = iconRect.top + iconRect.height / 2;

    let raf = 0;
    const start = performance.now();

    const frame = (now: number) => {
      const t = Math.min(1, (now - start) / DURATION_MS);
      ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
      for (const particle of particlesRef.current) {
        drawParticle(ctx, particle, originX, originY, t);
      }
      if (t < 1) {
        raf = requestAnimationFrame(frame);
      } else {
        ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
      }
    };
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', resize);
    };
  }, []);

  return (
    <div className="plan-celebration-backdrop" onClick={onClose}>
      <canvas ref={canvasRef} className="plan-celebration-canvas" aria-hidden="true" />
      <div
        className="plan-celebration-card"
        style={{ ['--plan-accent' as string]: accent }}
        onClick={(e) => e.stopPropagation()}
      >
        <div ref={iconRef} className="plan-celebration-icon">
          <img src={planIconAsset(plan.tier_level)} alt="" />
        </div>
        <h2 className="plan-celebration-title">
          {isJa ? `${plan.name}へようこそ!` : `Welcome to ${plan.name}!`}
        </h2>
        <p className="plan-celebration-message">
          {isJa
            ? '新しいプランはもう有効になっています。クレジットはまもなく反映されます。'
            : 'Your new plan is active now, and your credits are on their way.'}
        </p>
        <button type="button" className="plan-celebration-btn" onClick={onClose}>
          {isJa ? 'はじめよう!' : "Let's go!"}
        </button>
      </div>
    </div>
  );
};
