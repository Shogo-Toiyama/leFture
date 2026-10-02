# lefture-artifact-worker

R2に保存された講義の成果物(トランスクリプトJSON・トピック画像など)を、Supabaseの
アクセストークンをWorker内でローカル検証した上で直接返すCloudflare Worker。

署名付きURLは発行せず、`https://<worker-url>/{uid}/{lectureId}/...` への
認証付きGETリクエスト1回でファイルの中身をそのまま返す。JWTの検証はSupabaseの
公開鍵(JWKS)を使うため、このWorkerはシークレットを一切持たない。

## 初回セットアップ

```bash
cd artifact_worker
npm install
npx wrangler login   # ブラウザが開くのでCloudflareアカウントで認証（初回だけ）
```

## デプロイ

```bash
npx wrangler deploy
```

初回実行時に `https://lefture-artifact-worker.<あなたのサブドメイン>.workers.dev` の
ようなURLが表示される。これがWorkerのベースURL。

## 動作確認

```bash
# <token> はSupabaseのアクセストークン(session.access_token)
# <path> は例えば "4859e134-.../36de58f6-.../pipeline_logs/role_classification.json"
curl -i "https://<worker-url>/<path>" \
  -H "Authorization: Bearer <token>"
```

- 200: 中身がそのまま返る
- 401: トークンが無い/不正/期限切れ
- 403: トークンのuidとパス先頭のuidが不一致 / `pipeline_logs/`(トランスクリプト等)をCore未満のプランで要求した
- 404: R2にそのオブジェクトが無い(まだ生成されていない等)
- 503: `pipeline_logs/`の要求で、プランの確認(RPC `get_my_tier_level`)に失敗した

## プランによる制限

`{uid}/{lectureId}/pipeline_logs/` 配下はトランスクリプトの本文を含むため、本人のプランが
Core(tier_level 2)以上のときだけ返す。プランは本人のトークンのままSupabaseのRPC
`get_my_tier_level`(migration `20261006000000_add_get_my_tier_level.sql`)で引くので、
Workerはservice roleキーを持たない。必要なtierは `src/index.ts` の `PIPELINE_LOGS_MIN_TIER` で、
バックエンドの `plan_features.py`(`FEATURE_SOURCE_TRANSCRIPT_VIEW`)と揃える。
デプロイはmigrationをpushした後に行うこと(先にデプロイすると、RPCが無くて全員503になる)。

## 設定値について

- `wrangler.toml` の `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` / `JWKS_CACHE_TTL_SECONDS` は
  シークレットではないため直書き(publishable keyは公開前提の値)。
- R2バケットへのアクセスは `[[r2_buckets]]` のバインディングで完結し、
  アクセスキー等の資格情報は一切不要。
- JWT検証はSupabaseの公開鍵(JWKS)を使うため、こちらもシークレット不要
  (`wrangler secret put` は使っていない)。

## コード変更後の再デプロイ

`src/`配下を編集したら、再度 `npx wrangler deploy` するだけ。

## (将来的な検討事項)

- カスタムドメインを付けたい場合は、CloudflareのZoneにこのWorkerのRouteを追加する
  (現状は `*.workers.dev` のデフォルトURLのままで運用している)。
- CIなどから自動デプロイしたくなったら、そのときは
  「Workers Scripts: Edit」「Workers R2 Storage: Edit」に絞ったAPIトークンを
  新規発行し、`CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` として渡す。
