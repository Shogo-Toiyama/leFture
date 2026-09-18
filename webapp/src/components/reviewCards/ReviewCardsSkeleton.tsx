import React from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { PvHeaderSkeleton } from '../PvHeaderSkeleton';

export const ReviewCardsSkeleton: React.FC = () => {
  return (
    <div className="pv-root">
      <div className="pv-split">
        <div className="pv-column">
          <header className="pv-top">
            <PvHeaderSkeleton bare>
              <div className="rcv-progress">
                {[0, 1, 2].map((g) => (
                  <div className="rcv-progress-group" key={g}>
                    {[0, 1, 2].map((seg) => (
                      <span key={seg} className="rcv-seg skeleton" style={{ background: 'none' }} />
                    ))}
                  </div>
                ))}
              </div>
            </PvHeaderSkeleton>
          </header>

          <div className="rcv-stage">
            <span className="pv-nav-btn" style={{ opacity: 0.4, pointerEvents: 'none' }}>
              <ChevronLeft size={22} />
            </span>

            <div className="rcv-stack">
              <span
                className="skeleton"
                style={{ width: '100%', height: '100%', display: 'block', borderRadius: 24 }}
              />
            </div>

            <span className="pv-nav-btn" style={{ opacity: 0.4, pointerEvents: 'none' }}>
              <ChevronRight size={22} />
            </span>
          </div>

          <p className="pv-hint">
            <span className="skeleton" style={{ width: 140, height: 12, borderRadius: 6, display: 'inline-block' }} />
          </p>
        </div>
      </div>
    </div>
  );
};
