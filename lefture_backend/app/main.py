import os
import json
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from google.cloud import tasks_v2
from app.services.pipeline import run_lecture_pipeline

# FastAPI アプリケーションの初期化
app = FastAPI()

# ---------------------------------------------------------
# 環境変数の読み込み (Cloud Runの設定画面で入力する値)
# ---------------------------------------------------------
PROJECT_ID = os.getenv("GCP_PROJECT_ID")
REGION = os.getenv("GCP_REGION", "us-central1")
QUEUE_NAME = os.getenv("QUEUE_NAME", "lecture-processing-queue")

CLOUD_RUN_URL = os.getenv("CLOUD_RUN_URL") 

SERVICE_ACCOUNT_EMAIL = os.getenv("SERVICE_ACCOUNT_EMAIL")

client = tasks_v2.CloudTasksClient()


# ---------------------------------------------------------
# データモデル定義
# ---------------------------------------------------------
class WebhookPayload(BaseModel):
    type: str
    table: str
    record: dict
    schema: str
    old_record: dict | None = None

class WorkerPayload(BaseModel):
    job_id: str


# ---------------------------------------------------------
# エンドポイント定義
# ---------------------------------------------------------

@app.get("/")
def health_check():
    return {"status": "ok", "service": "leFture-backend"}

@app.post("/webhook/process-lecture", status_code=202)
async def trigger_processing(payload: WebhookPayload):
    """
    [表の顔: 受付窓口]
    Supabase からの Webhook を受け取り、Cloud Tasks に「行列」を作る。
    処理はせず、即座に 202 Accepted を返して課金を止める。
    """
    print(f"📩 Webhook received: {payload.type} on {payload.table}")

    if payload.type != "INSERT":
        return {"message": "Ignored (not INSERT)"}

    record = payload.record
    job_id = record.get("id")
    
    if not job_id:
        raise HTTPException(status_code=400, detail="Missing job id")

    # 環境変数チェック (設定漏れを防ぐため)
    if not (PROJECT_ID and CLOUD_RUN_URL and SERVICE_ACCOUNT_EMAIL):
        error_msg = "❌ Missing Environment Variables! Check GCP_PROJECT_ID, CLOUD_RUN_URL, SERVICE_ACCOUNT_EMAIL."
        print(error_msg)
        raise HTTPException(status_code=500, detail=error_msg)

    # 1. 親キューのパスを作成
    parent = client.queue_path(PROJECT_ID, REGION, QUEUE_NAME)

    # 2. Worker (裏口) に渡すデータ
    worker_payload = {"job_id": job_id}
    
    # 3. タスクの構成 (ここで Service Account を使って認証を通す)
    task = {
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": f"{CLOUD_RUN_URL}/worker/run-pipeline",  # 自分自身の裏口を叩く
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(worker_payload).encode(),
            "oidc_token": {
                "service_account_email": SERVICE_ACCOUNT_EMAIL,
                "audience": CLOUD_RUN_URL,
            }
        }
    }

    # 4. タスクをキューに追加 (Enqueue)
    try:
        response = client.create_task(request={"parent": parent, "task": task})
        print(f"✅ Task created: {response.name}")
    except Exception as e:
        print(f"❌ Failed to create task: {e}")
        # ここでエラーが出たら Supabase に再送してもらうために 500 を返す
        raise HTTPException(status_code=500, detail=f"Cloud Tasks Error: {e}")

    return {"message": "Job queued successfully", "job_id": job_id}


@app.post("/worker/run-pipeline")
async def worker_endpoint(payload: WorkerPayload):
    """
    [裏の顔: 実働部隊]
    Cloud Tasks から呼ばれる専用エンドポイント。
    ここで重い処理 (pipeline) を実行する。
    処理が終わるまでレスポンスを返さない = その間はずっと CPU が割り当てられる。
    """
    job_id = payload.job_id
    print(f"👷 Worker started processing Job ID: {job_id}")

    try:
        # パイプライン実行 (await で完了するまでここで待機！)
        await run_lecture_pipeline(job_id)
        
        print(f"✅ Worker finished Job ID: {job_id}")
        return {"status": "success"}
    
    except Exception as e:
        print(f"❌ Worker failed: {e}")
        # Cloud Tasks はエラー (500系) が返ると自動でリトライしてくれる設定がある。
        # 今回はパイプライン内で DB にエラー書き込み済みなので、
        # 無限リトライを防ぐためにあえて正常終了 (200) を返す手もあるが、
        # ここではログに残すために例外を投げる。
        raise HTTPException(status_code=500, detail=str(e))