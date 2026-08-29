import React, { useEffect, useRef } from 'react';

interface ModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
}

export const Modal: React.FC<ModalProps> = ({ open, onClose, title, children }) => {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog ref={dialogRef} className="modal" onClose={onClose} onCancel={onClose}>
      <div className="modal-header">
        <h2>{title}</h2>
        <button type="button" className="modal-close" onClick={onClose} aria-label="Close">
          ×
        </button>
      </div>
      <div className="modal-body">{children}</div>
    </dialog>
  );
};
