import React, { useEffect, useRef } from 'react';

interface GlitterFacet {
  relX: number;
  relY: number;
  size: number;
  tint: string;
  ribbonAffinity: number;
  basePhase: number;
  baseSpeed: number;
  baseOpacity: number;
}

interface CrossStar {
  relX: number;
  relY: number;
  speed: number;
  phase: number;
  color: string;
}

// 疑似乱数生成器（固定シードで常に同じ美しい配置を再現）
function createPrng(seed: number) {
  let s = seed % 2147483647;
  if (s <= 0) s += 2147483646;
  return () => {
    s = (s * 16807) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

const TINTS = [
  '#FFFFFF', // ダイヤモンドホワイト
  '#67E8F9', // ネオンシアン
  '#F472B6', // ホログラフィックピンク
  '#FBBF24', // プリズムゴールド
  '#C084FC', // コズミックバイオレット
  '#34D399', // エメラルドグリーン
  '#38BDF8', // スカイシアン
];

// 80個のホログラムラメ粒子
const GLITTER_FACETS: GlitterFacet[] = (() => {
  const rng = createPrng(88);
  const list: GlitterFacet[] = [];
  for (let i = 0; i < 80; i++) {
    list.push({
      relX: 0.05 + 0.9 * rng(),
      relY: 0.04 + 0.92 * rng(),
      size: 0.9 + rng() * 1.5,
      tint: TINTS[Math.floor(rng() * TINTS.length)],
      ribbonAffinity: 0.5 + rng() * 0.5,
      basePhase: rng() * Math.PI * 2,
      baseSpeed: 0.8 + rng() * 1.2,
      baseOpacity: 0.08 + rng() * 0.16,
    });
  }
  return list;
})();

// Flutter版と同一の十字星芒
const CROSS_STARS: CrossStar[] = [
  { relX: 0.88, relY: 0.14, speed: 1.0, phase: 0.0, color: '#E1BEE7' },
  { relX: 0.68, relY: 0.24, speed: 1.2, phase: 1.2, color: '#67E8F9' },
  { relX: 0.93, relY: 0.36, speed: 0.9, phase: 2.4, color: '#F472B6' },
  { relX: 0.74, relY: 0.50, speed: 1.3, phase: 0.8, color: '#67E8F9' },
  { relX: 0.86, relY: 0.64, speed: 1.1, phase: 3.1, color: '#E1BEE7' },
  { relX: 0.64, relY: 0.76, speed: 0.85, phase: 1.9, color: '#67E8F9' },
  { relX: 0.91, relY: 0.88, speed: 1.15, phase: 4.2, color: '#F472B6' },
];

function easeInOutSine(t: number): number {
  return -(Math.cos(Math.PI * t) - 1) / 2;
}

export const CosmicPlanCanvas: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animId: number;
    let width = 0;
    let height = 0;

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.floor(width * dpr);
      canvas.height = Math.floor(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };

    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    // アニメーション周期: 約3.8秒（画面通過約2.4秒、待機インターバル約1.4秒の快適テンポ）
    const CYCLE_DURATION_MS = 3800;
    const SWEEP_DURATION_MS = 2400; // カードを横切るスピード（約1秒）は完璧に維持
    const ROTATION_ANGLE = Math.PI / 4; // 45度

    let startTime: number | null = null;

    const render = (now: number) => {
      if (startTime === null) startTime = now;
      const elapsed = (now - startTime) % CYCLE_DURATION_MS;

      if (width > 0 && height > 0) {
        ctx.clearRect(0, 0, width, height);

        // 1. スイープの進行計算 (0.0〜1.0)
        let sweepProgress = 1.0;
        let isSweeping = false;
        if (elapsed < SWEEP_DURATION_MS) {
          const t = elapsed / SWEEP_DURATION_MS;
          sweepProgress = easeInOutSine(t);
          isSweeping = true;
        }

        // 画面外の無駄な待機移動を削り、カード外縁直前から直後(-1.15〜+1.15)へ最短で駆け抜ける
        const tilt = isSweeping ? -1.15 + sweepProgress * 2.3 : 2.0;
        const centerX = width * 0.5 + tilt * (width * 0.55);
        const centerY = height * 0.5 + tilt * (height * 0.55);

        // 2. 星雲の呼吸光彩 (Nebula Pulse)
        const nebulaPulse = Math.sin((elapsed / CYCLE_DURATION_MS) * Math.PI * 2) * 0.04;

        // ディープバイオレット星雲 (右側)
        const gViolet = ctx.createRadialGradient(
          width * 0.82,
          height * 0.32,
          0,
          width * 0.82,
          height * 0.32,
          width * 0.55
        );
        gViolet.addColorStop(0, `rgba(168, 85, 247, ${Math.max(0.05, 0.22 + nebulaPulse)})`);
        gViolet.addColorStop(0.55, 'rgba(99, 102, 241, 0.08)');
        gViolet.addColorStop(1, 'transparent');
        ctx.fillStyle = gViolet;
        ctx.fillRect(0, 0, width, height);

        // ネオンシアンのオーロラスポット (左下〜中央)
        const gCyan = ctx.createRadialGradient(
          width * 0.25,
          height * 0.7,
          0,
          width * 0.25,
          height * 0.7,
          width * 0.45
        );
        gCyan.addColorStop(0, `rgba(6, 182, 212, ${Math.max(0.04, 0.16 - nebulaPulse)})`);
        gCyan.addColorStop(0.5, 'rgba(56, 189, 248, 0.06)');
        gCyan.addColorStop(1, 'transparent');
        ctx.fillStyle = gCyan;
        ctx.fillRect(0, 0, width, height);

        // 3. 旋回・偏光プリズム光帯 (Rainbow Foil Sheen)
        const diagonal = Math.sqrt(width * width + height * height);
        const ribbonWidth = diagonal * 0.75;
        const ribbonHalf = ribbonWidth * 0.5;

        if (isSweeping) {
          ctx.save();
          ctx.translate(centerX, centerY);
          ctx.rotate(ROTATION_ANGLE);
          ctx.globalCompositeOperation = 'screen';

          const sheenGrad = ctx.createLinearGradient(-ribbonHalf, 0, ribbonHalf, 0);
          sheenGrad.addColorStop(0.0, 'transparent');
          sheenGrad.addColorStop(0.18, 'rgba(6, 182, 212, 0.06)');
          sheenGrad.addColorStop(0.32, 'rgba(168, 85, 247, 0.08)');
          sheenGrad.addColorStop(0.44, 'rgba(236, 72, 153, 0.12)');
          sheenGrad.addColorStop(0.50, 'rgba(255, 255, 255, 0.18)'); // ★直射ダイヤモンド光沢
          sheenGrad.addColorStop(0.56, 'rgba(251, 191, 36, 0.11)');
          sheenGrad.addColorStop(0.68, 'rgba(16, 185, 129, 0.07)');
          sheenGrad.addColorStop(0.82, 'rgba(56, 189, 248, 0.05)');
          sheenGrad.addColorStop(1.0, 'transparent');

          ctx.fillStyle = sheenGrad;
          ctx.fillRect(-ribbonHalf, -diagonal, ribbonWidth, diagonal * 2);
          ctx.restore();
        }

        // 4. 高密度ダイヤモンド・グリッター鏡面反射 (Specular Glitter Sparkles)
        // 光帯の直射光がラメ粒子の上を横切る瞬間に、カラーオーラ＋白熱コア＋十字光芒を励起
        for (const flake of GLITTER_FACETS) {
          const x = flake.relX * width;
          const y = flake.relY * height;

          // ベースの穏やかな瞬き (0.04〜0.22)
          const baseWave = Math.sin(
            (now / 1000) * flake.baseSpeed + flake.basePhase
          );
          let intensity = Math.max(0, flake.baseOpacity + baseWave * 0.06);

          // 光帯通過時の励起トリガー
          if (isSweeping) {
            const relX = x - centerX;
            const relY = y - centerY;
            // 45度回転軸に対する直交距離
            const ribbonDist = Math.abs(
              relX * Math.cos(-ROTATION_ANGLE) - relY * Math.sin(-ROTATION_ANGLE)
            );
            const ribbonCore = ribbonHalf * 0.38;
            if (ribbonDist < ribbonCore) {
              const excitation =
                Math.pow(1.0 - ribbonDist / ribbonCore, 2.4) * flake.ribbonAffinity;
              intensity = Math.max(intensity, excitation);
            }
          }

          if (intensity > 0.04) {
            // ① 色付きオーラ（ラメのカラー反射）
            ctx.fillStyle = flake.tint;
            ctx.globalAlpha = Math.min(0.85, intensity * 0.7);
            ctx.beginPath();
            ctx.arc(x, y, flake.size * (1.2 + intensity * 1.8), 0, Math.PI * 2);
            ctx.fill();

            // ② ダイヤモンド白熱コア
            ctx.fillStyle = '#FFFFFF';
            ctx.globalAlpha = Math.min(1.0, intensity * 0.95);
            ctx.beginPath();
            ctx.arc(x, y, flake.size * (0.7 + intensity * 0.6), 0, Math.PI * 2);
            ctx.fill();

            // ③ 高輝度時の十字ダイヤモンド光芒 (Diamond Starburst)
            if (intensity > 0.38) {
              const beam = (intensity - 0.38) * 11;
              const beamAlpha = Math.min(0.9, (intensity - 0.38) * 1.8);
              ctx.strokeStyle = '#FFFFFF';
              ctx.lineWidth = 0.8;
              ctx.lineCap = 'round';
              ctx.globalAlpha = beamAlpha;

              ctx.beginPath();
              ctx.moveTo(x - beam, y);
              ctx.lineTo(x + beam, y);
              ctx.moveTo(x, y - beam);
              ctx.lineTo(x, y + beam);
              ctx.stroke();

              // ④ 超高輝度時の8方向斜めスターバースト
              if (intensity > 0.68) {
                const diagBeam = (intensity - 0.68) * 6.5;
                ctx.beginPath();
                ctx.moveTo(x - diagBeam, y - diagBeam);
                ctx.lineTo(x + diagBeam, y + diagBeam);
                ctx.moveTo(x - diagBeam, y + diagBeam);
                ctx.lineTo(x + diagBeam, y - diagBeam);
                ctx.stroke();
              }
            }
          }
        }

        // 5. 十字星芒 (Cross Stars)
        for (const star of CROSS_STARS) {
          const sx = star.relX * width;
          const sy = star.relY * height;
          const pulse = (Math.sin((now / 1000) * star.speed + star.phase) + 1.0) / 2.0;

          const coreOpacity = Math.min(0.55, 0.2 + pulse * 0.3);
          const glowOpacity = Math.min(0.22, 0.06 + pulse * 0.15);
          const lineOpacity = Math.min(0.4, 0.12 + pulse * 0.24);
          const beamLength = 3.0 + pulse * 2.8;

          // オーラグロー
          ctx.fillStyle = star.color;
          ctx.globalAlpha = glowOpacity;
          ctx.beginPath();
          ctx.arc(sx, sy, 3.8, 0, Math.PI * 2);
          ctx.fill();

          // 白熱コア
          ctx.fillStyle = '#FFFFFF';
          ctx.globalAlpha = coreOpacity;
          ctx.beginPath();
          ctx.arc(sx, sy, 1.2, 0, Math.PI * 2);
          ctx.fill();

          // 十字光条
          ctx.strokeStyle = '#FFFFFF';
          ctx.lineWidth = 0.6;
          ctx.lineCap = 'round';
          ctx.globalAlpha = lineOpacity;
          ctx.beginPath();
          ctx.moveTo(sx - beamLength, sy);
          ctx.lineTo(sx + beamLength, sy);
          ctx.moveTo(sx, sy - beamLength);
          ctx.lineTo(sx, sy + beamLength);
          ctx.stroke();
        }

        ctx.globalAlpha = 1.0;
      }

      animId = requestAnimationFrame(render);
    };

    animId = requestAnimationFrame(render);

    return () => {
      cancelAnimationFrame(animId);
      ro.disconnect();
    };
  }, []);

  return <canvas ref={canvasRef} className="cosmic-plan-canvas" aria-hidden="true" />;
};
