import React, { useEffect } from 'react';

export interface ModalDialogProps {
  title: string;
  count?: number;
  onClose: () => void;
  children: React.ReactNode;
  maxWidth?: number | string;
  /**
   * 指定すると、このモーダルを閉じずにバックドロップの左側へ固定パネルとして
   * 表示し、カード本体はその右側へ寄せる(例: アナウンスからのトランスクリプト
   * 表示。AnnouncementsModal + TranscriptSheetの二重表示に使う)。
   */
  sidePanel?: React.ReactNode;
}

export const ModalDialog: React.FC<ModalDialogProps> = ({
  title,
  count,
  onClose,
  children,
  maxWidth = 680,
  sidePanel,
}) => {
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  return (
    <div className={`lecture-modal-backdrop ${sidePanel ? 'has-side-panel' : ''}`} onClick={onClose}>
      {sidePanel && (
        <div className="lecture-modal-side-panel" onClick={(e) => e.stopPropagation()}>
          {sidePanel}
        </div>
      )}
      <div
        className="lecture-modal-card"
        style={{ maxWidth }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="lecture-modal-header">
          <div className="modal-title-row">
            <h2>{title}</h2>
            {count !== undefined && <span className="modal-count-badge">{count}</span>}
          </div>
          <button type="button" className="modal-close-btn" onClick={onClose} aria-label="Close">
            ✕
          </button>
        </div>
        <div className="lecture-modal-body">{children}</div>
      </div>
    </div>
  );
};
