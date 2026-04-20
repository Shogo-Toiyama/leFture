import requests
import time
import os
from dotenv import load_dotenv

load_dotenv()
API_URL = os.getenv("MODAL_API_URL")

if not API_URL:
    print("❌ エラー: .env ファイルに 'MODAL_API_URL' が設定されていません。")
    exit()

# ==========================================
# 1. API用のペイロードを組み立てる
# ==========================================
payload = {
    "text": "Shall I compare thee to a summer’s day? Thou art more lovely and more temperate: Rough winds do shake the darling buds of May, And summer’s lease hath all too short a date; Sometime too hot the eye of heaven shines, And often is his gold complexion dimm’d; And every fair from fair sometime declines, By chance or nature’s changing course untrimm’d; But thy eternal summer shall not fade, Nor lose possession of that fair thou ow’st; Nor shall death brag thou wander’st in his shade, When in eternal lines to time thou grow’st: So long as men can breathe or eyes can see, So long lives this, and this gives life to thee Naturally, our list had to start with the Bard. While it is tough to pick a favorite work of William Shakespeare, “Sonnet 18” is definitely a top contender. Not only is it one of the most famous poems ever written, but it’s also one of his most beautiful and iconic love poems. Want to express deep affection? Forget those funny roses-are-red poems and start with one of the English language’s literary giants.",
    "voice": "af_heart",
    "speed": 1.0,
    "lang": "en-us"
}

print("🌐 Modal API に音声生成リクエストをPOST送信します...")
print(f"📝 生成するテキスト: '{payload['text'][:50]}...'")

# ==========================================
# 2. リクエスト送信 ＆ 時間計測
# ==========================================
start_time = time.time()

try:
    response = requests.post(API_URL, json=payload)
except Exception as e:
    print(f"❌ 通信エラーが発生しました: {e}")
    exit()

end_time = time.time()

# ==========================================
# 3. 結果発表
# ==========================================
if response.status_code == 200:
    print(f"\n🎉 通信成功！")
    
    # Modalバックエンドから返されたヘッダー情報の取得（X-Processing-Time）
    server_time = response.headers.get("X-Processing-Time", "0")
    
    print(f"⏱️ 通信を含めた全体所要時間: {end_time - start_time:.2f} 秒")
    print(f"⚡ API内部での純粋な計算時間: {server_time} 秒")
    print("-" * 70)

    output_file_path = "output_audio.wav"
    
    # バイナリデータをWAVとして保存
    with open(output_file_path, "wb") as f:
        f.write(response.content)
        
    print(f"💾 完璧です！生成された音声を '{output_file_path}' に保存しました！")
    
else:
    print(f"❌ エラー (ステータスコード: {response.status_code})")
    print(response.text)