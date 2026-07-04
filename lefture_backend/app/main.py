import os
import json
import time
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from fastapi import FastAPI, HTTPException, UploadFile, Request, File, Form, Header
from supabase import create_client, ClientOptions
from nltk.tokenize import sent_tokenize
from pydantic import BaseModel
from google.cloud import tasks_v2
from google.api_core.exceptions import AlreadyExists

# Cloud Tasksのタスク名は決定的にするが、task_id/chunk単体だけをキーにすると
# CHECK_AND_ASSEMBLEの「チャンクが揃うまでPENDINGに戻って自己リトライする」といった
# 正当な再試行までCloud Tasksの名前重複チェックでブロックされてしまう
# （同名タスクは完了後 約1時間 再利用できないため）。
# そのため短い時間バケットをキーに含め、「ごく短時間の重複投入だけ」を弾く。
TASK_DEDUP_WINDOW_SECONDS = 30

def _dedup_bucket() -> int:
    return int(time.time() // TASK_DEDUP_WINDOW_SECONDS)

from app.core.supabase import get_supabase_client
from app.services.task_runners import (
    receive_transcribe_chunk,
    process_transcribe_chunk,
    run_check_and_assemble_transcript_task,
    run_role_classification_task,
    run_core_extraction_task,
    run_announcement_generation_task,
    run_topic_mapping_task,
    run_review_card_task,
    run_fun_fact_search_task,
    run_fun_facts_task,
    run_detail_contents_task,
    run_image_prompt_generation_task,
    run_image_rendering_task,
    run_finalize_job_task
)

# ---------------------------------------------------------
# FastAPI アプリケーションの初期化
# ---------------------------------------------------------
app = FastAPI(title="leFture Backend Worker", version="2.0.0")

# 同期I/O（Supabase/boto3/requests/Cloud Tasksクライアント）をasyncio.to_threadで
# 逃がすためのスレッドプールを明示サイジング。デフォルト(min(32, cpu+4))だと
# 100人同時利用のような高負荷時にスレッド待ちで詰まるため。
@app.on_event("startup")
async def _configure_thread_pool():
    loop = asyncio.get_event_loop()
    loop.set_default_executor(ThreadPoolExecutor(max_workers=64))

# ---------------------------------------------------------
# 環境変数の読み込み
# ---------------------------------------------------------
PROJECT_ID = os.getenv("GCP_PROJECT_ID")
REGION = os.getenv("GCP_REGION", "us-west1")
QUEUE_NAME = os.getenv("QUEUE_NAME", "lefture-processing-queue")
CHUNK_QUEUE_NAME = os.getenv("CHUNK_QUEUE_NAME", "lefture-chunk-queue")
CLOUD_RUN_URL = os.getenv("CLOUD_RUN_URL")
SERVICE_ACCOUNT_EMAIL = os.getenv("SERVICE_ACCOUNT_EMAIL")
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_PUBLISHABLE_KEY = os.getenv("SUPABASE_PUBLISHABLE_KEY")
WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET") # 追加: Supabase Webhookからのリクエストを検証するシークレット
STALE_TASK_TIMEOUT_MINUTES = int(os.getenv("STALE_TASK_TIMEOUT_MINUTES", "20")) # Cloud Scheduler駆動のリカバリが「止まっている」と判定するまでの分数

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

class StartAnalysisRequest(BaseModel):
    lecture_id: str
    expected_chunks: int

class TranscribeChunkPayload(BaseModel):
    """Cloud Tasks から /worker/transcribe-chunk-process に渡されるデータ"""
    lecture_id: str
    chunk_index: int
    start_time: float
    whisper_context: str = ""
    r2_audio_path: str
    uid: str

class MasterAudioUploadUrlRequest(BaseModel):
    lecture_id: str

class MasterAudioUploadCompleteRequest(BaseModel):
    lecture_id: str

# ---------------------------------------------------------
# 分析開始 (start_analysis)
# ---------------------------------------------------------
@app.post("/start-analysis")
async def start_analysis(payload: StartAnalysisRequest, request: Request):
    print(f"🚀 Start Analysis called for Lecture: {payload.lecture_id}, Chunks: {payload.expected_chunks}")

    # 1. Flutterから送られてきたJWTトークンを取得
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    
    token = auth_header.replace("Bearer ", "").strip()

    # 2. ユーザーの権限でSupabaseクライアントを作成 (RLS突破)
    user_client = create_client(
        SUPABASE_URL, 
        SUPABASE_PUBLISHABLE_KEY, 
        options=ClientOptions(headers={"Authorization": f"Bearer {token}"})
    )

    # 3. トークンからユーザー情報を取得
    user_res = user_client.auth.get_user(token)
    if not user_res or not user_res.user:
        raise HTTPException(status_code=401, detail="Unauthorized user")
    
    user_id = user_res.user.id

    # 管理者クライアントを取得 (RLSをバイパスして安全に書き込むため)
    admin_client = get_supabase_client()

    # 4. 親ジョブを作成 (processing_jobs)
    job_data = {
      "lecture_id": payload.lecture_id,
      "user_id": user_id,
      "expected_chunks": payload.expected_chunks,
      "status": "PENDING"
    }
    job_res = admin_client.table("processing_jobs").insert(job_data).execute()
    job_id = job_res.data[0]["id"]

    # 5. タスクの設計図（DAG）を定義
    tasks_blueprint = [
        # Phase 1: 基礎データの準備
        {"task_type": "CHECK_AND_ASSEMBLE", "dependencies": []},
        
        # Phase 2: 全体俯瞰とトピック分割
        {"task_type": "CORE_EXTRACTION", "dependencies": ["CHECK_AND_ASSEMBLE"]},
        
        # Phase 3: 細かな役割分類
        {"task_type": "ROLE_CLASSIFICATION", "dependencies": ["CORE_EXTRACTION"]},

        # Phase 4: 抽出データの整理
        {"task_type": "ANNOUNCEMENT_GENERATION", "dependencies": ["ROLE_CLASSIFICATION"]},
        {"task_type": "TOPIC_MAPPING", "dependencies": ["ROLE_CLASSIFICATION"]},

        # Phase 5: コンテンツ生成 
        {"task_type": "REVIEW_CARD_GENERATION", "dependencies": ["TOPIC_MAPPING"]},

        # Phase 6-A: 画像生成 (プロンプト作成 -> レンダリングの2段階)
        {"task_type": "IMAGE_PROMPT_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION"]},
        {"task_type": "IMAGE_RENDERING", "dependencies": ["IMAGE_PROMPT_GENERATION"]},

        # Phase 6-B: Fun Fact (検索 -> 生成の2段階)
        {"task_type": "FUN_FACT_SEARCH", "dependencies": ["CORE_EXTRACTION"]}, # 検索ワードだけあれば走れる
        {"task_type": "FUN_FACTS_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION", "FUN_FACT_SEARCH"]}, # レビューカードと検索結果の両方を待つ
        
        # Phase 6-C: Detail Contents
        {"task_type": "DETAIL_CONTENTS_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION"]},
        
        # Phase 7: 最後の集計係 (主要な成果物が全て出揃うのを待つ)
        {"task_type": "FINALIZE_JOB", "dependencies": [
            "ANNOUNCEMENT_GENERATION", 
            "IMAGE_RENDERING", 
            "FUN_FACTS_GENERATION", 
            "DETAIL_CONTENTS_GENERATION"
        ]}
    ]

    # 6. DBに挿入しやすい形に整形
    insert_data = [
        {
            "job_id": job_id,
            "task_type": t["task_type"],
            "dependencies": json.dumps(t["dependencies"]), # JSON文字列化
            "status": "PENDING"
        }
        for t in tasks_blueprint
    ]

    # 7. 子タスクを一気に登録 (processing_tasks)
    admin_client.table("processing_tasks").insert(insert_data).execute()

    # 大成功！
    return {"message": "Analysis started successfully", "job_id": job_id}

