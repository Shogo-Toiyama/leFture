import { supabase } from './supabase';
import { GOOGLE_CLIENT_ID } from './env';

function generateRandomString(length = 32): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  const array = new Uint8Array(length);
  window.crypto.getRandomValues(array);
  for (let i = 0; i < length; i++) {
    result += chars[array[i] % chars.length];
  }
  return result;
}

async function sha256Hex(plain: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(plain);
  const hash = await window.crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hash));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Google OAuth 2.0 のポップアップウィンドウを開いて直接 ID Token を取得し、
 * supabase.auth.signInWithIdToken に渡してセッションを確立する。
 *
 * 特徴:
 * 1. Supabase のリダイレクトURLを経由しないため「...supabase.co に続行」が表示されない。
 * 2. One Tap ではなく中央ポップアップウィンドウのため、何度閉じてもボタンを押せば毎回確実に開く。
 *
 * ノンス仕様 (auth_provider.dart:44-48 と同等):
 * - Google OAuth の URL には SHA-256 ハッシュ済みの nonce を渡す (IDトークンの nonce クレームに格納される)。
 * - Supabase の signInWithIdToken には生の rawNonce を渡す (Supabase側がハッシュ化してトークン内クレームと照合する)。
 */
export async function signInWithGoogleDirect(): Promise<void> {
  const rawNonce = generateRandomString();
  const hashedNonce = await sha256Hex(rawNonce);
  const state = generateRandomString();
  const redirectUri = window.location.origin;

  // Google OAuth 2.0 認証エンドポイント
  const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  authUrl.searchParams.set('client_id', GOOGLE_CLIENT_ID);
  authUrl.searchParams.set('redirect_uri', redirectUri);
  authUrl.searchParams.set('response_type', 'id_token');
  authUrl.searchParams.set('scope', 'openid email profile');
  authUrl.searchParams.set('nonce', hashedNonce);
  authUrl.searchParams.set('state', state);
  authUrl.searchParams.set('prompt', 'select_account');

  // 画面中央にポップアップウィンドウを配置
  const width = 500;
  const height = 600;
  const left = window.screenX + (window.outerWidth - width) / 2;
  const top = window.screenY + (window.outerHeight - height) / 2;

  const popup = window.open(
    authUrl.toString(),
    'google-oauth-popup',
    `width=${width},height=${height},left=${left},top=${top},status=no,resizable=yes,scrollbars=yes`
  );

  if (!popup) {
    throw new Error('Popup was blocked by browser. Please allow popups for this site.');
  }

  return new Promise((resolve, reject) => {
    // ポップアップがリダイレクトされてURLハッシュ（#id_token=...）を受け取るのを監視
    const interval = setInterval(async () => {
      try {
        if (popup.closed) {
          clearInterval(interval);
          reject(new Error('popup_closed_by_user'));
          return;
        }

        // 同一オリジンに戻ってきたかをチェック
        if (popup.location.href.startsWith(redirectUri)) {
          const hash = popup.location.hash;
          if (hash) {
            const params = new URLSearchParams(hash.substring(1));
            const idToken = params.get('id_token');
            const returnedState = params.get('state');
            const error = params.get('error');

            if (error) {
              clearInterval(interval);
              popup.close();
              reject(new Error(error));
              return;
            }

            if (idToken && returnedState === state) {
              clearInterval(interval);
              popup.close();

              // Supabase に ID Token と生の Nonce を渡してセッション確立
              const { error: signInError } = await supabase.auth.signInWithIdToken({
                provider: 'google',
                token: idToken,
                nonce: rawNonce,
              });

              if (signInError) {
                reject(signInError);
              } else {
                resolve();
              }
              return;
            }
          }
        }
      } catch {
        // クロスオリジン（accounts.google.com 上）にいる間はアクセス制限で例外が出るため無視してポーリング継続
      }
    }, 200);
  });
}
