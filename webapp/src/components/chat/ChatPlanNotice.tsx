import React from 'react';
import { useCreditSummary } from '../../hooks/useCreditSummary';
import { useLanguage } from '../../i18n/LanguageContext';
import { CHAT_SOURCE_LABEL_KEYS } from '../../lib/chatCitations';
import { CHAT_SOURCE_TYPE_FEATURES, hasFeature } from '../../lib/planFeatures';

/**
 * チャットのヘッダー直下の細い注意書き: 今のプランでチャットが検索しない材料。
 * 回答役(LLM)にはプランを伝えず、案内はここだけで固定の文言で出す
 * (回答のたびにプランの話が混ざって宣伝っぽくなるのを避けるため)。
 * 外れる材料が無いプラン(Core以上)と、プランを読み込む前は何も出さない。
 */
export const ChatPlanNotice: React.FC = () => {
  const { t } = useLanguage();
  const { summary } = useCreditSummary(false);
  if (!summary) return null;

  const excluded = CHAT_SOURCE_TYPE_FEATURES
    .filter(([, feature]) => !hasFeature(summary.tier_level, feature, summary.gating_disabled))
    .map(([sourceType]) => t(CHAT_SOURCE_LABEL_KEYS[sourceType]));
  if (excluded.length === 0) return null;

  const items = excluded.join(t('chatPlanExcludedSourcesSeparator'));
  return <div className="chat-plan-notice">{t('chatPlanExcludedSources', { items })}</div>;
};
