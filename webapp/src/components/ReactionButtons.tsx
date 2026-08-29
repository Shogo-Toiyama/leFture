import React from 'react';
import type { Reaction } from '../types/content';

interface ReactionButtonsProps {
  reaction: Reaction;
  onChange: (reaction: 'like' | 'dislike') => void;
}

export const ReactionButtons: React.FC<ReactionButtonsProps> = ({ reaction, onChange }) => (
  <div className="reaction-buttons">
    <button
      type="button"
      className={reaction === 'like' ? 'reaction-active' : ''}
      onClick={() => onChange('like')}
      aria-label="Like"
    >
      👍
    </button>
    <button
      type="button"
      className={reaction === 'dislike' ? 'reaction-active' : ''}
      onClick={() => onChange('dislike')}
      aria-label="Dislike"
    >
      👎
    </button>
  </div>
);
