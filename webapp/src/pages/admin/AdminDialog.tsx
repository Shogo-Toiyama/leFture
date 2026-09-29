import React, { useEffect, useRef } from 'react';
import { X } from 'lucide-react';
import { ErrorLine, useAdminAction } from './adminUi';

export const AdminDialog: React.FC<{
  open: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
}> = ({ open, onClose, title, children }) => {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);
  return (
    <dialog ref={ref} className="adm-root adm-dialog" onClose={onClose} onCancel={onClose}>
      <div className="adm-dialog-head">
        <h2 className="adm-card-title">{title}</h2>
        <button type="button" className="adm-icon-btn" onClick={onClose} aria-label="閉じる">
          <X size={16} />
        </button>
      </div>
      {open && children}
    </dialog>
  );
};

/**
 * 実行ボタン付きの確認ダイアログ。children にフォーム項目を置き、
 * canSubmit で送信可否を決める。onConfirm が成功したら閉じる。
 */
export const ActionDialog: React.FC<{
  open: boolean;
  onClose: () => void;
  title: string;
  confirmLabel: string;
  danger?: boolean;
  canSubmit?: boolean;
  onConfirm: () => Promise<unknown>;
  onDone?: () => void;
  children?: React.ReactNode;
}> = ({ open, onClose, title, confirmLabel, danger, canSubmit = true, onConfirm, onDone, children }) => {
  const { busy, error, run, setError } = useAdminAction();

  useEffect(() => {
    if (open) setError(null);
  }, [open, setError]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    let ok = false;
    await run(async () => {
      await onConfirm();
      ok = true;
    });
    if (ok) {
      onClose();
      onDone?.();
    }
  };

  return (
    <AdminDialog open={open} onClose={onClose} title={title}>
      <form className="adm-dialog-body" onSubmit={submit}>
        {children}
        <ErrorLine message={error} />
        <div className="adm-dialog-actions">
          <button type="button" className="adm-btn" onClick={onClose} disabled={busy}>
            キャンセル
          </button>
          <button
            type="submit"
            className={`adm-btn ${danger ? 'adm-btn-danger-solid' : 'adm-btn-primary'}`}
            disabled={busy || !canSubmit}
          >
            {busy ? '実行中…' : confirmLabel}
          </button>
        </div>
      </form>
    </AdminDialog>
  );
};
