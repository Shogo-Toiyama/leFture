import { supabase } from './supabase';
import { apiFetch } from './api';

export function hasEmailIdentity(user: { identities?: { provider: string }[] | null } | null): boolean {
  return Boolean(user?.identities?.some((identity) => identity.provider === 'email'));
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
