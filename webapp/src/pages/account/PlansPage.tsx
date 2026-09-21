import React from 'react';
import { PlansContent } from './PlansContent';

/**
 * プラン一覧・比較ページ。中身(カード列+比較表+各種モーダル)は`PlansContent`
 * に集約されており、オンボーディングのPlanステップ(OnboardingPlanStep)からも
 * 同じ中身がheader/onPlanActivatedだけ差し替えて埋め込まれる。
 */
export const PlansPage: React.FC = () => {
  return (
    <div className="plans-page">
      {/* 上部コズミックスペクトラム極光グラデーション (Core:黄 → Standard:青 → Pro:赤 → Max:紫) */}
      <div className="plans-top-gradient" aria-hidden="true" />
      <div className="plans-page-inner">
        <PlansContent />
      </div>
    </div>
  );
};
