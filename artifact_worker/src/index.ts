/**
 * lefture-artifact-worker
 *
 * R2に保存された講義の成果物(トランスクリプトJSON・トピック画像など)を、
 * SupabaseのアクセストークンでWorker内ローカル検証した上で直接返すプロキシ。
 *
 * リクエスト例:
 *   GET https://<worker-url>/{uid}/{lectureId}/pipeline_logs/role_classification.json
 *   Authorization: Bearer <supabase access token>
 *
 * パス先頭の{uid}がトークンのsub(ユーザーID)と一致しない場合は403で拒否する。
 * これにより、他人の成果物には(トークンを持っていても)アクセスできない。
 *
 * {uid}/{lectureId}/pipeline_logs/ 配下(トランスクリプトを含む中間JSON)は、
 * 本人のプランがPIPELINE_LOGS_MIN_TIER以上のときだけ返す(画面側のロックだけに
 * 頼らず、配信元で止める)。
 */

import { verifySupabaseJwt } from './verifySupabaseJwt';
import { expiryFor, isSignableKey, signKey, verifySignedKey } from './signedUrl';

export interface Env {
  LECTURE_ASSETS: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
  JWKS_CACHE_TTL_SECONDS: string;
  /** 講義音声の署名付きURL用のHMAC鍵(wrangler secret)。未設定なら署名付きURLは使えない。 */
  AUDIO_URL_SIGNING_SECRET?: string;
}

// pipeline_logs/を返すのに必要なtier_level(2=Core)。クライアントがここから読むのは
// トランスクリプト(role_classification.json / transcript_assembled.json)だけで、
// 他のファイルも文字起こしの本文を含むため、ディレクトリごとトランスクリプト閲覧
// (FEATURE_SOURCE_TRANSCRIPT_VIEW)と同じプランに限る。
// 値はバックエンドのlefture_backend/app/services/helpers/plan_features.pyと必ず揃えること。
const PIPELINE_LOGS_MIN_TIER = 2;

const CORS_HEADERS = {
  // ネイティブアプリ(iOS/Android)からのリクエストにCORSは無関係だが、
  // 将来Flutter Web版を出す場合に備えて安価に許可しておく。
  // 認証はCookieではなくBearerトークンなので、Access-Control-Allow-Originを
  // 緩めてもCSRF等のリスクは増えない。
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Range, If-Range',
  'Access-Control-Expose-Headers': 'Content-Range, Content-Length, Accept-Ranges, ETag',
};

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

// R2に保存時のContent-Typeが何らかの理由で欠けていた場合の保険的フォールバック。
function guessContentType(key: string): string {
  if (key.endsWith('.json')) return 'application/json';
  if (key.endsWith('.jpg') || key.endsWith('.jpeg')) return 'image/jpeg';
  if (key.endsWith('.png')) return 'image/png';
  if (key.endsWith('.webp')) return 'image/webp';
  if (key.endsWith('.m4a')) return 'audio/mp4';
  return 'application/octet-stream';
}

function isPipelineLog(key: string): boolean {
  // {uid}/{lectureId}/pipeline_logs/...
  return key.split('/')[2] === 'pipeline_logs';
}

/**
 * 本人のtier_levelを、本人のアクセストークンのままSupabaseのRPC(get_my_tier_level)で引く。
 * RPCはauth.uid()で本人に絞るため、Workerはservice roleキーを持たなくてよい。
 * 取得できなければnull(呼び出し側で拒否する)。
 */
