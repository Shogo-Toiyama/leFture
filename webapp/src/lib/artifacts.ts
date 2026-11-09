import { supabase } from './supabase';
import { ARTIFACT_WORKER_URL } from './env';

export class ArtifactFetchError extends Error {
  constructor(
    message: string,
    public storagePath: string
  ) {
    super(message);
    this.name = 'ArtifactFetchError';
  }
}

async function fetchArtifact(storagePath: string): Promise<Response> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new ArtifactFetchError('Not signed in', storagePath);

  const response = await fetch(`${ARTIFACT_WORKER_URL}/${storagePath}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    throw new ArtifactFetchError(`HTTP ${response.status}`, storagePath);
  }
  return response;
}

export async function fetchArtifactJson<T>(storagePath: string): Promise<T> {
  const response = await fetchArtifact(storagePath);
  return (await response.json()) as T;
}

/**
 * 講義音声(`{uid}/{lectureId}/master_audio.m4a`)の署名付きURLをWorkerに発行してもらう。
 * <audio src>はAuthorizationヘッダーを付けられないので、署名をURLに含める。ブラウザは
 * このURLにRangeリクエストを出し、再生位置の周りだけを取りに行く。
 * Workerが対応していない(秘密鍵が未設定など)場合はnull(呼び出し側は全体ダウンロードへ)。
 */
export async function fetchSignedAudioUrl(storagePath: string): Promise<string | null> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new ArtifactFetchError('Not signed in', storagePath);
  try {
    const response = await fetch(`${ARTIFACT_WORKER_URL}/sign/${storagePath}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) return null;
    const body = (await response.json()) as { url?: unknown };
    return typeof body.url === 'string' ? body.url : null;
  } catch {
    return null;
  }
}

/** 画像などバイナリ成果物用。呼び出し側でURL.revokeObjectURLすること。 */
export async function fetchArtifactObjectUrl(storagePath: string): Promise<string> {
  const response = await fetchArtifact(storagePath);
  const blob = await response.blob();
  return URL.createObjectURL(blob);
}

/**
 * transcript_page.dart相当: role_classification.jsonを優先し、
 * 無ければtranscript_assembled.jsonにフォールバックする。
 */
export async function fetchTranscriptArtifact<T>(userId: string, lectureId: string): Promise<T> {
  const primary = `${userId}/${lectureId}/pipeline_logs/role_classification.json`;
  const fallback = `${userId}/${lectureId}/pipeline_logs/transcript_assembled.json`;
  try {
    return await fetchArtifactJson<T>(primary);
  } catch {
    return await fetchArtifactJson<T>(fallback);
  }
}
