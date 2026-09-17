import React from 'react';
import { Heart, ThumbsDown } from 'lucide-react';
import type { Reaction } from '../types/content';

interface ReactionBarProps {
  reaction: Reaction;
  onChange: (reaction: 'like' | 'dislike') => void;
}

/** Flutter版(Icons.favorite/favorite_border + Icons.thumb_down/thumb_down_alt_outlined)に揃える。 */
export const ReactionBar: React.FC<ReactionBarProps> = ({ reaction, onChange }) => (
  <div className="reaction-bar">
    <button
      type="button"
      className={`icon-button ${reaction === 'like' ? 'is-active' : ''}`}
      onClick={() => onChange('like')}
      aria-pressed={reaction === 'like'}
      aria-label="Helpful"
      title="Helpful"
    >
      <Heart size={16} fill={reaction === 'like' ? 'currentColor' : 'none'} />
    </button>
    <button
      type="button"
      className={`icon-button ${reaction === 'dislike' ? 'is-active' : ''}`}
      onClick={() => onChange('dislike')}
      aria-pressed={reaction === 'dislike'}
      aria-label="Not helpful"
      title="Not helpful"
    >
      <ThumbsDown size={16} fill={reaction === 'dislike' ? 'currentColor' : 'none'} />
    </button>
  </div>
);
