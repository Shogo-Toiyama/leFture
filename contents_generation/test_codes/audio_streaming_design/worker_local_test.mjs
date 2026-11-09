// Local test of artifact_worker's Range + signed-URL handling against `wrangler dev --local`.
//
// Setup (from artifact_worker/):
//   printf 'AUDIO_URL_SIGNING_SECRET=local-test-secret\n' > .dev.vars
//   npx wrangler r2 object put lefture-assets/u1/l1/master_audio.m4a --local --file <audio> --content-type audio/x-m4a
//   npx wrangler r2 object put lefture-assets/u1/l1/images/topic_1.jpg --local --file <any>
//   npx wrangler dev --local --port 8799 --ip 127.0.0.1
// Run:
//   node contents_generation/test_codes/audio_streaming_design/worker_local_test.mjs <same audio file>
//
// The signature is computed here with the same algorithm as artifact_worker/src/signedUrl.ts,
// so no Supabase session is needed. The JWT-protected /sign endpoint is only checked for
// its unauthenticated and wrong-file rejections.
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';

const BASE = 'http://127.0.0.1:8799';
const SECRET = 'local-test-secret';
const KEY = 'u1/l1/master_audio.m4a';
const file = readFileSync(process.argv[2]);
const now = Math.floor(Date.now() / 1000);

const sign = (key, exp, secret = SECRET) =>
  createHmac('sha256', secret).update(`${key}\n${exp}`).digest('base64url');
const signed = (key, exp, sig = sign(key, exp)) => `${BASE}/${key}?exp=${exp}&sig=${sig}`;

let failed = 0;
const check = (name, cond, detail = '') => {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`);
  if (!cond) failed++;
};

const exp = now + 3600;
const url = signed(KEY, exp);

// 1. full body
let r = await fetch(url);
let body = Buffer.from(await r.arrayBuffer());
check('full GET via signature -> 200 + whole file', r.status === 200 && body.equals(file), `status=${r.status} bytes=${body.length}`);
check('Accept-Ranges: bytes', r.headers.get('accept-ranges') === 'bytes');

// 2. middle range
r = await fetch(url, { headers: { Range: 'bytes=1000-1999' } });
body = Buffer.from(await r.arrayBuffer());
check('Range 1000-1999 -> 206 + exact bytes', r.status === 206 && body.equals(file.subarray(1000, 2000)), `status=${r.status}`);
check('Content-Range header', r.headers.get('content-range') === `bytes 1000-1999/${file.length}`, r.headers.get('content-range'));
check('Content-Length = 1000', r.headers.get('content-length') === '1000');

// 3. open-ended and suffix ranges
r = await fetch(url, { headers: { Range: `bytes=${file.length - 100}-` } });
body = Buffer.from(await r.arrayBuffer());
check('open-ended range -> last 100 bytes', r.status === 206 && body.equals(file.subarray(file.length - 100)), r.headers.get('content-range'));
r = await fetch(url, { headers: { Range: 'bytes=-50' } });
body = Buffer.from(await r.arrayBuffer());
check('suffix range -50 -> last 50 bytes', r.status === 206 && body.equals(file.subarray(file.length - 50)), r.headers.get('content-range'));

// 4. unsatisfiable range
r = await fetch(url, { headers: { Range: `bytes=${file.length + 10}-${file.length + 20}` } });
check('range past end -> 416', r.status === 416, `status=${r.status} content-range=${r.headers.get('content-range')}`);

// 5. HEAD
r = await fetch(url, { method: 'HEAD' });
check('HEAD -> 200 with size', r.status === 200 && r.headers.get('content-length') === String(file.length), `status=${r.status}`);
const etag = r.headers.get('etag');

// 6. If-Range
r = await fetch(url, { headers: { Range: 'bytes=0-9', 'If-Range': '"stale-etag"' } });
check('If-Range mismatch -> 200 whole file', r.status === 200, `status=${r.status}`);
await r.arrayBuffer();
r = await fetch(url, { headers: { Range: 'bytes=0-9', 'If-Range': etag } });
check('If-Range match -> 206', r.status === 206, `status=${r.status}`);
await r.arrayBuffer();

// 7. rejections
r = await fetch(signed(KEY, exp, sign(KEY, exp, 'wrong-secret')));
check('wrong signature -> 403', r.status === 403, `status=${r.status}`);
r = await fetch(signed(KEY, now - 10));
check('expired signature -> 403', r.status === 403, `status=${r.status}`);
r = await fetch(`${BASE}/${KEY}?exp=${exp + 1}&sig=${sign(KEY, exp)}`);
check('tampered exp -> 403', r.status === 403, `status=${r.status}`);
r = await fetch(signed('u1/l1/images/topic_1.jpg', exp));
check('signature on a non-audio file -> 403', r.status === 403, `status=${r.status}`);
r = await fetch(signed('u2/l1/master_audio.m4a', exp, sign(KEY, exp)));
check('signature reused for another key -> 403', r.status === 403, `status=${r.status}`);
r = await fetch(`${BASE}/${KEY}`);
check('no signature, no token -> 401', r.status === 401, `status=${r.status}`);
r = await fetch(`${BASE}/sign/${KEY}`);
check('/sign without token -> 401', r.status === 401, `status=${r.status}`);
r = await fetch(`${BASE}/sign/u1/l1/images/topic_1.jpg`);
check('/sign for a non-audio file -> 400', r.status === 400, `status=${r.status}`);

console.log(failed ? `\n${failed} check(s) FAILED` : '\nall checks passed');
process.exit(failed ? 1 : 0);
