import os
import sys
import json
from dotenv import load_dotenv
from supabase import create_client

# .env ファイルがあればロードする
load_dotenv()

# ==========================================
# ⚙️ 設定 (必要に応じて書き換えてください)
# ==========================================
# ここに必要なIDとチャンク数を設定します。
# 実行時に引数として渡すこともできます: 
#   python trigger_analysis.py <lecture_id> <owner_id> <expected_chunks>
LECTURE_ID = "3017abbd-af51-4a51-82d8-d81344fd02e7"
OWNER_ID = "651540df-c3d3-4438-b400-13037f13bb5c" # テスト用オーナーID（通常はユーザーのUUID）
EXPECTED_CHUNKS = 163

# 引数がある場合はそちらを優先する
if len(sys.argv) >= 4:
    LECTURE_ID = sys.argv[1]
    OWNER_ID = sys.argv[2]
    EXPECTED_CHUNKS = int(sys.argv[3])

# ==========================================
# 🔑 環境変数の取得
# ==========================================
# ローカルの環境変数または .env ファイルから取得します
SUPABASE_URL = os.environ.get("SUPABASE_URL")
# セキュリティ確保のため、SERVICE_ROLE_KEY を使用します (RLSをバイパスするため)
SUPABASE_SECRET_KEY = os.environ.get("SUPABASE_SECRET_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_SECRET_KEY:
    print("❌ エラー: SUPABASE_URL または SUPABASE_SECRET_KEY (SUPABASE_SERVICE_ROLE_KEY) が環境変数に見つかりません。")
    print("環境変数に設定するか、カレントディレクトリに .env ファイルを作成して設定してください。")
    sys.exit(1)

print(f"🔗 Supabase接続中: {SUPABASE_URL}")
supabase = create_client(SUPABASE_URL, SUPABASE_SECRET_KEY)

# ==========================================
# 🚀 ジョブの登録とDAG（タスク）の直接挿入
# ==========================================
try:
    print(f"📝 1. 親ジョブを作成中 (lecture_id: {LECTURE_ID}, chunks: {EXPECTED_CHUNKS})...")
    job_data = {
        "lecture_id": LECTURE_ID,
        "owner_id": OWNER_ID,
        "expected_chunks": EXPECTED_CHUNKS,
        "status": "PENDING"
    }
    job_res = supabase.table("processing_jobs").insert(job_data).execute()
    
    if not job_res.data:
        print("❌ エラー: ジョブの登録に失敗しました（データが返されませんでした）。")
        sys.exit(1)
        
    job_id = job_res.data[0]["id"]
    print(f"✅ 親ジョブを作成しました。Job ID: {job_id}")

    # タスクの設計図（DAG）の定義
    tasks_blueprint = [
        {"task_type": "CHECK_AND_ASSEMBLE", "dependencies": []},
        {"task_type": "CORE_EXTRACTION", "dependencies": ["CHECK_AND_ASSEMBLE"]},
        {"task_type": "ROLE_CLASSIFICATION", "dependencies": ["CORE_EXTRACTION"]},
        {"task_type": "ANNOUNCEMENT_GENERATION", "dependencies": ["ROLE_CLASSIFICATION"]},
        {"task_type": "TOPIC_MAPPING", "dependencies": ["ROLE_CLASSIFICATION"]},
        {"task_type": "REVIEW_CARD_GENERATION", "dependencies": ["TOPIC_MAPPING"]},
        {"task_type": "IMAGE_PROMPT_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION"]},
        {"task_type": "IMAGE_RENDERING", "dependencies": ["IMAGE_PROMPT_GENERATION"]},
        {"task_type": "FUN_FACT_SEARCH", "dependencies": ["CORE_EXTRACTION"]},
        {"task_type": "FUN_FACTS_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION", "FUN_FACT_SEARCH"]},
        {"task_type": "DETAIL_CONTENTS_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION"]},
        {"task_type": "FINALIZE_JOB", "dependencies": [
            "ANNOUNCEMENT_GENERATION", 
            "IMAGE_RENDERING", 
            "FUN_FACTS_GENERATION", 
            "DETAIL_CONTENTS_GENERATION"
        ]}
    ]

    print("📝 2. 子タスクを一括登録中 (processing_tasks)...")
    insert_data = [
        {
            "job_id": job_id,
            "task_type": t["task_type"],
            "dependencies": json.dumps(t["dependencies"]),
            "status": "PENDING"
        }
        for t in tasks_blueprint
    ]
    supabase.table("processing_tasks").insert(insert_data).execute()
    print("✅ 全てのタスクを登録しました！")
    print(f"\n🎉 手動登録が成功しました。SupabaseのWebhook経由でバックエンドの分析が動き出します。")
    print(f"👉 追跡用 Job ID: {job_id}")

except Exception as e:
    print(f"❌ 登録中にエラーが発生しました: {e}")
    sys.exit(1)
