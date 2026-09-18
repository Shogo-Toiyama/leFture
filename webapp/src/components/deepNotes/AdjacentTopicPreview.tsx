import React from 'react';

interface AdjacentTopicPreviewProps {
  title: string;
  imageUrl: string | null;
  direction: 'prev' | 'next';
  onClick: () => void;
}

/**
 * 前後トピックの予告。_AdjacentTopicHeroPreview(Flutter)と同じく、画像を薄く敷いて
 * 進行方向の反対側を紙色に溶かし、タイトルだけを白フチで浮かせる。
 */
export const AdjacentTopicPreview: React.FC<AdjacentTopicPreviewProps> = ({
  title,
  imageUrl,
  direction,
  onClick,
}) => (
  <button
    type="button"
    className={`dnv-adjacent ${direction === 'prev' ? 'is-prev' : 'is-next'}`}
    onClick={onClick}
  >
    {imageUrl && <img src={imageUrl} alt="" />}
    <span className="dnv-adjacent-label">{title}</span>
  </button>
);
