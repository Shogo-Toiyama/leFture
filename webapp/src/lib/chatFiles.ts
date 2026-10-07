import { ApiError, apiFetch, extractErrorCode } from './api';
import { ChatFileError, shrinkImage, shrinkOfficeFile } from './chatFileShrink';
import {
  CHAT_MAX_ATTACHMENT_CHARS,
  CHAT_MAX_FILE_BYTES,
  type ChatFileDraft,
  type ChatFileInfo,
  type ChatFileKind,
} from '../types/chat';

/**
 * チャットに添付するファイル(バックエンド: lefture_backend/app/services/chat_files.py)。
 *
 * 選ぶ → 端末で縮める → アップロード先を頼む(draftの行) → R2へ直接PUT → バックエンドが中身を取り出す(LLMなし)。
 * 画像は長辺2048pxのJPEGに、docx・pptxは中の画像を同じように縮めて作り直す(2026-10-06の検証で、
 * 37枚のスクショのpptxが32MB → 5.4MB。読み取りの精度は変わらなかった)。PDFはブラウザで安全に
 * 作り直せないのでそのまま送る(上限が大きい)。テキスト・コードのファイルは、アップロードせずに
 * 中身を読んでテキストの資料にする(htmlも見た目の文字ではなくコードとして読む)。
 */

const KIND_BY_EXTENSION: Record<string, ChatFileKind> = {
  pdf: 'pdf',
  docx: 'docx',
  pptx: 'pptx',
  jpg: 'image',
  jpeg: 'image',
  png: 'image',
  webp: 'image',
  gif: 'image',
  bmp: 'image',
  heic: 'image',
  heif: 'image',
};

/** 中身をそのまま読んでテキストの資料にするファイル(授業の課題・自分のコードなど)。 */
const TEXT_EXTENSIONS = new Set([
  'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'log', 'tex', 'bib', 'rst',
  'html', 'htm', 'css', 'scss', 'js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'vue', 'svelte',
  'py', 'ipynb', 'java', 'kt', 'kts', 'scala', 'c', 'h', 'cc', 'cpp', 'hpp', 'cs', 'go', 'rs', 'swift', 'm', 'mm',
  'rb', 'php', 'pl', 'lua', 'r', 'jl', 'hs', 'ml', 'ex', 'exs', 'erl', 'clj', 'lisp', 'scm', 'rkt', 'dart',
  'sql', 'sh', 'bash', 'zsh', 'ps1', 'bat', 'asm', 's', 'v', 'sv', 'vhd', 'vhdl', 'mat', 'gradle', 'cmake',
]);
/** テキストのファイルとして読む大きさの上限(10万字の日本語でも収まる)。 */
const MAX_TEXT_FILE_BYTES = 2 * 1024 * 1024;

/** ファイル選択の accept。 */
export const CHAT_FILE_ACCEPT = [
  '.pdf', '.docx', '.pptx', 'image/*', '.heic', '.heif',
  ...[...TEXT_EXTENSIONS].map((ext) => `.${ext}`),
].join(',');

export { ChatFileError };

function extensionOf(name: string): string {
  const i = name.lastIndexOf('.');
  return i >= 0 ? name.slice(i + 1).toLowerCase() : '';
}

/** アップロードして読むファイルの種類。テキストとして読むもの・未対応はnull。 */
export function fileKindFor(file: File): ChatFileKind | null {
  const byExt = KIND_BY_EXTENSION[extensionOf(file.name)];
  if (byExt) return byExt;
  // 貼り付けたスクショは名前が無い("image.png")ことがあるので、種類でも判定する
  if (file.type.startsWith('image/')) return 'image';
  return null;
}

export function isTextFile(file: File): boolean {
  return TEXT_EXTENSIONS.has(extensionOf(file.name)) || (file.type.startsWith('text/') && !fileKindFor(file));
}

/** テキスト・コードのファイルを読む(テキストの資料にする)。長すぎれば ATTACHMENT_TOO_LONG。 */
export async function readTextFile(file: File): Promise<string> {
  if (file.size > MAX_TEXT_FILE_BYTES) {
    throw new ChatFileError('ATTACHMENT_TOO_LONG', { max_chars: CHAT_MAX_ATTACHMENT_CHARS });
  }
  const text = (await file.text()).replace(/\r\n/g, '\n');
  if (!text.trim()) throw new ChatFileError('FILE_EMPTY');
  if (text.length > CHAT_MAX_ATTACHMENT_CHARS) {
    throw new ChatFileError('ATTACHMENT_TOO_LONG', { max_chars: CHAT_MAX_ATTACHMENT_CHARS });
  }
  return text;
}

