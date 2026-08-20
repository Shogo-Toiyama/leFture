import React, { useEffect, useState } from 'react';
import { ChevronUp } from 'lucide-react';

export const ScrollToTop: React.FC = () => {
  const [scrollProgress, setScrollProgress] = useState(0);
  const [isVisible, setIsVisible] = useState(false);
  const [isHovered, setIsHovered] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      const scrollY = window.scrollY;
      const docHeight = document.documentElement.scrollHeight - window.innerHeight;

      setIsVisible(scrollY > 350);

      if (docHeight > 0) {
        const progress = Math.min(Math.max(scrollY / docHeight, 0), 1);
        setScrollProgress(progress);
      }
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    handleScroll();

    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const scrollToTop = () => {
    window.scrollTo({
      top: 0,
      behavior: 'smooth',
    });
  };

  // ---------------------------------------------------------------------------
  // 🔘 サイズ設定（ここを変えるだけで全体が黄金比率でスケールします）
  // ---------------------------------------------------------------------------
  const size = 80;

  // 中心座標と各種半径
  const center = size / 2;
  const outerBorderRadius = center - 0.75; // 一番外側のガラス境界線
  const orbitRadius = center - 4.5; // ゴールド進行リングの半径

  const circumference = 2 * Math.PI * orbitRadius;
  const strokeDashoffset = circumference - scrollProgress * circumference;

  const iconSize = Math.round(size * 0.7); // 矢印サイズ
  const fontSize = Math.max(9, Math.round(size * 0.115)); // Topフォントサイズ

  return (
    <button
      type="button"
      onClick={scrollToTop}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      aria-label="Scroll to top"
      style={{
        position: 'fixed',
        bottom: '28px',
        right: '28px',
        width: `${size}px`,
        height: `${size}px`,
        borderRadius: '50%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        // Transparent light glass
        background: isHovered
          ? 'rgba(255, 255, 255, 0.12)'
          : 'rgba(255, 255, 255, 0.05)',
        backdropFilter: 'blur(5px)',
        WebkitBackdropFilter: 'blur(5px)',
        border: 'none',
        cursor: 'pointer',
        zIndex: 90,
        opacity: isVisible ? 1 : 0,
        pointerEvents: isVisible ? 'auto' : 'none',
        transform: isVisible
          ? isHovered
            ? 'translateY(-3px) scale(1.03)'
            : 'translateY(0) scale(1)'
          : 'translateY(16px) scale(0.85)',
        boxShadow: isHovered
          ? '0 12px 32px rgba(0, 0, 0, 0.35), 0 0 16px rgba(255, 179, 0, 0.3)'
          : '0 6px 20px rgba(0, 0, 0, 0.2)',
        transition: 'all 0.32s cubic-bezier(0.16, 1, 0.3, 1)',
        padding: 0,
        overflow: 'visible',
      }}
    >
      {/* 
        同心円SVG
      */}
      <svg
        width={size}
        height={size}
        viewBox={`0 0 ${size} ${size}`}
        style={{
          position: 'absolute',
          inset: 0,
          pointerEvents: 'none',
        }}
      >
        {/* ① 最外枠のガラス境界線 */}
        <circle
          cx={center}
          cy={center}
          r={outerBorderRadius}
          fill="none"
          stroke="rgba(255, 255, 255, 0.14)"
          strokeWidth="1.2"
        />

        {/* ② 内側の進行トラック線 */}
        <circle
          cx={center}
          cy={center}
          r={orbitRadius}
          fill="none"
          stroke="rgba(255, 255, 255, 0.09)"
          strokeWidth="1.2"
        />

        {/* ③ ゴールド進行リング */}
        <circle
          cx={center}
          cy={center}
          r={orbitRadius}
          fill="none"
          stroke="#FFB300"
          strokeWidth="1.5"
          strokeDasharray={circumference}
          strokeDashoffset={strokeDashoffset}
          strokeLinecap="round"
          transform={`rotate(-90 ${center} ${center})`}
          style={{
            transition: 'stroke-dashoffset 0.1s linear',
            filter: 'drop-shadow(0 0 2.5px rgba(255, 179, 0, 0.6))',
          }}
        />
      </svg>

      {/* 
        矢印 ＋ Top文字 グループ
      */}
      <div
        style={{
          position: 'relative',
          zIndex: 2,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          transform: isHovered
            ? `translateY(-${Math.round(size * 0.10) + 2}px)`
            : `translateY(-${Math.round(size * 0.10)}px)`,
          transition: 'transform 0.25s ease',
        }}
      >
        {/* 金色＆細いスタイリッシュな矢印 */}
        <ChevronUp
          size={iconSize}
          color={isHovered ? '#FFB300' : 'rgba(255, 255, 255, 0.7)'}
          strokeWidth={1.05}
          style={{
            display: 'block',
            filter: 'drop-shadow(0 0 3px rgba(255, 179, 0, 0.4))',
          }}
        />
        {/* 矢印との間隔を開けた Top テキスト */}
        <span
          style={{
            fontFamily: 'var(--font-sans, "Inter", sans-serif)',
            fontSize: `${fontSize}px`,
            fontWeight: 600,
            letterSpacing: '0.14em',
            textTransform: 'uppercase',
            color: isHovered ? '#FFB300' : 'rgba(255, 255, 255, 0.7)',
            marginTop: `-${Math.round(iconSize * 0.16)}px`, // 間隔を広めに調整
            transition: 'color 0.25s ease',
            lineHeight: 1,
          }}
        >
          Top
        </span>
      </div>
    </button>
  );
};
