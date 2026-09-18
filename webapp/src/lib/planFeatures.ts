/**
 * プランごとの機能開放を判定するロジックのミラー。
 * 真実の源はバックエンド(lefture_backend/app/services/helpers/plan_features.py)で、
 * 実際の生成・保存可否は常にサーバー側のhas_feature()が最終判断する。
 * ここでの判定結果はUIロック表示のヒントとしてのみ使う(まだどのページからも
 * 呼び出されていない — 準備段階)。
 */

/** Freeプラン等でDeepNotes生成が意図的にスキップされたトピックのnote_contentsセンチネル値。 */
export const DEEP_NOTES_SKIPPED_PLAN_LIMIT = '__SKIPPED_PLAN_LIMIT__';

export const TIER_FREE = 0;
export const TIER_LITE = 1;
export const TIER_CORE = 2;
export const TIER_MAX = 3;

export const FEATURE_KEYWORD_EXTRACTION_SUBSCRIBER = 'keyword_extraction_subscriber';
export const FEATURE_ANNOUNCEMENT_GENERATION = 'announcement_generation';
export const FEATURE_SOURCE_TRANSCRIPT_VIEW = 'source_transcript_view';
export const FEATURE_TOPIC_MAP = 'topic_map';
export const FEATURE_DEEP_NOTES_FULL = 'deep_notes_full';
export const FEATURE_FUN_FACT_SEARCH = 'fun_fact_search';
export const FEATURE_REALTIME_TRANSCRIBE = 'realtime_transcribe';

export type FeatureKey =
  | typeof FEATURE_KEYWORD_EXTRACTION_SUBSCRIBER
  | typeof FEATURE_ANNOUNCEMENT_GENERATION
  | typeof FEATURE_SOURCE_TRANSCRIPT_VIEW
  | typeof FEATURE_TOPIC_MAP
  | typeof FEATURE_DEEP_NOTES_FULL
  | typeof FEATURE_FUN_FACT_SEARCH
  | typeof FEATURE_REALTIME_TRANSCRIBE;

const FEATURE_MIN_TIER: Record<FeatureKey, number> = {
  [FEATURE_KEYWORD_EXTRACTION_SUBSCRIBER]: TIER_CORE,
  [FEATURE_ANNOUNCEMENT_GENERATION]: TIER_CORE,
  [FEATURE_SOURCE_TRANSCRIPT_VIEW]: TIER_CORE,
  [FEATURE_TOPIC_MAP]: TIER_LITE,
  [FEATURE_DEEP_NOTES_FULL]: TIER_LITE,
  [FEATURE_FUN_FACT_SEARCH]: TIER_CORE,
  [FEATURE_REALTIME_TRANSCRIBE]: TIER_MAX,
};

/**
 * 指定tierLevelがfeatureKeyを使える権利を持つか。
 * gatingDisabledは/billing/summaryが返すgating_disabledフィールドをそのまま渡す
 * (β期間中の全機能開放キルスイッチ。実際の判定はサーバー側has_feature()が最終)。
 */
export function hasFeature(tierLevel: number, featureKey: FeatureKey, gatingDisabled = false): boolean {
  if (gatingDisabled) return true;
  return tierLevel >= FEATURE_MIN_TIER[featureKey];
}

const TIER_NAMES: Record<number, string> = {
  [TIER_FREE]: 'Free',
  [TIER_LITE]: 'Lite',
  [TIER_CORE]: 'Core',
  [TIER_MAX]: 'Max',
};

/** ロック解除に必要な最小tierのプラン名(表示用)。 */
export function requiredPlanNameForFeature(featureKey: FeatureKey): string {
  return TIER_NAMES[FEATURE_MIN_TIER[featureKey]] ?? TIER_NAMES[TIER_CORE];
}
