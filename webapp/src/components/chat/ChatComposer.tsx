import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle,
  ArrowUp,
  AtSign,
  BookOpen,
  FileText,
  Files,
  LoaderCircle,
  Paperclip,
  Pencil,
  Plus,
  Quote,
  Square,
  Upload,
  X,
} from 'lucide-react';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import {
  CHAT_CREDITS_PER_10K_TOKENS,
  CHAT_MAX_ATTACHMENTS_PER_MESSAGE,
  CHAT_MAX_MESSAGE_CHARS,
  CHAT_MAX_SELECTED_TOKENS,
  CHAT_MENTION_RE,
  type ChatAttachment,
  type ChatAttachmentRef,
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
import {
  findMentionQuery,
  labelBeforeCaret,
  makeLabel,
  mentionRanges,
  presentMentions,
  toMessageContent,
  type ComposerMention,
  type MentionTarget,
} from '../../lib/chatMentions';
import {
  fileDraftAborters,
  publishFileDraftPatch,
  removedFileDrafts,
  saveComposerSnapshot,
  subscribeFileDraftPatches,
  takeComposerSnapshot,
} from '../../lib/chatComposerDrafts';
import { useAttachmentImageUrl } from '../../hooks/useAttachmentImageUrl';
import { AttachmentEditorModal, type AttachmentEditorValue } from './AttachmentEditorModal';
import { AttachmentKindIcon } from './AttachmentViewerModal';
import { DraftPreviewModal } from './DraftPreviewModal';

/** 外から入力欄に資料を入れる・外す(資料の一覧の「全文で添付」「メンション」「取り消す」)。 */
export interface ChatInsertRequest {
  attachment: ChatAttachment;
  mode: 'full' | 'mention' | 'remove';
  nonce: number;
}

interface ChatComposerProps {
  /** 入力欄の中身を預ける置き場の名前(会話ごと。パネル ⇄ 全画面の切り替えで中身を戻すため)。 */
  draftKey: string;
  disabled: boolean;
  placeholder: string;
  /** 返答の生成中: 送信ボタンの代わりに停止ボタンを出す(入力はそのまま続けられる) */
  onStop?: () => void;
  /** 停止を押して、止まるのを待っている */
  stopping?: boolean;
  /** 送ったメッセージを編集中: 入力欄の上に出すバーの文言(「以降の2往復は削除されます」など) */
  editingLabel?: string | null;
  onCancelEdit?: () => void;
  /**
   * 送信。contentの「@名前」は資料の印(⟦att:id⟧)に置き換え済み。draftsはこの送信で新しく添付する資料
   * (いつも全文で添付)、referencesはこの会話の既存の資料を指したもの(全文で添付 / メンション)。
   */
  onSend: (content: string, drafts: ChatDraftAttachment[], references: ChatAttachmentRef[]) => void;
  /** 次の送信に添える選択テキスト(チップとして見せ、外せる)。 */
  selectedText: string | null;
  onClearSelectedText?: () => void;
  /** 話題にしている講義名(チップとして見せ、外せる)。 */
  lectureTitle: string | null;
  onDetachLecture?: () => void;
  /** 全文で読んでいる資料(チップとして見せ、×で全文で読むのをやめられる)。 */
  selectedAttachments?: ChatAttachment[];
  onUnselectAttachment?: (attachmentId: string) => void;
  /** この会話の使える資料(@の候補・資料の一覧)。 */
  mentionables?: ChatAttachment[];
  /** ＋メニューの「この会話の資料」: 資料の一覧を開く。 */
  onOpenAttachmentList?: () => void;
  /** 候補の質問を押したとき・送れなかった送信を戻すときに、外から入力欄(と資料)を埋める。 */
  prefill?: {
    text: string;
    attachments?: ChatDraftAttachment[];
    references?: ChatAttachmentRef[];
    nonce: number;
  } | null;
  /** 会話の上にドロップされたファイル(nonceが変わるたびに添付する)。 */
  droppedFiles?: { files: File[]; nonce: number } | null;
  /** 資料の一覧から入れる資料(nonceが変わるたびに入れる)。 */
  insertRequest?: ChatInsertRequest | null;
  /** 入力欄で指している既存の資料が変わったとき(資料の一覧に「添付する予定」を見せるため)。 */
  onPendingChange?: (refs: ChatAttachmentRef[]) => void;
  /** 送った資料の中身を見る(「@名前」の操作から)。 */
  onViewAttachment?: (attachmentId: string) => void;
  autoFocus?: boolean;
}

/** 入力欄が伸びる上限(行数ではなく高さで止める)。 */
const MAX_TEXTAREA_HEIGHT = 168;
/** 文字数の残りを出し始める目安。 */
const COUNTER_THRESHOLD = CHAT_MAX_MESSAGE_CHARS - 500;
/** @の候補に出す数。 */
const MENTION_PICKER_MAX = 8;

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
    case 'UPLOAD_FAILED':
      // 状態コード(0はCORS・通信の切断。それ以外はR2の返事)を出して、原因を追えるようにする
      return { key: 'chatFileErrorUpload', params: { status: typeof detail.status === 'number' ? detail.status : '-' } };
    default:
      return { key: 'chatFileErrorGeneric' };
  }
}