# ---------------------------------------------------------
# 司令塔 (orchestrator)
# ---------------------------------------------------------
@app.post("/webhook/orchestrator")
async def orchestrator_webhook(request: Request, x_webhook_secret: str = Header(None)):
    # 0. セキュリティチェック: SupabaseのWebhookからのリクエストか検証
    if WEBHOOK_SECRET and x_webhook_secret != WEBHOOK_SECRET:
        print("🔒 Unauthorized webhook attempt blocked.")
        raise HTTPException(status_code=401, detail="Unauthorized webhook")

    payload = await request.json()
    event_type = payload.get("type")
    record = payload.get("record", {})
    old_record = payload.get("old_record", {})

    # 1. 反応すべきイベントかチェック
    is_new = (event_type == "INSERT" and record.get("status") == "PENDING")
    is_newly_completed = (event_type == "UPDATE" and record.get("status") == "COMPLETED" and old_record.get("status") != "COMPLETED")
    is_manually_retried = (event_type == "UPDATE" and record.get("status") == "PENDING" and old_record.get("status") != "PENDING")

    if not (is_new or is_newly_completed or is_manually_retried):
        return {"message": "Not a triggerable state. Ignoring."}

    print(f"🎼 Orchestrator waking up! Triggered by Task: {record.get('task_type')} ({event_type})")

    # 2. Service Role Key を持った管理者クライアントを取得
    # （Webhookはシステムとして動くためRLSをバイパスする必要がある）
    admin_client = get_supabase_client()
    job_id = record.get("job_id")

    # 3. このジョブに紐づく「すべてのタスク」の最新状態を取得
    res = admin_client.table("processing_tasks").select("*").eq("job_id", job_id).execute()
    all_tasks = res.data

    # すでに完了しているタスクのリスト
    completed_types = [t["task_type"] for t in all_tasks if t["status"] == "COMPLETED"]

    # 4. DAG（依存関係）の評価：次に実行できるタスクを探す！
    ready_tasks = []
    for t in all_tasks:
        if t["status"] != "PENDING":
            continue
        
        # 依存関係（JSON文字列になっている可能性を考慮）をリストにする
        deps_data = t.get("dependencies", [])
        deps = json.loads(deps_data) if isinstance(deps_data, str) else deps_data
        
        # 依存しているタスクが「すべて」completed_typesに含まれていれば実行可能！
        if all(dep in completed_types for dep in deps):
            ready_tasks.append(t)

    if not ready_tasks:
        print("⏸️ No ready tasks found at this moment.")
        return {"message": "No ready tasks"}

    print(f"🚀 Found {len(ready_tasks)} ready task(s): {[t['task_type'] for t in ready_tasks]}")

    # 5. 実行可能なタスクを処理
    for task in ready_tasks:
        # 5-1. 二重起動を防ぐため、DBのステータスを 'QUEUED' に更新する
        # updated_at も明示的に更新しておく（reap-stale-tasksがこの時刻を基準に
        # 「QUEUEDのままenqueueに失敗して止まっているタスク」を検出するため）
        update_res = admin_client.table("processing_tasks")\
            .update({"status": "QUEUED", "updated_at": datetime.now().isoformat()})\
            .eq("id", task["id"])\
            .eq("status", "PENDING")\
            .execute()
        
        if not update_res.data:
            print(f"⚠️ Failed to update task {task['task_type']} to QUEUED (might be already processing)")
            continue

        # 5-2. 💡【重要な変更】HTTP通信を使わず、直接同じファイル内の `enqueue_task` 関数を呼び出す！
        # これによりオーバーヘッドゼロでCloud Tasksにキューイングされます。
        try:
            await enqueue_task(EnqueuePayload(
                job_id=job_id,
                task_id=task["id"],
                task_type=task["task_type"]
            ))
        except Exception as e:
            print(f"❌ Error directly enqueueing task {task['task_type']}: {e}")

    return {"message": "Orchestration successful"}

