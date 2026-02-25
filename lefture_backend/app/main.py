import os
import json
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, BackgroundTasks
from nltk.tokenize import sent_tokenize
from pydantic import BaseModel
from google.cloud import tasks_v2
from app.services.task_runners import (
    run_transcribe_chunk_worker,
    run_check_and_assemble_transcript_task,
    run_role_classification_task,
    run_core_extraction_task,
    run_announcement_generation_task,
    run_topic_mapping_task,
    run_review_card_task,
    run_fun_facts_task,
    run_detail_contents_task,
    run_image_generation_task
)

# ---------------------------------------------------------
# FastAPI アプリケーションの初期化
# ---------------------------------------------------------
app = FastAPI(title="leFture Backend Worker", version="2.0.0")

# ---------------------------------------------------------
# 環境変数の読み込み
# ---------------------------------------------------------
PROJECT_ID = os.getenv("GCP_PROJECT_ID")
REGION = os.getenv("GCP_REGION", "us-central1")
QUEUE_NAME = os.getenv("QUEUE_NAME", "lecture-analyzing-queue")
CLOUD_RUN_URL = os.getenv("CLOUD_RUN_URL") 
SERVICE_ACCOUNT_EMAIL = os.getenv("SERVICE_ACCOUNT_EMAIL")

# Cloud Tasks クライアント (グローバルで1つ持っておく)
client = tasks_v2.CloudTasksClient()

# ---------------------------------------------------------
# データモデル定義
# ---------------------------------------------------------
class EnqueuePayload(BaseModel):
    """指揮者 (Orchestrator) から送られてくる依頼データ"""
    job_id: str
    task_id: str
    task_type: str

class WorkerPayload(BaseModel):
    """Cloud Tasks から各ワーカー (職人) に渡されるデータ"""
    job_id: str
    task_id: str

# ---------------------------------------------------------
# 【変更】リアルタイム・トランスクライブ受付（ダイレクトPOST）
# ---------------------------------------------------------
@app.post("/worker/transcribe-chunk")
async def worker_transcribe_chunk(
    background_tasks: BackgroundTasks, # ← これが即時レスポンスの魔法
    lecture_id: str = Form(...),       # ← Flutterから送られるメタデータ
    chunk_index: int = Form(...),      # ← Flutterから送られるメタデータ
    file: UploadFile = File(...)       # ← WAVファイル本体
):
    """
    FlutterからWAVファイルを直接受け取るエンドポイント。
    ダウンロード待ち時間をゼロにし、即座に200を返して裏で処理を回す。
    """
    if not file:
        raise HTTPException(status_code=400, detail="No audio file provided")

    # 1. WAVファイルをメモリ上(bytes)に直接読み込む（ディスクに保存しないため爆速）
    audio_bytes = await file.read()
    
    # 2. バックグラウンドタスクとして職人を走らせる
    # こうすることで、このHTTPリクエスト自体は次の行の return で瞬時に終了し、Flutterを待たせない
    background_tasks.add_task(
        run_transcribe_chunk_worker, # ← 今までの職人関数
        lecture_id=lecture_id,
        chunk_index=chunk_index,
        audio_bytes=audio_bytes
    )
    
    # 3. Flutterには即座に成功を返す
    return {"status": "success", "message": f"Chunk {chunk_index} received."}

# ---------------------------------------------------------
# 🗺️ タスクの種類と、呼び出す裏口 (URL) のマッピング辞書
# ---------------------------------------------------------
TASK_ROUTES = {
    "CHECK_AND_ASSEMBLE": "/worker/check-and-assemble",
    "ROLE_CLASSIFICATION": "/worker/role-classification",
    "CORE_EXTRACTION": "/worker/core-extraction",
    "ANNOUNCEMENT_GENERATION": "/worker/announcement-generation",
    "TOPIC_MAPPING": "/worker/topic-mapping",
    "REVIEW_CARD": "/worker/review-card",
    "FUN_FACTS": "/worker/fun-facts",
    "DETAIL_CONTENTS": "/worker/detail-contents",
    "IMAGE_GENERATION": "/worker/image-generation"
}

# ---------------------------------------------------------
# 1. 【表の顔: 受付窓口】指揮者からの依頼を受ける
# ---------------------------------------------------------
@app.post("/enqueue-task", status_code=202)
async def enqueue_task(payload: EnqueuePayload):
    """
    指揮者(Edge Function)から呼ばれ、Cloud Tasksにジョブを登録する。
    処理はCloud Tasksに任せて、即座に202 Acceptedを返す。
    """
    print(f"📩 Orchestrator requested to enqueue: {payload.task_type} (Task ID: {payload.task_id})")

    # 環境変数のチェック
    if not (PROJECT_ID and CLOUD_RUN_URL and SERVICE_ACCOUNT_EMAIL):
        error_msg = "❌ Missing Environment Variables!"
        print(error_msg)
        raise HTTPException(status_code=500, detail=error_msg)

    # タスクの種類に対応する裏口(URLパス)があるかチェック
    route_path = TASK_ROUTES.get(payload.task_type)
    if not route_path:
        raise HTTPException(status_code=400, detail=f"Unknown task_type: {payload.task_type}")

    # 1. 親キューのパスを作成
    parent = client.queue_path(PROJECT_ID, REGION, QUEUE_NAME)

    # 2. ワーカー (職人) に渡すデータ (job_id と task_id の両方が必須！)
    worker_payload = {
        "job_id": payload.job_id,
        "task_id": payload.task_id
    }
    
    # 3. Cloud Tasksのジョブ構成
    task = {
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": f"{CLOUD_RUN_URL}{route_path}",  # 割り出された専用の裏口を叩く！
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(worker_payload).encode(),
            "oidc_token": {
                "service_account_email": SERVICE_ACCOUNT_EMAIL,
                "audience": CLOUD_RUN_URL,
            }
        }
    }

    # 4. キューに追加 (Enqueue)
    try:
        response = client.create_task(request={"parent": parent, "task": task})
        print(f"✅ Enqueued {payload.task_type} to Cloud Tasks: {response.name}")
    except Exception as e:
        print(f"❌ Failed to enqueue task: {e}")
        raise HTTPException(status_code=500, detail=f"Cloud Tasks Error: {e}")

    return {"message": "Task queued successfully", "task_id": payload.task_id}


# ---------------------------------------------------------
# 2. 【裏の顔: 職人たちの部屋】Cloud Tasks から呼ばれる専用エンドポイント
# ---------------------------------------------------------

@app.post("/worker/check-and-assemble")
async def worker_check_and_assemble(payload: WorkerPayload):
    await run_check_and_assemble_transcript_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/role-classification")
async def worker_role_classification(payload: WorkerPayload):
    await run_role_classification_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/core-extraction")
async def worker_core_extraction(payload: WorkerPayload):
    await run_core_extraction_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/announcement-generation")
async def worker_announcement_generation(payload: WorkerPayload):
    await run_announcement_generation_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/topic-mapping")
async def worker_topic_mapping(payload: WorkerPayload):
    await run_topic_mapping_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/review-card")
async def worker_review_card(payload: WorkerPayload):
    await run_review_card_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/fun-facts")
async def worker_fun_facts(payload: WorkerPayload):
    await run_fun_facts_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/detail-contents")
async def worker_detail_contents(payload: WorkerPayload):
    await run_detail_contents_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/image-generation")
async def worker_image_generation(payload: WorkerPayload):
    await run_image_generation_task(payload.job_id, payload.task_id)
    return {"status": "success"}