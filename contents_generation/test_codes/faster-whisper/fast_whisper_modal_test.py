import requests
import time
import os
import json
from dotenv import load_dotenv

load_dotenv()
API_URL = os.getenv("MODAL_API_URL")

# ==========================================
# 1. 音声ファイルの準備
# ==========================================
audio_file_path = "lecture_audio.m4a"

print(f"📁 '{audio_file_path}' の存在を確認中...")

if not os.path.exists(audio_file_path):
    print(f"❌ エラー: '{audio_file_path}' が見つかりません。")
    exit()

# ==========================================
# 2. リクエスト送信 ＆ 時間計測
# ==========================================
print("🌐 Modal API に音声ファイルをPOST送信します...")
print("（※初回はコンテナが立ち上がるまで数秒〜十数秒かかります）")

start_time = time.time()

# FastAPIの `UploadFile` に合わせてファイルを multipart/form-data 形式で送信
with open(audio_file_path, "rb") as f:
    files = {"file": (os.path.basename(audio_file_path), f, "audio/mpeg")}
    response = requests.post(API_URL, files=files)

end_time = time.time()

# ==========================================
# 3. 結果発表
# ==========================================
if response.status_code == 200:
    result = response.json()
    print(f"\n🎉 通信成功！")
    print(f"⏱️ 通信を含めた全体所要時間: {end_time - start_time:.2f} 秒")
    print(f"⚡ API内部での純粋なGPU計算時間: {result.get('processing_time_seconds', 0)} 秒")
    print(f"🗣️ 検出言語: {result.get('language')} (確度: {result.get('language_probability')})")
    print("-" * 70)

    # 結果をJSONファイルとしても保存
    output_file_path = "transcript_result.json"
    with open(output_file_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
        
    print(f"💾 完璧です！トランスクリプトを '{output_file_path}' に保存しました！")
    
else:
    print(f"❌ エラー (ステータスコード: {response.status_code})")
    print(response.text)