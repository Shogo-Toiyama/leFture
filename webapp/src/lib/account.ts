import { supabase } from './supabase';
import { apiFetch } from './api';
import { BACKEND_API_URL } from './env';

export function hasEmailIdentity(user: { identities?: { provider: string }[] | null } | null): boolean {
  return Boolean(user?.identities?.some((identity) => identity.provider === 'email'));
}

/**
 * Flutter版 BackendWarmup.waitUntilReady() 相当。
 * Cloud Runバックエンドのコールドスタートを考慮し、/health を最大45秒間ポーリングする。
 */
export async function waitUntilBackendReady(maxWaitMs = 45000, signal?: AbortSignal): Promise<boolean> {
  const deadline = Date.now() + maxWaitMs;
  while (Date.now() < deadline) {
    if (signal?.aborted) return false;
    try {
      const response = await fetch(`${BACKEND_API_URL}/health`, { signal });
      if (response.ok) return true;
    } catch {
      // 起動中は接続失敗/タイムアウトが起こり得るので無視して再試行
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return false;
}

/**
 * auth_provider.dart:469-530相当。メール/パスワードユーザーは削除前に
 * パスワード再入力で再認証する(mobileと同じ安全策)。
 * ソーシャルログインのみのユーザーは呼び出し元でユーザー名再入力による
 * 確認を済ませてから呼ぶ想定 (バックエンド側はJWTだけで削除できるため)。
 */
export async function deleteAccount(reauthEmail?: string, reauthPassword?: string): Promise<void> {
  if (reauthEmail && reauthPassword) {
    const { error } = await supabase.auth.signInWithPassword({ email: reauthEmail, password: reauthPassword });
    if (error) throw error;
  }

  await apiFetch('/auth/delete-account', { method: 'POST' });
  await supabase.auth.signOut();
}

