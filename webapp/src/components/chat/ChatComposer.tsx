import React, { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import {
  AlertCircle,
  ArrowUp,
  BookOpen,
  FileText,
  Files,
  LoaderCircle,
  Paperclip,
  Plus,
  Quote,
  Upload,
  X,
} from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import {
  CHAT_MAX_ATTACHMENTS_PER_MESSAGE,
  CHAT_MAX_MESSAGE_CHARS,
  type ChatAttachment,
  type ChatDraftAttachment,
  type ChatFileDraft,
} from '../../types/chat';
import { newClientMessageId, removeChatAttachment } from '../../lib/chat';
import {
  CHAT_FILE_ACCEPT,
  ChatFileError,
  fileKindFor,
  isTextFile,
  prepareChatFile,
  readTextFile,
} from '../../lib/chatFiles';
import { AttachmentEditorModal, type AttachmentEditorValue } from './AttachmentEditorModal';
import { AttachmentKindIcon } from './AttachmentViewerModal';

interface ChatComposerProps {
  disabled: boolean;
  placeholder: string;
  /** 送信。draftsはこの送信で添付する資料(無ければ空)。 */
  onSend: (content: string, drafts: ChatDraftAttachment[]) => void;
  /** 次の送信に添える選択テキスト(チップとして見せ、外せる)。 */
  selectedText: string | null;
  onClearSelectedText?: () => void;
  /** 話題にしている講義名(チップとして見せ、外せる)。 */
  lectureTitle: string | null;
  onDetachLecture?: () => void;
  /** 全文で読ませている資料(チップとして見せ、×で全文で読むのをやめられる)。 */
  selectedAttachments?: ChatAttachment[];
  onUnselectAttachment?: (attachmentId: string) => void;
  /** この会話に選べる資料があるか(＋メニューの「既存の資料を選ぶ」を押せるか)。 */
  hasAttachments?: boolean;
  /** ＋メニューの「既存の資料を選ぶ」: 資料の一覧を開く。 */
  onOpenAttachmentList?: () => void;
  /** 候補の質問を押したとき・送れなかった送信を戻すときに、外から入力欄(と資料)を埋める。 */
  prefill?: { text: string; attachments?: ChatDraftAttachment[]; nonce: number } | null;
  /** 会話の上にドロップされたファイル(nonceが変わるたびに添付する)。 */
  droppedFiles?: { files: File[]; nonce: number } | null;
  autoFocus?: boolean;
}

/** 入力欄が伸びる上限(行数ではなく高さで止める)。 */
const MAX_TEXTAREA_HEIGHT = 168;
/** 文字数の残りを出し始める目安。 */
const COUNTER_THRESHOLD = CHAT_MAX_MESSAGE_CHARS - 500;

/** 編集モーダルの状態: 新しく添付する(貼り付けから来たか) / 下書きを直す。 */
type EditorState =
  | { mode: 'new'; value: AttachmentEditorValue; fromPaste: boolean }
  | { mode: 'edit'; localId: string; value: AttachmentEditorValue };

export type Copy = { key: TranslationKey; params?: Record<string, string | number> };

/** チップに出す名前(名前が無ければ本文の最初の行・ファイル名)。 */
function draftLabel(draft: ChatDraftAttachment): string {
  if (draft.title.trim()) return draft.title.trim();
  if (draft.kind === 'file') return draft.fileName;
  return draft.content.split('\n').find((line) => line.trim())?.trim() ?? '';
}

/** ファイルを準備できなかった理由の文言。 */
export function fileErrorCopy(code: string | undefined, detail: Record<string, unknown> = {}): Copy {
  const mb = (bytes: unknown) => (typeof bytes === 'number' ? Math.round(bytes / (1024 * 1024)) : 30);
  switch (code) {
    case 'UNSUPPORTED_FILE_TYPE':
      return { key: 'chatFileErrorUnsupported' };
    case 'FILE_TOO_LARGE':
      return { key: 'chatFileErrorTooLarge', params: { max: mb(detail.max_bytes) } };
    case 'FILE_TOO_LARGE_MEDIA':
      return { key: 'chatFileErrorTooLargeMedia', params: { max: mb(detail.max_bytes) } };
    case 'PDF_ENCRYPTED':
      return { key: 'chatFileErrorEncrypted' };
    case 'FILE_EMPTY':
      return { key: 'chatFileErrorEmpty' };
    case 'TOO_MANY_PAGES':
      return { key: 'chatFileErrorTooManyPages', params: { max: Number(detail.max_pages) || 500 } };
    case 'TOO_MANY_IMAGES':
      return { key: 'chatFileErrorTooManyImages', params: { max: Number(detail.max_images) || 60 } };
    case 'ATTACHMENT_TOO_LONG':
      return { key: 'chatFileErrorTooLong', params: { max: Number(detail.max_chars) || 100_000 } };
    case 'FILE_TOO_COMPLEX':
      return { key: 'chatFileErrorTooComplex' };
    case 'TOO_MANY_DRAFTS':
      return { key: 'chatFileErrorTooManyDrafts' };
    case 'IMAGE_DECODE_FAILED':
      return { key: 'chatFileErrorDecode' };
    case 'FILE_CORRUPT':
      return { key: 'chatFileErrorCorrupt' };
    case 'ACCOUNT_SUSPENDED':
      return { key: 'chatErrorSuspended' };
    default:
      return { key: 'chatFileErrorGeneric' };
  }
}

export const ChatComposer: React.FC<ChatComposerProps> = ({
  disabled,
  placeholder,
  onSend,
  selectedText,
  onClearSelectedText,
  lectureTitle,
  onDetachLecture,
  selectedAttachments = [],
  onUnselectAttachment,
  hasAttachments = false,
  onOpenAttachmentList,
  prefill,
  droppedFiles,
  autoFocus,
}) => {
  const { t, formatNumber } = useLanguage();
  const [value, setValue] = useState('');
  const [drafts, setDrafts] = useState<ChatDraftAttachment[]>([]);
  const [menuOpen, setMenuOpen] = useState(false);
  const [editor, setEditor] = useState<EditorState | null>(null);
  /** ファイルを添付できなかった理由(チップにならないもの: 形式・件数・テキストファイルの長さ) */
  const [notice, setNotice] = useState<Copy | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  // 非同期の処理(アップロード)から今の下書きを読むため
  const draftsRef = useRef<ChatDraftAttachment[]>([]);
  draftsRef.current = drafts;
  /** 準備中に外したファイル(後からアップロード先が分かったら、サーバーのdraftも消す) */
  const removedRef = useRef(new Set<string>());
  const abortersRef = useRef(new Map<string, AbortController>());

  useLayoutEffect(() => {
    if (!prefill) return;
    setValue(prefill.text);
    if (prefill.attachments) setDrafts(prefill.attachments);
    textareaRef.current?.focus();
  }, [prefill]);

  // 内容に合わせて高さを伸ばす(上限を超えたら中でスクロール)
  useLayoutEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, MAX_TEXTAREA_HEIGHT)}px`;
  }, [value]);

  // メニューの外を押したら閉じる
  useEffect(() => {
    if (!menuOpen) return;
    const onPointerDown = (e: PointerEvent) => {
      if (!menuRef.current?.contains(e.target as Node)) setMenuOpen(false);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMenuOpen(false);
    };
    document.addEventListener('pointerdown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [menuOpen]);

  const updateFileDraft = useCallback((localId: string, patch: Partial<ChatFileDraft>) => {
    if (removedRef.current.has(localId)) {
      // 準備中に外された: アップロード先が後から分かったら、サーバーのdraftも消す
      if (patch.attachmentId) void removeChatAttachment(patch.attachmentId).catch(() => {});
      if (patch.previewUrl) URL.revokeObjectURL(patch.previewUrl);
      return;
    }
    setDrafts((prev) => prev.map((d) => (d.localId === localId && d.kind === 'file' ? { ...d, ...patch } : d)));
  }, []);

  /** ファイルを添付する(選択・ドロップ・貼り付け)。テキスト・コードのファイルはテキストの資料にする。 */
  const addFiles = useCallback(
    async (files: File[]) => {
      setNotice(null);
      let count = draftsRef.current.length;
      for (const file of files) {
        if (count >= CHAT_MAX_ATTACHMENTS_PER_MESSAGE) {
          setNotice({ key: 'chatAttachmentLimitPerMessage', params: { max: CHAT_MAX_ATTACHMENTS_PER_MESSAGE } });
          break;
        }
        const kind = fileKindFor(file);
        if (!kind) {
          if (!isTextFile(file)) {
            setNotice(fileErrorCopy('UNSUPPORTED_FILE_TYPE'));
            continue;
          }
          count += 1;
          try {
            const content = await readTextFile(file);
            setDrafts((prev) => [...prev, { localId: newClientMessageId(), kind: 'text', title: file.name, content }]);
          } catch (e) {
            count -= 1;
            const err = e instanceof ChatFileError ? e : new ChatFileError('FILE_CORRUPT');
            setNotice(fileErrorCopy(err.code, err.detail));
          }
          continue;
        }
        count += 1;
        const localId = newClientMessageId();
        const aborter = new AbortController();
        abortersRef.current.set(localId, aborter);
        setDrafts((prev) => [
          ...prev,
          { localId, kind: 'file', fileKind: kind, fileName: file.name || 'image', title: '', stage: 'compressing' },
        ]);
        prepareChatFile(file, kind, (patch) => updateFileDraft(localId, patch), aborter.signal)
          .then((info) => updateFileDraft(localId, { stage: 'ready', info, progress: undefined }))
          .catch((e: unknown) => {
            if ((e as Error)?.name === 'AbortError') return;
            const err = e instanceof ChatFileError ? e : new ChatFileError('UPLOAD_FAILED');
            updateFileDraft(localId, { stage: 'error', errorCode: err.code, errorDetail: err.detail });
          })
          .finally(() => abortersRef.current.delete(localId));
      }
    },
    [updateFileDraft]
  );

  // 会話の上にドロップされたファイル
  useEffect(() => {
    if (droppedFiles?.files.length) void addFiles(droppedFiles.files);
  }, [droppedFiles, addFiles]);

  const removeDraft = (draft: ChatDraftAttachment) => {
    setDrafts((prev) => prev.filter((d) => d.localId !== draft.localId));
    if (draft.kind !== 'file') return;
    removedRef.current.add(draft.localId);
    abortersRef.current.get(draft.localId)?.abort();
    if (draft.attachmentId) void removeChatAttachment(draft.attachmentId).catch(() => {});
    if (draft.previewUrl) URL.revokeObjectURL(draft.previewUrl);
  };

  const trimmed = value.trim();
  const overLimit = value.length > CHAT_MAX_MESSAGE_CHARS;
  const draftsFull = drafts.length >= CHAT_MAX_ATTACHMENTS_PER_MESSAGE;
  // 準備中・失敗したファイルがある間は送れない(失敗したものは外してもらう)
  const filesPending = drafts.some((d) => d.kind === 'file' && d.stage !== 'ready');
  // 資料だけを送るのも許す
  const canSend = !disabled && !overLimit && !filesPending && (trimmed.length > 0 || drafts.length > 0);

  const submit = () => {
    if (!canSend) return;
    onSend(trimmed, drafts);
    setValue('');
    setDrafts([]);
    setNotice(null);
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // 日本語入力の変換確定のEnterでは送らない(isComposing / keyCode 229)
    if (event.nativeEvent.isComposing || event.keyCode === 229) return;
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      submit();
    }
  };

  const onPaste = (event: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const pasted = event.clipboardData.getData('text');
    // スクショなどのファイルの貼り付け。文字も一緒にあるとき(Officeから文字をコピーすると画像も付く)は文字を優先する
    const files = Array.from(event.clipboardData.files ?? []);
    if (files.length > 0 && !pasted.trim()) {
      event.preventDefault();
      void addFiles(files);
      return;
    }
    // メッセージの上限を超える長さの貼り付けは、入力欄に入れずに資料の編集へ回す
    const el = event.currentTarget;
    const selected = el.selectionEnd - el.selectionStart;
    if (!pasted || value.length - selected + pasted.length <= CHAT_MAX_MESSAGE_CHARS || draftsFull) return;
    event.preventDefault();
    setEditor({ mode: 'new', value: { title: '', content: pasted }, fromPaste: true });
  };

  const openNewText = () => {
    setMenuOpen(false);
    setEditor({ mode: 'new', value: { title: '', content: '' }, fromPaste: false });
  };

  const openFilePicker = () => {
    setMenuOpen(false);
    fileInputRef.current?.click();
  };

  // 打ちすぎて上限を超えた本文を、そのまま資料にする
  const convertValueToDraft = () => {
    setEditor({ mode: 'new', value: { title: '', content: value }, fromPaste: true });
  };

  const saveEditor = (next: AttachmentEditorValue) => {
    if (!editor) return;
    if (editor.mode === 'edit') {
      setDrafts((prev) => prev.map((d) => (d.localId === editor.localId && d.kind === 'text' ? { ...d, ...next } : d)));
    } else {
      setDrafts((prev) => [...prev, { localId: newClientMessageId(), kind: 'text', ...next }]);
      // 入力欄から回した本文は、資料にしたので入力欄からは消す
      if (editor.fromPaste && editor.value.content === value) setValue('');
    }
    setEditor(null);
    textareaRef.current?.focus();
  };

  /** ファイルのチップの右側(段階・ページ数・エラー)。 */
  const fileMeta = (draft: ChatFileDraft): string => {
    switch (draft.stage) {
      case 'compressing':
        return t('chatFileCompressing');
      case 'uploading':
        return t('chatFileUploading', { percent: Math.round((draft.progress ?? 0) * 100) });
      case 'reading':
        return t('chatFileReading');
      case 'error': {
        const copy = fileErrorCopy(draft.errorCode, draft.errorDetail);
        return t(copy.key, copy.params);
      }
      default: {
        const info = draft.info;
        if (!info) return '';
        const parts: string[] = [];
        if (info.kind === 'image') parts.push(t('chatFileImage'));
        else if (info.kind === 'pdf' && info.page_count) parts.push(t('chatFilePages', { count: info.page_count }));
        else if (info.kind === 'pptx' && info.page_count) parts.push(t('chatFileSlides', { count: info.page_count }));
        else parts.push(t('chatAttachmentChars', { count: formatNumber(info.text_chars) }));
        if (info.kind !== 'image' && info.vision_count > 0) {
          parts.push(t('chatFileVisionCount', { count: info.vision_count }));
        }
        return parts.join(' · ');
      }
    }
  };

  return (
    <form
      className="chat-composer"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
    >
      {(selectedText || lectureTitle || drafts.length > 0 || selectedAttachments.length > 0) && (
        <div className="chat-attachments">
          {selectedAttachments.map((a) => (
            <span key={a.id} className="chat-attachment is-file is-selected" title={a.title ?? undefined}>
              <AttachmentKindIcon kind={a.kind} />
              <span className="chat-attachment-text">{a.title || t('chatAttachmentUntitled')}</span>
              <span className="chat-attachment-meta">{t('chatAttachmentFullRead')}</span>
              {onUnselectAttachment && (
                <button type="button" onClick={() => onUnselectAttachment(a.id)} aria-label={t('chatAttachmentUnselect')}>
                  <X size={12} />
                </button>
              )}
            </span>
          ))}
          {drafts.map((draft) =>
            draft.kind === 'file' ? (
              <span
                key={draft.localId}
                className={`chat-attachment is-file is-upload is-${draft.stage}`}
                title={draft.stage === 'error' ? `${draft.fileName}: ${fileMeta(draft)}` : draft.fileName}
              >
                {draft.previewUrl ? (
                  <img className="chat-attachment-thumb" src={draft.previewUrl} alt="" />
                ) : draft.stage === 'error' ? (
                  <AlertCircle size={12} />
                ) : draft.stage === 'ready' ? (
                  <AttachmentKindIcon kind={draft.fileKind} />
                ) : (
                  <LoaderCircle size={12} className="chat-attachment-spin" />
                )}
                <span className="chat-attachment-text">{draftLabel(draft)}</span>
                <span className="chat-attachment-meta">{fileMeta(draft)}</span>
                <button type="button" onClick={() => removeDraft(draft)} aria-label={t('chatRemoveAttachment')}>
                  <X size={12} />
                </button>
                {draft.stage === 'uploading' && (
                  <span className="chat-attachment-progress" aria-hidden="true">
                    <span style={{ width: `${Math.round((draft.progress ?? 0) * 100)}%` }} />
                  </span>
                )}
              </span>
            ) : (
              <span key={draft.localId} className="chat-attachment is-file">
                <button
                  type="button"
                  className="chat-attachment-open"
                  onClick={() =>
                    setEditor({
                      mode: 'edit',
                      localId: draft.localId,
                      value: { title: draft.title, content: draft.content },
                    })
                  }
                  title={draftLabel(draft)}
                >
                  <Paperclip size={12} />
                  <span className="chat-attachment-text">{draftLabel(draft)}</span>
                  <span className="chat-attachment-meta">
                    {t('chatAttachmentChars', { count: formatNumber(draft.content.length) })}
                  </span>
                </button>
                <button type="button" onClick={() => removeDraft(draft)} aria-label={t('chatRemoveAttachment')}>
                  <X size={12} />
                </button>
              </span>
            )
          )}
          {selectedText && (
            <span className="chat-attachment is-quote" title={selectedText}>
              <Quote size={12} />
              <span className="chat-attachment-text">{selectedText}</span>
              {onClearSelectedText && (
                <button type="button" onClick={onClearSelectedText} aria-label={t('chatRemoveAttachment')}>
                  <X size={12} />
                </button>
              )}
            </span>
          )}
          {lectureTitle && (
            <span className="chat-attachment" title={lectureTitle}>
              <BookOpen size={12} />
              <span className="chat-attachment-text">{t('chatAttachedLecture', { title: lectureTitle })}</span>
              {onDetachLecture && (
                <button type="button" onClick={onDetachLecture} aria-label={t('chatRemoveAttachment')}>
                  <X size={12} />
                </button>
              )}
            </span>
          )}
        </div>
      )}

      {notice && (
        <p className="chat-composer-notice" role="alert">
          <AlertCircle size={13} />
          <span>{t(notice.key, notice.params)}</span>
          <button type="button" onClick={() => setNotice(null)} aria-label={t('close')}>
            <X size={12} />
          </button>
        </p>
      )}

      <div className={`chat-input-row ${overLimit ? 'is-over' : ''}`}>
        <div className="chat-attach-wrap" ref={menuRef}>
          <button
            type="button"
            className={`chat-attach-btn ${menuOpen ? 'is-open' : ''}`}
            onClick={() => setMenuOpen((open) => !open)}
            aria-label={t('chatAttach')}
            aria-haspopup="menu"
            aria-expanded={menuOpen}
            title={t('chatAttach')}
          >
            <Plus size={18} />
          </button>
          {menuOpen && (
            <div className="chat-attach-menu" role="menu">
              <button
                type="button"
                role="menuitem"
                disabled={!hasAttachments || !onOpenAttachmentList}
                onClick={() => {
                  setMenuOpen(false);
                  onOpenAttachmentList?.();
                }}
              >
                <Files size={16} />
                <span className="chat-attach-menu-label">
                  <span>{t('chatAttachSelect')}</span>
                  <small>{hasAttachments ? t('chatAttachSelectHint') : t('chatAttachSelectNone')}</small>
                </span>
              </button>
              <button type="button" role="menuitem" onClick={openNewText} disabled={draftsFull}>
                <FileText size={16} />
                <span className="chat-attach-menu-label">
                  <span>{t('chatAttachLongText')}</span>
                  <small>
                    {draftsFull
                      ? t('chatAttachmentLimitPerMessage', { max: CHAT_MAX_ATTACHMENTS_PER_MESSAGE })
                      : t('chatAttachTextHint')}
                  </small>
                </span>
              </button>
              <button type="button" role="menuitem" onClick={openFilePicker} disabled={draftsFull}>
                <Upload size={16} />
                <span className="chat-attach-menu-label">
                  <span>{t('chatAttachFile')}</span>
                  <small>
                    {draftsFull
                      ? t('chatAttachmentLimitPerMessage', { max: CHAT_MAX_ATTACHMENTS_PER_MESSAGE })
                      : t('chatAttachFileHint')}
                  </small>
                </span>
              </button>
            </div>
          )}
          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept={CHAT_FILE_ACCEPT}
            hidden
            onChange={(event) => {
              const files = Array.from(event.target.files ?? []);
              event.target.value = '';
              if (files.length) void addFiles(files);
            }}
          />
        </div>
        <textarea
          id="chat-composer-input"
          ref={textareaRef}
          rows={1}
          value={value}
          placeholder={placeholder}
          onChange={(event) => setValue(event.target.value)}
          onKeyDown={onKeyDown}
          onPaste={onPaste}
          autoFocus={autoFocus}
          aria-label={placeholder}
        />
        <button
          type="submit"
          className="chat-send-btn"
          disabled={!canSend}
          aria-label={t('chatSend')}
          title={filesPending ? t('chatFileNotReadyHint') : undefined}
        >
          <ArrowUp size={18} />
        </button>
      </div>

      {value.length > COUNTER_THRESHOLD && (
        <span className={`chat-counter ${overLimit ? 'is-over' : ''}`}>
          {overLimit ? (
            <>
              {t('chatErrorTooLong', { max: CHAT_MAX_MESSAGE_CHARS })}
              {!draftsFull && (
                <button type="button" className="chat-link-btn" onClick={convertValueToDraft}>
                  <Paperclip size={12} />
                  {t('chatAttachmentConvert')}
                </button>
              )}
            </>
          ) : (
            `${value.length} / ${CHAT_MAX_MESSAGE_CHARS}`
          )}
        </span>
      )}

      <AttachmentEditorModal
        initial={editor?.value ?? null}
        editing={editor?.mode === 'edit'}
        fromPaste={editor?.mode === 'new' && editor.fromPaste}
        onSave={saveEditor}
        onClose={() => setEditor(null)}
      />
    </form>
  );
};
