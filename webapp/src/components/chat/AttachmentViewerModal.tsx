import React, { useEffect, useRef, useState } from 'react';
import { AlertCircle, ExternalLink, FileText, ImageIcon, Paperclip, Presentation, X } from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import { getChatAttachmentFileUrl } from '../../lib/chat';
import type {
  ChatAttachment,
  ChatAttachmentKind,
  ChatAttachmentSection,
  ChatAttachmentStatus,
} from '../../types/chat';

/** 見せる資料。送った資料(DBの行)のほか、送る前・送信中の下書きも同じ形で見せる。 */
export interface ViewableAttachment {
  title: string | null;
  content: string;
  status?: ChatAttachmentStatus;
  summary?: string | null;
  sections?: ChatAttachmentSection[];
  kind?: ChatAttachmentKind;
  /** 送ったファイルのとき: 元のファイル(画像なら画像)を開くための資料のid */
  fileId?: string;
  pageCount?: number | null;
}

export function viewableFromAttachment(a: ChatAttachment): ViewableAttachment {
  return {
    title: a.title || a.file_name,
    content: a.content,
    status: a.status,
    summary: a.summary,
    sections: a.sections,
    kind: a.kind,
    fileId: a.kind !== 'text' ? a.id : undefined,
    pageCount: a.page_count,
  };
}

/** 資料の種類のアイコン(入力欄・会話の中のチップ・一覧で使う)。 */
export const AttachmentKindIcon: React.FC<{ kind: ChatAttachmentKind; size?: number }> = ({ kind, size = 12 }) => {
  if (kind === 'image') return <ImageIcon size={size} />;
  if (kind === 'pptx') return <Presentation size={size} />;
  if (kind === 'pdf' || kind === 'docx') return <FileText size={size} />;
  return <Paperclip size={size} />;
};

interface AttachmentViewerModalProps {
  attachment: ViewableAttachment | null;
  /** 渡すと「この会話から外す」ボタンを出す(送った資料のときだけ)。 */
  onRemove?: () => Promise<void>;
  onClose: () => void;
}

