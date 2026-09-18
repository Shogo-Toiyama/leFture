import React from 'react';

interface CreditPackIllustrationProps {
  creditAmount: number;
  className?: string;
  size?: number | string;
}

export const CreditPackIllustration: React.FC<CreditPackIllustrationProps> = ({
  creditAmount,
  className = '',
  size = '100%',
}) => {
  // クレジット量に応じて1枚のコイン・重なりコイン・コインの山・超大量のコインの山を描画
  if (creditAmount <= 100) {
    return <SingleCoinSvg className={className} size={size} />;
  } else if (creditAmount <= 300) {
    return <StackCoinsSvg className={className} size={size} />;
  } else if (creditAmount <= 700) {
    return <PileCoinsSvg className={className} size={size} />;
  } else {
    return <MegaVaultCoinsSvg className={className} size={size} />;
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// 1. Single Coin (100クレジット / スターター)
// ─────────────────────────────────────────────────────────────────────────────
const SingleCoinSvg: React.FC<{ className?: string; size: number | string }> = ({ className, size }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 80 80"
    fill="none"
    width={size}
    height={size}
    className={className}
  >
    <defs>
      <radialGradient id="singleGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#C084FC" stopOpacity="0.45" />
        <stop offset="60%" stopColor="#7E22CE" stopOpacity="0.15" />
        <stop offset="100%" stopColor="#3B0764" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="coinGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#F3E8FF" />
        <stop offset="30%" stopColor="#C084FC" />
        <stop offset="70%" stopColor="#A855F7" />
        <stop offset="100%" stopColor="#6B21A8" />
      </linearGradient>
      <linearGradient id="goldStarGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#FEF08A" />
        <stop offset="50%" stopColor="#FACC15" />
        <stop offset="100%" stopColor="#EAB308" />
      </linearGradient>
      <linearGradient id="innerCoin" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#3B1259" />
        <stop offset="100%" stopColor="#1E0B30" />
      </linearGradient>
      <linearGradient id="rimHighlight" x1="0%" y1="0%" x2="0%" y2="100%">
        <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.55" />
        <stop offset="100%" stopColor="#FFFFFF" stopOpacity="0" />
      </linearGradient>
    </defs>

    {/* グロー背景 */}
    <circle cx="40" cy="40" r="38" fill="url(#singleGlow)" />

    {/* 軌道リング */}
    <ellipse cx="40" cy="40" rx="34" ry="14" transform="rotate(-15 40 40)" stroke="#C084FC" strokeWidth="1" strokeDasharray="2 3" opacity="0.4" />

    {/* コインの影 */}
    <ellipse cx="40" cy="62" rx="20" ry="5" fill="#0D061A" opacity="0.6" />

    {/* コイン外枠 (厚みとリム) */}
    <circle cx="40" cy="41" r="23" fill="#581C87" />
    <circle cx="40" cy="39" r="23" fill="url(#coinGrad)" />
    <circle cx="40" cy="39" r="20.5" fill="url(#innerCoin)" stroke="url(#coinGrad)" strokeWidth="1.5" />

    {/* コイン内側の縁飾り */}
    <circle cx="40" cy="39" r="17.5" stroke="#C084FC" strokeWidth="0.8" strokeDasharray="1.5 2" opacity="0.6" />

    {/* コイン中心の星 (丸みのあるスターアイコン) */}
    <path d="M40 26.5 L42.8 33.2 L50 34.2 L44.8 39.2 L46 46.5 L40 43.2 L34 46.5 L35.2 39.2 L30 34.2 L37.2 33.2 Z" fill="url(#goldStarGrad)" />
    {/* 星のセンターハイライト */}
    <circle cx="40" cy="37.5" r="2.2" fill="#FEF9C3" opacity="0.9" />

    {/* 光沢ハイライト（上部リム） */}
    <path d="M21 35 A21 21 0 0 1 59 35 A21 16 0 0 0 21 35 Z" fill="url(#rimHighlight)" opacity="0.45" />

    {/* スパークル星 */}
    <path d="M60 20 Q63 20 63 17 Q63 20 66 20 Q63 20 63 23 Q63 20 60 20 Z" fill="#FDE047" />
    <path d="M18 52 Q20 52 20 50 Q20 52 22 52 Q20 52 20 54 Q20 52 18 52 Z" fill="#E9D5FF" opacity="0.8" />
    <circle cx="61" cy="54" r="1.5" fill="#C084FC" opacity="0.7" />
  </svg>
);

// ─────────────────────────────────────────────────────────────────────────────
// 2. Stack of Coins (300クレジット前後)
// ─────────────────────────────────────────────────────────────────────────────
const StackCoinsSvg: React.FC<{ className?: string; size: number | string }> = ({ className, size }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 80 80"
    fill="none"
    width={size}
    height={size}
    className={className}
  >
    <defs>
      <radialGradient id="stackGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#C084FC" stopOpacity="0.55" />
        <stop offset="50%" stopColor="#A855F7" stopOpacity="0.2" />
        <stop offset="100%" stopColor="#3B0764" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="coinGrad2" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#F3E8FF" />
        <stop offset="35%" stopColor="#C084FC" />
        <stop offset="70%" stopColor="#A855F7" />
        <stop offset="100%" stopColor="#6B21A8" />
      </linearGradient>
      <linearGradient id="goldStarGrad2" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#FEF08A" />
        <stop offset="50%" stopColor="#FACC15" />
        <stop offset="100%" stopColor="#EAB308" />
      </linearGradient>
      <linearGradient id="innerCoin2" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#351052" />
        <stop offset="100%" stopColor="#190729" />
      </linearGradient>
      <linearGradient id="rimLight2" x1="0%" y1="0%" x2="0%" y2="100%">
        <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.55" />
        <stop offset="100%" stopColor="#FFFFFF" stopOpacity="0" />
      </linearGradient>
    </defs>

    {/* アンビエントグロー */}
    <circle cx="40" cy="40" r="39" fill="url(#stackGlow)" />

    {/* 軌道ライン */}
    <ellipse cx="40" cy="42" rx="36" ry="16" transform="rotate(-10 40 42)" stroke="#C084FC" strokeWidth="1" strokeDasharray="3 3" opacity="0.35" />

    {/* 全体の影 */}
    <ellipse cx="40" cy="65" rx="26" ry="6" fill="#0D061A" opacity="0.65" />

    {/* コイン 1 (左奥) */}
    <g transform="translate(25, 34)">
      <ellipse cx="0" cy="2" rx="16" ry="15" fill="#4C1D95" />
      <ellipse cx="0" cy="0" rx="16" ry="15" fill="url(#coinGrad2)" />
      <ellipse cx="0" cy="0" rx="14" ry="13" fill="url(#innerCoin2)" stroke="url(#coinGrad2)" strokeWidth="1" />
      <path d="M0 -7 L1.6 -2.5 L6 -1.8 L2.7 1.5 L3.5 6 L0 3.8 L-3.5 6 L-2.7 1.5 L-6 -1.8 L-1.6 -2.5 Z" fill="url(#goldStarGrad2)" opacity="0.85" />
    </g>

    {/* コイン 2 (右奥) */}
    <g transform="translate(53, 36)">
      <ellipse cx="0" cy="2" rx="17" ry="16" fill="#4C1D95" />
      <ellipse cx="0" cy="0" rx="17" ry="16" fill="url(#coinGrad2)" />
      <ellipse cx="0" cy="0" rx="15" ry="14" fill="url(#innerCoin2)" stroke="url(#coinGrad2)" strokeWidth="1" />
      <path d="M0 -8 L1.8 -2.8 L6.5 -2 L3 1.8 L3.8 6.8 L0 4.2 L-3.8 6.8 L-3 1.8 L-6.5 -2 L-1.8 -2.8 Z" fill="url(#goldStarGrad2)" opacity="0.85" />
    </g>

    {/* コイン 3 (手前中央・メイン) */}
    <g transform="translate(38, 44)">
      <circle cx="0" cy="2" r="20" fill="#581C87" />
      <circle cx="0" cy="0" r="20" fill="url(#coinGrad2)" />
      <circle cx="0" cy="0" r="17.8" fill="url(#innerCoin2)" stroke="url(#coinGrad2)" strokeWidth="1.4" />
      <circle cx="0" cy="0" r="15.2" stroke="#C084FC" strokeWidth="0.7" strokeDasharray="1.5 2" opacity="0.6" />
      <path d="M0 -11 L2.4 -3.8 L9.5 -2.7 L4.2 2.5 L5.5 9.5 L0 6.2 L-5.5 9.5 L-4.2 2.5 L-9.5 -2.7 L-2.4 -3.8 Z" fill="url(#goldStarGrad2)" />
      <circle cx="0" cy="0" r="2" fill="#FEF9C3" />
      <path d="M-17 -3 A17 17 0 0 1 17 -3 A17 13 0 0 0 -17 -3 Z" fill="url(#rimLight2)" opacity="0.45" />
    </g>

    {/* キラキラスパークル */}
    <path d="M64 16 Q67 16 67 13 Q67 16 70 16 Q67 16 67 19 Q67 16 64 16 Z" fill="#FDE047" />
    <path d="M14 26 Q16 26 16 24 Q16 26 18 26 Q16 26 16 28 Q16 26 14 26 Z" fill="#E9D5FF" opacity="0.9" />
    <path d="M67 52 Q69 52 69 50 Q69 52 71 52 Q69 52 69 54 Q69 52 67 52 Z" fill="#C084FC" opacity="0.8" />
    <circle cx="20" cy="62" r="1.5" fill="#FACC15" opacity="0.7" />
  </svg>
);

// ─────────────────────────────────────────────────────────────────────────────
// 3. Pile of Coins (500クレジット用 / 5個のコインの山)
// ─────────────────────────────────────────────────────────────────────────────
const PileCoinsSvg: React.FC<{ className?: string; size: number | string }> = ({ className, size }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 80 80"
    fill="none"
    width={size}
    height={size}
    className={className}
  >
    <defs>
      <radialGradient id="pileGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#E879F9" stopOpacity="0.5" />
        <stop offset="45%" stopColor="#A855F7" stopOpacity="0.3" />
        <stop offset="85%" stopColor="#3B0764" stopOpacity="0.05" />
        <stop offset="100%" stopColor="#1E0B30" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="pileCoinGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#FAF5FF" />
        <stop offset="30%" stopColor="#D8B4FE" />
        <stop offset="70%" stopColor="#A855F7" />
        <stop offset="100%" stopColor="#6B21A8" />
      </linearGradient>
      <linearGradient id="goldStarGrad3" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#FEF08A" />
        <stop offset="45%" stopColor="#FACC15" />
        <stop offset="100%" stopColor="#EAB308" />
      </linearGradient>
      <linearGradient id="innerCoin3" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#330E50" />
        <stop offset="100%" stopColor="#160524" />
      </linearGradient>
      <linearGradient id="burstGrad" x1="0%" y1="0%" x2="0%" y2="100%">
        <stop offset="0%" stopColor="#FDE047" stopOpacity="0.8" />
        <stop offset="100%" stopColor="#C084FC" stopOpacity="0" />
      </linearGradient>
    </defs>

    {/* 強いオーラグロー */}
    <circle cx="40" cy="40" r="40" fill="url(#pileGlow)" />

    {/* 舞い上がる光の粒子線 */}
    <line x1="40" y1="20" x2="40" y2="10" stroke="url(#burstGrad)" strokeWidth="1.5" strokeLinecap="round" />
    <line x1="28" y1="24" x2="22" y2="16" stroke="url(#burstGrad)" strokeWidth="1.2" strokeLinecap="round" />
    <line x1="52" y1="24" x2="58" y2="16" stroke="url(#burstGrad)" strokeWidth="1.2" strokeLinecap="round" />

    {/* 全体の影 */}
    <ellipse cx="40" cy="67" rx="28" ry="6" fill="#090312" opacity="0.75" />

    {/* 1. 左奥コイン */}
    <g transform="translate(22, 42) rotate(-14)">
      <circle cx="0" cy="1.8" r="14.5" fill="#4C1D95" />
      <circle cx="0" cy="0" r="14.5" fill="url(#pileCoinGrad)" />
      <circle cx="0" cy="0" r="12.5" fill="url(#innerCoin3)" stroke="url(#pileCoinGrad)" strokeWidth="1" />
      <path d="M0 -7 L1.6 -2.4 L6 -1.8 L2.8 1.6 L3.4 6.2 L0 4 L-3.4 6.2 L-2.8 1.6 L-6 -1.8 L-1.6 -2.4 Z" fill="url(#goldStarGrad3)" opacity="0.85" />
    </g>

    {/* 2. 右奥コイン */}
    <g transform="translate(58, 42) rotate(14)">
      <circle cx="0" cy="1.8" r="14.5" fill="#4C1D95" />
      <circle cx="0" cy="0" r="14.5" fill="url(#pileCoinGrad)" />
      <circle cx="0" cy="0" r="12.5" fill="url(#innerCoin3)" stroke="url(#pileCoinGrad)" strokeWidth="1" />
      <path d="M0 -7 L1.6 -2.4 L6 -1.8 L2.8 1.6 L3.4 6.2 L0 4 L-3.4 6.2 L-2.8 1.6 L-6 -1.8 L-1.6 -2.4 Z" fill="url(#goldStarGrad3)" opacity="0.85" />
    </g>

    {/* 3. 中央上・頂点コイン */}
    <g transform="translate(40, 27)">
      <circle cx="0" cy="1.8" r="14.5" fill="#581C87" />
      <circle cx="0" cy="0" r="14.5" fill="url(#pileCoinGrad)" />
      <circle cx="0" cy="0" r="12.5" fill="url(#innerCoin3)" stroke="url(#pileCoinGrad)" strokeWidth="1" />
      <path d="M0 -8 L1.8 -2.6 L6.8 -1.8 L3 1.8 L3.8 6.8 L0 4.3 L-3.8 6.8 L-3 1.8 L-6.8 -1.8 L-1.8 -2.6 Z" fill="url(#goldStarGrad3)" />
      <circle cx="0" cy="0" r="1.5" fill="#FEF9C3" />
    </g>

    {/* 4. 手前左コイン */}
    <g transform="translate(26, 54) rotate(-8)">
      <circle cx="0" cy="2" r="16.5" fill="#4C1D95" />
      <circle cx="0" cy="0" r="16.5" fill="url(#pileCoinGrad)" />
      <circle cx="0" cy="0" r="14.5" fill="url(#innerCoin3)" stroke="url(#pileCoinGrad)" strokeWidth="1.2" />
      <path d="M0 -9 L2 -3 L7.5 -2.2 L3.5 2 L4.2 7.8 L0 5 L-4.2 7.8 L-3.5 2 L-7.5 -2.2 L-2 -3 Z" fill="url(#goldStarGrad3)" opacity="0.9" />
    </g>

    {/* 5. 最前面・手前右メインコイン */}
    <g transform="translate(48, 52)">
      <circle cx="0" cy="2.2" r="18.5" fill="#581C87" />
      <circle cx="0" cy="0" r="18.5" fill="url(#pileCoinGrad)" />
      <circle cx="0" cy="0" r="16.2" fill="url(#innerCoin3)" stroke="url(#pileCoinGrad)" strokeWidth="1.3" />
      <circle cx="0" cy="0" r="13.8" stroke="#C084FC" strokeWidth="0.7" strokeDasharray="1.5 2" opacity="0.65" />
      <path d="M0 -10.5 L2.3 -3.6 L9 -2.5 L4 2.3 L5.2 9 L0 5.8 L-5.2 9 L-4 2.3 L-9 -2.5 L-2.3 -3.6 Z" fill="url(#goldStarGrad3)" />
      <circle cx="0" cy="2" r="2" fill="#FEF9C3" />
      <path d="M-15 -3 A15 15 0 0 1 15 -3 A15 11 0 0 0 -15 -3 Z" fill="#FFFFFF" opacity="0.45" />
    </g>

    {/* スパークル群 */}
    <path d="M40 5 Q43 5 43 1 Q43 5 46 5 Q43 5 43 9 Q43 5 40 5 Z" fill="#FEF08A" />
    <path d="M68 22 Q71 22 71 19 Q71 22 74 22 Q71 22 71 25 Q71 22 68 22 Z" fill="#FDE047" />
    <path d="M10 32 Q13 32 13 29 Q13 32 16 32 Q13 32 13 35 Q13 32 10 32 Z" fill="#F0ABFC" />
    <path d="M70 56 Q72 56 72 54 Q72 56 74 56 Q72 56 72 58 Q72 56 70 56 Z" fill="#C084FC" />
    <circle cx="16" cy="18" r="1.5" fill="#FEF08A" opacity="0.8" />
    <circle cx="64" cy="65" r="1.2" fill="#E9D5FF" opacity="0.7" />
  </svg>
);

// ─────────────────────────────────────────────────────────────────────────────
// 4. Mega Vault / Mountain of Coins (1000〜2000クレジット用 / 超大量)
// ─────────────────────────────────────────────────────────────────────────────
const MegaVaultCoinsSvg: React.FC<{ className?: string; size: number | string }> = ({ className, size }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 80 80"
    fill="none"
    width={size}
    height={size}
    className={className}
  >
    <defs>
      <radialGradient id="megaGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#FDE047" stopOpacity="0.45" />
        <stop offset="35%" stopColor="#F472B6" stopOpacity="0.35" />
        <stop offset="65%" stopColor="#A855F7" stopOpacity="0.25" />
        <stop offset="100%" stopColor="#3B0764" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="megaCoinGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#FFFFFF" />
        <stop offset="25%" stopColor="#F3E8FF" />
        <stop offset="55%" stopColor="#C084FC" />
        <stop offset="80%" stopColor="#9333EA" />
        <stop offset="100%" stopColor="#581C87" />
      </linearGradient>
      <linearGradient id="megaStarGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#FEF08A" />
        <stop offset="50%" stopColor="#FACC15" />
        <stop offset="100%" stopColor="#EAB308" />
      </linearGradient>
      <linearGradient id="megaInnerCoin" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#380D58" />
        <stop offset="100%" stopColor="#140324" />
      </linearGradient>
      <linearGradient id="rayGrad" x1="0%" y1="100%" x2="0%" y2="0%">
        <stop offset="0%" stopColor="#FDE047" stopOpacity="0.75" />
        <stop offset="60%" stopColor="#E879F9" stopOpacity="0.35" />
        <stop offset="100%" stopColor="#C084FC" stopOpacity="0" />
      </linearGradient>
    </defs>

    {/* 背景の巨大アンビエントオーラ */}
    <circle cx="40" cy="42" r="40" fill="url(#megaGlow)" />

    {/* 放射状の光線 */}
    <path d="M40 42 L34 2 L46 2 Z" fill="url(#rayGrad)" opacity="0.45" />
    <path d="M40 42 L12 10 L22 4 Z" fill="url(#rayGrad)" opacity="0.35" />
    <path d="M40 42 L68 10 L58 4 Z" fill="url(#rayGrad)" opacity="0.35" />
    <path d="M40 42 L2 28 L6 18 Z" fill="url(#rayGrad)" opacity="0.25" />
    <path d="M40 42 L78 28 L74 18 Z" fill="url(#rayGrad)" opacity="0.25" />

    {/* 全体の影 */}
    <ellipse cx="40" cy="71" rx="34" ry="7" fill="#07020E" opacity="0.85" />

    {/* 最奥のコイン群 */}
    <g transform="translate(14, 62) rotate(-25)">
      <ellipse cx="0" cy="1.5" rx="12" ry="8" fill="#3B0764" />
      <ellipse cx="0" cy="0" rx="12" ry="8" fill="url(#megaCoinGrad)" />
      <ellipse cx="0" cy="0" rx="10.5" ry="7" fill="url(#megaInnerCoin)" />
    </g>
    <g transform="translate(66, 62) rotate(25)">
      <ellipse cx="0" cy="1.5" rx="12" ry="8" fill="#3B0764" />
      <ellipse cx="0" cy="0" rx="12" ry="8" fill="url(#megaCoinGrad)" />
      <ellipse cx="0" cy="0" rx="10.5" ry="7" fill="url(#megaInnerCoin)" />
    </g>
    <g transform="translate(18, 52) rotate(-15)">
      <ellipse cx="0" cy="1.5" rx="13" ry="9" fill="#4C1D95" />
      <ellipse cx="0" cy="0" rx="13" ry="9" fill="url(#megaCoinGrad)" />
      <ellipse cx="0" cy="0" rx="11" ry="7.5" fill="url(#megaInnerCoin)" />
      <path d="M0 -4 L0.8 -1.5 L3 -1 L1.4 0.8 L1.8 3.2 L0 2.2 L-1.8 3.2 L-1.4 0.8 L-3 -1 L-0.8 -1.5 Z" fill="url(#megaStarGrad)" opacity="0.75" />
    </g>
    <g transform="translate(62, 52) rotate(15)">
      <ellipse cx="0" cy="1.5" rx="13" ry="9" fill="#4C1D95" />
      <ellipse cx="0" cy="0" rx="13" ry="9" fill="url(#megaCoinGrad)" />
      <ellipse cx="0" cy="0" rx="11" ry="7.5" fill="url(#megaInnerCoin)" />
      <path d="M0 -4 L0.8 -1.5 L3 -1 L1.4 0.8 L1.8 3.2 L0 2.2 L-1.8 3.2 L-1.4 0.8 L-3 -1 L-0.8 -1.5 Z" fill="url(#megaStarGrad)" opacity="0.75" />
    </g>

    {/* 中段のコインの山 */}
    <g transform="translate(24, 42) rotate(-10)">
      <circle cx="0" cy="1.8" r="14" fill="#4C1D95" />
      <circle cx="0" cy="0" r="14" fill="url(#megaCoinGrad)" />
      <circle cx="0" cy="0" r="12" fill="url(#megaInnerCoin)" stroke="url(#megaCoinGrad)" strokeWidth="0.8" />
      <path d="M0 -7 L1.6 -2.4 L6 -1.8 L2.8 1.6 L3.4 6.2 L0 4 L-3.4 6.2 L-2.8 1.6 L-6 -1.8 L-1.6 -2.4 Z" fill="url(#megaStarGrad)" opacity="0.85" />
    </g>
    <g transform="translate(56, 42) rotate(10)">
      <circle cx="0" cy="1.8" r="14" fill="#4C1D95" />
      <circle cx="0" cy="0" r="14" fill="url(#megaCoinGrad)" />
      <circle cx="0" cy="0" r="12" fill="url(#megaInnerCoin)" stroke="url(#megaCoinGrad)" strokeWidth="0.8" />
      <path d="M0 -7 L1.6 -2.4 L6 -1.8 L2.8 1.6 L3.4 6.2 L0 4 L-3.4 6.2 L-2.8 1.6 L-6 -1.8 L-1.6 -2.4 Z" fill="url(#megaStarGrad)" opacity="0.85" />
    </g>
    <g transform="translate(40, 35)">
      <circle cx="0" cy="2" r="15" fill="#581C87" />
      <circle cx="0" cy="0" r="15" fill="url(#megaCoinGrad)" />
      <circle cx="0" cy="0" r="13" fill="url(#megaInnerCoin)" stroke="url(#megaCoinGrad)" strokeWidth="1" />
      <path d="M0 -8 L1.8 -2.6 L6.8 -1.8 L3 1.8 L3.8 6.8 L0 4.3 L-3.8 6.8 L-3 1.8 L-6.8 -1.8 L-1.8 -2.6 Z" fill="url(#megaStarGrad)" />
    </g>

    {/* 前面手前のコイン */}
    <g transform="translate(25, 56) rotate(-8)">
      <circle cx="0" cy="2" r="16" fill="#4C1D95" />
      <circle cx="0" cy="0" r="16" fill="url(#megaCoinGrad)" />
      <circle cx="0" cy="0" r="14" fill="url(#megaInnerCoin)" stroke="url(#megaCoinGrad)" strokeWidth="1.2" />
      <path d="M0 -9 L2 -3 L7.5 -2.2 L3.5 2 L4.2 7.8 L0 5 L-4.2 7.8 L-3.5 2 L-7.5 -2.2 L-2 -3 Z" fill="url(#megaStarGrad)" opacity="0.9" />
    </g>
    <g transform="translate(55, 56) rotate(8)">
      <circle cx="0" cy="2" r="16" fill="#4C1D95" />
      <circle cx="0" cy="0" r="16" fill="url(#megaCoinGrad)" />
      <circle cx="0" cy="0" r="14" fill="url(#megaInnerCoin)" stroke="url(#megaCoinGrad)" strokeWidth="1.2" />
      <path d="M0 -9 L2 -3 L7.5 -2.2 L3.5 2 L4.2 7.8 L0 5 L-4.2 7.8 L-3.5 2 L-7.5 -2.2 L-2 -3 Z" fill="url(#megaStarGrad)" opacity="0.9" />
    </g>
    {/* 最前面・中央メインコイン */}
    <g transform="translate(40, 58)">
      <circle cx="0" cy="2.5" r="19" fill="#581C87" />
      <circle cx="0" cy="0" r="19" fill="url(#megaCoinGrad)" />
      <circle cx="0" cy="0" r="16.5" fill="url(#megaInnerCoin)" stroke="url(#megaCoinGrad)" strokeWidth="1.4" />
      <circle cx="0" cy="0" r="14.2" stroke="#E9D5FF" strokeWidth="0.8" strokeDasharray="1.5 2" opacity="0.7" />
      <path d="M0 -11 L2.4 -3.8 L9.5 -2.7 L4.2 2.5 L5.5 9.5 L0 6.2 L-5.5 9.5 L-4.2 2.5 L-9.5 -2.7 L-2.4 -3.8 Z" fill="url(#megaStarGrad)" />
      <circle cx="0" cy="2" r="2.2" fill="#FEF9C3" />
      <path d="M-16 -3 A16 16 0 0 1 16 -3 A16 12 0 0 0 -16 -3 Z" fill="#FFFFFF" opacity="0.5" />
    </g>

    {/* フライングコイン */}
    <g transform="translate(18, 22) rotate(-22)">
      <ellipse cx="0" cy="1.2" rx="10" ry="7" fill="#4C1D95" />
      <ellipse cx="0" cy="0" rx="10" ry="7" fill="url(#megaCoinGrad)" />
      <ellipse cx="0" cy="0" rx="8.5" ry="5.8" fill="url(#megaInnerCoin)" />
      <path d="M0 -3.5 L0.7 -1.2 L2.8 -0.8 L1.3 0.8 L1.6 2.8 L0 1.8 L-1.6 2.8 L-1.3 0.8 L-2.8 -0.8 L-0.7 -1.2 Z" fill="url(#megaStarGrad)" />
    </g>
    <g transform="translate(62, 22) rotate(22)">
      <ellipse cx="0" cy="1.2" rx="10" ry="7" fill="#4C1D95" />
      <ellipse cx="0" cy="0" rx="10" ry="7" fill="url(#megaCoinGrad)" />
      <ellipse cx="0" cy="0" rx="8.5" ry="5.8" fill="url(#megaInnerCoin)" />
      <path d="M0 -3.5 L0.7 -1.2 L2.8 -0.8 L1.3 0.8 L1.6 2.8 L0 1.8 L-1.6 2.8 L-1.3 0.8 L-2.8 -0.8 L-0.7 -1.2 Z" fill="url(#megaStarGrad)" />
    </g>
    <g transform="translate(40, 15)">
      <circle cx="0" cy="1" r="7.5" fill="#581C87" />
      <circle cx="0" cy="0" r="7.5" fill="url(#megaCoinGrad)" />
      <circle cx="0" cy="0" r="6.2" fill="url(#megaInnerCoin)" />
      <path d="M0 -4 L0.8 -1.4 L3.4 -1 L1.5 1 L2 3.4 L0 2.2 L-2 3.4 L-1.5 1 L-3.4 -1 L-0.8 -1.4 Z" fill="url(#megaStarGrad)" />
    </g>

    {/* スパークル群 */}
    <path d="M40 2 Q43 2 43 -1 Q43 2 46 2 Q43 2 43 5 Q43 2 40 2 Z" fill="#FEF08A" />
    <path d="M72 14 Q75 14 75 11 Q75 14 78 14 Q75 14 75 17 Q75 14 72 14 Z" fill="#FDE047" />
    <path d="M8 20 Q11 20 11 17 Q11 20 14 20 Q11 20 11 23 Q11 20 8 20 Z" fill="#F0ABFC" />
    <path d="M74 48 Q76 48 76 46 Q76 48 78 48 Q76 48 76 50 Q76 48 74 48 Z" fill="#C084FC" />
    <path d="M6 46 Q8 46 8 44 Q8 46 10 46 Q8 46 8 48 Q8 46 6 46 Z" fill="#FDE047" />
    <circle cx="28" cy="8" r="1.5" fill="#FEF08A" opacity="0.9" />
    <circle cx="53" cy="8" r="1.5" fill="#FEF08A" opacity="0.9" />
    <circle cx="10" cy="60" r="1.2" fill="#E9D5FF" opacity="0.8" />
    <circle cx="70" cy="62" r="1.2" fill="#E9D5FF" opacity="0.8" />
  </svg>
);
