import { supabase } from './supabase';
import { BACKEND_API_URL } from './env';

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public body: unknown
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/**
 * lefture_backend (FastAPI) 呼び出し用の共通fetchラッパー。
 * 現在のSupabaseセッションのaccess_tokenを自動的にAuthorization: Bearerに付与する。
 */
export async function apiFetch<T = unknown>(
  path: string,
  init: RequestInit = {}
): Promise<T> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;

  const headers = new Headers(init.headers);
  headers.set('Content-Type', 'application/json');
  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(`${BACKEND_API_URL}${path}`, {
    ...init,
    headers,
  });

  const contentType = response.headers.get('content-type') ?? '';
  const body = contentType.includes('application/json') ? await response.json() : await response.text();

  if (!response.ok) {
    throw new ApiError(extractErrorMessage(body, path, response.status), response.status, body);
  }

  return body as T;
}

/**
 * FastAPI側のHTTPExceptionは detail が単純な文字列の場合と、
 * {error_code, message} 形式のオブジェクトの場合の両方がある
 * (例: /billing/claim-plan, /start-analysisの402)。両対応で人間可読な文言を取り出す。
 */
function extractErrorMessage(body: unknown, path: string, status: number): string {
  if (typeof body !== 'object' || body === null || !('detail' in body)) {
    return `Request to ${path} failed with status ${status}`;
  }
  const detail = (body as { detail: unknown }).detail;
  if (typeof detail === 'string') return detail;
  if (typeof detail === 'object' && detail !== null && 'message' in detail) {
    return String((detail as { message: unknown }).message);
  }
  return `Request to ${path} failed with status ${status}`;
}
