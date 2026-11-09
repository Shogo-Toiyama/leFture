/**
 * ブラウザ内(IndexedDB)に、録音中の音声チャンクを逐次保存する。
 *
 * PCの音の録音(systemAudioCapture.ts)は授業1コマ分=60〜90分続くため、
 * 途中でタブが落ちたり誤って閉じたりすると、メモリ上の録音は全部消えてしまう。
 * MediaRecorderが10秒ごとに吐くチャンクをここに書き足しておけば、次に
 * アップロード画面を開いたときに「保存されていない録音」として復元できる。
 * チャンクは同じMediaRecorderの出力を順番に繋いだものなので、途中で途切れていても
 * そこまでの分は有効な音声ファイル(断片化MP4)になる。
 *
 * IndexedDBが使えない環境(プライベートウィンドウ等)でも録音自体は続けたいので、
 * 呼び出し側はここの失敗を握りつぶしてよい(=復元できないだけ)。
 */

const DB_NAME = 'lefture-recordings';
const DB_VERSION = 1;
const SESSIONS = 'sessions';
const CHUNKS = 'chunks';

/**
 * 録音中のリアクション/メモ。Supabaseの`lecture_moments`に入れる値と同じ形
 * (講義はアップロード時に作るので、それまではここに持っておく)。
 * timestampSecは録音した時間(一時停止中は進まない)で、音声ファイル上の位置と一致する。
 */
export interface RecordingMoment {
  id: string;
  momentType: string;
  noteText: string | null;
  timestampSec: number;
  createdAt: string;
}

export interface RecordingSessionMeta {
  id: string;
  /** 録音開始時刻(ISO文字列) */
  startedAt: string;
  /** 最後にチャンクを書き足した時刻(ISO文字列)。startedAtとの差が録音できた長さの目安 */
  updatedAt: string;
  mimeType: string;
  bytes: number;
  chunks: number;
  moments?: RecordingMoment[];
}

interface ChunkRow {
  sessionId: string;
  seq: number;
  blob: Blob;
}

let dbPromise: Promise<IDBDatabase> | null = null;

function openDb(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(SESSIONS)) db.createObjectStore(SESSIONS, { keyPath: 'id' });
      if (!db.objectStoreNames.contains(CHUNKS)) {
        const store = db.createObjectStore(CHUNKS, { keyPath: ['sessionId', 'seq'] });
        store.createIndex('sessionId', 'sessionId', { unique: false });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  // 失敗したら次回また開き直せるようにする
  dbPromise.catch(() => {
    dbPromise = null;
  });
  return dbPromise;
}

function done(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

function request<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export async function createRecordingSession(id: string, startedAt: Date, mimeType: string): Promise<void> {
  const db = await openDb();
  const tx = db.transaction(SESSIONS, 'readwrite');
  const iso = startedAt.toISOString();
  const meta: RecordingSessionMeta = { id, startedAt: iso, updatedAt: iso, mimeType, bytes: 0, chunks: 0 };
  tx.objectStore(SESSIONS).put(meta);
  await done(tx);
}

export async function appendRecordingChunk(sessionId: string, seq: number, blob: Blob): Promise<void> {
  const db = await openDb();
  const tx = db.transaction([SESSIONS, CHUNKS], 'readwrite');
  const row: ChunkRow = { sessionId, seq, blob };
  tx.objectStore(CHUNKS).put(row);
  const sessions = tx.objectStore(SESSIONS);
  const meta = await request<RecordingSessionMeta | undefined>(sessions.get(sessionId));
  if (meta) {
    sessions.put({
      ...meta,
      updatedAt: new Date().toISOString(),
      bytes: meta.bytes + blob.size,
      chunks: meta.chunks + 1,
    });
  }
  await done(tx);
}

export async function updateRecordingSessionMoments(id: string, moments: RecordingMoment[]): Promise<void> {
  const db = await openDb();
  const tx = db.transaction(SESSIONS, 'readwrite');
  const sessions = tx.objectStore(SESSIONS);
  const meta = await request<RecordingSessionMeta | undefined>(sessions.get(id));
  if (meta) sessions.put({ ...meta, moments });
  await done(tx);
}

/** 中身のある(=1チャンク以上保存された)セッションを、新しい順に返す。 */
export async function listRecordingSessions(): Promise<RecordingSessionMeta[]> {
  const db = await openDb();
  const tx = db.transaction(SESSIONS, 'readonly');
  const all = await request<RecordingSessionMeta[]>(tx.objectStore(SESSIONS).getAll());
  return all.filter((s) => s.bytes > 0).sort((a, b) => b.startedAt.localeCompare(a.startedAt));
}

export async function loadRecordingFile(meta: RecordingSessionMeta, fileName: string): Promise<File> {
  const db = await openDb();
  const tx = db.transaction(CHUNKS, 'readonly');
  const rows = await request<ChunkRow[]>(
    tx.objectStore(CHUNKS).index('sessionId').getAll(IDBKeyRange.only(meta.id))
  );
  rows.sort((a, b) => a.seq - b.seq);
  return new File(
    rows.map((r) => r.blob),
    fileName,
    { type: meta.mimeType.split(';')[0] }
  );
}

export async function deleteRecordingSession(id: string): Promise<void> {
  const db = await openDb();
  const tx = db.transaction([SESSIONS, CHUNKS], 'readwrite');
  tx.objectStore(SESSIONS).delete(id);
  const chunks = tx.objectStore(CHUNKS);
  const keys = await request<IDBValidKey[]>(chunks.index('sessionId').getAllKeys(IDBKeyRange.only(id)));
  for (const key of keys) chunks.delete(key);
  await done(tx);
}
