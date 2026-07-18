import os
import json
import time
import asyncio
from typing import Optional
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from fastapi import FastAPI, HTTPException, UploadFile, Request, File, Form, Header
from supabase import create_client, ClientOptions
from nltk.tokenize import sent_tokenize
from pydantic import BaseModel
from google.cloud import tasks_v2
from google.api_core.exceptions import AlreadyExists
from standardwebhooks.webhooks import Webhook, WebhookVerificationError

# Cloud Tasksのタスク名は決定的にするが、task_id/chunk単体だけをキーにすると
# CHECK_AND_ASSEMBLEの「チャンクが揃うまでPENDINGに戻って自己リトライする」といった
# 正当な再試行までCloud Tasksの名前重複チェックでブロックされてしまう
# （同名タスクは完了後 約1時間 再利用できないため）。
# そのため短い時間バケットをキーに含め、「ごく短時間の重複投入だけ」を弾く。
TASK_DEDUP_WINDOW_SECONDS = 30

def _dedup_bucket() -> int:
    return int(time.time() // TASK_DEDUP_WINDOW_SECONDS)

from app.core.supabase import get_supabase_client
from app.services.email_service import (
    send_verification_email,
    send_password_reset_email,
    send_email_change_email,
    send_important_notification,
)
from app.services.task_runners import (
    receive_transcribe_chunk,
    process_transcribe_chunk,
    run_check_and_assemble_transcript_task,
    run_transcribe_master_task,
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
    run_finalize_job_task,
    mark_topic_map_stale,
    run_topic_map_reconstruction_task,
    build_pending_addition_for_lecture,
    CHUNK_STALE_TIMEOUT_MINUTES,
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
TOPIC_MAP_STALE_TIMEOUT_MINUTES = int(os.getenv("TOPIC_MAP_STALE_TIMEOUT_MINUTES", "60")) # Lecture削除/移動でstaleになったTopic Mapを、ユーザー操作が無くても自動でRecreateするまでの分数
LECTURE_HARD_DELETE_RETENTION_DAYS = int(os.getenv("LECTURE_HARD_DELETE_RETENTION_DAYS", "30")) # ソフト削除(deleted_at)からハードデリートまでの日数
PATROL_HARD_DELETE_BATCH_SIZE = int(os.getenv("PATROL_HARD_DELETE_BATCH_SIZE", "50")) # Patrol1回あたりでハードデリートする講義数の上限(タイムアウト防止。溢れた分は次回実行で処理される)
CLOUD_TASKS_MAX_ATTEMPTS = int(os.getenv("CLOUD_TASKS_MAX_ATTEMPTS", "5")) # lefture-processing-queueのRetry Config(Max Attempts)と必ず一致させる。GCP側で変更したらここも変更すること
STALE_FAILED_JOB_TIMEOUT_MINUTES = int(os.getenv("STALE_FAILED_JOB_TIMEOUT_MINUTES", "15")) # 即時判定(X-CloudTasks-TaskRetryCount)の取りこぼし対策。FAILEDのまま動きがないタスクを見て親ジョブをFAILED化するまでの分数
SEND_EMAIL_HOOK_SECRET = os.getenv("SEND_EMAIL_HOOK_SECRET", "") # Supabase Auth「Send Email Hook」の署名検証シークレット(Standard Webhooks形式)

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
    expected_chunks: int = 0
    # False(既定): アップロード完了後の自動発火用。既にこのlectureに対する
    # 未完了(!=COMPLETED)Jobがあれば新規作成せず、その既存Job IDを冪等に返す。
    # True: 「Start Over」ボタンなど、ユーザーが明示的に選んだ再実行専用。
    # 既存の未完了Jobをすべてキャンセルしてから新しいJobを作り直す(従来通りの挙動)。
    force: bool = False

class RetryTaskRequest(BaseModel):
    task_id: str

class TopicMapMarkStaleRequest(BaseModel):
    """Lectureの削除・移動が起きた瞬間にFlutterから呼ばれる（LLMは呼ばず記録だけ）。"""
    course_id: str
    lecture_id: str
    action: str  # "remove" | "add"

class TopicMapReconstructRequest(BaseModel):
    """「Recreate Topic Map」ボタンから呼ばれる（Phase A+Bを同期的に実行）。"""
    course_id: str

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

    # 3.5 講義情報を取得し、course_id が存在するか検証する
    try:
        lec_res = await asyncio.to_thread(
            lambda: admin_client.table("lectures").select("course_id").eq("id", payload.lecture_id).single().execute()
        )
        if not lec_res.data or not lec_res.data.get("course_id"):
            raise HTTPException(
                status_code=400,
                detail="Lecture must be assigned to a course before analysis can start."
            )
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(
            status_code=400,
            detail=f"Failed to verify lecture course association: {str(e)}"
        )

    # 3.6 同じlecture_idの未完了(!=COMPLETED)jobが既にあるか確認する。
    old_jobs_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").select("id")
            .eq("lecture_id", payload.lecture_id).neq("status", "COMPLETED")
            .order("created_at", desc=True).execute()
    )
    old_jobs = old_jobs_res.data or []

    # force=False(自動発火)で既に未完了jobがある場合は、新規作成せず既存jobを
    # 冪等に返す。アップロード完了直後の自動発火は、チャンクのアップロード
    # リトライ(クライアント側は成功をACKできず再送するが、サーバー側は既に
    # 成功しているケース)によって複数回呼ばれ得るため、ここでガードしないと
    # 同じlectureに対して二重にjob/taskが作られてしまう(過去に実際に発生した)。
    # 「Start Over」ボタン等、ユーザーが明示的に再実行を選んだ場合はforce=Trueで
    # 呼ばれ、以下のキャンセル→新規作成を素通りする。
    if old_jobs and not payload.force:
        existing_job_id = old_jobs[0]["id"]
        print(f"⏭️ Active job already exists for lecture {payload.lecture_id} ({existing_job_id}). Returning existing job (idempotent no-op).")
        return {"message": "Analysis already in progress", "job_id": existing_job_id}

    # 3.7 古いjobのタスクを無効化する(force=Trueの場合のみここに到達)。
    # R2上のパスは {uid}/{lecture_id}/... のみで組まれておりjob_idを含まないため、
    # 古いjobのタスクが後から（Cloud Tasksの遅延リトライ等で）動き出すと、新しいjobの
    # 書き込みと衝突してデータが壊れる。CANCELLEDは orchestrator/patrol のどちらも
    # 拾わない終端ステータスなので、これだけで再開を防げる。
    for old_job in old_jobs:
        await asyncio.to_thread(
            lambda old_job=old_job: admin_client.table("processing_tasks").update({
                "status": "CANCELLED",
                "updated_at": datetime.now().isoformat(),
            }).eq("job_id", old_job["id"]).in_(
                "status", ["PENDING", "QUEUED", "RUNNING", "FAILED"]
            ).execute()
        )

    # 3.8 リアルタイムかプレレコーデッドかを判定
    is_realtime = payload.expected_chunks > 0
    if not is_realtime:
        # DBにすでにトランスクリプトがある場合はリアルタイムとして扱う
        count_res = await asyncio.to_thread(
            lambda: admin_client.table("lecture_transcripts")
                .select("id", count="exact")
                .eq("lecture_id", payload.lecture_id)
                .execute()
        )
        if (count_res.count or 0) > 0:
            is_realtime = True

    first_task = "CHECK_AND_ASSEMBLE" if is_realtime else "TRANSCRIBE_MASTER"

    # 4. 親ジョブを作成 (processing_jobs)
    job_data = {
      "lecture_id": payload.lecture_id,
      "user_id": user_id,
      "expected_chunks": payload.expected_chunks if is_realtime else 0,
      "status": "PENDING"
    }
    job_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").insert(job_data).execute()
    )
    job_id = job_res.data[0]["id"]

    # 5. タスクの設計図（DAG）を定義
    tasks_blueprint = [
        # Phase 1: 基礎データの準備
        {"task_type": first_task, "dependencies": []},
        
        # Phase 2: 全体俯瞰とトピック分割
        {"task_type": "CORE_EXTRACTION", "dependencies": [first_task]},
        
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
    await asyncio.to_thread(
        lambda: admin_client.table("processing_tasks").insert(insert_data).execute()
    )

    # 大成功！
    return {"message": "Analysis started successfully", "job_id": job_id}

# ---------------------------------------------------------
# 個別タスクのリトライ (カスケード対応)
# ---------------------------------------------------------

# R2上に「既にあれば再生成をスキップする」キャッシュを持つtask_typeと、
# そのキャッシュのprefix組み立て方。カスケードリトライでこれらのtask_typeが
# 対象に含まれる場合、DBのstatusをPENDINGに戻すだけでは古い成果物が
# 再利用されてしまうため、明示的にR2上のキャッシュも消す。
# (announcements/fun_facts/review_cards/lecture_topics/deep_notesへの書き込みは
#  全てdelete→insertで上書きされるため、ここに載せる必要はない)
_CACHED_TASK_TYPE_PREFIXES = {
    "IMAGE_RENDERING": lambda uid, lecture_id: f"{uid}/{lecture_id}/images/",
    "REVIEW_CARD_GENERATION": lambda uid, lecture_id: f"{uid}/{lecture_id}/pipeline_cache/review_cards_topic_",
    "DETAIL_CONTENTS_GENERATION": lambda uid, lecture_id: f"{uid}/{lecture_id}/pipeline_cache/detail_contents_topic_",
}


def _compute_cascade_task_types(all_tasks: list, target_task_type: str) -> set:
    """
    tasks_blueprint(main.py:200-235)がprocessing_tasks.dependenciesとして
    保存している依存関係(逆方向)から、target_task_type自身とそれに
    (直接・間接に)依存している全ての後続task_typeの集合を求める。
    """
    forward = {}
    for t in all_tasks:
        deps = t.get("dependencies", [])
        deps = json.loads(deps) if isinstance(deps, str) else deps
        for d in deps:
            forward.setdefault(d, []).append(t["task_type"])

    affected = set()
    queue = [target_task_type]
    while queue:
        current = queue.pop()
        if current in affected:
            continue
        affected.add(current)
        queue.extend(forward.get(current, []))
    return affected


@app.post("/retry-task")
async def retry_task(payload: RetryTaskRequest, request: Request):
    """
    指定タスクを(FAILED/COMPLETEDいずれの状態からでも)PENDINGに戻してやり直す。
    そのタスクに依存している後続タスクも全てPENDINGに戻す(カスケード)。
    理由: 例えばIMAGE_RENDERINGの失敗が実は前段のIMAGE_PROMPT_GENERATIONが
    出したプロンプトの質のせい、ということがあり得るため、上流をやり直したら
    下流も連動してやり直る必要がある。R2上に再生成スキップ用のキャッシュを
    持つtask_type(_CACHED_TASK_TYPE_PREFIXES)は、あわせてキャッシュも消す。
    PENDINGへの書き戻しは既存のSupabase Webhook経由で
    /webhook/orchestrator の is_manually_retried 分岐が自動的に拾って再enqueueする。
    """
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    token = auth_header.replace("Bearer ", "").strip()
    user_client = create_client(
        SUPABASE_URL,
        SUPABASE_PUBLISHABLE_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {token}"})
    )
    user_res = user_client.auth.get_user(token)
    if not user_res or not user_res.user:
        raise HTTPException(status_code=401, detail="Unauthorized user")
    user_id = user_res.user.id

    admin_client = get_supabase_client()

    task_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_tasks").select("id, job_id, task_type, status")
            .eq("id", payload.task_id).single().execute()
    )
    if not task_res.data:
        raise HTTPException(status_code=404, detail="Task not found")
    task = task_res.data

    # タスク→ジョブ経由で所有者を検証（他人のタスクを操作できないように）
    job_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").select("id, user_id, lecture_id")
            .eq("id", task["job_id"]).single().execute()
    )
    if not job_res.data or job_res.data["user_id"] != user_id:
        raise HTTPException(status_code=403, detail="Not authorized to retry this task")

    if task["status"] not in ("FAILED", "COMPLETED"):
        raise HTTPException(
            status_code=400,
            detail=f"Task is not in a retryable state (current status: {task['status']})",
        )

    all_tasks_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_tasks")
            .select("id, task_type, status, dependencies").eq("job_id", task["job_id"]).execute()
    )
    all_tasks = all_tasks_res.data or []

    affected_types = _compute_cascade_task_types(all_tasks, task["task_type"])
    affected_tasks = [t for t in all_tasks if t["task_type"] in affected_types]

    # 集合の中に実行中のものが混じっていたら、巻き込んで壊さないよう丸ごと拒否する
    in_flight = [t for t in affected_tasks if t["status"] in ("QUEUED", "RUNNING")]
    if in_flight:
        raise HTTPException(
            status_code=409,
            detail=f"{len(in_flight)} affected task(s) are currently in progress. Try again shortly.",
        )

    resettable_ids = [t["id"] for t in affected_tasks if t["status"] != "PENDING"]
    if resettable_ids:
        await asyncio.to_thread(
            lambda: admin_client.table("processing_tasks").update({
                "status": "PENDING",
                "error_message": None,
                "updated_at": datetime.now().isoformat(),
            }).in_("id", resettable_ids).execute()
        )

    # 再生成スキップ用のR2キャッシュを持つtask_typeが対象に含まれていたら、
    # あわせてキャッシュも消して確実に再生成させる
    uid, lecture_id = job_res.data["user_id"], job_res.data["lecture_id"]
    from app.core.r2_storage import storage_service
    for task_type, prefix_fn in _CACHED_TASK_TYPE_PREFIXES.items():
        if task_type in affected_types:
            await asyncio.to_thread(storage_service.delete_prefix, prefix_fn(uid, lecture_id))

    # 詰まっていた/完了済みだったジョブも「進行中」に戻す(冪等)
    await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").update({"status": "RUNNING"})
            .eq("id", task["job_id"]).in_("status", ["FAILED", "COMPLETED"]).execute()
    )

    return {
        "message": "Task queued for retry",
        "task_id": payload.task_id,
        "affected_task_types": sorted(affected_types),
    }

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
    # CHECK_AND_ASSEMBLEのように「揃うまで待つ」タスクは、待機中はPENDINGではなく
    # 専用のWAITINGステータスに入るため(このDAG判定はstatus=='PENDING'のみを
    # 対象にしている)、ここは元のシンプルな判定のままでよい。RUNNING→PENDINGの
    # 遷移(=stale reaperによるクラッシュ復旧など、本当に再実行してほしいケース)
    # は今まで通り即座に拾われる。
    is_manually_retried = (event_type == "UPDATE" and record.get("status") == "PENDING" and old_record.get("status") != "PENDING")

    if not (is_new or is_newly_completed or is_manually_retried):
        return {"message": "Not a triggerable state. Ignoring."}

    print(f"🎼 Orchestrator waking up! Triggered by Task: {record.get('task_type')} ({event_type})")

    # 2. Service Role Key を持った管理者クライアントを取得
    # （Webhookはシステムとして動くためRLSをバイパスする必要がある）
    admin_client = get_supabase_client()
    job_id = record.get("job_id")

    # 3. このジョブに紐づく「すべてのタスク」の最新状態を取得
    # ★ 同期I/O(Supabase)を必ずスレッドに逃がす: CHECK_AND_ASSEMBLEは待ち合わせ中
    # 例外→PENDING遷移で毎回このwebhookを起こすため、同時多発的にこのハンドラが
    # 走ることがある。ここを直接awaitせず同期実行すると、単一のasyncioイベント
    # ループがブロックされて他のリクエスト(他のwebhook呼び出しや後続タスクの
    # COMPLETED通知など)が処理待ちで詰まり、Supabase側のpg_net webhookタイムアウト
    # (既定10秒、失敗時の自動再送なし)を誘発してオーケストレーションが永久に
    # 止まってしまう。これが実際に起きた不具合の直接原因だった。
    res = await asyncio.to_thread(
        lambda: admin_client.table("processing_tasks").select("*").eq("job_id", job_id).execute()
    )
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

    # 4.5 最初のタスクが動き出す瞬間にジョブ全体をRUNNINGへ(PENDINGの時だけ・冪等)
    await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").update({"status": "RUNNING"})
            .eq("id", job_id).eq("status", "PENDING").execute()
    )

    # 5. 実行可能なタスクを処理
    for task in ready_tasks:
        # 5-1. 二重起動を防ぐため、DBのステータスを 'QUEUED' に更新する
        # updated_at も明示的に更新しておく（reap-stale-tasksがこの時刻を基準に
        # 「QUEUEDのままenqueueに失敗して止まっているタスク」を検出するため）
        update_res = await asyncio.to_thread(
            lambda task=task: admin_client.table("processing_tasks")
                .update({"status": "QUEUED", "updated_at": datetime.now().isoformat()})
                .eq("id", task["id"])
                .eq("status", "PENDING")
                .execute()
        )

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
    "TRANSCRIBE_MASTER": "/worker/transcribe-master",
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

