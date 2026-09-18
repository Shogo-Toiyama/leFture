import React from 'react';
import { Lock, X } from 'lucide-react';
import type { LectureTopic } from '../../types/content';

export interface DeepNoteEntry {
  topic: LectureTopic;
  summary: string;
  /** trueならこのトピックのDeepNotesはプラン制限で生成されていない(deep_notes_list_page.dart準拠)。 */
  isLocked?: boolean;
}

interface DeepNoteListDrawerProps {
  title: string;
  entries: DeepNoteEntry[];
  currentIndex: number;
  closeLabel: string;
  onSelect: (position: number) => void;
  onClose: () => void;
}

/**
 * ノート一覧。常に左からのオーバーレイ(モーダル)として開く(復習カードと
 * 同じ構え)。本文や出典シートと同時に操作できる必要はないので、幅に関わらず
 * 覆いかぶさる。開いている間だけマウントされる。
 */
export const DeepNoteListDrawer: React.FC<DeepNoteListDrawerProps> = ({
  title,
  entries,
  currentIndex,
  closeLabel,
  onSelect,
  onClose,
}) => (
  <aside className="pv-list-overlay">
    <div className="pv-drawer-head">
      <span className="pv-drawer-title">{title}</span>
      <button type="button" className="pv-icon-btn" onClick={onClose} aria-label={closeLabel}>
        <X size={18} />
      </button>
    </div>

    <div className="pv-drawer-scroll">
      {entries.map((entry, i) => (
        <button
          key={entry.topic.id}
          type="button"
          className={`pv-tile is-stacked ${i === currentIndex ? 'is-current' : ''} ${entry.isLocked ? 'is-locked' : ''}`}
          onClick={() => onSelect(i)}
        >
          <span className="pv-tile-badge">{i + 1}</span>
          <span className="pv-tile-text">
            <span className="pv-tile-title">{entry.topic.topic_title}</span>
            {entry.summary && <span className="pv-tile-summary">{entry.summary}</span>}
          </span>
          {entry.isLocked && <Lock size={14} className="pv-tile-lock" />}
        </button>
      ))}
    </div>
  </aside>
);
