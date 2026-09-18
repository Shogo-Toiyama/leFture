import React from 'react';
import { PvHeaderSkeleton } from '../PvHeaderSkeleton';

const LINE_WIDTHS = [96, 88, 92, 60, 84, 90, 70];

export const DeepNotesDetailSkeleton: React.FC = () => {
  return (
    <div className="pv-root">
      <div className="pv-split">
        <div className="pv-column">
          <PvHeaderSkeleton />

          <div className="dnv-scroll">
            <div className="dnv-sheet">
              <div className="dnv-hero">
                <span className="skeleton" style={{ width: '100%', height: '100%', display: 'block', borderRadius: 'inherit' }} />
              </div>

              <span className="skeleton" style={{ width: '70%', height: 28, borderRadius: 8, display: 'block', marginBottom: 12 }} />
              <span className="skeleton" style={{ width: '95%', height: 15, borderRadius: 6, display: 'block', marginBottom: 6 }} />
              <span className="skeleton" style={{ width: '60%', height: 15, borderRadius: 6, display: 'block', marginBottom: 24 }} />

              {LINE_WIDTHS.map((w, i) => (
                <span
                  key={i}
                  className="skeleton"
                  style={{ width: `${w}%`, height: 14, borderRadius: 6, display: 'block', marginBottom: 10 }}
                />
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
