import os
import sys
import json
import base64
import requests
from pathlib import Path
from dotenv import load_dotenv, find_dotenv

# カレントディレクトリまたは親ディレクトリの .env を探してロード
env_path = find_dotenv(usecwd=True)
if env_path:
    print(f"Loading environment variables from: {env_path}")
    load_dotenv(env_path)
else:
    load_dotenv()

ACCOUNT_ID = os.getenv("CLOUDFLARE_ACCOUNT_ID")
API_KEY = os.getenv("CLOUDFLARE_API_KEY")

# APIキーやアカウントIDの確認
if not ACCOUNT_ID or ACCOUNT_ID == "your_account_id_here":
    print("⚠️ WARNING: CLOUDFLARE_ACCOUNT_ID is not set properly in .env file.")
if not API_KEY or API_KEY == "your_api_key_here":
    print("⚠️ WARNING: CLOUDFLARE_API_KEY is not set properly in .env file.")

# 使用するWhisperモデル
# 本番(lefture_backend/app/services/logic/transcription.py)と同じモデルでないと
# レスポンス形式(言語フィールドの有無など)が違う可能性があるため合わせる。
MODEL = "@cf/openai/whisper-large-v3-turbo"

def transcribe_audio_cloudflare(audio_file_path: str):
    """
    Cloudflare Workers AI の Whisper API に音声ファイルを送信し、
    返ってきたレスポンス情報を全てターミナルに出力します。
    """
    path = Path(audio_file_path)
    if not path.exists():
        print(f"❌ Error: Audio file not found at '{audio_file_path}'")
        sys.exit(1)

    url = f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/{MODEL}"

    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }

    print(f"\n🚀 Sending request to Cloudflare Workers AI Whisper API...")
    print(f"URL: {url}")
    print(f"Audio File: {path.resolve()} ({path.stat().st_size} bytes)")

    with open(path, "rb") as f:
        audio_bytes = f.read()

    # 本番(TranscriptionService.run_in_memory)と同じく、JSON+Base64で送る。
    # languageキーを渡さない = 自動言語判定を試す。
    payload = {"audio": base64.b64encode(audio_bytes).decode("utf-8")}

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=60)
    except Exception as e:
        print(f"❌ HTTP Request failed: {e}")
        sys.exit(1)

    # レスポンスの全内容を出力
    print("\n" + "=" * 70)
    print("📥 FULL RESPONSE RECEIVED FROM CLOUDFLARE WHISPER API")
    print("=" * 70)
    print(f"Status Code : {response.status_code} {response.reason}")
    print("\n--- Response Headers ---")
    for key, val in response.headers.items():
        print(f"{key}: {val}")

    print("\n--- Response Body ---")
    try:
        json_data = response.json()
        print(json.dumps(json_data, indent=2, ensure_ascii=False))
    except json.JSONDecodeError:
        print("(Non-JSON Response)")
        print(response.text)
    print("=" * 70 + "\n")

if __name__ == "__main__":
    # コマンドライン引数から音声パスを受け取るか、デフォルトのテスト音声を使用
    if len(sys.argv) > 1:
        target_audio = sys.argv[1]
    else:
        # デフォルトのテスト音声を探索
        script_dir = Path(__file__).parent
        default_test_audio = script_dir.parent / "test_audio" / "chunk_025.wav"
        if default_test_audio.exists():
            target_audio = str(default_test_audio)
        else:
            target_audio = "sample.wav"

    transcribe_audio_cloudflare(target_audio)
