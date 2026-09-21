import React, { useEffect, useRef, useState } from 'react';
import { Check } from 'lucide-react';
import { useLanguage } from '../../../i18n/LanguageContext';

const BOX_SIZE = 260;
const DURATION_MS = 1100;
const GREEN: [number, number, number] = [76, 175, 80]; // AppColors.growthGreen (#4CAF50)

interface BurstParticle {
  angle: number;
  distance: number;
  size: number;
  delay: number;
}

function generateParticles(): BurstParticle[] {
  return Array.from({ length: 30 }, () => ({
    angle: Math.random() * Math.PI * 2,
    distance: 55 + Math.random() * 95,
    size: 2.2 + Math.random() * 3.4,
    delay: Math.random() * 0.12,
  }));
}

function easeOut(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

/**
 * onboarding_done_step.dartの`_GreenBurstPainter`相当(フラッシュ→衝撃波→
 * パーティクルの三段構成)。全画面ではなく260x260のボックス内に収める点も同じ。
 */
function drawBurst(ctx: CanvasRenderingContext2D, progress: number, particles: BurstParticle[]) {
  const cx = BOX_SIZE / 2;
  const cy = BOX_SIZE / 2;
  ctx.clearRect(0, 0, BOX_SIZE, BOX_SIZE);

  // 1. フラッシュ
  const flashT = Math.min(1, progress / 0.32);
  if (flashT < 1) {
    const opacity = flashT < 0.3 ? flashT / 0.3 : 1 - (flashT - 0.3) / 0.7;
    const radius = 10 + (95 - 10) * easeOut(flashT);
    const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
    const [r, g, b] = GREEN;
    grad.addColorStop(0, `rgba(255,255,255,${0.9 * Math.max(0, opacity)})`);
    grad.addColorStop(0.38, `rgba(${r},${g},${b},${0.5 * Math.max(0, opacity)})`);
    grad.addColorStop(1, `rgba(${r},${g},${b},0)`);
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fill();
  }

  // 2. 衝撃波(2本)
  for (const delay of [0, 0.1]) {
    const t = Math.min(1, Math.max(0, (progress - delay) / 0.58));
    if (progress < delay || t >= 1) continue;
    const eased = easeOut(t);
    const radius = 34 + (128 - 34) * eased;
    const opacity = 1 - eased;
    const [r, g, b] = GREEN;
    ctx.strokeStyle = `rgba(${r},${g},${b},${0.85 * opacity})`;
    ctx.lineWidth = 3.2 + (0.5 - 3.2) * eased;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.stroke();
  }

  // 3. パーティクル
  const [r, g, b] = GREEN;
  for (const p of particles) {
    const local = Math.min(1, Math.max(0, (progress - p.delay) / 0.62));
    if (progress < p.delay) continue;
    const eased = easeOut(local);
    const dist = p.distance * eased;
    const opacity = local < 0.15 ? local / 0.15 : 1 - (local - 0.15) / 0.85;
    if (opacity <= 0) continue;
    const x = cx + Math.cos(p.angle) * dist;
    const y = cy + Math.sin(p.angle) * dist;
    const isWhite = eased < 0.45;
    ctx.fillStyle = isWhite
      ? `rgba(255,255,255,${Math.min(1, Math.max(0, opacity))})`
      : `rgba(${r},${g},${b},${Math.min(1, Math.max(0, opacity))})`;
    ctx.beginPath();
    ctx.arc(x, y, (p.size * (1 - local * 0.3)) / 2, 0, Math.PI * 2);
    ctx.fill();
  }
}

const CheckmarkImpact: React.FC<{ visible: boolean }> = ({ visible }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const particlesRef = useRef<BurstParticle[]>(generateParticles());
  const firedRef = useRef(false);

  useEffect(() => {
    if (!visible || firedRef.current) return;
    firedRef.current = true;
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = BOX_SIZE * dpr;
    canvas.height = BOX_SIZE * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    let raf = 0;
    const start = performance.now();
    const frame = (now: number) => {
      const t = Math.min(1, (now - start) / DURATION_MS);
      drawBurst(ctx, t, particlesRef.current);
      if (t < 1) raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  }, [visible]);

  return (
    <div className="onb-done-impact">
      <canvas ref={canvasRef} className="onb-done-burst-canvas" style={{ width: BOX_SIZE, height: BOX_SIZE }} aria-hidden="true" />
      <div className={`onb-done-checkmark ${visible ? 'is-visible' : ''}`}>
        <Check size={36} color="var(--green)" strokeWidth={3} />
      </div>
    </div>
  );
};

/** onboarding_done_step.dart相当。最終ステップ: 緑のチェックマークバースト演出。 */
export const OnboardingDoneStep: React.FC<{ onFinish: () => void }> = ({ onFinish }) => {
  const { t } = useLanguage();
  const [mark, setMark] = useState(false);
  const [title, setTitle] = useState(false);
  const [subtitle, setSubtitle] = useState(false);
  const [button, setButton] = useState(false);

  useEffect(() => {
    const timers = [
      setTimeout(() => setMark(true), 120),
      setTimeout(() => setTitle(true), 520),
      setTimeout(() => setSubtitle(true), 660),
      setTimeout(() => setButton(true), 860),
    ];
    return () => timers.forEach(clearTimeout);
  }, []);

  return (
    <div className="onb-done">
      <CheckmarkImpact visible={mark} />
      <h1 className={`onb-done-title onb-fade-up ${title ? 'is-visible' : ''}`}>{t('onboardingDoneTitle')}</h1>
      <p className={`onb-done-subtitle onb-fade-up ${subtitle ? 'is-visible' : ''}`}>{t('onboardingDoneSubtitle')}</p>
      <div className={`onb-fade-up ${button ? 'is-visible' : ''}`} style={{ width: '100%' }}>
        <button type="button" className="onb-cta-btn onb-cta-btn-pulse" onClick={onFinish}>
          {t('onboardingGetStartedButton')}
        </button>
      </div>
    </div>
  );
};
