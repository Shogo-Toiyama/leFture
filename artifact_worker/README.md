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
- 403: トークンのuidとパス先頭のuidが不一致
- 404: R2にそのオブジェクトが無い(まだ生成されていない等)

## 設定値について

- `wrangler.toml` の `SUPABASE_URL` / `JWKS_CACHE_TTL_SECONDS` はシークレットではないため直書き。
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