# ---------------------------------------------------------
# リアルタイム・トランスクライブ受付（ダイレクトPOST）
# ---------------------------------------------------------
@app.post("/worker/transcribe-chunk")
async def worker_transcribe_chunk(
    lecture_id: str = Form(...),
    start_time: float = Form(...),
    chunk_index: int = Form(...),
    whisper_context: str = Form(""),
    file: UploadFile = File(...)
):
    """
    FlutterからM4A(AAC)ファイルを受け取り、R2への保存とCloud Tasksへのenqueueだけ
    行って即座に返す（受付窓口）。実際の文字起こしは /worker/transcribe-chunk-process
    が非同期に行うため、Cloudflare Whisper側がハングしてもこのリクエスト自体は
    詰まらない。
    """
    if not file:
        raise HTTPException(status_code=400, detail="No audio file provided")

    # 1. M4Aファイルをメモリ上(bytes)に直接読み込む
    audio_bytes = await file.read()

    # 2. R2への保存とCloud Tasksへのenqueueだけ行い、即座に返す
    await receive_transcribe_chunk(
        lecture_id=lecture_id,
        start_time=start_time,
        chunk_index=chunk_index,
        audio_bytes=audio_bytes,
        whisper_context=whisper_context,
    )

    return {"status": "success", "message": f"Chunk {chunk_index} received and queued for transcription."}