// ---------------------------------------------------------------------------
// アップロード
// ---------------------------------------------------------------------------

interface UploadTarget {
  attachment_id: string;
  upload_url: string;
  content_type: string;
  kind: ChatFileKind;
  max_bytes: number;
}

function putToR2(url: string, blob: Blob, contentType: string, onRatio: (ratio: number) => void, signal?: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', url);
    xhr.setRequestHeader('Content-Type', contentType);
    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) onRatio(e.loaded / e.total);
    });
    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) return resolve();
      // 原因を追えるように、R2の返事(署名の不一致など)をコンソールに残す
      console.error('[chat] upload to storage failed', xhr.status, xhr.responseText.slice(0, 300));
      reject(new ChatFileError('UPLOAD_FAILED', { status: xhr.status }));
    });
    // status 0: CORSで止められた・通信が切れた(ブラウザは理由を教えない。コンソールにCORSのエラーが出る)
    xhr.addEventListener('error', () => {
      console.error('[chat] upload to storage failed (network or CORS)', xhr.status);
      reject(new ChatFileError('UPLOAD_FAILED', { status: xhr.status }));
    });
    xhr.addEventListener('abort', () => reject(new DOMException('Upload cancelled', 'AbortError')));
    signal?.addEventListener('abort', () => xhr.abort());
    xhr.send(blob);
  });
}

function withExtension(name: string, ext: string): string {
  const i = name.lastIndexOf('.');
  return `${i > 0 ? name.slice(0, i) : name || 'image'}.${ext}`;
}

/** APIのエラーをChatFileErrorにする(error_codeとdetailを残す)。 */
function toFileError(e: unknown): ChatFileError {
  if (e instanceof ChatFileError) return e;
  if (e instanceof ApiError) {
    const body = e.body as { detail?: unknown } | null;
    const detail = body && typeof body.detail === 'object' && body.detail ? (body.detail as Record<string, unknown>) : {};
    return new ChatFileError(extractErrorCode(e) ?? `HTTP_${e.status}`, detail);
  }
  return new ChatFileError('UPLOAD_FAILED');
}

/**
 * 1ファイルを、送れる状態(draft・取り出し済み)にする。段階が進むたびにonUpdateで下書きを更新する。
 * 失敗したらChatFileErrorを投げる(アップロード先を頼んだ後なら、attachmentIdはonUpdateで渡し済み)。
 */
export async function prepareChatFile(
  file: File,
  kind: ChatFileKind,
  onUpdate: (patch: Partial<ChatFileDraft>) => void,
  signal?: AbortSignal
): Promise<ChatFileInfo> {
  try {
    onUpdate({ stage: 'compressing' });
    let blob: Blob = file;
    let name = file.name || 'file';
    if (kind === 'image') {
      blob = (await shrinkImage(file, false)).blob;
      name = withExtension(name, 'jpg');
      onUpdate({ previewUrl: URL.createObjectURL(blob) });
    } else if (kind === 'docx' || kind === 'pptx') {
      blob = await shrinkOfficeFile(file, kind);
    }
    if (blob.size > CHAT_MAX_FILE_BYTES[kind]) {
      // docx・pptxが縮めても大きいのは、たいてい動画・音声が入っているとき
      throw new ChatFileError(kind === 'docx' || kind === 'pptx' ? 'FILE_TOO_LARGE_MEDIA' : 'FILE_TOO_LARGE', {
        max_bytes: CHAT_MAX_FILE_BYTES[kind],
      });
    }
    if (signal?.aborted) throw new DOMException('Cancelled', 'AbortError');

    const target = await apiFetch<UploadTarget>('/chat/attachments/uploads', {
      method: 'POST',
      body: JSON.stringify({ file_name: name, file_size: blob.size }),
    });
    onUpdate({ stage: 'uploading', attachmentId: target.attachment_id, progress: 0 });
    await putToR2(target.upload_url, blob, target.content_type, (progress) => onUpdate({ progress }), signal);

    onUpdate({ stage: 'reading' });
    return await apiFetch<ChatFileInfo>(`/chat/attachments/${target.attachment_id}/extract`, { method: 'POST' });
  } catch (e) {
    if ((e as Error)?.name === 'AbortError') throw e;
    throw toFileError(e);
  }
}