async def _run_worker_task(request: Request, payload: WorkerPayload, task_fn) -> dict:
    """
    /worker/* エンドポイントの共通実行部。タスク失敗時、Cloud Tasksが付与する
    X-CloudTasks-TaskRetryCount ヘッダー(0始まりの現在の再送回数)を見て、
    それが今回のリトライサイクルにおける最後の試行だった場合は、
    Patrol(30分間隔)を待たずにその場で親ジョブをFAILEDにする。
    processing_tasks側は各task_fn内で既にFAILED記録済みなので、
    ここではjob側の判定だけ行う。
    """
    try:
        await task_fn(payload.job_id, payload.task_id)
    except Exception:
        retry_count = int(request.headers.get("X-CloudTasks-TaskRetryCount", "0"))
        if retry_count >= CLOUD_TASKS_MAX_ATTEMPTS - 1:
            admin_client = get_supabase_client()
            await asyncio.to_thread(
                lambda: admin_client.table("processing_jobs")
                    .update({"status": "FAILED"})
                    .eq("id", payload.job_id)
                    .not_.in_("status", ["COMPLETED", "FAILED"])
                    .execute()
            )
        raise
    return {"status": "success"}

@app.post("/worker/check-and-assemble")
async def worker_check_and_assemble(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_check_and_assemble_transcript_task)