# ---------------------------------------------------------
# リアルタイム・トランスクライブ処理（Cloud Tasksから呼ばれる非同期ワーカー）
# ---------------------------------------------------------
@app.post("/worker/transcribe-chunk-process")
async def worker_transcribe_chunk_process(payload: TranscribeChunkPayload):
    """
    /worker/transcribe-chunk がenqueueしたタスクを実際に処理する。
    Cloudflare Whisperの呼び出し等が失敗した場合は例外をそのまま伝播させ、
    非2xxを返すことでCloud Tasksの自動リトライに任せる（他の /worker/* と同じ規約）。
    """
    await process_transcribe_chunk(
        lecture_id=payload.lecture_id,
        chunk_index=payload.chunk_index,
        start_time=payload.start_time,
        whisper_context=payload.whisper_context,
        r2_audio_path=payload.r2_audio_path,
        uid=payload.uid,
    )
    return {"status": "success", "message": f"Chunk {payload.chunk_index} fully processed."}

# ---------------------------------------------------------
# 🎥 マスターオーディオ(全体音源)のアップロード受付
# ---------------------------------------------------------
# Cloud Runのリクエストボディには32MBのハード上限があり、64kbpsのマスター音声でも
# 約70分の録音で超えてしまう（60〜90分超の講義は普通にあるため構造的な問題）。
# そのためCloud Runを経由させず、R2への署名付きURLをFlutterに発行し、
# クライアントから直接R2へPUTしてもらう方式にする。
MASTER_AUDIO_CONTENT_TYPE = "audio/x-m4a"


@app.post("/worker/request-master-audio-upload-url")
async def worker_request_master_audio_upload_url(payload: MasterAudioUploadUrlRequest):
    """マスター音声をR2へ直接PUTするための署名付きURLを発行する。"""
    supabase = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: supabase.table("lectures").select("user_id").eq("id", payload.lecture_id).single().execute()
    )
    if not res.data:
        raise HTTPException(status_code=404, detail=f"Lecture {payload.lecture_id} not found")
    uid = res.data["user_id"]

    from app.services.task_runners import storage_service
    upload_url, storage_path = await asyncio.to_thread(
        storage_service.generate_presigned_put_url,
        uid=uid,
        lecture_id=payload.lecture_id,
        file_name="master_audio.m4a",
        content_type=MASTER_AUDIO_CONTENT_TYPE,
    )

    return {"upload_url": upload_url, "storage_path": storage_path}


@app.post("/worker/complete-master-audio-upload")
async def worker_complete_master_audio_upload(payload: MasterAudioUploadCompleteRequest):
    """
    Flutterが直接R2へのPUTを終えた後に呼ぶ。クライアントの自己申告を鵜呑みにせず、
    実際にR2上にファイルが存在することを確認してからaudio_pathを更新する。
    """
    supabase = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: supabase.table("lectures").select("user_id").eq("id", payload.lecture_id).single().execute()
    )
    if not res.data:
        raise HTTPException(status_code=404, detail=f"Lecture {payload.lecture_id} not found")
    uid = res.data["user_id"]

    from app.services.task_runners import storage_service
    storage_path = f"{uid}/{payload.lecture_id}/master_audio.m4a"

    exists = await asyncio.to_thread(storage_service.object_exists, storage_path)
    if not exists:
        raise HTTPException(status_code=400, detail="Uploaded file not found in storage yet")

    await asyncio.to_thread(
        lambda: supabase.table("lectures").update({
            "audio_path": storage_path,
            "updated_at": datetime.now().isoformat()
        }).eq("id", payload.lecture_id).execute()
    )

    return {"status": "success", "message": f"Master audio path recorded: {storage_path}"}

