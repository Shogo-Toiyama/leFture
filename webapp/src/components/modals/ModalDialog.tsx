import React, { useEffect } from 'react';

export interface ModalDialogProps {
  title: string;
  count?: number;
  onClose: () => void;
  children: React.ReactNode;
  maxWidth?: number | string;
}

export const ModalDialog: React.FC<ModalDialogProps> = ({
  title,
  count,
  onClose,
  children,
  maxWidth = 680,
}) => {
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  return (
    <div className="lecture-modal-backdrop" onClick={onClose}>
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
