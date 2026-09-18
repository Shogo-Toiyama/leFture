import React from 'react';

interface ReviewCoverCardProps {
  title: string;
  kicker: string;
  imageUrl: string | null;
}

/** トピックの表紙カード。_CoverCard(Flutter)と同じく画像の下端に白帯でタイトルを敷く。 */
export const ReviewCoverCard: React.FC<ReviewCoverCardProps> = ({ title, kicker, imageUrl }) => (
  <article className="rcv-card is-cover">
    <div className="rcv-cover">
      {imageUrl ? (
        <img className="rcv-cover-img" src={imageUrl} alt="" />
      ) : (
        <div className="pv-cover-fallback" />
      )}
      <div className="rcv-cover-band">
        <span className="rcv-cover-kicker">{kicker}</span>
        {title}
      </div>
    </div>
  </article>
);