@app.post("/worker/transcribe-master")
async def worker_transcribe_master(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_transcribe_master_task)

@app.post("/worker/role-classification")
async def worker_role_classification(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_role_classification_task)

@app.post("/worker/core-extraction")
async def worker_core_extraction(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_core_extraction_task)

@app.post("/worker/announcement-generation")
async def worker_announcement_generation(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_announcement_generation_task)

@app.post("/worker/topic-mapping")
async def worker_topic_mapping(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_topic_mapping_task)

@app.post("/worker/review-card")
async def worker_review_card(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_review_card_task)

@app.post("/worker/image-prompt-generation")
async def worker_image_prompt_generation(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_image_prompt_generation_task)

@app.post("/worker/image-rendering")
async def worker_image_rendering(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_image_rendering_task)

@app.post("/worker/fun-fact-search")
async def worker_fun_fact_search(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_fun_fact_search_task)

@app.post("/worker/fun-facts-generation")
async def worker_fun_facts_generation(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_fun_facts_task)

@app.post("/worker/detail-contents")
async def worker_detail_contents(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_detail_contents_task)

@app.post("/worker/finalize-job")
async def worker_finalize_job(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_finalize_job_task)


# ---------------------------------------------------------
# 🗺️ Topic Map: Lecture削除/移動 と Recreate（processing_jobsのDAGとは独立）
# ---------------------------------------------------------
# この2本は録音パイプラインのjob_id/task_idチェーンに一切依存しない、クライアント
# 発火の単発エンドポイント。mark-staleは記録だけの軽量な処理なので即時応答、
# reconstructはLLM呼び出しを1回含むため数秒かかりうるが、依存関係のない単発処理
# なのでCloud Tasksのキューに乗せず、リクエストの中で同期的に完結させている。