/** 資料を読む(編集はできない)。目次があれば、押すとその節の本文へ飛ぶ。 */
export const AttachmentViewerModal: React.FC<AttachmentViewerModalProps> = ({ attachment, onRemove, onClose }) => {
  const { t, formatNumber } = useLanguage();
  const bodyRef = useRef<HTMLDivElement>(null);
  const [confirmingRemove, setConfirmingRemove] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [removeFailed, setRemoveFailed] = useState(false);
  /** 画像の資料: 表示する画像の署名付きURL(開いたときに頼む) */
  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const [openingFile, setOpeningFile] = useState(false);
  const [openFailed, setOpenFailed] = useState(false);

  const fileId = attachment?.fileId;
  const isImage = attachment?.kind === 'image';
  useEffect(() => {
    setImageUrl(null);
    setOpenFailed(false);
    if (!fileId || !isImage) return;
    let cancelled = false;
    getChatAttachmentFileUrl(fileId)
      .then((r) => !cancelled && setImageUrl(r.url))
      .catch(() => !cancelled && setOpenFailed(true));
    return () => {
      cancelled = true;
    };
  }, [fileId, isImage]);

  useEffect(() => {
    setConfirmingRemove(false);
    setRemoveFailed(false);
    if (!attachment) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [attachment, onClose]);

  if (!attachment) return null;

  const sections = attachment.sections ?? [];
  const title = attachment.title || t('chatAttachmentUntitled');
  const jumpTo = (index: number) => {
    const el = bodyRef.current?.querySelector<HTMLElement>(`[data-section="${index}"]`);
    el?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  /** 元のファイルを新しいタブで開く(署名付きURLは短い時間だけ有効なので、押したときに頼む)。 */
  const openOriginal = async () => {
    if (!attachment.fileId) return;
    // ポップアップブロックを避けるため、先にタブを開いてから行き先を入れる
    const tab = window.open('', '_blank');
    setOpeningFile(true);
    setOpenFailed(false);
    try {
      const { url } = await getChatAttachmentFileUrl(attachment.fileId);
      if (tab) {
        tab.opener = null;
        tab.location.href = url;
      } else {
        window.location.href = url;
      }
    } catch {
      tab?.close();
      setOpenFailed(true);
    } finally {
      setOpeningFile(false);
    }
  };

  const remove = async () => {
    if (!onRemove) return;
    setRemoving(true);
    setRemoveFailed(false);
    try {
      await onRemove();
      onClose();
    } catch {
      setRemoveFailed(true);
    } finally {
      setRemoving(false);
    }
  };

  return (
    <div className="citation-modal-backdrop" onClick={onClose}>
      <div
        className="citation-modal-card chat-attachment-modal"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="citation-modal-grab-bar" aria-hidden="true">
          <span className="citation-modal-grab-handle" />
        </div>
        <div className="citation-modal-header">
          <div className="citation-modal-title-group">
            <div className="citation-modal-badges">
              <span className="citation-modal-badge-kind">
                <AttachmentKindIcon kind={attachment.kind ?? 'text'} size={14} />
                <span>{t('chatSourceAttachment')}</span>
              </span>
              {attachment.kind === 'pdf' && attachment.pageCount ? (
                <span className="citation-modal-badge-meta">{t('chatFilePages', { count: attachment.pageCount })}</span>
              ) : attachment.kind === 'pptx' && attachment.pageCount ? (
                <span className="citation-modal-badge-meta">{t('chatFileSlides', { count: attachment.pageCount })}</span>
              ) : null}
              {attachment.content.length > 0 && (
                <span className="citation-modal-badge-meta">
                  {t('chatAttachmentChars', { count: formatNumber(attachment.content.length) })}
                </span>
              )}
              {attachment.status && attachment.status !== 'ready' && <AttachmentStatusBadge status={attachment.status} />}
            </div>
            <h3 className="citation-modal-title">{title}</h3>
          </div>
          <button type="button" className="citation-modal-close-btn" onClick={onClose} aria-label={t('close')}>
            <X size={18} />
          </button>
        </div>

        <div className="citation-modal-body chat-attachment-viewer" ref={bodyRef}>
          {isImage && attachment.fileId && (
            <div className="chat-attachment-viewer-image">
              {imageUrl ? (
                <a href={imageUrl} target="_blank" rel="noreferrer">
                  <img src={imageUrl} alt={title} />
                </a>
              ) : (
                !openFailed && <span className="chat-attachment-viewer-image-loading">{t('chatAttachmentImageLoading')}</span>
              )}
            </div>
          )}
          {attachment.summary && <p className="chat-attachment-viewer-summary">{attachment.summary}</p>}

          {sections.length > 1 && (
            <nav className="chat-attachment-toc" aria-label={t('chatAttachmentContents')}>
              <h4>{t('chatAttachmentContents')}</h4>
              <ol>
                {sections.map((s) => (
                  <li key={s.index}>
                    <button type="button" onClick={() => jumpTo(s.index)}>
                      <span className="chat-attachment-toc-title">{s.title}</span>
                      {s.description && <span className="chat-attachment-toc-desc">{s.description}</span>}
                    </button>
                  </li>
                ))}
              </ol>
            </nav>
          )}

          <h4 className="chat-attachment-viewer-heading">{t('chatAttachmentFullText')}</h4>
          {sections.length > 1 ? (
            sections.map((s) => (
              <section key={s.index} data-section={s.index} className="chat-attachment-viewer-section">
                <span className="chat-attachment-viewer-section-label">
                  {s.index}. {s.title}
                </span>
                <div className="chat-attachment-viewer-text">{attachment.content.slice(s.start, s.end).trim()}</div>
              </section>
            ))
          ) : (
            <div className="chat-attachment-viewer-text">{attachment.content}</div>
          )}
        </div>

        <div className="citation-modal-footer">
          {openFailed && (
            <span className="chat-attachment-remove-error" role="alert">
              <AlertCircle size={14} />
              {t('chatAttachmentOpenFileFailed')}
            </span>
          )}
          {attachment.fileId && !isImage && !confirmingRemove && (
            <button
              type="button"
              className="citation-modal-btn-secondary chat-attachment-open-file"
              disabled={openingFile}
              onClick={() => void openOriginal()}
            >
              <ExternalLink size={14} />
              {t('chatAttachmentOpenFile')}
            </button>
          )}
          {removeFailed && (
            <span className="chat-attachment-remove-error" role="alert">
              <AlertCircle size={14} />
              {t('chatAttachmentRemoveFailed')}
            </span>
          )}
          {onRemove &&
            (confirmingRemove ? (
              <div className="chat-attachment-remove-confirm">
                <span>{t('chatAttachmentRemoveConfirm')}</span>
                <button type="button" className="citation-modal-btn-secondary" onClick={() => setConfirmingRemove(false)}>
                  {t('cancel')}
                </button>
                <button type="button" className="citation-modal-btn-danger" disabled={removing} onClick={remove}>
                  {t('chatAttachmentRemove')}
                </button>
              </div>
            ) : (
              <button type="button" className="citation-modal-btn-secondary" onClick={() => setConfirmingRemove(true)}>
                {t('chatAttachmentRemove')}
              </button>
            ))}
          {!confirmingRemove && (
            <button type="button" className="citation-modal-btn-secondary" onClick={onClose}>
              {t('chatClose')}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

/** 資料の状態(確認中・使えなかった)の小さな印。 */
export const AttachmentStatusBadge: React.FC<{ status: ChatAttachmentStatus }> = ({ status }) => {
  const { t } = useLanguage();
  if (status === 'ready') return null;
  const key =
    status === 'processing'
      ? 'chatAttachmentProcessing'
      : status === 'blocked'
        ? 'chatAttachmentBlocked'
        : 'chatAttachmentFailed';
  return <span className={`chat-attachment-status is-${status}`}>{t(key)}</span>;
};
