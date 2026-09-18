import React from 'react';

const LINE_WIDTHS = [92, 78, 85, 60, 90, 70, 95, 55, 80, 88];

/** 呼び出し側の .tsv-sheet の中身として差し込む(自前のラッパーは持たない)。 */
export const TranscriptViewSkeleton: React.FC = () => {
  return (
    <div aria-busy="true" aria-live="polite">
      <div className="tsv-topic-head" style={{ ['--seg' as string]: 'var(--deep-gold)' }}>
        <span className="tsv-topic-bar" />
        <span className="skeleton" style={{ width: 60, height: 12, borderRadius: 6 }} />
        <span className="skeleton" style={{ width: 160, height: 12, borderRadius: 6 }} />
      </div>

      {LINE_WIDTHS.map((w, i) => (
        <div className="tsv-line" key={i}>
          <span className="skeleton" style={{ width: '3.1rem', height: 13, borderRadius: 6, flexShrink: 0 }} />
          <span className="skeleton" style={{ width: `${w}%`, height: 13, borderRadius: 6 }} />
        </div>
      ))}
    </div>
  );
};
