import { supabase } from './supabase';
import { GOOGLE_CLIENT_ID } from './env';

// index.html内のインラインスクリプトと手動で同期させること。
const PENDING_STORAGE_KEY = 'lefture_google_oauth_pending';
const BROADCAST_CHANNEL_NAME = 'lefture-google-oauth';
const POPUP_TIMEOUT_MS = 120_000;

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

interface GoogleOAuthCallbackPayload {
  state: string | null;
  idToken: string | null;
  error: string | null;
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
 *
 * 完了検知はwindow.closed/popup.locationを外から覗き見る方式ではなく、ポップアップ自身が
 * (index.htmlのインラインスクリプト経由で)BroadcastChannelで能動的に知らせてくる方式。
 * Googleのログインページが最近付けるようになったCross-Origin-Opener-Policyにより、
 * ポップアップが一度accounts.google.comに遷移すると、その後自社ドメインに戻ってきても
 * 親ウィンドウからpopup.closed/popup.locationへのアクセスが恒久的に塞がれるため
 * (ブラウジングコンテキストグループの分離が以降のナビゲーションでも復元されない)。
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

  localStorage.setItem(PENDING_STORAGE_KEY, '1');

  const popup = window.open(
    authUrl.toString(),
    'google-oauth-popup',
    `width=${width},height=${height},left=${left},top=${top},status=no,resizable=yes,scrollbars=yes`
  );

  if (!popup) {
    localStorage.removeItem(PENDING_STORAGE_KEY);
    throw new Error('Popup was blocked by browser. Please allow popups for this site.');
  }

  return new Promise((resolve, reject) => {
    let settled = false;
    const channel = new BroadcastChannel(BROADCAST_CHANNEL_NAME);

    const cleanup = () => {
      settled = true;
      localStorage.removeItem(PENDING_STORAGE_KEY);
      channel.close();
      clearInterval(closedCheckInterval);
      clearTimeout(timeoutId);
    };

    const handlePayload = async (payload: GoogleOAuthCallbackPayload) => {
      if (settled || payload.state !== state) return;
      cleanup();

      if (payload.error) {
        reject(new Error(payload.error));
        return;
      }
      if (!payload.idToken) {
        reject(new Error('No ID token returned'));
        return;
      }

      // Supabase に ID Token と生の Nonce を渡してセッション確立
      const { error: signInError } = await supabase.auth.signInWithIdToken({
        provider: 'google',
        token: payload.idToken,
        nonce: rawNonce,
      });

      if (signInError) {
        reject(signInError);
      } else {
        resolve();
      }
    };

    channel.onmessage = (event: MessageEvent<GoogleOAuthCallbackPayload>) => {
      void handlePayload(event.data);
    };

    // ユーザーが手動でポップアップを閉じた場合のベストエフォート検知。
    // accounts.google.com遷移後はCOOPで塞がれて例外になる/常にfalseになることがあるが、
    // その場合は下のタイムアウトが安全網になる。
    const closedCheckInterval = setInterval(() => {
      try {
        if (popup.closed) {
          cleanup();
          reject(new Error('popup_closed_by_user'));
        }
      } catch {
        // COOPにより判定不能。無視してポーリング継続(タイムアウトに任せる)。
      }
    }, 500);

    const timeoutId = setTimeout(() => {
      if (settled) return;
      cleanup();
      try {
        popup.close();
      } catch {
        // 既にCOOPで参照が切れている場合は何もできない。ユーザーが手動で閉じる。
      }
      reject(new Error('popup_timeout'));
    }, POPUP_TIMEOUT_MS);
  });
}