# ---------------------------------------------------------
# 🗺️ タスクの種類と、呼び出す裏口 (URL) のマッピング辞書
# ---------------------------------------------------------
TASK_ROUTES = {
    "CHECK_AND_ASSEMBLE": "/worker/check-and-assemble",
    "ROLE_CLASSIFICATION": "/worker/role-classification",
    "CORE_EXTRACTION": "/worker/core-extraction",
    "ANNOUNCEMENT_GENERATION": "/worker/announcement-generation",
    "TOPIC_MAPPING": "/worker/topic-mapping",
    "REVIEW_CARD_GENERATION": "/worker/review-card",
    "IMAGE_PROMPT_GENERATION": "/worker/image-prompt-generation",
    "IMAGE_RENDERING": "/worker/image-rendering",
    "FUN_FACT_SEARCH": "/worker/fun-fact-search",
    "FUN_FACTS_GENERATION": "/worker/fun-facts-generation",
    "DETAIL_CONTENTS_GENERATION": "/worker/detail-contents",
    "FINALIZE_JOB": "/worker/finalize-job"
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
    # name を task_id から決定的に組み立てることで、同じタスクが誤って
    # 二重にenqueueされても(オーケストレーターの競合等)Cloud Tasks側で弾かれる。
    task = {
        "name": client.task_path(PROJECT_ID, REGION, QUEUE_NAME, f"task-{payload.task_id}-{_dedup_bucket()}"),
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
        response = await asyncio.to_thread(client.create_task, request={"parent": parent, "task": task})
        print(f"✅ Enqueued {payload.task_type} to Cloud Tasks: {response.name}")
    except AlreadyExists:
        # 同名タスクが既に投入済み＝二重投入。正常系として扱う。
        print(f"⏭️ Task {payload.task_id} already enqueued (duplicate request ignored).")
    except Exception as e:
        print(f"❌ Failed to enqueue task: {e}")
        raise HTTPException(status_code=500, detail=f"Cloud Tasks Error: {e}")

    return {"message": "Task queued successfully", "task_id": payload.task_id}


# ---------------------------------------------------------
# 🎤 チャンク文字起こし専用のenqueue（DAGパイプラインとは別キュー）
# ---------------------------------------------------------
async def enqueue_transcribe_chunk_task(
    lecture_id: str,
    chunk_index: int,
    start_time: float,
    whisper_context: str,
    r2_audio_path: str,
    uid: str,
):
    """
    /worker/transcribe-chunk-process を叩くCloud Tasksタスクをenqueueする。
    DAGパイプライン用の QUEUE_NAME とは別の CHUNK_QUEUE_NAME を使う。録音終了後の
    重いDAG処理のバーストが、録音中のユーザーのリアルタイム文字起こしを
    遅延させないようにするため。
    """
    if not (PROJECT_ID and CLOUD_RUN_URL and SERVICE_ACCOUNT_EMAIL):
        raise RuntimeError("❌ Missing Environment Variables for Cloud Tasks enqueue!")

    parent = client.queue_path(PROJECT_ID, REGION, CHUNK_QUEUE_NAME)

    worker_payload = {
        "lecture_id": lecture_id,
        "chunk_index": chunk_index,
        "start_time": start_time,
        "whisper_context": whisper_context,
        "r2_audio_path": r2_audio_path,
        "uid": uid,
    }

    # name を lecture_id + chunk_index から決定的に組み立てることで、
    # 同じチャンクが誤って二重にenqueueされてもCloud Tasks側で弾かれる
    # （reaperによる再enqueueと通常経路が競合した場合の保険にもなる）。
    task = {
        "name": client.task_path(PROJECT_ID, REGION, CHUNK_QUEUE_NAME, f"chunk-{lecture_id}-{chunk_index}-{_dedup_bucket()}"),
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": f"{CLOUD_RUN_URL}/worker/transcribe-chunk-process",
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(worker_payload).encode(),
            "oidc_token": {
                "service_account_email": SERVICE_ACCOUNT_EMAIL,
                "audience": CLOUD_RUN_URL,
            }
        }
    }

    try:
        response = await asyncio.to_thread(client.create_task, request={"parent": parent, "task": task})
        print(f"✅ Enqueued TRANSCRIBE_CHUNK (chunk {chunk_index}) to Cloud Tasks: {response.name}")
    except AlreadyExists:
        print(f"⏭️ Chunk {chunk_index} for lecture {lecture_id} already enqueued (duplicate request ignored).")


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

@app.post("/worker/image-prompt-generation")
async def worker_image_prompt_generation(payload: WorkerPayload):
    await run_image_prompt_generation_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/image-rendering")
async def worker_image_rendering(payload: WorkerPayload):
    await run_image_rendering_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/fun-fact-search")
async def worker_fun_fact_search(payload: WorkerPayload):
    await run_fun_fact_search_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/fun-facts-generation")
async def worker_fun_facts_generation(payload: WorkerPayload):
    await run_fun_facts_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/detail-contents")
async def worker_detail_contents(payload: WorkerPayload):
    await run_detail_contents_task(payload.job_id, payload.task_id)
    return {"status": "success"}

@app.post("/worker/finalize-job")
async def worker_finalize_job(payload: WorkerPayload):
    await run_finalize_job_task(payload.job_id, payload.task_id)
    return {"status": "success"}


# ---------------------------------------------------------
# 🩺 Patrol（Cloud Scheduler駆動の汎用メンテナンス・ディスパッチャー）
# ---------------------------------------------------------
# Cloud Schedulerのジョブは1つだけ用意し、このエンドポイントを叩いてもらう。
# 中身は独立したチェック関数のリストで、将来「deleted_atの掃除」「エラー回収」等を
# 追加するときはPATROL_CHECKSに関数を1つ足すだけでよく、Cloud Scheduler側の
# 設定変更は不要。1つのチェックが失敗しても他のチェックが止まらないよう、
# それぞれ独立してtry/exceptする。
# （音声チャンク自体の詰まりは task_runners._recover_stuck_chunks が
#   CHECK_AND_ASSEMBLEの待ち合わせリトライの中で回収するため、ここでは対象にしない）

async def _patrol_reap_stale_dag_tasks() -> dict:
    """
    processing_tasksのうち、QUEUED/RUNNINGのまま STALE_TASK_TIMEOUT_MINUTES 以上
    updated_at が更新されていない行を PENDING に戻す。この更新はSupabaseの
    Database Webhook経由で既存の /webhook/orchestrator を自動的に起こし、
    再enqueueまで面倒を見てくれる。タスクの種類に依存しない汎用的な仕組みなので、
    将来タスク種別が増えてもこのロジックは変更不要。
    """
    admin_client = get_supabase_client()
    threshold = (datetime.now(timezone.utc) - timedelta(minutes=STALE_TASK_TIMEOUT_MINUTES)).isoformat()

    stale_tasks_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_tasks")
            .select("id, task_type")
            .in_("status", ["QUEUED", "RUNNING"])
            .lt("updated_at", threshold)
            .execute()
    )

    recovered = 0
    for t in (stale_tasks_res.data or []):
        reset_res = await asyncio.to_thread(
            lambda t=t: admin_client.table("processing_tasks")
                .update({"status": "PENDING", "updated_at": datetime.now().isoformat()})
                .eq("id", t["id"])
                .in_("status", ["QUEUED", "RUNNING"])
                .execute()
        )
        if reset_res.data:
            recovered += 1
            print(f"🩹 Recovered stale task {t['id']} ({t['task_type']}): reset to PENDING")

    return {"recovered_tasks": recovered, "threshold_minutes": STALE_TASK_TIMEOUT_MINUTES}


# 将来ここに追加していく（例）:
# async def _patrol_cleanup_soft_deleted() -> dict: ...
# async def _patrol_collect_error_reports() -> dict: ...

PATROL_CHECKS = [
    ("reap_stale_dag_tasks", _patrol_reap_stale_dag_tasks),
]


@app.post("/maintenance/patrol")
async def patrol():
    """Cloud Schedulerから定期的に呼ばれる、汎用メンテナンスのディスパッチャー。"""
    results = {}
    for name, check_fn in PATROL_CHECKS:
        try:
            results[name] = await check_fn()
        except Exception as e:
            results[name] = {"error": str(e)}
            print(f"⚠️ Patrol check '{name}' failed: {e}")
    return results