# Cloudflare Whisper Client Test

Cloudflare Workers AI の Whisper API (`@cf/openai/whisper`) を呼び出し、受領したレスポンスの全内容（ステータスコード、ヘッダー、BodyのJSONなど）をターミナルに出力するテストプログラムです。

## セットアップ

1. 同ディレクトリ内の `.env` ファイルに Cloudflare の `CLOUDFLARE_ACCOUNT_ID` と `CLOUDFLARE_API_KEY` を設定してください。

```env
CLOUDFLARE_ACCOUNT_ID=your_account_id
CLOUDFLARE_API_KEY=your_api_key
```

2. 必要なライブラリをインストールします。

```bash
pip install requests python-dotenv
```

## 使い方

デフォルトのテスト音声（`../test_audio/chunk_025.wav`）で実行する場合:

```bash
python main.py
```

任意の音声ファイルを指定して実行する場合:

```bash
python main.py /path/to/your/audio.mp3
```

## 動作説明
- Cloudflare Workers AI の API に `Content-Type: application/octet-stream` で音声バイナリを送信します。
- レスポンス受領後、ステータスコード・レスポンスヘッダー・レスポンスBody (整形JSON) をすべてターミナルに表示します。
