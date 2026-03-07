import requests
import time
import json
import os
from dotenv import load_dotenv

load_dotenv()
API_URL = os.getenv("MODAL_API_URL")

# ==========================================
# 1. JSONファイルから全文章を読み込む
# ==========================================
json_file_path = "transcript_data.json"
print(f"📁 '{json_file_path}' からデータを読み込んでいます...")

try:
    with open(json_file_path, "r", encoding="utf-8") as f:
        transcript_data = json.load(f)
    print(f"✅ 合計 {len(transcript_data)} 文を読み込みました！\n")
except FileNotFoundError:
    print(f"❌ エラー: '{json_file_path}' が見つかりません。パスを確認してください。")
    exit()

# ==========================================
# 2. API用のペイロードを組み立てる
# ==========================================
payload = {
    "transcript_data": transcript_data,
    "theme": "Computer System Architecture",
    "batch_size": 32  # GPUなので32で全く問題なし！
}

print("🌐 Modal API にフルデータをPOST送信します...")

# ==========================================
# 3. リクエスト送信 ＆ 時間計測
# ==========================================
start_time = time.time()
response = requests.post(API_URL, json=payload)
end_time = time.time()

# ==========================================
# 4. 結果発表
# ==========================================
if response.status_code == 200:
    result = response.json()
    print(f"🎉 通信成功！")
    print(f"⏱️ 通信を含めた全体所要時間: {end_time - start_time:.2f} 秒")
    print(f"⚡ API内部での純粋なGPU計算時間: {result.get('processing_time_seconds', 0):.2f} 秒")
    print(f"📊 処理完了した文章数: {result.get('count', 0)} 文")
    print("-" * 70)

    returned_data = result.get("transcript_data", [])
    output_file_path = "transcript_with_role.json"
    
    with open(output_file_path, "w", encoding="utf-8") as f:
        json.dump(returned_data, f, ensure_ascii=False, indent=2)
        
    print(f"💾 完璧です！すべてのデータに 'role' を付与して '{output_file_path}' に保存しました！")
    
else:
    print(f"❌ エラー (ステータスコード: {response.status_code})")
    print(response.text)