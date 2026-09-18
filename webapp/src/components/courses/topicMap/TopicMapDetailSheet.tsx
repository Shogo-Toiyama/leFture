import React from 'react';
import { ArrowRight, ArrowLeft, PlayCircle, X } from 'lucide-react';
import { AdaptiveSheet } from '../../modals/AdaptiveSheet';
import { useLanguage } from '../../../i18n/LanguageContext';

export interface RelatedTopicEdge {
  title: string;
  relationType: string;
  isOutgoing: boolean;
}

export interface TopicMapPanelData {
  courseTitle: string;
  lectureNum: number;
  /** null = Lecture View, 非null = Topic View。 */
  topicNum: number | null;
  title: string;
  summary: string | null;
  /** Topic Viewのみ。 */
  clusterName: string | null;
  /** Topic Viewのみ。 */
  relatedTopics: RelatedTopicEdge[];
}

interface TopicMapDetailSheetProps {
  data: TopicMapPanelData | null;
  onClose: () => void;
  onGoToLecture: () => void;
}

/**
 * lecture_topic_detail_panel.dart の相当品。Flutterはドラッグでリサイズできる
 * ボトムパネルだが、Web版は他ページと同じ AdaptiveSheet (PC: 左から/スマホ: 下から)
 * に統一している。
 */
export const TopicMapDetailSheet: React.FC<TopicMapDetailSheetProps> = ({ data, onClose, onGoToLecture }) => {
  const { language, t } = useLanguage();
  const isJa = language === 'ja';
  const open = data !== null;

  const breadcrumb = data
    ? [
        data.courseTitle,
        isJa ? `講義 ${data.lectureNum}` : `Lecture ${data.lectureNum}`,
        data.topicNum != null ? (isJa ? `トピック ${data.topicNum}` : `Topic ${data.topicNum}`) : null,
      ]
        .filter(Boolean)
        .join(isJa ? ' ・ ' : ', ')
    : '';

  const hasSummary = Boolean(data?.summary?.trim());

  return (
    <AdaptiveSheet
      open={open}
      onClose={onClose}
      side="left"
      width="420px"
      className="topicmap-detail-sheet"
      showScrim={false}
      allowBackdropInteractionOnSide={true}
    >
      {data && (
        <div className="tmds-body">
          <div className="tmds-header-row">
            <p className="tmds-breadcrumb">{breadcrumb.toUpperCase()}</p>
            <button
              type="button"
              className="tmds-close-btn"
              onClick={onClose}
              aria-label={isJa ? '閉じる' : 'Close'}
            >
              <X size={20} />
            </button>
          </div>
          <h3 className="tmds-title">{data.title}</h3>
          <p className={`tmds-summary ${hasSummary ? '' : 'is-placeholder'}`}>
            {hasSummary ? data.summary : t('topicMapSummaryPending')}
          </p>

          <button type="button" className="tmds-go-btn" onClick={onGoToLecture}>
            <PlayCircle size={18} />
            <span>{t('topicMapGoToLecture')}</span>
          </button>

          {data.topicNum != null && (
            <>
              <div className="tmds-section">
                <p className="tmds-section-label">{t('topicMapCluster')}</p>
                <p className={`tmds-cluster-name ${data.clusterName ? '' : 'is-placeholder'}`}>
                  {data.clusterName ?? t('topicMapClusterUnclustered')}
                </p>
              </div>

              <div className="tmds-section">
                <p className="tmds-section-label">{t('topicMapRelatedTopics')}</p>
                {data.relatedTopics.length === 0 ? (
                  <p className="tmds-related-empty">{t('topicMapRelatedEmpty')}</p>
                ) : (
                  <ul className="tmds-related-list">
                    {data.relatedTopics.map((edge, i) => (
                      <li key={i} className="tmds-related-item">
                        {edge.isOutgoing ? (
                          <ArrowRight size={15} className="tmds-related-arrow" />
                        ) : (
                          <ArrowLeft size={15} className="tmds-related-arrow" />
                        )}
                        <span className="tmds-related-text">
                          <span className="tmds-related-title">{edge.title}</span>
                          <span className="tmds-related-relation">
                            {edge.isOutgoing ? edge.relationType : `${edge.relationType} (${t('topicMapOfThis')})`}
                          </span>
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </>
          )}
        </div>
      )}
    </AdaptiveSheet>
  );
};
