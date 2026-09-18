import React, { useEffect } from 'react';
import { X, AlertTriangle } from 'lucide-react';

export interface ConfirmModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm?: () => void;
  title: string;
  message: React.ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  isDanger?: boolean;
  hideCancel?: boolean;
}

export const ConfirmModal: React.FC<ConfirmModalProps> = ({
  open,
  onClose,
  onConfirm,
  title,
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  isDanger = false,
  hideCancel = false,
}) => {
  useEffect(() => {
    if (!open) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="lecture-modal-backdrop"
      style={{ zIndex: 1100, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }}
      onClick={onClose}
    >
      <div
        className="lecture-modal-card"
        style={{
          maxWidth: 440,
          width: '100%',
          background: '#121422',
          border: '1px solid var(--glass-border)',
          borderRadius: 16,
          boxShadow: '0 20px 48px rgba(0, 0, 0, 0.7)',
          overflow: 'hidden',
          animation: 'sheet-fade-in 0.2s ease-out',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '1.25rem 1.4rem 0.75rem',
            borderBottom: '1px solid rgba(255, 255, 255, 0.08)',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
            {isDanger && <AlertTriangle size={20} color="var(--correction-red, #ff5252)" />}
            <h3 style={{ margin: 0, fontSize: '1.15rem', color: '#fff', fontWeight: 700 }}>{title}</h3>
          </div>
          <button
            type="button"
            className="adaptive-sheet-close-btn"
            onClick={onClose}
            aria-label="Close"
          >
            <X size={18} />
          </button>
        </div>

        <div style={{ padding: '1.25rem 1.4rem', color: 'var(--universe-text, #f2f2f2)', fontSize: '0.92rem', lineHeight: 1.5 }}>
          {message}
        </div>

        <div
          style={{
            display: 'flex',
            justifyContent: 'flex-end',
            gap: '0.75rem',
            padding: '0.9rem 1.4rem 1.25rem',
            borderTop: '1px solid rgba(255, 255, 255, 0.06)',
          }}
        >
          {!hideCancel && (
            <button
              type="button"
              className="btn btn-ghost"
              onClick={onClose}
              style={{
                fontSize: '0.88rem',
                background: 'rgba(255, 255, 255, 0.08)',
                color: '#ffffff',
                border: '1px solid rgba(255, 255, 255, 0.2)',
                borderRadius: '8px',
                padding: '0.55rem 1.15rem',
                cursor: 'pointer',
                fontWeight: 600,
              }}
            >
              {cancelLabel}
            </button>
          )}
          <button
            type="button"
            className={isDanger ? 'btn btn-danger' : 'btn btn-primary'}
            style={
              isDanger
                ? {
                    background: 'var(--correction-red, #ff5252)',
                    color: '#ffffff',
                    border: '1px solid transparent',
                    borderRadius: '8px',
                    padding: '0.55rem 1.15rem',
                    fontSize: '0.88rem',
                    cursor: 'pointer',
                    fontWeight: 600,
                  }
                : {
                    background: 'var(--gold)',
                    color: '#241a00',
                    border: '1px solid transparent',
                    borderRadius: '8px',
                    padding: '0.55rem 1.15rem',
                    fontSize: '0.88rem',
                    cursor: 'pointer',
                    fontWeight: 600,
                  }
            }
            onClick={() => {
              if (onConfirm) onConfirm();
              onClose();
            }}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
};
