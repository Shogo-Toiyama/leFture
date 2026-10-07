import type { ChatDraftAttachment, ChatFileDraft } from '../types/chat';
import type { ComposerMention } from './chatMentions';

/**
 * 入力欄の中身を、入力欄が作り直される一瞬だけメモリに預ける(ChatComposer)。
 *
 * パネル ⇄ 全画面の切り替えは別の画面へ移動するので、入力欄がいったん消えて作り直される。そのとき
 * 打っていた文字・添付した資料が消えないように、中身が変わるたびに預け、作り直されたときに受け取る
 * (会話ごと。メモリにだけ置くので、ページを読み直せば消える。localStorageには置かない)。
 * 期限は付けない: 最後に打った時刻から数えると、打ってしばらくしてから切り替えたときに戻らなくなる。
 * アップロード中のファイルの進み具合は、作り直された入力欄にも届くように、ここを通して配る。
 */

export interface ComposerSnapshot {
  value: string;
  drafts: ChatDraftAttachment[];
  mentions: ComposerMention[];
  savedAt: number;
}

const snapshots = new Map<string, ComposerSnapshot>();
const listeners = new Set<(localId: string, patch: Partial<ChatFileDraft>) => void>();

/** 準備中に外したファイル・止めるための合図(入力欄が作り直されても効くように、ここに置く)。 */
export const removedFileDrafts = new Set<string>();
export const fileDraftAborters = new Map<string, AbortController>();

export function saveComposerSnapshot(key: string, snapshot: Omit<ComposerSnapshot, 'savedAt'>): void {
  if (!snapshot.value && snapshot.drafts.length === 0) {
    snapshots.delete(key);
    return;
  }
  snapshots.set(key, { ...snapshot, savedAt: Date.now() });
}

/** 預けた中身を受け取る。無ければnull。 */
export function takeComposerSnapshot(key: string): ComposerSnapshot | null {
  return snapshots.get(key) ?? null;
}

/** アップロード中のファイルの進み具合を配る(預けている中身にも反映する)。 */
export function publishFileDraftPatch(localId: string, patch: Partial<ChatFileDraft>): void {
  for (const snap of snapshots.values()) {
    snap.drafts = snap.drafts.map((d) => (d.localId === localId && d.kind === 'file' ? { ...d, ...patch } : d));
  }
  listeners.forEach((fn) => fn(localId, patch));
}

export function subscribeFileDraftPatches(fn: (localId: string, patch: Partial<ChatFileDraft>) => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
