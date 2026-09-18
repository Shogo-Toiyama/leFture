import React from 'react';

/**
 * 機能ロック表示用の鍵アイコン。plan_lock_illustration.dart のSVGをそのまま移植したもの。
 * colorには解放に必要なプランのアクセントカラー(tierAccent().accent)を渡す。
 */
export const PlanLockIllustration: React.FC<{ color: string; size?: number }> = ({ color, size = 96 }) => {
  const light = lighten(color, 0.45);

  return (
    <svg width={size} height={size} viewBox="0 0 96 96" fill="none" aria-hidden="true">
      <defs>
        <linearGradient id="lockGrad" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor={light} />
          <stop offset="100%" stopColor={color} />
        </linearGradient>
        <radialGradient id="lockGlow" cx="50%" cy="44%" r="58%">
          <stop offset="0%" stopColor={color} stopOpacity={0.38} />
          <stop offset="60%" stopColor={color} stopOpacity={0.14} />
          <stop offset="100%" stopColor={color} stopOpacity={0} />
        </radialGradient>
        <linearGradient id="lockGlass" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor={light} stopOpacity={0.22} />
          <stop offset="100%" stopColor={color} stopOpacity={0.06} />
        </linearGradient>
      </defs>

      <circle cx="48" cy="46" r="42" fill="url(#lockGlow)" />

      <path
        d="M32 44 V32 a16 16 0 0 1 32 0 V44"
        stroke="url(#lockGrad)"
        strokeWidth="6"
        strokeLinecap="round"
        fill="none"
      />

      <rect x="22" y="42" width="52" height="40" rx="13" fill="#0E1E38" stroke="url(#lockGrad)" strokeWidth="2" />
      <rect x="22" y="42" width="52" height="40" rx="13" fill="url(#lockGlass)" />

      <circle cx="48" cy="58" r="5.5" fill="url(#lockGrad)" />
      <rect x="45.4" y="61" width="5.2" height="11" rx="2.2" fill="url(#lockGrad)" />

      <path
        d="M78 20 l2.2 5.4 5.4 2.2 -5.4 2.2 -2.2 5.4 -2.2 -5.4 -5.4 -2.2 5.4 -2.2 z"
        fill={light}
        opacity={0.85}
      />
      <circle cx="16" cy="62" r="2.2" fill={light} opacity={0.7} />
      <circle cx="22" cy="24" r="1.4" fill={light} opacity={0.55} />
    </svg>
  );
};

/** colorToHex(Color.lerp(color, Colors.white, t)) 相当。#RRGGBBのみ対応。 */
function lighten(hex: string, t: number): string {
  const m = /^#([0-9a-fA-F]{6})$/.exec(hex);
  if (!m) return hex;
  const num = parseInt(m[1], 16);
  const r = (num >> 16) & 0xff;
  const g = (num >> 8) & 0xff;
  const b = num & 0xff;
  const mix = (c: number) => Math.round(c + (255 - c) * t);
  const toHex = (c: number) => c.toString(16).padStart(2, '0');
  return `#${toHex(mix(r))}${toHex(mix(g))}${toHex(mix(b))}`;
}
