import React from 'react';
import type { Reaction } from '../types/content';

interface ReactionBarProps {
  reaction: Reaction;
  onChange: (reaction: 'like' | 'dislike') => void;
}

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
      👍
    </button>
    <button
      type="button"
      className={`icon-button ${reaction === 'dislike' ? 'is-active' : ''}`}
      onClick={() => onChange('dislike')}
      aria-pressed={reaction === 'dislike'}
      aria-label="Not helpful"
      title="Not helpful"
    >
      👎
    </button>
  </div>
);
