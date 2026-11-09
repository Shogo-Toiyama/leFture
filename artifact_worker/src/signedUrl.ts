/**
 * 講義音声の署名付きURL。
 *
 * プレイヤー(Flutterのaudioplayers、ブラウザの<audio>)はAuthorizationヘッダーを
 * 付けられないため、音声だけは「パス + 有効期限」をHMACで署名したURLで配信する。
 * プレイヤーはこのURLにRangeリクエストを出し、再生位置の周りだけを取得する。
 *
 * - 署名できるのは `{uid}/{lectureId}/master_audio.m4a` だけ(プラン限定の
 *   pipeline_logs/ 等の抜け道にしないため)。発行時にJWTでuidの一致を確かめる。
 * - 有効期限は3時間ごとの区切りに揃える(6〜9時間)。同じ区切りの中では同じURLに
 *   なるので、ブラウザのキャッシュが効く。最長の講義(約6時間)でも再生中に切れない。
 * - 期限の判定はWorkerの時計で行うので、端末の時計のずれは関係ない。
 * - 秘密鍵(AUDIO_URL_SIGNING_SECRET)を入れ替えると、発行済みのURLは全て無効になる。
 */

const SIGNABLE_KEY = /^[^/]+\/[^/]+\/master_audio\.m4a$/;
const EXPIRY_BUCKET_SECONDS = 3 * 60 * 60;
const EXPIRY_BUCKETS_AHEAD = 3;

export function isSignableKey(key: string): boolean {
  return SIGNABLE_KEY.test(key);
}

/** 現在時刻から、3時間区切りに揃えた有効期限(UNIX秒)。6〜9時間後になる。 */
export function expiryFor(nowSeconds: number): number {
  return (Math.floor(nowSeconds / EXPIRY_BUCKET_SECONDS) + EXPIRY_BUCKETS_AHEAD) * EXPIRY_BUCKET_SECONDS;
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

function message(key: string, exp: number): Uint8Array {
  return new TextEncoder().encode(`${key}\n${exp}`);
}

function toBase64Url(bytes: ArrayBuffer): string {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64Url(s: string): Uint8Array | null {
  try {
    const padded = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4);
    const bin = atob(padded);
    return Uint8Array.from(bin, (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

export async function signKey(secret: string, key: string, exp: number): Promise<string> {
  const sig = await crypto.subtle.sign('HMAC', await hmacKey(secret), message(key, exp));
  return toBase64Url(sig);
}

/** 署名が正しく、期限内で、署名できる種類のパスならtrue(比較は定数時間)。 */
export async function verifySignedKey(
  secret: string,
  key: string,
  expParam: string | null,
  sigParam: string | null,
  nowSeconds: number,
): Promise<boolean> {
  if (!expParam || !sigParam || !isSignableKey(key)) return false;
  const exp = Number(expParam);
  if (!Number.isInteger(exp) || exp <= nowSeconds) return false;
  const sig = fromBase64Url(sigParam);
  if (!sig) return false;
  return crypto.subtle.verify('HMAC', await hmacKey(secret), sig, message(key, exp));
}