@app.post("/topic-map/mark-stale")
async def topic_map_mark_stale(payload: TopicMapMarkStaleRequest):
    """
    Lectureの削除・Course移動が起きた瞬間にFlutterから呼ばれる。LLMは呼ばず、
    pending_removals/pending_additionsに記録してis_staleを立てるだけ。
    実際のグラフ修復は「Recreate Topic Map」操作かPatrolのアイドルタイムアウトが行う。
    """
    if payload.action not in ("remove", "add"):
        raise HTTPException(status_code=400, detail=f"Invalid action: {payload.action}")

    lecture_title = None
    lecture_topics = None
    if payload.action == "add":
        try:
            addition = await build_pending_addition_for_lecture(payload.lecture_id)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to read lecture's core extraction result: {e}")
        lecture_title = addition["lecture_title"]
        lecture_topics = addition["topics"]

    result = await mark_topic_map_stale(
        course_id=payload.course_id,
        action=payload.action,
        lecture_id=payload.lecture_id,
        lecture_topics=lecture_topics,
        lecture_title=lecture_title,
    )
    return result


@app.post("/topic-map/reconstruct")
async def topic_map_reconstruct(payload: TopicMapReconstructRequest):
    """
    「Recreate Topic Map」ボタンから呼ばれる。pending_removals/pending_additionsを
    まとめて消化し、Phase A(決定的除去)→Phase B(LLMによる修復)を同期的に実行する。
    """
    try:
        result = await run_topic_map_reconstruction_task(payload.course_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Topic map reconstruction failed: {e}")

    if result.get("status") == "blocked":
        if result.get("reason") == "lecture_processing_in_progress":
            detail = "このCourseはまだ分析中のLectureがあるため、今はTopic Mapを再構成できません。分析が終わってから再試行してください。"
        else:
            detail = "このCourseのTopic Mapは既に再構成が進行中です。しばらくしてから再試行してください。"
        raise HTTPException(status_code=409, detail=detail)

    return result


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


async def _patrol_advance_stalled_dags() -> dict:
    """
    タスクがCOMPLETEDになった瞬間、Supabaseの Database Webhook 経由で
    /webhook/orchestrator が起こされ、依存が満たされた後続タスクをQUEUEDに
    してenqueueする設計になっている。しかしこのWebhook配信は best-effort
    であり（Supabase側のリトライ保証は限定的、デプロイ中の一瞬の応答不良等でも
    容易に失われる）、1回でも配信が失敗すると、それ以降は誰も「次に実行可能な
    タスクがないか」を再チェックしないため、依存関係がとっくに満たされている
    のにPENDINGのまま永久に取り残されるタスクが発生し得る。
    _patrol_reap_stale_dag_tasksはQUEUED/RUNNINGで詰まったタスクしか救えず
    （このケースはそもそもQUEUEDにすら到達していない）、このケースをカバー
    できない。ここではジョブ単位で「依存が全て満たされているのにPENDINGの
    ままのタスク」を直接探し、/webhook/orchestrator と全く同じ判定ロジックで
    QUEUED化＆enqueueまで行う、Webhook配信ミスに対するバックストップ。
    """
    admin_client = get_supabase_client()

    active_jobs_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs")
            .select("id").in_("status", ["PENDING", "RUNNING"]).execute()
    )
    job_ids = [j["id"] for j in (active_jobs_res.data or [])]

    advanced = 0
    for job_id in job_ids:
        all_tasks_res = await asyncio.to_thread(
            lambda job_id=job_id: admin_client.table("processing_tasks")
                .select("*").eq("job_id", job_id).execute()
        )
        all_tasks = all_tasks_res.data or []
        completed_types = {t["task_type"] for t in all_tasks if t["status"] == "COMPLETED"}

        ready_tasks = []
        for t in all_tasks:
            if t["status"] != "PENDING":
                continue
            deps = t.get("dependencies") or []
            deps = json.loads(deps) if isinstance(deps, str) else deps
            if all(d in completed_types for d in deps):
                ready_tasks.append(t)

        for task in ready_tasks:
            # orchestrator_webhookと同じく、QUEUEDへの遷移をeq("status","PENDING")で
            # アトミックに行い、ちょうど本物のWebhookが同時に処理していた場合の
            # 二重enqueueを防ぐ。
            update_res = await asyncio.to_thread(
                lambda task=task: admin_client.table("processing_tasks")
                    .update({"status": "QUEUED", "updated_at": datetime.now().isoformat()})
                    .eq("id", task["id"]).eq("status", "PENDING").execute()
            )
            if not update_res.data:
                continue
            try:
                await enqueue_task(EnqueuePayload(job_id=job_id, task_id=task["id"], task_type=task["task_type"]))
                advanced += 1
                print(f"🩹 Patrol advanced stalled task {task['task_type']} (job {job_id}) — orchestrator webhook was likely missed.")
            except Exception as e:
                print(f"⚠️ Patrol failed to enqueue stalled task {task['task_type']}: {e}")

    return {"advanced_tasks": advanced}


