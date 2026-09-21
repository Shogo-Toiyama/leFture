import React from 'react';

/**
 * user_interface/lib/presentation/pages/onboarding/widgets/onboarding_illustrations.dart
 * のSVGをそのまま移植したもの。gradient/idはステップごとに一意な接頭辞を付け、
 * 同時にDOMへ複数マウントされても衝突しないようにしてある。
 */

export const LanguageStepIllustration: React.FC<{ height?: number }> = ({ height = 84 }) => (
  <svg viewBox="0 0 220 92" fill="none" style={{ height, width: 'auto' }} aria-hidden="true">
    <defs>
      <linearGradient id="langBlueGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#60A5FA" />
        <stop offset="50%" stopColor="#3B82F6" />
        <stop offset="100%" stopColor="#1D4ED8" />
      </linearGradient>
      <linearGradient id="langCyanGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#7DD3FC" />
        <stop offset="100%" stopColor="#0284C7" />
      </linearGradient>
      <radialGradient id="langGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#38BDF8" stopOpacity="0.32" />
        <stop offset="60%" stopColor="#1E40AF" stopOpacity="0.12" />
        <stop offset="100%" stopColor="#1E3A8A" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="langGlass" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#60A5FA" stopOpacity="0.22" />
        <stop offset="100%" stopColor="#1E3A8A" stopOpacity="0.06" />
      </linearGradient>
    </defs>

    <ellipse cx="110" cy="46" rx="72" ry="36" fill="url(#langGlow)" />

    <ellipse cx="110" cy="46" rx="84" ry="24" transform="rotate(-12 110 46)" stroke="url(#langCyanGrad)" strokeWidth="1.2" strokeDasharray="3 3" opacity="0.45" />
    <ellipse cx="110" cy="46" rx="98" ry="30" transform="rotate(-12 110 46)" stroke="url(#langBlueGrad)" strokeWidth="0.8" opacity="0.25" />

    <circle cx="28" cy="44" r="2" fill="#93C5FD" opacity="0.8" />
    <circle cx="190" cy="48" r="2.5" fill="#38BDF8" />
    <circle cx="68" cy="22" r="1.5" fill="#BFDBFE" />
    <circle cx="158" cy="68" r="1.8" fill="#60A5FA" />

    <circle cx="110" cy="46" r="24" fill="#0B1528" stroke="url(#langBlueGrad)" strokeWidth="1.8" />
    <circle cx="110" cy="46" r="24" fill="url(#langGlass)" />
    <ellipse cx="110" cy="46" rx="13" ry="24" stroke="#60A5FA" strokeWidth="1.2" opacity="0.6" />
    <line x1="110" y1="22" x2="110" y2="70" stroke="#60A5FA" strokeWidth="1.2" opacity="0.6" />
    <line x1="86" y1="46" x2="134" y2="46" stroke="#60A5FA" strokeWidth="1.2" opacity="0.6" />
    <path d="M89 36 Q110 41 131 36" stroke="#93C5FD" strokeWidth="1" opacity="0.45" fill="none" />
    <path d="M89 56 Q110 51 131 56" stroke="#93C5FD" strokeWidth="1" opacity="0.45" fill="none" />

    <g transform="translate(42, 28)">
      <rect width="36" height="28" rx="8" fill="#0E1E38" stroke="url(#langCyanGrad)" strokeWidth="1.4" />
      <rect width="36" height="28" rx="8" fill="url(#langGlass)" />
      <path d="M26 28 L32 34 L31 28 Z" fill="#0E1E38" stroke="url(#langCyanGrad)" strokeWidth="1.4" strokeLinejoin="round" />
      <text x="18" y="19" textAnchor="middle" fill="#93C5FD" fontSize="13" fontFamily="system-ui, -apple-system, sans-serif" fontWeight={700}>A</text>
    </g>

    <g transform="translate(142, 34)">
      <rect width="36" height="28" rx="8" fill="#0E1E38" stroke="url(#langBlueGrad)" strokeWidth="1.4" />
      <rect width="36" height="28" rx="8" fill="url(#langGlass)" />
      <path d="M10 28 L4 34 L5 28 Z" fill="#0E1E38" stroke="url(#langBlueGrad)" strokeWidth="1.4" strokeLinejoin="round" />
      <line x1="11" y1="14" x2="11" y2="20" stroke="#38BDF8" strokeWidth="2" strokeLinecap="round" />
      <line x1="15" y1="11" x2="15" y2="23" stroke="#60A5FA" strokeWidth="2" strokeLinecap="round" />
      <line x1="19" y1="8" x2="19" y2="26" stroke="#93C5FD" strokeWidth="2" strokeLinecap="round" />
      <line x1="23" y1="12" x2="23" y2="22" stroke="#60A5FA" strokeWidth="2" strokeLinecap="round" />
      <line x1="27" y1="15" x2="27" y2="19" stroke="#38BDF8" strokeWidth="2" strokeLinecap="round" />
    </g>

    <g transform="translate(162, 16)">
      <path d="M0 5 Q5 5 5 0 Q5 5 10 5 Q5 5 5 10 Q5 5 0 5 Z" fill="#BAE6FD" opacity="0.9" />
    </g>
    <g transform="translate(54, 62)">
      <path d="M0 4 Q4 4 4 0 Q4 4 8 4 Q4 4 4 8 Q4 4 0 4 Z" fill="#93C5FD" opacity="0.75" />
    </g>
  </svg>
);

