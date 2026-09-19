# lefture-email-worker

Cloudflare Email Sending (`send_email` binding) を利用して、GCP (`lefture_backend`) や外部システムからのトランザクションメール送信を一元中継する専用 Worker です。

---

## 主な機能
- **安全な認証**: `Authorization: Bearer <EMAIL_WORKER_SECRET>` または `X-Internal-Secret` による事前共有鍵認証
- **Cloudflare Email Sending 統合**: Resend 等の外部SaaSを経由せず、Cloudflare内部ネットワークから直通配信
- **HTML/テキスト/添付ファイル対応**: リッチHTMLメール、プレーンテキスト、Base64添付ファイルのサポート
- **ヘルスチェック**: `GET /health` による稼働確認

---

## 前提条件
1. **Workers Paid プラン**:
   任意の宛先（未検証のメールアドレス）へ送信するため、Cloudflare アカウントが Workers Paid に加入している必要があります。
2. **送信元ドメインのオンボーディング**:
   Cloudflare ダッシュボードの **Compute (Workers & Pages)** > **Email Service** > **Email Sending** にて、送信元ドメイン（`lefture.com` 等）を登録・有効化（SPF/DKIM/DMARCが設定されている状態）してください。

---

## デプロイ手順

### 1. 依存関係のインストール
```bash
cd email_worker
npm install
```

### 2. シークレットキーの設定
Worker に認証用の共有秘密鍵（ランダムな安全な文字列）を設定します：
```bash
npx wrangler secret put EMAIL_WORKER_SECRET
# プロンプトで強力なパスワード/トークンを入力（例: openssl rand -hex 32）
```

### 3. デプロイ
```bash
npm run deploy
```
デプロイ後、発行されたURL（例: `https://lefture-email-worker.<subdomain>.workers.dev`）を確認します。

---

## API仕様

### `POST /send`
メールを送信します。

#### リクエストヘッダー
```http
Authorization: Bearer <EMAIL_WORKER_SECRET>
Content-Type: application/json
```

#### リクエストボディ
```json
{
  "to": "user@example.com",
  "subject": "【leFture】メールアドレスの確認",
  "html": "<h1>ご確認ありがとうございます</h1><p>...</p>",
  "text": "テキスト版本文（任意）",
  "from_name": "leFture",
  "from_address": "hello@lefture.com",
  "reply_to": "support@lefture.com"
}
```

#### レスポンス (200 OK)
```json
{
  "success": true,
  "message": "Email delivered successfully",
  "recipient": "user@example.com",
  "timestamp": "2026-09-18T10:00:00.000Z"
}
```
