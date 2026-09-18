import React from 'react';
import { TranscriptView } from './TranscriptView';

interface TranscriptSheetProps {
  lectureId: string;
  sids: string[];
  onClose: () => void;
}

/**
 * 出典表示用のトランスクリプトシート。
 * 広い画面では本文の左に「並べて」置き(本文を覆わない)、
 * 狭い画面ではボトムシートとして上に重ねる。切り替えはCSSの側で行う。
 */
export const TranscriptSheet: React.FC<TranscriptSheetProps> = ({ lectureId, sids, onClose }) => (
  <aside className="pv-panel tsheet is-gold">
    <TranscriptView
      lectureId={lectureId}
      highlightSids={new Set(sids)}
      onClose={onClose}
      variant="sheet"
    />
  </aside>
);