async function fetchTierLevel(env: Env, token: string): Promise<number | null> {
  try {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/get_my_tier_level`, {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    if (!res.ok) {
      console.error(`get_my_tier_level failed: ${res.status} ${await res.text()}`);
      return null;
    }
    const tier = await res.json();
    return typeof tier === 'number' ? tier : null;
  } catch (e) {
    console.error('get_my_tier_level threw', e);
    return null;
  }
}

/**
 * R2のオブジェクトを返す。Rangeヘッダーがあれば該当部分だけを206で返す
 * (音声のストリーミング再生用。プレイヤーが再生位置の周りだけを取りに来る)。
 * Rangeが無ければ従来通り全体を200で返す。HEADは本文なしでヘッダーだけ返す。
 */
async function serveObject(
  request: Request,
  env: Env,
  key: string,
  cacheControl: string,
): Promise<Response> {
  const baseHeaders: Record<string, string> = {
    'Accept-Ranges': 'bytes',
    'Cache-Control': cacheControl,
    ...CORS_HEADERS,
  };

  if (request.method === 'HEAD') {
    const head = await env.LECTURE_ASSETS.head(key);
    if (!head) return jsonError(404, 'Not found');
    return new Response(null, {
      status: 200,
      headers: {
        ...baseHeaders,
        'Content-Type': head.httpMetadata?.contentType ?? guessContentType(key),
        'Content-Length': String(head.size),
        ETag: head.httpEtag,
      },
    });
  }

  let wantsRange = request.headers.has('Range');
  // If-Range: 手元の部分キャッシュと今のファイルが違う(例: 形式を揃えるために
  // 上書きされた)なら、範囲ではなく全体を返す(RFC 9110)。古い断片と新しい断片が
  // 混ざらないようにするため。
  const ifRange = request.headers.get('If-Range');
  if (wantsRange && ifRange) {
    const head = await env.LECTURE_ASSETS.head(key);
    if (!head) return jsonError(404, 'Not found');
    if (head.httpEtag !== ifRange) wantsRange = false;
  }

  let object: R2ObjectBody | null;
  try {
    object = wantsRange
      ? await env.LECTURE_ASSETS.get(key, { range: request.headers })
      : await env.LECTURE_ASSETS.get(key);
  } catch {
    // 範囲がファイルの外など、満たせないRange
    const head = await env.LECTURE_ASSETS.head(key);
    if (!head) return jsonError(404, 'Not found');
    return new Response(null, {
      status: 416,
      headers: { ...baseHeaders, 'Content-Range': `bytes */${head.size}` },
    });
  }
  if (!object) return jsonError(404, 'Not found');

  // 開始位置がファイルの外のRangeは、R2の実装によっては例外にならず全体が
  // 返ってくることがある(ローカルのwrangler devで確認)。ここで416にする。
  if (wantsRange) {
    const start = /^bytes=(\d+)-/.exec(request.headers.get('Range') ?? '')?.[1];
    if (start !== undefined && Number(start) >= object.size) {
      await object.body.cancel();
      return new Response(null, {
        status: 416,
        headers: { ...baseHeaders, 'Content-Range': `bytes */${object.size}` },
      });
    }
  }

  const headers: Record<string, string> = {
    ...baseHeaders,
    'Content-Type': object.httpMetadata?.contentType ?? guessContentType(key),
    ETag: object.httpEtag,
  };

  const range = object.range as { offset?: number; length?: number; suffix?: number } | undefined;
  if (wantsRange && range) {
    const start = range.suffix !== undefined
      ? Math.max(0, object.size - range.suffix)
      : (range.offset ?? 0);
    const length = range.suffix !== undefined
      ? object.size - start
      : (range.length ?? object.size - start);
    headers['Content-Range'] = `bytes ${start}-${start + length - 1}/${object.size}`;
    headers['Content-Length'] = String(length);
    return new Response(object.body, { status: 206, headers });
  }

  headers['Content-Length'] = String(object.size);
  return new Response(object.body, { status: 200, headers });
}

type AuthResult =
  | { ok: false; error: Response }
  | { ok: true; token: string; payload: NonNullable<Awaited<ReturnType<typeof verifySupabaseJwt>>> };

/** Authorization: Bearer <JWT> を検証して、成功すればpayloadを返す。 */
async function authenticate(request: Request, env: Env): Promise<AuthResult> {
  const authHeader = request.headers.get('Authorization') ?? '';
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) return { ok: false, error: jsonError(401, 'Missing Authorization header') };
  const token = match[1];
  const ttl = Number(env.JWKS_CACHE_TTL_SECONDS) || 21600;
  const payload = await verifySupabaseJwt(token, env.SUPABASE_URL, ttl);
  if (!payload) return { ok: false, error: jsonError(401, 'Invalid or expired token') };
  return { ok: true, token, payload };
}

function parseKey(pathname: string): string | null {
  // 先頭の "/" を取り除いたものがそのままR2のオブジェクトキーになる。
  // 例: /4859e134-.../36de58f6-.../pipeline_logs/role_classification.json
  const key = decodeURIComponent(pathname.replace(/^\/+/, ''));
  if (!key || key.includes('..')) return null;
  return key;
}

const SIGN_PREFIX = '/sign/';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return jsonError(405, 'Method not allowed');
    }

    const url = new URL(request.url);
    const nowSeconds = Math.floor(Date.now() / 1000);

    // --- 署名付きURLの発行: GET /sign/{uid}/{lectureId}/master_audio.m4a ---
    if (url.pathname.startsWith(SIGN_PREFIX)) {
      if (!env.AUDIO_URL_SIGNING_SECRET) {
        // 秘密鍵が未設定。クライアントは従来の全体ダウンロードにフォールバックする。
        return jsonError(503, 'Signed URLs are not configured');
      }
      const key = parseKey(url.pathname.slice(SIGN_PREFIX.length));
      if (!key || !isSignableKey(key)) return jsonError(400, 'Only lecture audio can be signed');
      const auth = await authenticate(request, env);
      if (!auth.ok) return auth.error;
      if (!key.startsWith(`${auth.payload.sub}/`)) return jsonError(403, 'Forbidden');

      const exp = expiryFor(nowSeconds);
      const sig = await signKey(env.AUDIO_URL_SIGNING_SECRET, key, exp);
      const signedUrl = `${url.origin}/${key.split('/').map(encodeURIComponent).join('/')}?exp=${exp}&sig=${sig}`;
      return new Response(JSON.stringify({ url: signedUrl, expires_at: exp }), {
        status: 200,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...CORS_HEADERS },
      });
    }

    const key = parseKey(url.pathname);
    if (!key) return jsonError(400, 'Invalid path');

    // --- 署名付きURLでのアクセス(講義音声のストリーミング再生) ---
    if (url.searchParams.has('sig')) {
      const ok = env.AUDIO_URL_SIGNING_SECRET
        ? await verifySignedKey(
            env.AUDIO_URL_SIGNING_SECRET,
            key,
            url.searchParams.get('exp'),
            url.searchParams.get('sig'),
            nowSeconds,
          )
        : false;
      if (!ok) return jsonError(403, 'Invalid or expired signature');
      // 形式を揃えるために上書きされうるので、毎回確認させる(no-cache)。
      return serveObject(request, env, key, 'private, no-cache');
    }

    // --- 従来: Authorizationヘッダーでのアクセス ---
    const auth = await authenticate(request, env);
    if (!auth.ok) return auth.error;

    // パスの先頭セグメントが自分のuidと一致する場合のみアクセスを許可する。
    // (例えば他人のlectureIdを知っていても、パス先頭が他人のuidなので弾かれる)
    if (!key.startsWith(`${auth.payload.sub}/`)) {
      return jsonError(403, 'Forbidden');
    }

    const planGated = isPipelineLog(key);
    if (planGated) {
      const tier = await fetchTierLevel(env, auth.token);
      if (tier === null) {
        return jsonError(503, 'Could not verify plan');
      }
      if (tier < PIPELINE_LOGS_MIN_TIER) {
        return jsonError(403, 'Plan does not include transcript access');
      }
    }

    // 生成後は不変なファイルなので、クライアント側でも積極的にキャッシュしてよい。
    // privateはCDN等の共有キャッシュに乗らないようにするため(認可済みの個人データのため)。
    // プランで出し分けるpipeline_logs/は、ダウングレード後にブラウザのキャッシュから
    // 読めてしまわないよう毎回ここを通す。音声は形式を揃えるために上書きされうるので
    // 毎回確認させる。
    const cacheControl = planGated || isSignableKey(key) ? 'private, no-cache' : 'private, max-age=86400';
    return serveObject(request, env, key, cacheControl);
  },
};