async def _patrol_wake_waiting_check_and_assemble() -> dict:
    """
    CHECK_AND_ASSEMBLEはチャンクが揃うまで、通常のDAG状態機械には含まれない
    専用のWAITINGステータスで待機する(orchestrator_webhookのDAG判定は
    status=='PENDING'のタスクしか見ないため、WAITINGには一切反応しない設計)。
    復帰は基本的にチャンク完了イベント(_maybe_wake_check_and_assemble)が
    即座に行うが、音声チャンク自体が詰まって二度と完了しない場合はその
    イベントが永遠に発生しない。ここでWAITINGのままCHUNK_STALE_TIMEOUT_MINUTES
    以上動きが無いタスクを定期的に見つけて強制的に一度起こし、
    run_check_and_assemble_transcript_task自身の詰まりチャンク回収
    (_recover_stuck_chunks)を回す。まだ準備が整っていなければまたWAITINGに
    戻るだけなので、無限リトライにはならない。
    """
    admin_client = get_supabase_client()
    threshold = (datetime.now(timezone.utc) - timedelta(minutes=CHUNK_STALE_TIMEOUT_MINUTES)).isoformat()

    stale_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_tasks")
            .select("id, job_id")
            .eq("task_type", "CHECK_AND_ASSEMBLE")
            .eq("status", "WAITING")
            .lt("updated_at", threshold)
            .execute()
    )

    woken = 0
    for t in (stale_res.data or []):
        update_res = await asyncio.to_thread(
            lambda t=t: admin_client.table("processing_tasks")
                .update({"status": "QUEUED", "updated_at": datetime.now().isoformat()})
                .eq("id", t["id"]).eq("status", "WAITING").execute()
        )
        if not update_res.data:
            continue
        try:
            await enqueue_task(EnqueuePayload(job_id=t["job_id"], task_id=t["id"], task_type="CHECK_AND_ASSEMBLE"))
            woken += 1
            print(f"🩹 Patrol woke stalled WAITING CHECK_AND_ASSEMBLE task {t['id']}")
        except Exception as e:
            print(f"⚠️ Patrol failed to wake CHECK_AND_ASSEMBLE task {t['id']}: {e}")

    return {"woken_tasks": woken, "threshold_minutes": CHUNK_STALE_TIMEOUT_MINUTES}


async def _patrol_fail_stuck_jobs() -> dict:
    """
    /worker/* の即時判定(_run_worker_task内、X-CloudTasks-TaskRetryCountを見て
    最終試行なら即FAILED化)が取りこぼした場合の緩いバックストップ。
    processing_tasksがFAILEDのままSTALE_FAILED_JOB_TIMEOUT_MINUTES以上
    updated_atが更新されていない行を見つけ、紐づくprocessing_jobsをFAILEDにする。
    """
    admin_client = get_supabase_client()
    threshold = (datetime.now(timezone.utc) - timedelta(minutes=STALE_FAILED_JOB_TIMEOUT_MINUTES)).isoformat()

    stuck_tasks_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_tasks")
            .select("job_id")
            .eq("status", "FAILED")
            .lt("updated_at", threshold)
            .execute()
    )

    stuck_job_ids = {t["job_id"] for t in (stuck_tasks_res.data or [])}

    failed = 0
    for job_id in stuck_job_ids:
        fail_res = await asyncio.to_thread(
            lambda job_id=job_id: admin_client.table("processing_jobs")
                .update({"status": "FAILED"})
                .eq("id", job_id)
                .not_.in_("status", ["COMPLETED", "FAILED"])
                .execute()
        )
        if fail_res.data:
            failed += 1
            print(f"🩹 Marked stuck job {job_id} as FAILED (backstop)")

    return {"failed_jobs": failed, "threshold_minutes": STALE_FAILED_JOB_TIMEOUT_MINUTES}


async def _patrol_reconstruct_stale_topic_maps() -> dict:
    """
    Lecture削除/移動でstaleになったTopic Mapのうち、stale_sinceから
    TOPIC_MAP_STALE_TIMEOUT_MINUTES(既定60分)以上ユーザーが「Recreate Topic Map」を
    押さずに放置しているものを、自動でまとめて再構成する。ユーザーが整理中に
    連続で削除・移動しても、ここに来る前に手動でRecreateすれば即座に解消されるので、
    これはあくまで「操作を忘れた/放置した」場合の保険。
    1件の再構成失敗が他のCourseの処理を止めないよう、Course単位でtry/exceptする。
    """
    admin_client = get_supabase_client()
    threshold = (datetime.now(timezone.utc) - timedelta(minutes=TOPIC_MAP_STALE_TIMEOUT_MINUTES)).isoformat()

    stale_res = await asyncio.to_thread(
        lambda: admin_client.table("topic_maps")
            .select("course_id")
            .eq("is_stale", True)
            .lt("stale_since", threshold)
            .execute()
    )

    reconstructed = 0
    skipped = 0
    failed = 0
    for row in (stale_res.data or []):
        course_id = row["course_id"]
        try:
            result = await run_topic_map_reconstruction_task(course_id)
            if result.get("status") == "blocked":
                # Lectureが分析中、または(手動Recreateとの競合等で)既に別プロセスが
                # 再構成中。無理に割り込ませず、次回のPatrol実行に委ねる。
                skipped += 1
                print(f"⏭️ Patrol skipped course {course_id}: {result.get('reason')}")
            else:
                reconstructed += 1
        except Exception as e:
            failed += 1
            print(f"⚠️ Patrol failed to reconstruct topic map for course {course_id}: {e}")

    return {
        "reconstructed": reconstructed,
        "skipped": skipped,
        "failed": failed,
        "threshold_minutes": TOPIC_MAP_STALE_TIMEOUT_MINUTES,
    }


async def _hard_delete_lecture(admin_client, uid: str, lecture_id: str) -> None:
    """
    講義1件を、関連する子テーブル・R2上のファイルとともに完全に削除する。
    Supabase側にON DELETE CASCADEがあるかどうかに依存しないよう、
    子テーブル→親テーブルの順で明示的に削除する。
    """
    # processing_tasksはlecture_idを持たずjob_id経由でしか紐づかないため、
    # 先にこの講義のprocessing_jobs.id一覧を取得する
    jobs_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").select("id").eq("lecture_id", lecture_id).execute()
    )
    job_ids = [j["id"] for j in (jobs_res.data or [])]
    if job_ids:
        await asyncio.to_thread(
            lambda: admin_client.table("processing_tasks").delete().in_("job_id", job_ids).execute()
        )

    # lecture_idを直接持つ子テーブルを削除
    child_tables = [
        "fun_facts", "review_cards", "deep_notes", "keywords",
        "lecture_topics", "announcements", "lecture_transcripts", "processing_jobs",
    ]
    for table in child_tables:
        await asyncio.to_thread(
            lambda t=table: admin_client.table(t).delete().eq("lecture_id", lecture_id).execute()
        )

    # R2上のファイル実体を削除({uid}/{lecture_id}/ 配下全て。パス構造は全パイプラインで統一されている)
    from app.core.r2_storage import storage_service
    await asyncio.to_thread(storage_service.delete_prefix, f"{uid}/{lecture_id}/")

    # 講義本体を最後に削除
    await asyncio.to_thread(
        lambda: admin_client.table("lectures").delete().eq("id", lecture_id).execute()
    )


