/**
 * プランのtier_level(0=Free, 1=Lite, 2=Core, 3=Max)からテーマカラーを決める。
 * plan_theme.dart の planThemeColor と、plan_card.dart の isPremium/isStandard
 * 出し分け(Max=紫のネオン、Core=紅のネオン)を1つにまとめたもの。
 * CreditsPage・PlansPageの両方で同じ色を使うための共有先。
 */
export interface TierTheme {
  accent: string;
  isPremium: boolean;
  isStandard: boolean;
}

export function tierAccent(tierLevel: number): TierTheme {
  if (tierLevel >= 3) return { accent: '#C084FC', isPremium: true, isStandard: false };
  if (tierLevel === 2) return { accent: '#FB7185', isPremium: false, isStandard: true };
  if (tierLevel === 1) return { accent: '#42A5F5', isPremium: false, isStandard: false };
  return { accent: '#FFB300', isPremium: false, isStandard: false };
}

/** planIconAsset(plan_theme.dart) 準拠。public/img/plan_icons/ に同名png済み。 */
export function planIconAsset(tierLevel: number): string {
  if (tierLevel >= 3) return '/img/plan_icons/galaxy.png';
  if (tierLevel === 2) return '/img/plan_icons/solarsystem.png';
  if (tierLevel === 1) return '/img/plan_icons/planet.png';
  return '/img/plan_icons/stardust.png';
}
