import os
import time
import requests
from dotenv import load_dotenv

# 同一ディレクトリの .env ファイルをロードする
script_dir = os.path.dirname(os.path.abspath(__file__))
dotenv_path = os.path.join(script_dir, ".env")
if os.path.exists(dotenv_path):
    load_dotenv(dotenv_path)
else:
    load_dotenv()

API_URL = os.getenv("MODAL_API_URL")

# Modalの T4 GPU の1秒間あたりの単価 ($0.000164)
T4_PRICE_PER_SEC = 0.000164

def run_batch_test():
    if not API_URL:
        print("❌ エラー: 環境変数 'MODAL_API_URL' が設定されていません。")
        return

    # テスト用音声ファイルが配置されるフォルダ
    test_audio_dir = os.path.join(script_dir, "test_audio")
    
    if not os.path.exists(test_audio_dir):
        print(f"📁 フォルダを作成します: {test_audio_dir}")
        os.makedirs(test_audio_dir, exist_ok=True)
        print(f"ℹ️ このフォルダにテストしたい WAV ファイルを配置して、再度このスクリプトを実行してください。")
        return

    # test_audio フォルダ内の WAV ファイルを取得
    wav_files = sorted([f for f in os.listdir(test_audio_dir) if f.lower().endswith('.wav')])
    
    if not wav_files:
        print(f"📁 '{test_audio_dir}' 内に WAV ファイルが見つかりませんでした。")
        print("ℹ️ テストしたい WAV ファイルを配置してから再度実行してください。")
        return

    print(f"🎵 {len(wav_files)} 個 of WAV ファイルを順にテストします。")
    print(f"⏳ 各テストの間に 10 秒の間隔を挟みます。\n")

    results = []

    for i, filename in enumerate(wav_files):
        file_path = os.path.join(test_audio_dir, filename)
        print(f"[{i+1}/{len(wav_files)}] 🚀 送信中: {filename} ...")
        
        start_time = time.time()
        
        try:
            with open(file_path, "rb") as f:
                # WAV ファイルなので MIME タイプを audio/wav に設定
                files = {"file": (filename, f, "audio/wav")}
                response = requests.post(API_URL, files=files)
            
            end_time = time.time()
            
            if response.status_code == 200:
                res_data = response.json()
                total_duration = end_time - start_time
                gpu_duration = res_data.get("processing_time_seconds", 0.0)
                
                print(f"  ✅ 成功 | 全体時間: {total_duration:.2f}秒 | GPU計算時間: {gpu_duration:.2f}秒")
                
                results.append({
                    "filename": filename,
                    "total_duration": total_duration,
                    "gpu_duration": gpu_duration,
                    "status": "success"
                })
            else:
                print(f"  ❌ エラー | HTTPステータス: {response.status_code}")
                results.append({
                    "filename": filename,
                    "status": "failed",
                    "error": f"HTTP {response.status_code}"
                })
                
        except Exception as e:
            print(f"  ❌ 送信エラー: {e}")
            results.append({
                "filename": filename,
                "status": "error",
                "error": str(e)
            })

        # 最後のファイルでなければ、10秒待機
        if i < len(wav_files) - 1:
            print("⏳ 10秒間待機します...")
            time.sleep(10)
            print()

    # 成功した結果の抽出
    success_results = [r for r in results if r["status"] == "success"]
    
    print("\n" + "="*50)
    print("📊 連続テスト結果サマリー")
    print("="*50)
    print(f"総ファイル数: {len(wav_files)}")
    print(f"成功: {len(success_results)} / 失敗: {len(wav_files) - len(success_results)}")
    
    if not success_results:
        print("🚨 成功したテストがありませんでした。処理を終了します。")
        return

    # 平均値の計算
    avg_total_duration = sum(r["total_duration"] for r in success_results) / len(success_results)
    avg_gpu_duration = sum(r["gpu_duration"] for r in success_results) / len(success_results)
    
    # 料金計算 (コールドスタート等も含めた全体所要時間ベースで算出)
    total_total_duration = sum(r["total_duration"] for r in success_results)
    total_cost = total_total_duration * T4_PRICE_PER_SEC
    avg_cost = avg_total_duration * T4_PRICE_PER_SEC

    print(f"\n⏱️ 全体所要時間 (ネットワーク通信を含む):")
    print(f"  - 平均時間: {avg_total_duration:.2f} 秒")
    
    print(f"\n⚡ Modal内部 GPU計算時間:")
    print(f"  - 平均時間: {avg_gpu_duration:.2f} 秒")
    
    print(f"\n💰 料金計算 (T4 GPU単価: ${T4_PRICE_PER_SEC}/秒 - 全体所要時間ベース):")
    print(f"  - 平均料金: ${avg_cost:.6f} / 回")
    print(f"  - 合計料金: ${total_cost:.6f}")
    print("="*50)

if __name__ == "__main__":
    run_batch_test()