async def _hard_delete_user_data(admin_client, uid: str) -> None:
    """
    アカウント削除時に、そのユーザーが所有するデータを全て完全に削除する。
    auth.usersの削除がDB側のON DELETE CASCADEに依存する保証がないため
    (_hard_delete_lectureと同じ方針)、明示的に子→親の順で削除する。
    最後にR2上の {uid}/ 配下を丸ごと削除し、講義単位の削除で取りこぼした
    ファイル(プロフィール画像・サポート添付など)も含めて掃除する。

    注意: support_tickets(問い合わせ履歴)は意図的に削除対象から除外している。
    サポート対応・不正利用調査のための記録として、ユーザー本人の削除とは
    切り離して保持する方針。削除すべきという判断であれば、ここに
    admin_client.table("support_tickets").delete().eq("user_id", uid).execute()
    を追加する。
    """
    # 1. ユーザーが所有する講義を全て列挙し、講義単位で完全削除
    #    (子テーブル: fun_facts/review_cards/deep_notes/keywords/lecture_topics/
    #     announcements/lecture_transcripts/processing_jobs/processing_tasks と
    #     R2上の音声・生成物を _hard_delete_lecture 内で削除済み)
    lectures_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures").select("id").eq("user_id", uid).execute()
    )
    for row in (lectures_res.data or []):
        await _hard_delete_lecture(admin_client, uid, row["id"])

    # 2. 講義に紐づかないユーザー単位のお知らせ(lecture_idがNULLのもの)を削除
    await asyncio.to_thread(
        lambda: admin_client.table("announcements").delete().eq("user_id", uid).execute()
    )

    # 3. コース単位のトピックマップを削除(コース本体より先に削除する)
    await asyncio.to_thread(
        lambda: admin_client.table("topic_maps").delete().eq("user_id", uid).execute()
    )

    # 4. コースを削除
    await asyncio.to_thread(
        lambda: admin_client.table("courses").delete().eq("user_id", uid).execute()
    )

    # 5. プロフィールを削除
    await asyncio.to_thread(
        lambda: admin_client.table("user_profiles").delete().eq("id", uid).execute()
    )

    # 6. R2上の {uid}/ 配下を丸ごと削除(講義単位の削除で取りこぼしたファイルの安全網)
    from app.core.r2_storage import storage_service
    await asyncio.to_thread(storage_service.delete_prefix, f"{uid}/")


async def _patrol_hard_delete_expired_lectures() -> dict:
    """
    deleted_atからLECTURE_HARD_DELETE_RETENTION_DAYS(既定30日)を過ぎた講義を、
    関連する子テーブル・R2上のファイルとともに完全に削除する。
    講義単位でtry/exceptし、1件の失敗が他の講義の削除を止めないようにする。
    deleted_atは削除操作以外では変化しないため、失敗して取り残された行や
    PATROL_HARD_DELETE_BATCH_SIZEを超えた分は次回のPatrol実行で自然に再試行される。
    """
    admin_client = get_supabase_client()
    threshold = (
        datetime.now(timezone.utc) - timedelta(days=LECTURE_HARD_DELETE_RETENTION_DAYS)
    ).isoformat()

    expired_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures")
            .select("id, user_id")
            .not_.is_("deleted_at", "null")
            .lt("deleted_at", threshold)
            .limit(PATROL_HARD_DELETE_BATCH_SIZE)
            .execute()
    )

    deleted = 0
    failed = 0
    for row in (expired_res.data or []):
        lecture_id, uid = row["id"], row["user_id"]
        try:
            await _hard_delete_lecture(admin_client, uid, lecture_id)
            deleted += 1
        except Exception as e:
            failed += 1
            print(f"⚠️ Patrol failed to hard-delete lecture {lecture_id}: {e}")

    return {"hard_deleted": deleted, "failed": failed, "retention_days": LECTURE_HARD_DELETE_RETENTION_DAYS}


# 将来ここに追加していく（例）:
# async def _patrol_collect_error_reports() -> dict: ...

