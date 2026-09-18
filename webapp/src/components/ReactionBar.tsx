import React from 'react';
import { Heart, ThumbsDown } from 'lucide-react';
import type { Reaction } from '../types/content';

interface ReactionBarProps {
  reaction: Reaction;
  onChange: (reaction: 'like' | 'dislike') => void;
}

/** 枠線なしでそのまま置かれたスタイリッシュなアイコンボタン */
export const ReactionBar: React.FC<ReactionBarProps> = ({ reaction, onChange }) => (
  <div className="reaction-bar">
    <button
      type="button"
      className={`reaction-icon-btn ${reaction === 'like' ? 'is-liked' : ''}`}
      onClick={() => onChange('like')}
      aria-pressed={reaction === 'like'}
      aria-label="Helpful"
      title="Helpful"
    >
      <Heart size={18} fill={reaction === 'like' ? 'currentColor' : 'none'} strokeWidth={2} />
    </button>
    <button
      type="button"
      className={`reaction-icon-btn ${reaction === 'dislike' ? 'is-disliked' : ''}`}
      onClick={() => onChange('dislike')}
      aria-pressed={reaction === 'dislike'}
      aria-label="Not helpful"
      title="Not helpful"
    >
      <ThumbsDown size={18} fill={reaction === 'dislike' ? 'currentColor' : 'none'} strokeWidth={2} />
    </button>
  </div>
);