export const ProfileStepIllustration: React.FC<{ height?: number }> = ({ height = 84 }) => (
  <svg viewBox="0 0 220 92" fill="none" style={{ height, width: 'auto' }} aria-hidden="true">
    <defs>
      <linearGradient id="profGreenGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#34D399" />
        <stop offset="50%" stopColor="#10B981" />
        <stop offset="100%" stopColor="#047857" />
      </linearGradient>
      <linearGradient id="profMintGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#A7F3D0" />
        <stop offset="100%" stopColor="#059669" />
      </linearGradient>
      <radialGradient id="profGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#10B981" stopOpacity="0.32" />
        <stop offset="60%" stopColor="#065F46" stopOpacity="0.12" />
        <stop offset="100%" stopColor="#064E3B" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="profGlass" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#34D399" stopOpacity="0.22" />
        <stop offset="100%" stopColor="#064E3B" stopOpacity="0.06" />
      </linearGradient>
    </defs>

    <ellipse cx="110" cy="46" rx="72" ry="36" fill="url(#profGlow)" />

    <ellipse cx="110" cy="46" rx="84" ry="24" transform="rotate(-11 110 46)" stroke="url(#profMintGrad)" strokeWidth="1.2" strokeDasharray="3 3" opacity="0.45" />
    <ellipse cx="110" cy="46" rx="98" ry="30" transform="rotate(-11 110 46)" stroke="url(#profGreenGrad)" strokeWidth="0.8" opacity="0.25" />

    <circle cx="28" cy="46" r="2" fill="#A7F3D0" opacity="0.8" />
    <circle cx="192" cy="46" r="2.5" fill="#34D399" />
    <circle cx="70" cy="22" r="1.5" fill="#D1FAE5" />
    <circle cx="158" cy="70" r="1.8" fill="#10B981" />

    <circle cx="110" cy="46" r="24" fill="#081C15" stroke="url(#profGreenGrad)" strokeWidth="1.8" />
    <circle cx="110" cy="46" r="24" fill="url(#profGlass)" />
    <circle cx="110" cy="38" r="8" fill="url(#profMintGrad)" />
    <path d="M96 58 C96 50 102 48 110 48 C118 48 124 50 124 58" fill="url(#profGreenGrad)" />

    <g transform="translate(42, 28)">
      <rect width="36" height="28" rx="8" fill="#081C15" stroke="url(#profMintGrad)" strokeWidth="1.4" />
      <rect width="36" height="28" rx="8" fill="url(#profGlass)" />
      <path
        d="M10 11 C13 10 16 11 18 12 C20 11 23 10 26 11 L26 23 C23 22 20 23 18 24 C16 23 13 22 10 23 Z"
        fill="none"
        stroke="#A7F3D0"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <line x1="18" y1="12" x2="18" y2="24" stroke="#A7F3D0" strokeWidth="1.5" />
    </g>

    <g transform="translate(142, 34)">
      <rect width="36" height="28" rx="8" fill="#081C15" stroke="url(#profGreenGrad)" strokeWidth="1.4" />
      <rect width="36" height="28" rx="8" fill="url(#profGlass)" />
      <path d="M18 7 L21 14 L28 14 L22 18 L24 25 L18 21 L12 25 L14 18 L8 14 L15 14 Z" fill="url(#profMintGrad)" />
    </g>

    <g transform="translate(164, 15)">
      <path d="M0 5 Q5 5 5 0 Q5 5 10 5 Q5 5 5 10 Q5 5 0 5 Z" fill="#D1FAE5" opacity="0.9" />
    </g>
    <g transform="translate(52, 62)">
      <path d="M0 4 Q4 4 4 0 Q4 4 8 4 Q4 4 4 8 Q4 4 0 4 Z" fill="#6EE7B7" opacity="0.8" />
    </g>
  </svg>
);