PATROL_CHECKS = [
    ("reap_stale_dag_tasks", _patrol_reap_stale_dag_tasks),
    ("advance_stalled_dags", _patrol_advance_stalled_dags),
    ("wake_waiting_check_and_assemble", _patrol_wake_waiting_check_and_assemble),
    ("fail_stuck_jobs", _patrol_fail_stuck_jobs),
    ("reconstruct_stale_topic_maps", _patrol_reconstruct_stale_topic_maps),
    ("hard_delete_expired_lectures", _patrol_hard_delete_expired_lectures),
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


# ---------------------------------------------------------
# 📧 メール送信エンドポイント
# ---------------------------------------------------------

class SendVerificationEmailRequest(BaseModel):
    to: str
    verification_link: str


class SendPasswordResetEmailRequest(BaseModel):
    to: str
    reset_link: str


class SendNotificationEmailRequest(BaseModel):
    to: str
    subject: str
    html: str


@app.post("/email/send-verification")
async def email_send_verification(payload: SendVerificationEmailRequest):
    """ユーザー登録確認メールを送信する"""
    try:
        result = await send_verification_email(payload.to, payload.verification_link)
        return {"success": True, **result}
    except Exception as e:
        print(f"❌ Failed to send verification email: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to send email: {str(e)}")


@app.post("/email/send-password-reset")
async def email_send_password_reset(payload: SendPasswordResetEmailRequest):
    """パスワードリセットメールを送信する"""
    try:
        result = await send_password_reset_email(payload.to, payload.reset_link)
        return {"success": True, **result}
    except Exception as e:
        print(f"❌ Failed to send password reset email: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to send email: {str(e)}")


@app.post("/email/send-notification")
async def email_send_notification(payload: SendNotificationEmailRequest):
    """汎用通知メールを送信する"""
    try:
        result = await send_important_notification(payload.to, payload.subject, payload.html)
        return {"success": True, **result}
    except Exception as e:
        print(f"❌ Failed to send notification email: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to send email: {str(e)}")


# ---------------------------------------------------------
# 🔗 Supabase Auth — Custom Send Email Hook
# ---------------------------------------------------------

SUPABASE_URL = os.getenv("SUPABASE_URL", "")


class _SupabaseHookEmailData(BaseModel):
    token: str = ""
    token_hash: str = ""
    token_new: str = ""
    token_hash_new: str = ""
    redirect_to: str = ""
    email_action_type: str
    site_url: str = ""


class _SupabaseHookUser(BaseModel):
    id: str
    email: str
    new_email: Optional[str] = None
    user_metadata: dict = {}


class SupabaseEmailHookRequest(BaseModel):
    user: _SupabaseHookUser
    email_data: _SupabaseHookEmailData


def _verify_supabase_hook_signature(raw_body: bytes, headers: dict) -> None:
    """
    Supabase Auth Hook の Standard Webhooks 署名を検証する。
    SEND_EMAIL_HOOK_SECRET 未設定時は(既存のWEBHOOK_SECRETと同様)検証をスキップするが、
    本番では必ず設定すること。値は Supabase Dashboard > Authentication > Hooks の
    Send Email Hook に表示される "v1,whsec_..." 形式のシークレットをそのまま使う。
    """
    if not SEND_EMAIL_HOOK_SECRET:
        print("⚠️  SEND_EMAIL_HOOK_SECRET is not set - skipping signature verification (INSECURE)")
        return

    secret = SEND_EMAIL_HOOK_SECRET
    if secret.startswith("v1,"):
        secret = secret[len("v1,"):]

    try:
        Webhook(secret).verify(raw_body, headers)
    except WebhookVerificationError as e:
        raise HTTPException(status_code=401, detail=f"Invalid webhook signature: {e}")


@app.post("/auth/send-email")
async def supabase_email_hook(request: Request):
    """
    Supabase Auth の「Send Email Hook」を受信して、
    アクションタイプに応じた確認メールを Resend 経由で送信する。

    対応する email_action_type:
      - signup       : ユーザー登録確認
      - recovery     : パスワードリセット
      - email_change : メールアドレス変更確認
          Secure Email Change が有効な場合、現在のメールと新しいメールの
          両方に確認リンクを送る必要がある。Supabase側のフィールド名は
          後方互換のため入れ替わっている点に注意:
            現在のメール(user.email)     宛て → token_hash_new
            新しいメール(user.new_email) 宛て → token_hash
    """
    raw_body = await request.body()
    _verify_supabase_hook_signature(raw_body, dict(request.headers))

    try:
        payload = SupabaseEmailHookRequest.model_validate_json(raw_body)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid payload: {e}")

    user_email    = payload.user.email
    display_name  = payload.user.user_metadata.get("display_name", "")
    email_data    = payload.email_data
    action_type   = email_data.email_action_type
    redirect_to   = email_data.redirect_to or email_data.site_url or ""

    def _verify_link(token_hash: str, verify_type: str) -> str:
        return (
            f"{SUPABASE_URL}/auth/v1/verify"
            f"?token_hash={token_hash}"
            f"&type={verify_type}"
            f"&redirect_to={redirect_to}"
        )

    try:
        if action_type == "signup":
            link = _verify_link(email_data.token_hash, "signup")
            await send_verification_email(user_email, link, display_name)
            print(f"✅ Sent {action_type} email to {user_email}")

        elif action_type == "recovery":
            link = _verify_link(email_data.token_hash, "recovery")
            await send_password_reset_email(user_email, link, display_name)
            print(f"✅ Sent {action_type} email to {user_email}")

        elif action_type == "email_change":
            new_email = payload.user.new_email
            recipients_notified = []

            if email_data.token_hash_new:
                current_link = _verify_link(email_data.token_hash_new, "email_change")
                await send_email_change_email(user_email, current_link, new_email or "")
                recipients_notified.append(user_email)

            if new_email and email_data.token_hash:
                new_link = _verify_link(email_data.token_hash, "email_change")
                await send_email_change_email(new_email, new_link, new_email)
                recipients_notified.append(new_email)

            if not recipients_notified:
                raise HTTPException(
                    status_code=400,
                    detail="email_change hook payload is missing new_email/token_hash/token_hash_new",
                )

            print(f"✅ Sent {action_type} email to {recipients_notified}")

        else:
            print(f"⚠️  Unknown email_action_type: {action_type}")
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported email_action_type: {action_type}",
            )

        return {"success": True}

    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Failed to send {action_type} email to {user_email}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to send {action_type} email: {str(e)}",
        )


# ---------------------------------------------------------
# 💬 お問い合わせ（Support Tickets）エンドポイント
# ---------------------------------------------------------

class SupportUploadUrlRequest(BaseModel):
    file_name: str
    content_type: str = "application/octet-stream"


class SupportSubmitRequest(BaseModel):
    category: str
    message: str
    attachment_urls: list[str] = []
    device_info: dict = {}


@app.post("/support/request-upload-url")
async def support_request_upload_url(
    payload: SupportUploadUrlRequest,
    request: Request,
):
    """お問い合わせ添付ファイル用の署名付きアップロードURLを発行する"""
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    token = auth_header.replace("Bearer ", "").strip()

    try:
        user_client = create_client(
            SUPABASE_URL, 
            SUPABASE_PUBLISHABLE_KEY, 
            options=ClientOptions(headers={"Authorization": f"Bearer {token}"})
        )
        user_res = user_client.auth.get_user(token)
        if not user_res or not user_res.user:
            raise HTTPException(status_code=401, detail="Unauthorized user")
        uid = user_res.user.id
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Authentication failed: {str(e)}")

    from app.services.task_runners import storage_service
    upload_url, storage_path = await asyncio.to_thread(
        storage_service.generate_presigned_support_url,
        uid=uid,
        file_name=payload.file_name,
        content_type=payload.content_type,
    )
    return {"upload_url": upload_url, "storage_path": storage_path}


