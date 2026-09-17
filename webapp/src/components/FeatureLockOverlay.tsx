import React from 'react';

interface FeatureLockOverlayProps {
  /** ロック中かどうか。falseの場合はchildrenをそのまま表示する。 */
  locked: boolean;
  /** ロック解除に必要なプラン名(例: "Core")。 */
  requiredPlanName: string;
  /** ロック時に重ねて表示する説明文。省略時は既定文言を使う。 */
  message?: string;
  children: React.ReactNode;
}

/**
 * プラン別機能ロックの見た目だけを提供するプレゼンテーショナルなコンポーネント。
 * Flutter版(lecture_viewer_page.dart)の鍵アイコン+アップグレード誘導の表現を
 * webapp向けに揃えたもの。判定ロジック自体はlib/planFeatures.tsのhasFeature()を
 * 呼び出し側で使う想定で、このコンポーネント自身はlocked/requiredPlanNameを
 * 受け取るだけの純粋な表示コンポーネント。
 *
 * まだどのページからもimportされていない(準備段階)。
 */
export const FeatureLockOverlay: React.FC<FeatureLockOverlayProps> = ({
  locked,
  requiredPlanName,
  message,
  children,
}) => {
  if (!locked) return <>{children}</>;

  return (
    <div className="feature-lock">
      <div className="feature-lock-content" aria-hidden="true">
        {children}
      </div>
      <div className="feature-lock-overlay">
        <span className="feature-lock-glyph" aria-hidden="true">
          🔒
        </span>
        <p className="feature-lock-message">
          {message ?? `この機能は${requiredPlanName}プラン以上でご利用いただけます`}
        </p>
      </div>
    </div>
  );
};
