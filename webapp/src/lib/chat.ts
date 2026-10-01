import { supabase } from './supabase';
import { BACKEND_API_URL } from './env';
import { ApiError, apiFetch, extractErrorCode } from './api';
import type {
  ChatMessage,
  ChatMessageContext,
  ChatRequestErrorCode,
  ChatStreamEvent,
  ChatThread,
} from '../types/chat';

/**
 * 横断チャットボットのデータアクセス。
 *
 * - 読み取り(スレッド一覧・過去メッセージ)はSupabaseをRLS越しに直接読む
 *   (chat_threads / chat_messages は本人のみSELECT可)。
 * - 書き込み(送信・名前変更・削除)は必ずバックエンド経由。ユーザーが
 *   assistantの発言を偽造できないよう、テーブルにクライアント用の
 *   書き込みポリシーは無い。
 */

const THREAD_COLUMNS = 'id, title, mode, context_lecture_id, last_message_at, created_at';
const MESSAGE_COLUMNS =
  'id, thread_id, role, content, status, citations, context, credits_charged_micro, created_at';

export async function listChatThreads(limit = 50): Promise<ChatThread[]> {
  const { data, error } = await supabase
    .from('chat_threads')
    .select(THREAD_COLUMNS)
    .is('deleted_at', null)
    .order('last_message_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as ChatThread[];
}

export async function getChatThread(threadId: string): Promise<ChatThread | null> {
  const { data, error } = await supabase
    .from('chat_threads')
    .select(THREAD_COLUMNS)
    .eq('id', threadId)
    .is('deleted_at', null)
    .maybeSingle();
  if (error) throw error;
  return (data as ChatThread | null) ?? null;
}

export async function listChatMessages(threadId: string): Promise<ChatMessage[]> {
  const { data, error } = await supabase
    .from('chat_messages')
    .select(MESSAGE_COLUMNS)
    .eq('thread_id', threadId)
    .is('deleted_at', null)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return (data ?? []).map(normalizeMessage);
}

export async function getChatMessage(messageId: string): Promise<ChatMessage | null> {
  const { data, error } = await supabase
    .from('chat_messages')
    .select(MESSAGE_COLUMNS)
    .eq('id', messageId)
    .maybeSingle();
  if (error) throw error;
  return data ? normalizeMessage(data) : null;
}

/** 端末のIANAタイムゾーン名(例: "Asia/Tokyo")。取れない環境ではundefined(送らない)。 */
function deviceTimeZone(): string | undefined {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || undefined;
  } catch {
    return undefined;
  }
}

function normalizeMessage(row: Record<string, unknown>): ChatMessage {
  return {
    ...(row as unknown as ChatMessage),
    citations: Array.isArray(row.citations) ? (row.citations as ChatMessage['citations']) : [],
    context: (row.context as ChatMessageContext | null) ?? {},
  };
}

export async function renameChatThread(threadId: string, title: string): Promise<void> {
  await apiFetch(`/chat/threads/${threadId}`, {
    method: 'PATCH',
    body: JSON.stringify({ title }),
  });
}

export async function deleteChatThread(threadId: string): Promise<void> {
  await apiFetch(`/chat/threads/${threadId}`, { method: 'DELETE' });
}

// ---------------------------------------------------------------------------
// 送信(SSE)
// ---------------------------------------------------------------------------

export interface SendChatMessageParams {
  threadId: string | null;
  clientMessageId: string;
  content: string;
  context?: ChatMessageContext;
}

/**
 * 送信前チェックで弾かれた(ストリームが始まる前にHTTPエラーが返った)場合や、
 * ネットワークが切れた場合に投げる。codeで画面の出し分けをする。
 */
export class ChatSendError extends Error {
  constructor(
    public code: ChatRequestErrorCode | string,
    message: string,
    public status: number | null,
    public detail: Record<string, unknown> = {}
  ) {
    super(message);
    this.name = 'ChatSendError';
  }
}

/**
 * POST /chat/messages を送り、SSEイベントを順にonEventへ渡す。
 * EventSourceはPOSTとAuthorizationヘッダを扱えないので、fetchの
 * ReadableStreamを自前でパースする。ストリームが最後まで届いたら解決する。
 *
 * 途中で通信が切れても、返答の生成・保存・課金はサーバー側で最後まで
 * 走り切る(バックエンドは返答を別タスクで生成している)。呼び出し側は
 * 切断時にDBから該当メッセージを読み直せばよい。
 */
export async function sendChatMessage(
  params: SendChatMessageParams,
  onEvent: (event: ChatStreamEvent) => void,
  signal?: AbortSignal
): Promise<void> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;

  let response: Response;
  try {
    response = await fetch(`${BACKEND_API_URL}/chat/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'text/event-stream',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({
        thread_id: params.threadId,
        client_message_id: params.clientMessageId,
        content: params.content,
        context: params.context ?? null,
        // 「昨日の授業」「今学期」を端末の日付で解決するため(バックエンドは無ければUTC)
        timezone: deviceTimeZone(),
      }),
      signal,
    });
  } catch (e) {
    if ((e as Error)?.name === 'AbortError') throw e;
    throw new ChatSendError('NETWORK', 'Network error', null);
  }

  if (!response.ok) {
    const contentType = response.headers.get('content-type') ?? '';
    const body = contentType.includes('application/json') ? await response.json() : await response.text();
    const apiError = new ApiError(`Request to /chat/messages failed with status ${response.status}`, response.status, body);
    const code = extractErrorCode(apiError) ?? `HTTP_${response.status}`;
    const detail =
      typeof body === 'object' && body !== null && typeof (body as { detail?: unknown }).detail === 'object'
        ? ((body as { detail: Record<string, unknown> }).detail ?? {})
        : {};
    const message = typeof detail.message === 'string' ? detail.message : apiError.message;
    throw new ChatSendError(code, message, response.status, detail);
  }

  if (!response.body) {
    throw new ChatSendError('NETWORK', 'Empty response body', response.status);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let separator = buffer.indexOf('\n\n');
      while (separator !== -1) {
        const raw = buffer.slice(0, separator);
        buffer = buffer.slice(separator + 2);
        const event = parseSseEvent(raw);
        if (event) onEvent(event);
        separator = buffer.indexOf('\n\n');
      }
    }
    buffer += decoder.decode();
    const tail = parseSseEvent(buffer);
    if (tail) onEvent(tail);
  } catch (e) {
    if ((e as Error)?.name === 'AbortError') throw e;
    throw new ChatSendError('NETWORK', 'Connection lost while receiving the reply', response.status);
  }
}

/** "event: xxx\ndata: {...}" 1件をChatStreamEventに変換する。読めなければnull。 */
export function parseSseEvent(raw: string): ChatStreamEvent | null {
  let eventName = '';
  const dataLines: string[] = [];
  for (const line of raw.split('\n')) {
    if (line.startsWith('event:')) eventName = line.slice(6).trim();
    else if (line.startsWith('data:')) dataLines.push(line.slice(5).trimStart());
  }
  if (!eventName || dataLines.length === 0) return null;
  try {
    const payload = JSON.parse(dataLines.join('\n')) as Record<string, unknown>;
    return { type: eventName, ...payload } as ChatStreamEvent;
  } catch {
    return null;
  }
}

/** crypto.randomUUIDが無い古い環境向けのフォールバック付きUUID生成。 */
export function newClientMessageId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
