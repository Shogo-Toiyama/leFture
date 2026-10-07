import React, { useEffect } from 'react';
import { AlertCircle, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import type { ChatFileDraft } from '../../types/chat';
import { AttachmentKindIcon } from './AttachmentViewerModal';

interface DraftPreviewModalProps {
  /** 見せる下書き(nullなら閉じている)。 */
  draft: ChatFileDraft | null;
  /** 準備できなかった理由の文言(fileErrorCopyの結果)。 */
  errorText?: string;
  onRemove: () => void;
  onClose: () => void;
}

/**
 * 送る前のファイルの中身を確かめる(入力欄のチップ・「@名前」から開く)。画像はそのまま、PDFは端末の
 * ファイルをブラウザで表示する。Word・PowerPointはブラウザで表示できないので、取り出して分かったこと
 * (ページ数・文字数・画像として読む数)を見せる(送った後は資料のビューアで本文と元のファイルを開ける)。
 */
export const DraftPreviewModal: React.FC<DraftPreviewModalProps> = ({ draft, errorText, onRemove, onClose }) => {
  const { t, formatNumber } = useLanguage();

  useEffect(() => {
    if (!draft) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [draft, onClose]);

  if (!draft) return null;
  const info = draft.info;
  const facts: string[] = [];
  if (info?.page_count && info.kind === 'pdf') facts.push(t('chatFilePages', { count: info.page_count }));
  if (info?.page_count && info.kind === 'pptx') facts.push(t('chatFileSlides', { count: info.page_count }));
  if (info && info.kind !== 'image') facts.push(t('chatAttachmentChars', { count: formatNumber(info.text_chars) }));
  if (info && info.kind !== 'image' && info.vision_count > 0) {
    facts.push(t('chatFileVisionCount', { count: info.vision_count }));
  }
  const stageKey: Record<ChatFileDraft['stage'], TranslationKey | null> = {
    compressing: 'chatFileCompressing',
    uploading: 'chatFileUploadingShort',
    reading: 'chatFileReading',
    ready: null,
    error: null,
  };
  const stage = stageKey[draft.stage];

  return (
    <div className="citation-modal-backdrop" onClick={onClose}>
      <div
        className="citation-modal-card chat-attachment-modal"
        role="dialog"
        aria-modal="true"
        aria-label={draft.fileName}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="citation-modal-grab-bar" aria-hidden="true">
          <span className="citation-modal-grab-handle" />
        </div>
        <div className="citation-modal-header">
          <div className="citation-modal-title-group">
            <div className="citation-modal-badges">
              <span className="citation-modal-badge-kind">
                <AttachmentKindIcon kind={draft.fileKind} size={14} />
                <span>{t('chatDraftPreviewBadge')}</span>
              </span>
              {stage && <span className="citation-modal-badge-meta">{t(stage)}</span>}
            </div>
            <h3 className="citation-modal-title">{draft.fileName}</h3>
          </div>
          <button type="button" className="citation-modal-close-btn" onClick={onClose} aria-label={t('close')}>
            <X size={18} />
          </button>
        </div>

        <div className="citation-modal-body chat-attachment-viewer">
          {draft.stage === 'error' && (
            <p className="chat-draft-preview-error" role="alert">
              <AlertCircle size={15} />
              <span>{errorText}</span>
            </p>
          )}
          {draft.previewUrl ? (
            <div className="chat-attachment-viewer-image">
              <img src={draft.previewUrl} alt={draft.fileName} />
            </div>
          ) : draft.localUrl && draft.fileKind === 'pdf' ? (
            <iframe className="chat-draft-preview-pdf" src={draft.localUrl} title={draft.fileName} />
          ) : (
            draft.fileKind !== 'image' && (
              <p className="chat-draft-preview-note">{t('chatDraftPreviewOffice')}</p>
            )
          )}
          {facts.length > 0 && <p className="chat-draft-preview-facts">{facts.join(' · ')}</p>}
          {info && info.vision_pages.length > 0 && (
            <p className="chat-draft-preview-note">
              {t('chatDraftPreviewVisionPages', { pages: info.vision_pages.slice(0, 20).join(', ') })}
            </p>
          )}
        </div>

        <div className="citation-modal-footer">
          <button
            type="button"
            className="citation-modal-btn-secondary"
            onClick={() => {
              onRemove();
              onClose();
            }}
          >
            {t('chatRemoveAttachment')}
          </button>
          <button type="button" className="citation-modal-btn-secondary" onClick={onClose}>
            {t('chatClose')}
          </button>
        </div>
      </div>
    </div>
  );
};
