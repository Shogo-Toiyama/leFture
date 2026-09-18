import React from 'react';
import { ReviewCardBlockView } from '../ReviewCardBlockView';
import { reviewCardTypeColor } from '../../lib/reviewCardTheme';
import type { Annotation } from '../../types/annotation';
import type { ReviewCard } from '../../types/content';

interface ReviewCardFaceProps {
  card: ReviewCard;
  annotations: Annotation[];
  /** トピック画像。null のときは無地の紙カードになる。 */
  imageUrl: string | null;
  typeLabel: string;
}

/**
 * 1枚の復習カード。
 * review_cards_viewer_page.dart の _ContentCard と同じ構成で、
 *   トピック画像 → 10px の余白 → 半透明の白い台紙 → 本文
 * の順に重ね、下端にカードタイプ(Hook / Next Action …)の帯を敷く。
 * スクロールするのは画面ではなく台紙の内側。
 */
export const ReviewCardFace: React.FC<ReviewCardFaceProps> = ({
  card,
  annotations,
  imageUrl,
  typeLabel,
}) => {
  const typeColor = reviewCardTypeColor(card.card_type);
  const emoji = card.hero_emoji?.trim() || '💡';
  const title = card.title?.trim();

  return (
    <article
      className={`rcv-card ${imageUrl ? '' : 'is-plain'}`}
      style={{
        ['--pv-type' as string]: typeColor,
        ...(imageUrl ? { backgroundImage: `url(${imageUrl})` } : null),
      }}
    >
      <div className="rcv-paper">
        <div className="rcv-scroll">
          <div className="rcv-hero-emoji" aria-hidden="true">
            {emoji}
          </div>
          {title && <h1 className="rcv-card-title">{title}</h1>}

          <div className="rcv-blocks">
            {card.card_content.map((block, i) => (
              <ReviewCardBlockView key={i} block={block} blockIdx={i} annotations={annotations} />
            ))}
          </div>
        </div>

        <div className="rcv-foot">
          <span className="rcv-type-label">{typeLabel}</span>
        </div>
      </div>
    </article>
  );
};