export const ChatComposer: React.FC<ChatComposerProps> = ({
  draftKey,
  disabled,
  onStop,
  stopping = false,
  editingLabel,
  onCancelEdit,
  placeholder,
  onSend,
  selectedText,
  onClearSelectedText,
  lectureTitle,
  onDetachLecture,
  selectedAttachments = [],
  onUnselectAttachment,
  mentionables = [],
  onOpenAttachmentList,
  prefill,
  droppedFiles,
  insertRequest,
  onPendingChange,
  onViewAttachment,
  autoFocus,
}) => {
  const { t, formatNumber } = useLanguage();
  // パネル ⇄ 全画面の切り替えで作り直されたときは、消える前の中身を受け取る
  const [restored] = useState(() => takeComposerSnapshot(draftKey));
  const [value, setValue] = useState(restored?.value ?? '');
  const [drafts, setDrafts] = useState<ChatDraftAttachment[]>(restored?.drafts ?? []);
  /** 入力欄の中の「@名前」と、それが指す資料 */
  const [mentions, setMentions] = useState<ComposerMention[]>(restored?.mentions ?? []);
  /** カーソルが「@名前」の中にあるとき、その資料の操作(中身を見る・全文⇄メンション・外す)を出す */
  const [activeLabel, setActiveLabel] = useState<string | null>(null);
  /** 中身を確かめている送る前のファイル */
  const [previewId, setPreviewId] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [editor, setEditor] = useState<EditorState | null>(null);
  /** ファイルを添付できなかった理由(チップにならないもの: 形式・件数・テキストファイルの長さ) */
  const [notice, setNotice] = useState<Copy | null>(null);
  /** @の候補(@の位置と、@の後ろに打った言葉) */
  const [picker, setPicker] = useState<{ start: number; query: string } | null>(null);
  const [pickerIndex, setPickerIndex] = useState(0);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const mirrorRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  // 非同期の処理(アップロード)・続けて入れる処理から、今の値を読むため
  const draftsRef = useRef<ChatDraftAttachment[]>([]);
  draftsRef.current = drafts;
  const valueRef = useRef('');
  valueRef.current = value;
  const mentionsRef = useRef<ComposerMention[]>([]);
  mentionsRef.current = mentions;
  /** 最後のカーソルの位置(入力欄の外でファイルを落としたときも、そこへ入れる) */
  const caretRef = useRef(0);
  // 中身が変わるたびに預ける(作り直された入力欄が受け取る)。消えるときに預けるのでは間に合わない:
  // 画面の切り替えでは、新しい入力欄が作られて受け取りに来た後で、古い入力欄が片付けられる
  useEffect(() => {
    saveComposerSnapshot(draftKey, { value, drafts, mentions });
  }, [draftKey, value, drafts, mentions]);

  // アップロード中のファイルの進み具合(この入力欄が始めたものも、作り直す前の入力欄が始めたものも届く)
  useEffect(
    () =>
      subscribeFileDraftPatches((localId, patch) =>
        setDrafts((prev) => prev.map((d) => (d.localId === localId && d.kind === 'file' ? { ...d, ...patch } : d)))
      ),
    []
  );

  // 入力欄で指している既存の資料(資料の一覧に「添付する予定」として見せる)
  useEffect(() => {
    if (!onPendingChange) return;
    const refs = new Map<string, ChatAttachmentRef>();
    for (const m of presentMentions(value, mentions)) {
      if (m.target.kind !== 'existing') continue;
      const prev = refs.get(m.target.attachmentId);
      refs.set(m.target.attachmentId, {
        attachment_id: m.target.attachmentId,
        mode: prev?.mode === 'full' || m.target.mode === 'full' ? 'full' : 'mention',
      });
    }
    onPendingChange([...refs.values()]);
  }, [value, mentions, onPendingChange]);

  const titleOf = useCallback(
    (id: string) => {
      const a = mentionables.find((m) => m.id === id);
      return a ? a.title || a.file_name || t('chatAttachmentUntitled') : null;
    },
    [mentionables, t]
  );

  /** 入力欄のカーソルの位置(range)に文字を入れる。rangeが無ければ最後のカーソルの位置。 */
  const insertAtCaret = useCallback((text: string, range?: { start: number; end: number }) => {
    const current = valueRef.current;
    const start = Math.min(range?.start ?? caretRef.current, current.length);
    const end = Math.min(range?.end ?? start, current.length);
    // 前の文字とくっつかないように空白を挟む
    const lead = start > 0 && !/\s/.test(current[start - 1]) ? ' ' : '';
    const next = current.slice(0, start) + lead + text + current.slice(end);
    const caret = start + lead.length + text.length;
    valueRef.current = next;
    caretRef.current = caret;
    setValue(next);
    requestAnimationFrame(() => {
      const el = textareaRef.current;
      if (!el) return;
      el.focus();
      el.setSelectionRange(caret, caret);
    });
  }, []);

  /** 資料を指す「@名前」を入れる(重複して指すときは同じ名前を使う)。 */
  const addMention = useCallback(
    (target: MentionTarget, title: string, range?: { start: number; end: number }) => {
      const sameTarget = mentionsRef.current.find((m) =>
        m.target.kind === 'existing' && target.kind === 'existing'
          ? m.target.attachmentId === target.attachmentId
          : m.target.kind === 'draft' && target.kind === 'draft' && m.target.localId === target.localId
      );
      let label: string;
      if (sameTarget) {
        label = sameTarget.label;
        // 同じ資料を別の渡し方で入れ直したら、その渡し方にそろえる(既に文中にあれば、もう一度は入れない)
        if (target.kind === 'existing' && sameTarget.target.kind === 'existing') {
          const updated = { ...sameTarget, target };
          mentionsRef.current = mentionsRef.current.map((m) => (m === sameTarget ? updated : m));
          setMentions(mentionsRef.current);
          if (valueRef.current.includes(label) && !range) return;
        }
      } else {
        label = makeLabel(title, mentionsRef.current.map((m) => m.label));
        mentionsRef.current = [...mentionsRef.current, { label, target }];
        setMentions(mentionsRef.current);
      }
      insertAtCaret(`${label} `, range);
    },
    [insertAtCaret]
  );

  // 送れなかった送信を戻す・候補の質問を入れる。本文の印は「@名前」に戻す
  useLayoutEffect(() => {
    if (!prefill) return;
    const restored: ComposerMention[] = [];
    const nextDrafts = prefill.attachments ?? [];
    const text = prefill.text.replace(new RegExp(CHAT_MENTION_RE.source, 'g'), (_m, id: string) => {
      const draft = nextDrafts.find((d) => d.localId === id || (d.kind === 'file' && d.attachmentId === id));
      const ref = prefill.references?.find((r) => r.attachment_id === id);
      const title = draft ? draftLabel(draft) : titleOf(id);
      if (!title) return '';
      const target: MentionTarget = draft
        ? { kind: 'draft', localId: draft.localId }
        : { kind: 'existing', attachmentId: id, mode: ref?.mode ?? 'mention' };
      const label = makeLabel(title, restored.map((m) => m.label));
      restored.push({ label, target });
      return label;
    });
    setValue(text);
    setMentions(restored);
    if (prefill.attachments) setDrafts(prefill.attachments);
    textareaRef.current?.focus();
    // titleOfは資料の一覧が変わるたびに変わるが、戻すのはprefillが来たときだけ
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [prefill]);

  // 内容に合わせて高さを伸ばす(上限を超えたら中でスクロール)
  useLayoutEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, MAX_TEXTAREA_HEIGHT)}px`;
    if (mirrorRef.current) mirrorRef.current.scrollTop = el.scrollTop;
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
    if (removedFileDrafts.has(localId)) {
      // 準備中に外された: アップロード先が後から分かったら、サーバーのdraftも消す
      if (patch.attachmentId) void removeChatAttachment(patch.attachmentId).catch(() => {});
      if (patch.previewUrl) URL.revokeObjectURL(patch.previewUrl);
      return;
    }
    publishFileDraftPatch(localId, patch);
  }, []);

  /**
   * ファイルを添付する(選択・ドロップ・貼り付け)。カーソルの位置に「@ファイル名」を入れる(文中のどこで
   * 何を指しているかがAIに伝わる)。テキスト・コードのファイルはテキストの資料にする。
   */
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
            const localId = newClientMessageId();
            setDrafts((prev) => [...prev, { localId, kind: 'text', title: file.name, content }]);
            addMention({ kind: 'draft', localId }, file.name);
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
        fileDraftAborters.set(localId, aborter);
        const fileName = file.name || 'image';
        setDrafts((prev) => [
          ...prev,
          {
            localId,
            kind: 'file',
            fileKind: kind,
            fileName,
            title: '',
            stage: 'compressing',
            // PDFは送る前にブラウザで中身を確かめられる
            localUrl: kind === 'pdf' ? URL.createObjectURL(file) : undefined,
          },
        ]);
        addMention({ kind: 'draft', localId }, fileName);
        prepareChatFile(file, kind, (patch) => updateFileDraft(localId, patch), aborter.signal)
          .then((info) => updateFileDraft(localId, { stage: 'ready', info, progress: undefined }))
          .catch((e: unknown) => {
            if ((e as Error)?.name === 'AbortError') return;
            const err = e instanceof ChatFileError ? e : new ChatFileError('UPLOAD_FAILED');
            updateFileDraft(localId, { stage: 'error', errorCode: err.code, errorDetail: err.detail });
          })
          .finally(() => fileDraftAborters.delete(localId));
      }
    },
    [updateFileDraft, addMention]
  );

  // 会話の上にドロップされたファイル
  useEffect(() => {
    if (droppedFiles?.files.length) void addFiles(droppedFiles.files);
  }, [droppedFiles, addFiles]);

  // 資料の一覧から入れる資料
  useEffect(() => {
    if (!insertRequest) return;
    const a = insertRequest.attachment;
    if (insertRequest.mode === 'remove') {
      const m = mentionsRef.current.find((x) => x.target.kind === 'existing' && x.target.attachmentId === a.id);
      if (m) {
        removeLabel(m.label);
        mentionsRef.current = mentionsRef.current.filter((x) => x !== m);
        setMentions(mentionsRef.current);
      }
      return;
    }
    addMention(
      { kind: 'existing', attachmentId: a.id, mode: insertRequest.mode },
      a.title || a.file_name || t('chatAttachmentUntitled')
    );
    // insertRequestが来たときだけ
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [insertRequest]);

  /** 入力欄から「@名前」を消す(下書きを外したとき)。 */
  const removeLabel = (label: string) => {
    const next = valueRef.current.split(`${label} `).join('').split(label).join('');
    valueRef.current = next;
    setValue(next);
  };

  const removeDraft = (draft: ChatDraftAttachment) => {
    setDrafts((prev) => prev.filter((d) => d.localId !== draft.localId));
    const mention = mentionsRef.current.find((m) => m.target.kind === 'draft' && m.target.localId === draft.localId);
    if (mention) {
      removeLabel(mention.label);
      mentionsRef.current = mentionsRef.current.filter((m) => m !== mention);
      setMentions(mentionsRef.current);
    }
    if (draft.kind !== 'file') return;
    removedFileDrafts.add(draft.localId);
    fileDraftAborters.get(draft.localId)?.abort();
    if (draft.attachmentId) void removeChatAttachment(draft.attachmentId).catch(() => {});
    if (draft.previewUrl) URL.revokeObjectURL(draft.previewUrl);
    if (draft.localUrl) URL.revokeObjectURL(draft.localUrl);
  };

  /** 「@名前」を入力欄から外す(既存の資料を指すのをやめる・新しく添付したファイルなら添付ごと外す)。 */
  const removeMention = (mention: ComposerMention) => {
    setActiveLabel(null);
    if (mention.target.kind === 'draft') {
      const target = mention.target;
      const draft = draftsRef.current.find((d) => d.localId === target.localId);
      if (draft) {
        removeDraft(draft);
        return;
      }
    }
    removeLabel(mention.label);
    mentionsRef.current = mentionsRef.current.filter((m) => m !== mention);
    setMentions(mentionsRef.current);
  };

  /** 既存の資料の渡し方を切り替える(全文で添付 ⇄ メンション)。 */
  const toggleMentionMode = (mention: ComposerMention) => {
    if (mention.target.kind !== 'existing') return;
    const target = { ...mention.target, mode: mention.target.mode === 'full' ? ('mention' as const) : ('full' as const) };
    mentionsRef.current = mentionsRef.current.map((m) => (m === mention ? { ...m, target } : m));
    setMentions(mentionsRef.current);
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
    const used = presentMentions(value, mentions);
    const content = toMessageContent(value, used, (m) => {
      if (m.target.kind === 'existing') return m.target.attachmentId;
      const target = m.target;
      const draft = drafts.find((d) => d.localId === target.localId);
      if (!draft) return null;
      return draft.kind === 'file' ? (draft.attachmentId ?? null) : draft.localId;
    }).trim();
    // 既存の資料: 同じ資料を何度指しても1つ(全文で添付が1つでもあれば全文)
    const refs = new Map<string, ChatAttachmentRef>();
    for (const m of used) {
      if (m.target.kind !== 'existing') continue;
      const prev = refs.get(m.target.attachmentId);
      refs.set(m.target.attachmentId, {
        attachment_id: m.target.attachmentId,
        mode: prev?.mode === 'full' || m.target.mode === 'full' ? 'full' : 'mention',
      });
    }
    onSend(content, drafts, [...refs.values()]);
    setValue('');
    setDrafts([]);
    setMentions([]);
    setNotice(null);
    setPicker(null);
  };

  // --- @の候補 ---
  const pickerItems = useMemo(() => {
    if (!picker) return [];
    const q = picker.query.toLowerCase();
    return mentionables
      .filter((a) => !q || `${a.title ?? ''} ${a.file_name ?? ''}`.toLowerCase().includes(q))
      .slice(-MENTION_PICKER_MAX)
      .reverse();
  }, [picker, mentionables]);

  const updatePicker = (el: HTMLTextAreaElement) => {
    caretRef.current = el.selectionStart;
    const inside = mentionRanges(el.value, mentionsRef.current).find(
      (r) => r.start < el.selectionStart && el.selectionStart < r.end
    );
    setActiveLabel(inside ? inside.mention.label : null);
    if (mentionables.length === 0 || el.selectionStart !== el.selectionEnd) {
      setPicker(null);
      return;
    }
    const found = findMentionQuery(el.value, el.selectionStart, mentionsRef.current.map((m) => m.label));
    setPicker(found);
    if (found?.query !== picker?.query) setPickerIndex(0);
  };

  const choosePicked = (a: ChatAttachment, mode: 'full' | 'mention') => {
    if (!picker) return;
    const range = { start: picker.start, end: caretRef.current };
    setPicker(null);
    addMention({ kind: 'existing', attachmentId: a.id, mode }, a.title || a.file_name || t('chatAttachmentUntitled'), range);
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // 日本語入力の変換確定のEnterでは送らない(isComposing / keyCode 229)
    if (event.nativeEvent.isComposing || event.keyCode === 229) return;
    if (picker && pickerItems.length > 0) {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        const step = event.key === 'ArrowDown' ? 1 : -1;
        setPickerIndex((i) => (i + step + pickerItems.length) % pickerItems.length);
        return;
      }
      if (event.key === 'Enter' || event.key === 'Tab') {
        event.preventDefault();
        choosePicked(pickerItems[Math.min(pickerIndex, pickerItems.length - 1)], 'mention');
        return;
      }
    }
    if (picker && event.key === 'Escape') {
      event.preventDefault();
      setPicker(null);
      return;
    }
    // 「@名前」はBackspace1回で丸ごと消す(途中が欠けると、どの資料か分からなくなるため)
    if (event.key === 'Backspace') {
      const el = event.currentTarget;
      if (el.selectionStart === el.selectionEnd) {
        const label = labelBeforeCaret(el.value, el.selectionStart, mentionsRef.current.map((m) => m.label));
        if (label) {
          event.preventDefault();
          const start = el.selectionStart - label.length;
          const next = el.value.slice(0, start) + el.value.slice(el.selectionStart);
          valueRef.current = next;
          caretRef.current = start;
          setValue(next);
          requestAnimationFrame(() => textareaRef.current?.setSelectionRange(start, start));
          return;
        }
      }
    }
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      submit();
    }
  };

  const onPaste = (event: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const pasted = event.clipboardData.getData('text');
    caretRef.current = event.currentTarget.selectionStart;
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
      const localId = newClientMessageId();
      const draft = { localId, kind: 'text' as const, ...next };
      setDrafts((prev) => [...prev, draft]);
      // 入力欄から回した本文は、資料にしたので入力欄からは消す
      if (editor.fromPaste && editor.value.content === value) {
        valueRef.current = '';
        caretRef.current = 0;
        setValue('');
      }
      addMention({ kind: 'draft', localId }, draftLabel(draft) || t('chatAttachmentUntitled'));
    }
    setEditor(null);
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

  // 入力欄の裏に重ねる層: 「@名前」に色を付ける(文字の幅は変えない)
  const ranges = mentionRanges(value, mentions);
  const highlighted: React.ReactNode[] = [];
  let pos = 0;
  ranges.forEach(({ start, end, mention }, i) => {
    highlighted.push(value.slice(pos, start));
    const full = mention.target.kind === 'draft' || mention.target.mode === 'full';
    highlighted.push(
      <mark key={i} className={`chat-mention-mark ${full ? 'is-full' : 'is-mention'}`}>
        {value.slice(start, end)}
      </mark>
    );
    pos = end;
  });
  highlighted.push(`${value.slice(pos)}\n`);

  const activeMention = activeLabel ? mentions.find((m) => m.label === activeLabel) ?? null : null;
  const previewDraft = (drafts.find((d) => d.localId === previewId && d.kind === 'file') as ChatFileDraft | undefined) ?? null;

  // 全文で読んでいる資料の件数と、1回あたりの目安(気づかずに増やしていかないように、いつも見せる)
  const pinnedTokens = selectedAttachments.reduce((sum, a) => sum + a.token_count, 0);
  const pinnedCredits = formatNumber((pinnedTokens / 10_000) * CHAT_CREDITS_PER_10K_TOKENS, {
    maximumFractionDigits: 1,
  });

  return (
    <form
      className="chat-composer"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
    >
      {editingLabel && (
        <div className="chat-edit-bar" role="status">
          <Pencil size={13} />
          <span>{editingLabel}</span>
          {onCancelEdit && (
            <button type="button" onClick={onCancelEdit} aria-label={t('chatEditCancel')} title={t('chatEditCancel')}>
              <X size={14} />
            </button>
          )}
        </div>
      )}
      {selectedAttachments.length > 0 && (
        <div className="chat-pinned-summary">
          <span>
            {t('chatPinnedSummary', {
              count: selectedAttachments.length,
              credits: pinnedCredits,
              percent: Math.round((pinnedTokens / CHAT_MAX_SELECTED_TOKENS) * 100),
            })}
          </span>
        </div>
      )}
      {(selectedText || lectureTitle || drafts.length > 0 || selectedAttachments.length > 0) && (
        <div className="chat-attachments">
          {selectedAttachments.map((a) => (
            <span key={a.id} className="chat-attachment is-file is-selected" title={a.title ?? undefined}>
              <AttachmentKindIcon kind={a.kind} />
              <span className="chat-attachment-text">{a.title || a.file_name || t('chatAttachmentUntitled')}</span>
              <span className="chat-attachment-meta">{t('chatAttachPinned')}</span>
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
                <button
                  type="button"
                  className="chat-attachment-open"
                  onClick={() => setPreviewId(draft.localId)}
                  aria-label={t('chatDraftPreviewOpen', { name: draft.fileName })}
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
                </button>
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
        {!picker && activeMention && (
          <MentionActionBar
            mention={activeMention}
            attachment={
              activeMention.target.kind === 'existing'
                ? mentionables.find((a) => a.id === (activeMention.target as { attachmentId: string }).attachmentId)
                : undefined
            }
            draft={
              activeMention.target.kind === 'draft'
                ? drafts.find((d) => d.localId === (activeMention.target as { localId: string }).localId)
                : undefined
            }
            onView={() => {
              const target = activeMention.target;
              if (target.kind === 'existing') {
                onViewAttachment?.(target.attachmentId);
                return;
              }
              const draft = drafts.find((d) => d.localId === target.localId);
              if (draft?.kind === 'file') setPreviewId(draft.localId);
              else if (draft) setEditor({ mode: 'edit', localId: draft.localId, value: { title: draft.title, content: draft.content } });
            }}
            onToggleMode={() => toggleMentionMode(activeMention)}
            onRemove={() => removeMention(activeMention)}
          />
        )}
        {picker && (
          <div className="chat-mention-picker" role="listbox" aria-label={t('chatMentionPickerTitle')}>
            <div className="chat-mention-picker-head">
              <AtSign size={13} />
              <span>{t('chatMentionPickerTitle')}</span>
              <small>{t('chatMentionPickerHint')}</small>
            </div>
            {pickerItems.length === 0 ? (
              <p className="chat-mention-picker-empty">{t('chatMentionPickerEmpty')}</p>
            ) : (
              pickerItems.map((a, i) => {
                const tooLong = a.token_count > CHAT_MAX_SELECTED_TOKENS;
                return (
                  <div
                    key={a.id}
                    role="option"
                    aria-selected={i === pickerIndex}
                    className={`chat-mention-option ${i === pickerIndex ? 'is-active' : ''}`}
                    onMouseEnter={() => setPickerIndex(i)}
                  >
                    <button
                      type="button"
                      className="chat-mention-option-main"
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() => choosePicked(a, 'mention')}
                    >
                      <AttachmentKindIcon kind={a.kind} size={14} />
                      <span className="chat-mention-option-title">
                        {a.title || a.file_name || t('chatAttachmentUntitled')}
                      </span>
                      {a.selected && <span className="chat-mention-option-badge">{t('chatAttachPinned')}</span>}
                    </button>
                    {!a.selected && (
                      <button
                        type="button"
                        className="chat-mention-option-full"
                        disabled={tooLong}
                        title={tooLong ? t('chatAttachmentTooLongToSelect') : t('chatAttachFullHint')}
                        onMouseDown={(e) => e.preventDefault()}
                        onClick={() => choosePicked(a, 'full')}
                      >
                        {t('chatAttachFull')}
                      </button>
                    )}
                  </div>
                );
              })
            )}
          </div>
        )}
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
                disabled={mentionables.length === 0 || !onOpenAttachmentList}
                onClick={() => {
                  setMenuOpen(false);
                  onOpenAttachmentList?.();
                }}
              >
                <Files size={16} />
                <span className="chat-attach-menu-label">
                  <span>{t('chatAttachSelect')}</span>
                  <small>{mentionables.length > 0 ? t('chatAttachSelectHint') : t('chatAttachSelectNone')}</small>
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
        <div className="chat-input-field">
          <div className="chat-input-mirror" ref={mirrorRef} aria-hidden="true">
            {highlighted}
          </div>
          <textarea
            id="chat-composer-input"
            ref={textareaRef}
            rows={1}
            value={value}
            placeholder={placeholder}
            onChange={(event) => {
              valueRef.current = event.target.value;
              setValue(event.target.value);
              updatePicker(event.target);
            }}
            onSelect={(event) => updatePicker(event.currentTarget)}
            onScroll={(event) => {
              if (mirrorRef.current) mirrorRef.current.scrollTop = event.currentTarget.scrollTop;
            }}
            onBlur={() => {
              setPicker(null);
              setActiveLabel(null);
            }}
            onKeyDown={onKeyDown}
            onPaste={onPaste}
            autoFocus={autoFocus}
            aria-label={placeholder}
          />
        </div>
        {onStop ? (
          <button
            type="button"
            className="chat-send-btn is-stop"
            onClick={onStop}
            disabled={stopping}
            aria-label={t('chatStop')}
            title={t('chatStop')}
          >
            {stopping ? <LoaderCircle size={16} className="chat-attachment-spin" /> : <Square size={13} fill="currentColor" />}
          </button>
        ) : (
          <button
            type="submit"
            className="chat-send-btn"
            disabled={!canSend}
            aria-label={t('chatSend')}
            title={filesPending ? t('chatFileNotReadyHint') : undefined}
          >
            <ArrowUp size={18} />
          </button>
        )}
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

      <DraftPreviewModal
        draft={previewDraft}
        errorText={
          previewDraft?.stage === 'error'
            ? t(fileErrorCopy(previewDraft.errorCode, previewDraft.errorDetail).key, fileErrorCopy(previewDraft.errorCode, previewDraft.errorDetail).params)
            : undefined
        }
        onRemove={() => previewDraft && removeDraft(previewDraft)}
        onClose={() => setPreviewId(null)}
      />
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

/**
 * 入力欄の「@名前」にカーソルがあるときの操作(押すとカーソルがそこに入るので、名前を押せば出る)。
 * 画像は小さな見本も見せる(文中のどこに何を入れたかを確かめやすいように)。
 */
const MentionActionBar: React.FC<{
  mention: ComposerMention;
  attachment?: ChatAttachment;
  draft?: ChatDraftAttachment;
  onView: () => void;
  onToggleMode: () => void;
  onRemove: () => void;
}> = ({ mention, attachment, draft, onView, onToggleMode, onRemove }) => {
  const { t } = useLanguage();
  const imageUrl = useAttachmentImageUrl(attachment?.kind === 'image' ? attachment.id : null);
  const thumb = draft?.kind === 'file' && draft.previewUrl ? draft.previewUrl : imageUrl;
  const kind = attachment?.kind ?? (draft?.kind === 'file' ? draft.fileKind : 'text');
  const isNew = mention.target.kind === 'draft';
  const full = isNew || (mention.target.kind === 'existing' && mention.target.mode === 'full');
  const title = attachment
    ? attachment.title || attachment.file_name || t('chatAttachmentUntitled')
    : draft
      ? draftLabel(draft)
      : mention.label.slice(1);
  const keep = (e: React.MouseEvent) => e.preventDefault();
  return (
    <div className="chat-mention-actions" role="toolbar" aria-label={title}>
      {thumb ? (
        <img className="chat-mention-actions-thumb" src={thumb} alt="" />
      ) : (
        <span className="chat-mention-actions-icon">
          <AttachmentKindIcon kind={kind} size={16} />
        </span>
      )}
      <span className="chat-mention-actions-text">
        <span className="chat-mention-actions-title">{title}</span>
        <small>{isNew ? t('chatMentionNewFull') : full ? t('chatAttachFull') : t('chatAttachMention')}</small>
      </span>
      <button type="button" onMouseDown={keep} onClick={onView}>
        {t('chatAttachView')}
      </button>
      {!isNew && (
        <button type="button" onMouseDown={keep} onClick={onToggleMode}>
          {full ? t('chatMentionToMention') : t('chatMentionToFull')}
        </button>
      )}
      <button type="button" className="is-danger" onMouseDown={keep} onClick={onRemove} aria-label={t('chatRemoveAttachment')}>
        <X size={14} />
      </button>
    </div>
  );
};
