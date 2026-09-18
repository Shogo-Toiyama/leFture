import React from 'react';
import { X } from 'lucide-react';
import { plainTextPreview, reviewCardTypeColor } from '../../lib/reviewCardTheme';
import type { ReviewTopicGroup } from './types';

interface ReviewCardListDrawerProps {
  title: string;
  groups: ReviewTopicGroup[];
  /** storagePath -> object URL */
  imageUrls: Record<string, string>;
  currentIndex: number;
  typeLabel: (cardType: string) => string;
  onSelect: (flatIndex: number) => void;
  onClose: () => void;
}

/**
 * カード一覧。常に左からのオーバーレイ(モーダル)として開く — 出典シートとは
 * 違い、本文や出典シートと同時に操作できる必要はないので、幅に関わらず
 * 覆いかぶさる。並びはトピックごとの縦一列。開いている間だけマウントされる。
 */
export const ReviewCardListDrawer: React.FC<ReviewCardListDrawerProps> = ({
  title,
  groups,
  imageUrls,
  currentIndex,
  typeLabel,
  onSelect,
  onClose,
}) => (
  <aside className="pv-list-overlay">
    <div className="pv-drawer-head">
      <span className="pv-drawer-title">{title}</span>
      <button type="button" className="pv-icon-btn" onClick={onClose} aria-label="Close list">
        <X size={18} />
      </button>
    </div>

    <div className="pv-drawer-scroll">
      {groups.map((group, gi) => {
        const coverUrl = group.topic.image_path ? imageUrls[group.topic.image_path] : undefined;
        return (
          <section className="pv-drawer-group" key={group.topic.id}>
            <h2 className="pv-drawer-group-title">{group.topic.topic_title}</h2>

            <button
              type="button"
              className={`pv-tile-cover ${currentIndex === group.startIndex ? 'is-current' : ''}`}
              onClick={() => onSelect(group.startIndex)}
            >
              {coverUrl ? <img src={coverUrl} alt="" /> : <span className="pv-cover-fallback" />}
              <span className="pv-tile-cover-band">{`Topic ${gi + 1}`}</span>
            </button>

            {group.cards.map((card, ci) => {
              const flatIndex = group.startIndex + ci + 1;
              const preview = card.title?.trim() || plainTextPreview(card.card_content);
              return (
                <button
                  key={card.id}
                  type="button"
                  className={`pv-tile ${currentIndex === flatIndex ? 'is-current' : ''}`}
                  style={{ ['--pv-type' as string]: reviewCardTypeColor(card.card_type) }}
                  onClick={() => onSelect(flatIndex)}
                >
                  <span className="pv-tile-emoji" aria-hidden="true">
                    {card.hero_emoji?.trim() || '💡'}
                  </span>
                  <span className="pv-tile-text">
                    <span className="pv-tile-label">{typeLabel(card.card_type)}</span>
                    <span className="pv-tile-title">{preview}</span>
                  </span>
                </button>
              );
            })}
          </section>
        );
      })}
    </div>
  </aside>
);