@app.post("/support/submit")
async def support_submit(
    payload: SupportSubmitRequest,
    request: Request,
):
    """お問い合わせ内容を受け取り、Supabase DBに保存、自動返信＆管理者へのメール通知を行う"""
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    token = auth_header.replace("Bearer ", "").strip()

    try:
        user_client = create_client(
            SUPABASE_URL, 
            SUPABASE_PUBLISHABLE_KEY, 
            options=ClientOptions(headers={"Authorization": f"Bearer {token}"})
        )
        user_res = user_client.auth.get_user(token)
        if not user_res or not user_res.user:
            raise HTTPException(status_code=401, detail="Unauthorized user")
        uid = user_res.user.id
        user_email = user_res.user.email
        display_name = (user_res.user.user_metadata or {}).get("display_name", "")
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Authentication failed: {str(e)}")

    # 1. ランダムなお問い合わせコード生成 (LFT-XXXXXX)
    import random
    import string
    random_str = "".join(random.choices(string.ascii_uppercase + string.digits, k=8))
    ticket_code = f"LFT-{random_str}"

    # 2. Supabase DB (support_tickets テーブル) へのインサート
    admin_client = get_supabase_client()
    try:
        ticket_data = {
            "ticket_code": ticket_code,
            "user_id": uid,
            "user_email": user_email,
            "category": payload.category,
            "message": payload.message,
            "attachment_urls": payload.attachment_urls,
            "device_info": payload.device_info,
            "status": "open",
        }
        await asyncio.to_thread(
            lambda: admin_client.table("support_tickets").insert(ticket_data).execute()
        )
    except Exception as e:
        print(f"❌ Failed to insert support ticket in Supabase: {e}")
        raise HTTPException(status_code=500, detail="Failed to save support ticket to database")

    # 3. ユーザーへ自動確認メールを送信 (From: support@lefture.com)
    try:
        user_html = f"""
        <h2>お問い合わせを受け付けました</h2>
        <p>{display_name or 'ユーザー'} 様</p>
        <p>leFture サポートにお問い合わせいただき、ありがとうございます。</p>
        <p>以下の内容でお問い合わせを受け付けました。</p>
        <hr style="border:none; border-top:1px solid #2A2A3A; margin:20px 0;"/>
        <p><strong>お問い合わせ番号:</strong> {ticket_code}</p>
        <p><strong>カテゴリ:</strong> {payload.category}</p>
        <p><strong>お問い合わせ内容:</strong><br/>{payload.message.replace(chr(10), '<br/>')}</p>
        <hr style="border:none; border-top:1px solid #2A2A3A; margin:20px 0;"/>
        <p>内容を確認の上、担当者より返信いたしますので、今しばらくお待ちください。</p>
        <p style="color:#8888AA; font-size:12px;">※このメールは送信専用アドレスから送信されています。</p>
        """
        from app.services.email_service import send_email
        await send_email(
            to=user_email,
            subject=f"leFture サポート - 受付完了 [{ticket_code}]",
            html=user_html,
        )
    except Exception as e:
        print(f"⚠️ Failed to send auto-reply email to user: {e}")

    # 4. 管理者へ通知メールを送信 (To: hello@lefture.com または lefture.app@gmail.com)
    # Reply-To にユーザーのメールアドレスを指定
    try:
        attachments_section = ""
        if payload.attachment_urls:
            # attachment_urls には R2 の非公開オブジェクトキー(storage_path)が入っているため、
            # そのままではメールから開けない。閲覧用の署名付きGET URLに変換して埋め込む。
            # (署名付きURLの有効期限は最大7日 = 604800秒。それを過ぎるとリンク切れになる点に注意)
            from app.core.r2_storage import storage_service
            import html as html_escape_lib
            attachments_section = "<p><strong>添付ファイル一覧:</strong></p><ul>"
            for storage_path in payload.attachment_urls:
                file_label = html_escape_lib.escape(storage_path.split("/")[-1])
                try:
                    view_url = await asyncio.to_thread(
                        storage_service.generate_presigned_get_url, storage_path
                    )
                    attachments_section += f'<li><a href="{view_url}">{file_label}</a>(リンクは7日間有効)</li>'
                except Exception as e:
                    print(f"⚠️ Failed to generate presigned URL for attachment {storage_path}: {e}")
                    attachments_section += f"<li>{file_label} (リンク生成に失敗しました。管理画面/Supabaseから直接確認してください: {html_escape_lib.escape(storage_path)})</li>"
            attachments_section += "</ul>"

        admin_html = f"""
        <h2>新しいお問い合わせを受信しました</h2>
        <p><strong>お問い合わせ番号:</strong> {ticket_code}</p>
        <p><strong>ユーザーのメールアドレス:</strong> {user_email}</p>
        <p><strong>ユーザーID:</strong> {uid}</p>
        <p><strong>カテゴリ:</strong> {payload.category}</p>
        <p><strong>お問い合わせ内容:</strong><br/>{payload.message.replace(chr(10), '<br/>')}</p>
        {attachments_section}
        <hr style="border:none; border-top:1px solid #2A2A3A; margin:20px 0;"/>
        <p><strong>デバイス情報:</strong></p>
        <pre>{json.dumps(payload.device_info, indent=2, ensure_ascii=False)}</pre>
        <hr style="border:none; border-top:1px solid #2A2A3A; margin:20px 0;"/>
        <p>※このメールにそのまま返信すると、お問い合わせの送信元（{user_email}）に直接返信が届きます。</p>
        """
        
        await send_email(
            to="lefture.app@gmail.com",
            subject=f"【要対応】お問い合わせ [{ticket_code}] (カテゴリ: {payload.category})",
            html=admin_html,
            reply_to=user_email,
        )
    except Exception as e:
        print(f"❌ Failed to send notification email to admin: {e}")

    return {"success": True, "ticket_code": ticket_code}


@app.post("/auth/delete-account")
async def auth_delete_account(request: Request):
    """ユーザーのアカウントを削除する。auth.usersから削除するため、Admin APIを呼び出す。"""
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    token = auth_header.replace("Bearer ", "").strip()

    try:
        user_client = create_client(
            SUPABASE_URL, 
            SUPABASE_PUBLISHABLE_KEY, 
            options=ClientOptions(headers={"Authorization": f"Bearer {token}"})
        )
        user_res = user_client.auth.get_user(token)
        if not user_res or not user_res.user:
            raise HTTPException(status_code=401, detail="Unauthorized user")
        uid = user_res.user.id
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Authentication failed: {str(e)}")

    admin_client = get_supabase_client()

    # 1. ユーザーが所有するDBレコード・R2上のファイルを先に完全削除する。
    #    auth.usersの削除を最後に回すことで、ここで失敗してもユーザーは
    #    まだ有効なアカウントとしてアプリから再度削除を試行できる
    #    (各削除処理はeq()で絞り込んだ削除のため、再実行しても安全)。
    try:
        await _hard_delete_user_data(admin_client, uid)
    except Exception as e:
        print(f"❌ Failed to hard-delete user data for {uid}: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete account data from server")

    # 2. 最後にAdmin APIでauth.usersから削除
    try:
        await asyncio.to_thread(
            lambda: admin_client.auth.admin.delete_user(uid)
        )
    except Exception as e:
        print(f"❌ Failed to delete user {uid} using admin client: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete account from server")

    print(f"👤 Deleted user account: {uid}")
    return {"success": True}