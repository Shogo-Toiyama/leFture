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

export interface Env {
  LECTURE_ASSETS: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
  JWKS_CACHE_TTL_SECONDS: string;
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
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization',
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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }
    if (request.method !== 'GET') {
      return jsonError(405, 'Method not allowed');
    }

    // 先頭の "/" を取り除いたものがそのままR2のオブジェクトキーになる。
    // 例: /4859e134-.../36de58f6-.../pipeline_logs/role_classification.json
    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.replace(/^\/+/, ''));

    if (!key || key.includes('..')) {
      return jsonError(400, 'Invalid path');
    }

    const authHeader = request.headers.get('Authorization') ?? '';
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (!match) {
      return jsonError(401, 'Missing Authorization header');
    }
    const token = match[1];

    const ttl = Number(env.JWKS_CACHE_TTL_SECONDS) || 21600;
    const payload = await verifySupabaseJwt(token, env.SUPABASE_URL, ttl);
    if (!payload) {
      return jsonError(401, 'Invalid or expired token');
    }

    // パスの先頭セグメントが自分のuidと一致する場合のみアクセスを許可する。
    // (例えば他人のlectureIdを知っていても、パス先頭が他人のuidなので弾かれる)
    if (!key.startsWith(`${payload.sub}/`)) {
      return jsonError(403, 'Forbidden');
    }

    const planGated = isPipelineLog(key);
    if (planGated) {
      const tier = await fetchTierLevel(env, token);
      if (tier === null) {
        return jsonError(503, 'Could not verify plan');
      }
      if (tier < PIPELINE_LOGS_MIN_TIER) {
        return jsonError(403, 'Plan does not include transcript access');
      }
    }

    const object = await env.LECTURE_ASSETS.get(key);
    if (!object) {
      return jsonError(404, 'Not found');
    }

    const contentType = object.httpMetadata?.contentType ?? guessContentType(key);

    return new Response(object.body, {
      status: 200,
      headers: {
        'Content-Type': contentType,
        // 生成後は不変なファイルなので、クライアント側でも積極的にキャッシュしてよい。
        // privateはCDN等の共有キャッシュに乗らないようにするため(認可済みの個人データのため)。
        // プランで出し分けるpipeline_logs/は、ダウングレード後にブラウザのキャッシュから
        // 読めてしまわないよう毎回ここを通す。
        'Cache-Control': planGated ? 'private, no-cache' : 'private, max-age=86400',
        'Content-Length': String(object.size),
        ...CORS_HEADERS,
      },
    });
  },
};
