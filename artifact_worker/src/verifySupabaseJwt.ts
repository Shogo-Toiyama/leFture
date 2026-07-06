/**
 * SupabaseのアクセストークンをWorker内でローカル検証するためのヘルパー。
 *
 * Supabaseは非対称鍵(ES256 / P-256)でJWTを署名しているため、公開鍵(JWKS)さえ
 * 手元にあれば秘密情報を一切持たずに検証できる。JWKSはSupabaseの
 * `/auth/v1/.well-known/jwks.json` から取得し、滅多に変わらないので
 * モジュールスコープの変数にキャッシュしてリクエストのたびには取りに行かない。
 */

export interface SupabaseJwtPayload {
  sub: string; // ユーザーID (uid)
  exp: number; // 有効期限 (unix seconds)
  aud?: string;
  role?: string;
  [key: string]: unknown;
}

interface Jwk {
  kid?: string;
  kty: string;
  crv?: string;
  x?: string;
  y?: string;
  alg?: string;
  [key: string]: unknown;
}

interface JwksCache {
  keys: Jwk[];
  fetchedAt: number; // epoch ms
}

// Workerのisolateが使い回される間は再フェッチを避けるためのモジュールスコープキャッシュ。
let jwksCache: JwksCache | null = null;

async function getJwks(supabaseUrl: string, ttlSeconds: number): Promise<Jwk[]> {
  const now = Date.now();
  if (jwksCache && now - jwksCache.fetchedAt < ttlSeconds * 1000) {
    return jwksCache.keys;
  }

  const response = await fetch(`${supabaseUrl}/auth/v1/.well-known/jwks.json`);
  if (!response.ok) {
    // フェッチ失敗時、古いキャッシュがあればそれを使い続ける（Supabase側の一時障害に耐える）
    if (jwksCache) return jwksCache.keys;
    throw new Error(`Failed to fetch JWKS: ${response.status}`);
  }

  const data = (await response.json()) as { keys: Jwk[] };
  jwksCache = { keys: data.keys, fetchedAt: now };
  return data.keys;
}

/** base64url文字列 → バイト列 */
function base64UrlToBytes(base64Url: string): Uint8Array {
  const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function base64UrlToJson<T>(base64Url: string): T {
  const bytes = base64UrlToBytes(base64Url);
  const text = new TextDecoder().decode(bytes);
  return JSON.parse(text) as T;
}

/**
 * SupabaseのアクセストークンをES256で検証し、ペイロードを返す。
 * 検証に失敗する(署名不正/期限切れ/対応する鍵が無い等)場合はnullを返す。
 *
 * 想定外のalgを使ったトークン(alg confusion攻撃対策)は無条件で拒否する。
 */
export async function verifySupabaseJwt(
  token: string,
  supabaseUrl: string,
  jwksCacheTtlSeconds: number,
): Promise<SupabaseJwtPayload | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [headerB64, payloadB64, signatureB64] = parts;

  let header: { alg?: string; kid?: string };
  let payload: SupabaseJwtPayload;
  try {
    header = base64UrlToJson(headerB64);
    payload = base64UrlToJson(payloadB64);
  } catch {
    return null;
  }

  // ES256以外は受け付けない（"alg": "none" 等を使った偽装を防ぐ）
  if (header.alg !== 'ES256') return null;

  // 有効期限チェック（多少のクロックずれを許容して30秒のマージンを持たせる）
  const nowSeconds = Date.now() / 1000;
  if (typeof payload.exp !== 'number' || payload.exp + 30 < nowSeconds) {
    return null;
  }

  let keys: Jwk[];
  try {
    keys = await getJwks(supabaseUrl, jwksCacheTtlSeconds);
  } catch {
    return null;
  }

  const jwk = header.kid ? keys.find((k) => k.kid === header.kid) : keys[0];
  if (!jwk || jwk.kty !== 'EC' || jwk.crv !== 'P-256') return null;

  let publicKey: CryptoKey;
  try {
    publicKey = await crypto.subtle.importKey(
      'jwk',
      jwk as JsonWebKey,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );
  } catch {
    return null;
  }

  const signedData = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const signature = base64UrlToBytes(signatureB64);

  const isValid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    publicKey,
    signature,
    signedData,
  );

  return isValid ? payload : null;
}
