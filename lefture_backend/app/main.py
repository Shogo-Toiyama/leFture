import os
import json
import time
import uuid
import asyncio
from typing import Optional
from urllib.parse import urlencode
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from fastapi import FastAPI, HTTPException, UploadFile, Request, File, Form, Header
from supabase import create_client, ClientOptions
from nltk.tokenize import sent_tokenize
from pydantic import BaseModel
from google.cloud import tasks_v2
from google.api_core.exceptions import AlreadyExists
from standardwebhooks.webhooks import Webhook, WebhookVerificationError

# チャンクenqueue専用の時間バケット。receive_transcribe_chunkにはenqueue前の
# アトミックなDBステータス遷移ガードが無い(クライアントの再送がそのまま二重
# enqueueになり得る)ため、ここだけはCloud Tasks側の名前重複チェックで
# 「ごく短時間の重複投入」を弾く必要がある。
# ★ DAGタスク(enqueue_task)側では使わない: あちらは呼び出し前に必ず
# `.eq("status", "PENDING"/"WAITING")` のアトミック更新で1回勝った呼び出しだけが
# enqueue_taskへ進む設計のため、この粗い時間バケットをタスク名に混ぜると、
# CHECK_AND_ASSEMBLEが待機→即座に再起床するような正当な後続呼び出しまで同じ
# バケットに落ちてCloud Tasks側でAlreadyExists扱いになり、実際には一度も
# 実行されないままQUEUEDで固まる不具合を起こした(該当タスクは既に完了して
# キューから消えているにもかかわらず、同名タスクは完了後 約1時間 再利用できない
# というCloud Tasksの制約に引っかかる)。
TASK_DEDUP_WINDOW_SECONDS = 30

def _dedup_bucket() -> int:
    return int(time.time() // TASK_DEDUP_WINDOW_SECONDS)

# processing_jobs の「もう自力では二度と進まない」終端ステータス。
# COMPLETED以外を一括で「進行中」とみなしてはいけない —— 一度FAILEDになった
# ジョブが残っているだけで、その後アップロードが成功して自動発火した
# /start-analysis が「Analysis already in progress」の冪等no-opを返してしまい、
# 音声は揃っているのに分析が永久に始まらない状態になっていた(電波の弱い場所で
# 実際に発生)。ERRORは旧pipeline.py(JobStatus.ERROR)が書く値、CANCELLEDは
# 講義削除時に /lectures/{id}/cancel-jobs が書く値。
DEAD_JOB_STATUSES = ("FAILED", "ERROR", "CANCELLED")

# 古いジョブを打ち切る際に CANCELLED へ落とすタスクのステータス。
# WAITINGを必ず含めること —— CHECK_AND_ASSEMBLEはチャンクが揃うまで通常のDAG
# 状態機械に含まれないWAITINGで待機するため、ここから漏らすと打ち切ったはずの
# 古いジョブのタスクがPatrol(_patrol_wake_waiting_check_and_assemble)に叩き
# 起こされ、新しいジョブの書き込みと衝突する。
CANCELLABLE_TASK_STATUSES = ["PENDING", "QUEUED", "WAITING", "RUNNING", "FAILED"]

from app.core.supabase import get_supabase_client
from app.services.helpers.credits import CREDITS_PER_USD
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
    run_fun_fact_brainstorming_task,
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


@app.get("/health")
async def health_check():
    """
    Cloud Runのコールドスタートをクライアント側から事前に吸収するためのウォームアップ用
    エンドポイント。DB/外部APIアクセスは一切行わず、プロセスが起動していれば即座に返す。
    """
    return {"status": "ok"}


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
SUBSCRIPTION_QUEUE_NAME = os.getenv("SUBSCRIPTION_QUEUE_NAME", "lefture-subscription-queue")
CLEANUP_QUEUE_NAME = os.getenv("CLEANUP_QUEUE_NAME", "lefture-maintenance-queue")
AUDIO_CHUNKS_RETENTION_DAYS = int(os.getenv("AUDIO_CHUNKS_RETENTION_DAYS", "7"))
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
PATROL_TIME_WINDOW_TOLERANCE_MINUTES = int(os.getenv("PATROL_TIME_WINDOW_TOLERANCE_MINUTES", "2")) # Cloud Schedulerは10分おきに叩くが、DB周回を伴う本チェックは0分・30分付近のみ実行(それ以外はウォームアップのみ)。配信遅延の許容幅
PATROL_DAILY_HOUR_UTC = int(os.getenv("PATROL_DAILY_HOUR_UTC", "0")) # サブスク更新など「1日1回」でよいPatrolチェックを走らせるUTC時(0-23)
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

class RenewSubscriptionPayload(BaseModel):
    """Cloud Tasks から /worker/renew-subscription に渡されるデータ"""
    mapping_id: str

class CleanupAudioChunksPayload(BaseModel):
    """Cloud Tasks から /worker/cleanup-audio-chunks に渡されるデータ"""
    user_id: str
    lecture_id: str

class ClaimPlanRequest(BaseModel):
    """Flutterから /billing/claim-plan に渡されるデータ。claim_mode='self_serve'の
    プランのみ有効化できる(store_purchaseプランはここでは弾かれる)。"""
    plan_id: str

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
    # 録音言語(lectures.recording_language)。未設定(None)ならWhisperの自動言語判定に任せる。
    language: str | None = None

class MasterAudioUploadUrlRequest(BaseModel):
    lecture_id: str

class MasterAudioUploadCompleteRequest(BaseModel):
    lecture_id: str

class AsrModelDownloadUrlRequest(BaseModel):
    model_id: str


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

    # 3.4 クレジット残高ゲート: 新規ジョブの受付だけをブロックする。
    # 実際の消費(consume_credits)は各タスク完了後の事後計測なので、進行中の
    # ジョブがこの時点より後に残高を0以下にしても最後まで実行され続ける
    # (オーバードラフト許容)。ここではあくまで「新しいジョブを始めさせない」
    # ゲートとしてだけ使う。
    #
    # credit_balanceがNULL(=user_credit_balancesに行が無い=一度もgrant_creditsが
    # 呼ばれていない、プラン未割当)と0以下(=割り当てられたが使い切った)は
    # Flutter側での見せ方が変わるはずなのでerror_codeで区別できるようにしておく。
    # user_credit_balancesはRLS有効・ポリシー無しでクライアントから直接触れない
    # 専用テーブル(user_profilesはFlutterから直接書き換え可能なため、課金情報は
    # 絶対に置かない)。
    credit_res = await asyncio.to_thread(
        lambda: admin_client.table("user_credit_balances").select("credit_balance").eq("user_id", user_id).maybe_single().execute()
    )
    credit_balance = (credit_res.data or {}).get("credit_balance") if credit_res.data else None
    if credit_balance is None:
        raise HTTPException(
            status_code=402,
            detail={
                "error_code": "NO_CREDIT_ALLOCATION",
                "message": "No credit plan has been assigned to this account yet.",
            },
        )
    if credit_balance <= 0:
        raise HTTPException(
            status_code=402,
            detail={
                "error_code": "INSUFFICIENT_CREDITS",
                "message": "Insufficient credits to start a new analysis job.",
                "credit_balance": credit_balance,
            },
        )

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
        lambda: admin_client.table("processing_jobs").select("id, status, expected_chunks")
            .eq("lecture_id", payload.lecture_id).neq("status", "COMPLETED")
            .order("created_at", desc=True).execute()
    )
    old_jobs = old_jobs_res.data or []

    # force=False(自動発火)で「まだ生きている」jobがある場合は、新規作成せず既存
    # jobを冪等に返す。アップロード完了直後の自動発火は、チャンクのアップロード
    # リトライ(クライアント側は成功をACKできず再送するが、サーバー側は既に
    # 成功しているケース)によって複数回呼ばれ得るため、ここでガードしないと
    # 同じlectureに対して二重にjob/taskが作られてしまう(過去に実際に発生した)。
    #
    # ★ 判定対象は「生きているjob」だけに限る(DEAD_JOB_STATUSESは除外)。
    # 通信が不安定な環境では「音声のアップロードが終わる前に手動でStart Analysis
    # → TRANSCRIBE_MASTERがaudio_path無しでFAILED」が起き、その後アップロードが
    # 成功して自動発火しても、このガードがFAILEDジョブを「進行中」とみなして
    # no-opを返し続けるため、分析が二度と始まらなくなっていた。
    # 「Start Over」ボタン等、ユーザーが明示的に再実行を選んだ場合はforce=Trueで
    # 呼ばれ、生きているjobごとキャンセル→新規作成する。
    active_jobs = [j for j in old_jobs if j.get("status") not in DEAD_JOB_STATUSES]
    if active_jobs and not payload.force:
        existing_job_id = active_jobs[0]["id"]
        print(f"⏭️ Active job already exists for lecture {payload.lecture_id} ({existing_job_id}). Returning existing job (idempotent no-op).")
        return {"message": "Analysis already in progress", "job_id": existing_job_id}

    # 3.7 古いjobのタスクを無効化する。
    # R2上のパスは {uid}/{lecture_id}/... のみで組まれておりjob_idを含まないため、
    # 古いjobのタスクが後から（Cloud Tasksの遅延リトライ等で）動き出すと、新しいjobの
    # 書き込みと衝突してデータが壊れる。CANCELLEDは orchestrator/patrol のどちらも
    # 拾わない終端ステータスなので、これだけで再開を防げる。
    # ★ FAILEDジョブから作り直す場合(上のactive_jobs判定を通過したケース)も必ず
    # ここを通すこと —— FAILEDなのはジョブ全体であって、個々のタスクにはまだ
    # QUEUED/WAITINGのまま生き残っているものがあり得る。
    for old_job in old_jobs:
        await asyncio.to_thread(
            lambda old_job=old_job: admin_client.table("processing_tasks").update({
                "status": "CANCELLED",
                "updated_at": datetime.now().isoformat(),
            }).eq("job_id", old_job["id"]).in_(
                "status", CANCELLABLE_TASK_STATUSES
            ).execute()
        )
        # 親ジョブ自体もCANCELLEDにする。これをしないと、Flutter側の
        # watchJob(最新1件を見る)やPatrol(PENDING/RUNNINGを拾う)から見て
        # 古いジョブが「まだ生きている」ように見え続ける。
        await asyncio.to_thread(
            lambda old_job=old_job: admin_client.table("processing_jobs").update({
                "status": "CANCELLED",
                "updated_at": datetime.now().isoformat(),
            }).eq("id", old_job["id"]).neq("status", "COMPLETED").execute()
        )

    # 3.8 expected_chunks(＝CHECK_AND_ASSEMBLEが待つチャンク数)を決める。
    # ★ 絶対に「今アップロード済みの件数」だけで決めてはいけない。電波が弱く
    # 12個中5個しか届いていない状態で手動起動されると、CHECK_AND_ASSEMBLEが
    # 「5/5揃った」と誤判定し、講義の前半だけで分析を完了してしまう(エラーに
    # ならず静かに欠落するため、一番たちが悪い)。
    # 3つの情報源の最大値を採ることで、expected_chunksが実績より小さくなること
    # だけは構造的に起こらないようにする:
    #   1. payload.expected_chunks … クライアントのローカルDBが持つ録音実績。最も信頼できる
    #   2. 過去jobのexpected_chunks … 別端末からの起動などで1が0のときの引き継ぎ
    #   3. lecture_transcriptsの実件数 … 上2つが無いときの最終フォールバック
    # 実際より大きい値になった場合は、CHECK_AND_ASSEMBLEが揃うまで待機し続ける
    # (＝アップロードの再開を待つ)だけで、詰まったチャンクは_recover_stuck_chunks
    # が回収するため、小さすぎる方向に倒すよりはるかに安全。
    count_res = await asyncio.to_thread(
        lambda: admin_client.table("lecture_transcripts")
            .select("id", count="exact")
            .eq("lecture_id", payload.lecture_id)
            .execute()
    )
    transcript_count = count_res.count or 0
    previous_expected = max(
        (j.get("expected_chunks") or 0 for j in old_jobs),
        default=0,
    )
    expected_chunks = max(payload.expected_chunks, previous_expected, transcript_count)

    is_realtime = expected_chunks > 0
    if expected_chunks != payload.expected_chunks:
        print(
            f"📐 expected_chunks adjusted for lecture {payload.lecture_id}: "
            f"payload={payload.expected_chunks}, previous_job={previous_expected}, "
            f"transcript_rows={transcript_count} → {expected_chunks}"
        )

    first_task = "CHECK_AND_ASSEMBLE" if is_realtime else "TRANSCRIBE_MASTER"

    # 4. 親ジョブを作成 (processing_jobs)
    job_data = {
      "lecture_id": payload.lecture_id,
      "user_id": user_id,
      "expected_chunks": expected_chunks,
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

        # Phase 6-B: Fun Fact (種出し -> 検索 -> 生成の3段階)
        {"task_type": "FUN_FACT_BRAINSTORMING", "dependencies": ["CORE_EXTRACTION"]}, # 選ばれたトピック/概念があれば走れる
        {"task_type": "FUN_FACT_SEARCH", "dependencies": ["FUN_FACT_BRAINSTORMING"]}, # 検索ワードだけあれば走れる
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
# 💳 課金: self_serveプランの選択・有効化
# ---------------------------------------------------------
# TODO: claim_mode='store_purchase'のプラン用に、Google Play/App Storeの
# 購入トークン・レシートをサーバー側で検証してからgrant_creditsに合流させる
# /billing/verify-google-purchase と /billing/verify-apple-purchase を実装する。
# クライアントが送ってきた購入情報をそのまま信用せず、必ずGoogle Play
# Developer API / App Store Server APIに問い合わせて真正性を確認すること。
@app.post("/billing/claim-plan")
async def claim_plan(payload: ClaimPlanRequest, request: Request):
    """
    claim_mode='self_serve'のプラン(現状はβ特別プランのみ)をユーザー自身が
    選択・有効化するためのエンドポイント。user_idは必ずJWTから復元し、
    リクエストボディからは絶対に受け取らない(なりすまし防止)。
    実際の検証(プランの有効性・claim_mode・二重claim防止)は全て
    claim_plan() SQL関数側でアトミックに行う。
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

    try:
        await asyncio.to_thread(
            lambda: admin_client.rpc(
                "claim_plan", {"p_user_id": user_id, "p_plan_id": payload.plan_id}
            ).execute()
        )
    except Exception as e:
        error_str = str(e)
        if "plan_not_found" in error_str:
            raise HTTPException(status_code=404, detail={"error_code": "PLAN_NOT_FOUND", "message": "Plan not found."})
        if "plan_not_self_serve" in error_str:
            raise HTTPException(status_code=403, detail={"error_code": "PLAN_NOT_SELF_SERVE", "message": "This plan cannot be claimed directly."})
        if "plan_expired" in error_str:
            raise HTTPException(status_code=410, detail={"error_code": "PLAN_EXPIRED", "message": "This plan is no longer available."})
        if "plan_already_claimed" in error_str or "duplicate key" in error_str:
            raise HTTPException(status_code=409, detail={"error_code": "PLAN_ALREADY_CLAIMED", "message": "This plan has already been claimed."})
        raise HTTPException(status_code=500, detail=f"Failed to claim plan: {e}")

    return {"status": "success", "plan_id": payload.plan_id}


@app.get("/billing/plans")
async def billing_plans(request: Request):
    """
    今claimできる(claim_mode='self_serve'かつ無効化されていない)プラン一覧。
    Flutter側にplan_idをハードコードさせないための一覧取得エンドポイント。
    店舗課金(claim_mode='store_purchase')のプランはここには含めない
    (ストアの購入フロー経由でのみ有効化されるべきなので)。
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

    admin_client = get_supabase_client()

    # disabled_atの絞り込みはPostgRESTのor=フィルタ文字列に頼らず、ここで
    # 判定する(タイムゾーンオフセット付きISO文字列の'+'がURLエンコード時に
    # 空白と誤解釈されるリスクを避けるため。プラン数は少ないので問題ない)。
    plans_res = await asyncio.to_thread(
        lambda: admin_client.table("subscription_plans")
            .select("id, name, monthly_credit_amount, price_usd, billing_interval_months, disabled_at")
            .eq("claim_mode", "self_serve")
            .execute()
    )

    now = datetime.now(timezone.utc)
    claimable = []
    for plan in (plans_res.data or []):
        disabled_at = plan.get("disabled_at")
        if disabled_at and datetime.fromisoformat(disabled_at) <= now:
            continue
        plan.pop("disabled_at", None)
        claimable.append(plan)

    return {"plans": claimable}


@app.get("/billing/summary")
async def billing_summary(request: Request):
    """
    Flutter側のクレジット表示(プログレスバー・詳細ページ)向けの一括サマリー。
    user_credit_balances/credit_grants/user_subscription_mappingsはどれも
    RLSでクライアントから直接触れない専用テーブルなので、必ずこのエンドポイント
    経由で取得させる。credits_per_usdも一緒に返すことで、Flutter側が
    しきい値計算(例: Realtime可否の$0.1判定)のために自前でハードコードした
    レートを持たずに済むようにする。
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

    summary_res = await asyncio.to_thread(
        lambda: admin_client.rpc("get_credit_summary", {"p_user_id": user_id}).execute()
    )
    row = (summary_res.data or [{}])[0] if summary_res.data else {}

    return {
        "credit_balance": row.get("credit_balance"),
        "monthly_allocation": row.get("monthly_allocation"),
        "extra_credit_balance": row.get("extra_credit_balance"),
        "has_active_plan": bool(row.get("has_active_plan")),
        "current_period_end": row.get("current_period_end"),
        "credits_per_usd": CREDITS_PER_USD,
    }


@app.get("/billing/history")
async def billing_history(request: Request):
    """
    クレジット利用履歴のエンドポイント (累積残量差分方式)。
    古い順に残量(balance_after)の表示用クレジット変化額を追跡・計算することで、
    履歴の合計と画面上の現在の残量数値が100%一致するように保証する。
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
    user_res = await asyncio.to_thread(lambda: user_client.auth.get_user(token))
    if not user_res or not user_res.user:
        raise HTTPException(status_code=401, detail="Unauthorized user")
    user_id = user_res.user.id

    admin_client = get_supabase_client()

    try:
        tx_res = await asyncio.to_thread(
            lambda: admin_client.table("credit_transactions")
                .select("id, created_at, delta, balance_after, reason")
                .eq("user_id", user_id)
                .order("created_at", desc=False)
                .limit(500)
                .execute()
        )

        transactions = tx_res.data or []
        if not transactions:
            return {"history": []}

        MICRO_PER_CREDIT = 1000000
        now = datetime.now(timezone.utc)
        today = now.date()

        negative_hourly_buckets = {}
        positive_items = []
        prev_display_balance = None

        for tx in transactions:
            created_at_str = tx.get("created_at")
            balance_after_raw = tx.get("balance_after")
            if not created_at_str or balance_after_raw is None:
                continue

            try:
                delta = int(tx.get("delta") or 0)
                balance_after = int(balance_after_raw)
            except (ValueError, TypeError):
                continue

            reason_raw = tx.get("reason") or "USAGE"
            reason = str(reason_raw) if not isinstance(reason_raw, (dict, list)) else "USAGE"
            tx_id = tx.get("id")

            try:
                dt = datetime.fromisoformat(str(created_at_str).replace("Z", "+00:00"))
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                else:
                    dt = dt.astimezone(timezone.utc)
            except Exception:
                continue

            curr_display_balance = balance_after // MICRO_PER_CREDIT

            if delta < 0:
                hour_key = dt.strftime("%Y-%m-%d %H:00")
                if hour_key not in negative_hourly_buckets:
                    start_balance = prev_display_balance if prev_display_balance is not None else ((balance_after - delta) // MICRO_PER_CREDIT)
                    negative_hourly_buckets[hour_key] = {
                        "start_display_balance": start_balance,
                        "end_display_balance": curr_display_balance,
                        "reasons": {reason},
                        "sample_time": dt,
                    }
                else:
                    negative_hourly_buckets[hour_key]["end_display_balance"] = curr_display_balance
                    negative_hourly_buckets[hour_key]["reasons"].add(reason)
                    negative_hourly_buckets[hour_key]["sample_time"] = dt

            elif delta > 0:
                start_balance = prev_display_balance if prev_display_balance is not None else ((balance_after - delta) // MICRO_PER_CREDIT)
                delta_credits = curr_display_balance - start_balance
                if delta_credits <= 0:
                    delta_credits = round(delta / MICRO_PER_CREDIT)
                    if delta_credits <= 0:
                        delta_credits = 1

                positive_items.append({
                    "id": str(tx_id) if tx_id else dt.isoformat(),
                    "dt": dt,
                    "delta_credits": delta_credits,
                    "reason": reason,
                })

            prev_display_balance = curr_display_balance

        all_entries = []

        for hour_key, bdata in negative_hourly_buckets.items():
            sample_time = bdata["sample_time"]
            start_bal = bdata["start_display_balance"]
            end_bal = bdata["end_display_balance"]
            reasons = list(bdata["reasons"])

            delta_credits = end_bal - start_bal
            if delta_credits >= 0:
                delta_credits = -1

            sample_date = sample_time.date()
            if sample_date == today:
                date_label = "Today"
            elif sample_date == today - timedelta(days=1):
                date_label = "Yesterday"
            else:
                date_label = sample_time.strftime("%b %d")

            time_label = sample_time.strftime("%I %p").lstrip("0")

            all_entries.append({
                "dt": sample_time,
                "item": {
                    "id": hour_key,
                    "date_label": date_label,
                    "time_label": time_label,
                    "timestamp": sample_time.isoformat(),
                    "delta_credits": delta_credits,
                    "formatted_delta": f"{delta_credits}",
                    "is_positive": False,
                    "reason_summary": ", ".join(reasons) if reasons else "Usage",
                }
            })

        for p in positive_items:
            dt = p["dt"]
            delta_credits = p["delta_credits"]
            reason = p["reason"]

            sample_date = dt.date()
            if sample_date == today:
                date_label = "Today"
            elif sample_date == today - timedelta(days=1):
                date_label = "Yesterday"
            else:
                date_label = dt.strftime("%b %d")

            time_label = dt.strftime("%I %p").lstrip("0")

            all_entries.append({
                "dt": dt,
                "item": {
                    "id": p["id"],
                    "date_label": date_label,
                    "time_label": time_label,
                    "timestamp": dt.isoformat(),
                    "delta_credits": delta_credits,
                    "formatted_delta": f"+{delta_credits}",
                    "is_positive": True,
                    "reason_summary": reason,
                }
            })

        all_entries.sort(key=lambda x: x["dt"], reverse=True)
        history_items = [entry["item"] for entry in all_entries]

        return {"history": history_items}
    except Exception as e:
        logger.error(f"Error processing billing history: {e}", exc_info=True)
        return {"history": []}


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
        language=payload.language,
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
# 🎙️ オンデバイスASR(sherpa_onnx)のモデル配布
# ---------------------------------------------------------
def _authenticate_request(request: Request) -> str:
    """AuthorizationヘッダのJWTを検証し、user_idを返す。R2上のASRモデル自体は
    ユーザーに紐付かない共有アセットだが、他エンドポイントと同様ログイン済み
    ユーザーからの呼び出しであることだけは確認しておく。"""
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
        return user_res.user.id
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Authentication failed: {str(e)}")


@app.post("/asr-models/manifest")
async def get_asr_models_manifest(request: Request):
    """録音言語ごとのオンデバイスASRモデル一覧(engineCompatVersion/modelVersion
    込みのマニフェスト)を返す。R2の asr_models/manifest.json をそのまま返すだけ。"""
    _authenticate_request(request)

    from app.core.r2_storage import storage_service
    try:
        raw = await asyncio.to_thread(storage_service.download_binary, "asr_models/manifest.json")
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Manifest not found: {str(e)}")
    return json.loads(raw)


@app.post("/asr-models/download-url")
async def get_asr_model_download_url(payload: AsrModelDownloadUrlRequest, request: Request):
    """指定model_idのtar.gzを取得するための署名付きGET URLをその場で発行する。
    署名URLには最大7日の有効期限があるため、マニフェストに埋め込まず毎回発行する。"""
    _authenticate_request(request)

    from app.core.r2_storage import storage_service
    try:
        raw = await asyncio.to_thread(storage_service.download_binary, "asr_models/manifest.json")
        manifest = json.loads(raw)
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Manifest not found: {str(e)}")

    valid_model_ids = {lang["modelId"] for lang in manifest.get("languages", {}).values()}
    if manifest.get("vad"):
        valid_model_ids.add(manifest["vad"]["modelId"])
    if manifest.get("whisper"):
        valid_model_ids.add(manifest["whisper"]["modelId"])
    if payload.model_id not in valid_model_ids:
        raise HTTPException(status_code=404, detail=f"Unknown model_id: {payload.model_id}")

    url = await asyncio.to_thread(
        storage_service.generate_presigned_get_url,
        f"asr_models/{payload.model_id}.tar.gz",
    )
    return {"url": url, "expires_in": 604800}


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
    "FUN_FACT_BRAINSTORMING": "/worker/fun-fact-brainstorming",
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
    # name は呼び出しごとに一意にする。二重enqueue防止は呼び出し元(orchestrator_webhook /
    # _maybe_wake_check_and_assemble / 各patrol関数)がenqueue_task呼び出し前に必ず行う
    # アトミックなDBステータス遷移(`.eq("status", "PENDING"/"WAITING")`)で担保済みのため、
    # ここでさらに時間バケットで名前を固定すると、CHECK_AND_ASSEMBLEのように短時間で
    # 「待機→再起床」を繰り返すタスクの正当な再enqueueまでCloud Tasks側の名前重複
    # チェック(AlreadyExists、しかも完了後 約1時間 再利用不可)でブロックしてしまう。
    task = {
        "name": client.task_path(PROJECT_ID, REGION, QUEUE_NAME, f"task-{payload.task_id}-{uuid.uuid4().hex[:12]}"),
        # ★ 未指定だとCloud Tasks側のデフォルト(10分)が使われ、TRANSCRIBE_MASTERのような
        # 長時間タスクだとCloud Run/Modal側がまだ待っている途中でCloud Tasksが先に
        # 見切りをつけてしまう(呼び出し元切断としてModal側にキャンセルが伝播し得る)。
        # requests.postのtimeout(1800秒、transcription.py)・Modalのtimeout(1800秒、
        # whisper_deploy_api.py)と揃える。HTTPターゲットタスクの上限も1800秒(30分)。
        "dispatch_deadline": timedelta(seconds=1800),
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
    language: str | None = None,
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
        "language": language,
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
# 💳 サブスクリプション月次更新専用のenqueue（DAG/チャンクとは別キュー）
# ---------------------------------------------------------
async def enqueue_renew_subscription_task(mapping_id: str) -> None:
    """
    /worker/renew-subscription を叩くCloud Tasksタスクをenqueueする。
    請求処理のバーストが講義処理のキューに影響しないよう、専用の
    SUBSCRIPTION_QUEUE_NAME を使う。

    name は mapping_id + 当日の日付から決定的に組み立てる。/maintenance/
    renew-subscriptions が万一同じ日に2回呼ばれても、Cloud Tasks側の名前
    重複チェックで二重enqueueを弾ける(実際の冪等性はrenew_subscription()
    SQL関数側の行ロック+期間チェックで担保済みだが、Cloud Tasksへの
    不要な積み増し自体も避けたいため二重に防御している)。
    """
    if not (PROJECT_ID and CLOUD_RUN_URL and SERVICE_ACCOUNT_EMAIL):
        raise RuntimeError("❌ Missing Environment Variables for Cloud Tasks enqueue!")

    parent = client.queue_path(PROJECT_ID, REGION, SUBSCRIPTION_QUEUE_NAME)

    worker_payload = {"mapping_id": mapping_id}
    today_str = datetime.now(timezone.utc).strftime("%Y%m%d")

    task = {
        "name": client.task_path(PROJECT_ID, REGION, SUBSCRIPTION_QUEUE_NAME, f"renew-{mapping_id}-{today_str}"),
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": f"{CLOUD_RUN_URL}/worker/renew-subscription",
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
        print(f"✅ Enqueued renew_subscription for mapping {mapping_id} to Cloud Tasks: {response.name}")
    except AlreadyExists:
        print(f"⏭️ Renewal for mapping {mapping_id} already enqueued today (duplicate request ignored).")


async def enqueue_cleanup_audio_chunks_task(user_id: str, lecture_id: str) -> None:
    """
    /worker/cleanup-audio-chunks を叩くCloud Tasksタスクをenqueueする。
    1日1回のパトロール(_patrol_enqueue_audio_chunks_cleanup)で実行され、
    同一日・同一講義の二重処理を防ぐ。
    """
    if not (PROJECT_ID and CLOUD_RUN_URL and SERVICE_ACCOUNT_EMAIL):
        raise RuntimeError("❌ Missing Environment Variables for Cloud Tasks enqueue!")

    parent = client.queue_path(PROJECT_ID, REGION, CLEANUP_QUEUE_NAME)
    worker_payload = {"user_id": user_id, "lecture_id": lecture_id}
    today_str = datetime.now(timezone.utc).strftime("%Y%m%d")

    task = {
        "name": client.task_path(PROJECT_ID, REGION, CLEANUP_QUEUE_NAME, f"cleanup-chunks-{lecture_id}-{today_str}"),
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": f"{CLOUD_RUN_URL}/worker/cleanup-audio-chunks",
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
        print(f"✅ Enqueued cleanup_audio_chunks for lecture {lecture_id} to Cloud Tasks: {response.name}")
    except AlreadyExists:
        print(f"⏭️ Cleanup for lecture {lecture_id} already enqueued today (duplicate request ignored).")


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

@app.post("/worker/fun-fact-brainstorming")
async def worker_fun_fact_brainstorming(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_fun_fact_brainstorming_task)

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


@app.post("/worker/renew-subscription")
async def worker_renew_subscription(payload: RenewSubscriptionPayload):
    """
    /maintenance/renew-subscriptions がenqueueしたタスクを実際に処理する。
    renew_subscription() SQL関数側が行ロック+期間チェックで冪等性を担保しているので、
    ここは失敗したら単に例外を再送出してCloud Tasksの自動リトライに任せるだけでよい。
    """
    admin_client = get_supabase_client()
    await asyncio.to_thread(
        lambda: admin_client.rpc("renew_subscription", {"p_mapping_id": payload.mapping_id}).execute()
    )
    return {"status": "success"}


@app.post("/worker/cleanup-audio-chunks")
async def worker_cleanup_audio_chunks(payload: CleanupAudioChunksPayload):
    """
    _patrol_enqueue_audio_chunks_cleanup がenqueueしたタスクを実際に処理する。
    指定講義の R2 audio_chunks/ 配下を一括削除し、
    lectures テーブルの metadata (jsonb) に audio_chunks_cleaned: True を記録する。
    """
    admin_client = get_supabase_client()
    from app.core.r2_storage import storage_service

    # 1. R2 の audio_chunks/ 配下を全削除
    prefix = f"{payload.user_id}/{payload.lecture_id}/audio_chunks/"
    deleted_count = await asyncio.to_thread(storage_service.delete_prefix, prefix)
    print(f"🧹 Cleaned up {deleted_count} audio chunks in R2 for lecture {payload.lecture_id}")

    # 2. Supabase の lectures.metadata にフラグをマージ更新
    lec_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures")
            .select("metadata")
            .eq("id", payload.lecture_id)
            .maybe_single()
            .execute()
    )

    current_metadata = (lec_res.data or {}).get("metadata") or {}
    current_metadata["audio_chunks_cleaned"] = True
    current_metadata["audio_chunks_cleaned_at"] = datetime.now(timezone.utc).isoformat()

    await asyncio.to_thread(
        lambda: admin_client.table("lectures")
            .update({"metadata": current_metadata})
            .eq("id", payload.lecture_id)
            .execute()
    )
    return {"status": "success", "deleted_chunks": deleted_count}


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
#
# Cloud Schedulerの呼び出し間隔自体は10分(コールドスタート防止のウォームアップ目的)。
# DB周回を伴うPATROL_CHECKS本体は0分・30分付近(PATROL_TIME_WINDOW_TOLERANCE_MINUTES)
# でのみ実行し、それ以外の呼び出しは起こすだけで何もしない。将来「1日1回でよいタスク」等
# 頻度の異なるタスクを増やす場合も、新しいCloud Schedulerジョブを作らず、この関数内で
# 現在時刻を見て分岐を増やす形にする(Cloud Schedulerの無料枠が3ジョブまでのため)。

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


async def _hard_delete_course(admin_client, uid: str, course_id: str) -> None:
    """
    コース1件を、配下の講義(_hard_delete_lectureで完全削除)・トピックマップ・
    コース本体とともに完全に削除する。講義側と同じ方針で、Supabase側の
    ON DELETE CASCADEに依存せず明示的に子→親の順で削除する。
    1件でも講義の削除に失敗したら例外を上げ、部分的に消えた状態を「成功」として
    隠さない(呼び出し元でユーザーにエラーを見せる)。
    """
    lectures_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures").select("id").eq("user_id", uid).eq("course_id", course_id).execute()
    )
    for row in (lectures_res.data or []):
        await _hard_delete_lecture(admin_client, uid, row["id"])

    await asyncio.to_thread(
        lambda: admin_client.table("topic_maps").delete().eq("course_id", course_id).execute()
    )

    await asyncio.to_thread(
        lambda: admin_client.table("courses").delete().eq("id", course_id).eq("user_id", uid).execute()
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


@app.post("/lectures/{lecture_id}/cancel-jobs")
async def cancel_lecture_jobs_endpoint(lecture_id: str, request: Request):
    """
    指定講義の未完了ジョブとそのタスクをすべてCANCELLEDにする。
    Flutterが講義をゴミ箱に入れた直後にbest-effortで呼ぶ。

    これが無いと、削除した講義のパイプラインがサーバー側で走り続け、削除の
    カスケード論理削除(削除時点で存在したコンテンツだけが対象)をすり抜けた
    Review Card / Fun Fact などが deleted_at=null の新規行として後から生成され、
    「削除したはずの講義に全コンテンツが結びつく」状態になっていた。
    クレジットも無駄に消費される。

    ハードデリート(_hard_delete_lecture)と違い、行そのものは消さない ——
    ゴミ箱からの復元後に「Start Analysis」でやり直せるようにするため。
    CANCELLEDはorchestrator/patrolのどちらも拾わない終端ステータスであり、
    /start-analysisのDEAD_JOB_STATUSESにも含まれるので、復元後の再実行は
    force無しでも新規ジョブとして通る。
    """
    uid = _authenticate_request(request)
    admin_client = get_supabase_client()

    lec_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures")
            .select("id, user_id")
            .eq("id", lecture_id)
            .maybe_single()
            .execute()
    )
    lecture = lec_res.data if lec_res else None
    if not lecture or lecture["user_id"] != uid:
        raise HTTPException(status_code=404, detail="Lecture not found")

    jobs_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").select("id")
            .eq("lecture_id", lecture_id).neq("status", "COMPLETED").execute()
    )
    job_ids = [j["id"] for j in (jobs_res.data or [])]

    for job_id in job_ids:
        await asyncio.to_thread(
            lambda job_id=job_id: admin_client.table("processing_tasks").update({
                "status": "CANCELLED",
                "updated_at": datetime.now().isoformat(),
            }).eq("job_id", job_id).in_("status", CANCELLABLE_TASK_STATUSES).execute()
        )
        await asyncio.to_thread(
            lambda job_id=job_id: admin_client.table("processing_jobs").update({
                "status": "CANCELLED",
                "updated_at": datetime.now().isoformat(),
            }).eq("id", job_id).neq("status", "COMPLETED").execute()
        )

    print(f"🛑 Cancelled {len(job_ids)} job(s) for lecture {lecture_id}")
    return {"success": True, "cancelled_jobs": len(job_ids)}


@app.post("/lectures/{lecture_id}/hard-delete")
async def hard_delete_lecture_endpoint(lecture_id: str, request: Request):
    """
    ゴミ箱(Trash)に入っている講義1件を完全削除する。
    Supabase側のカスケード設定に依存せず、_hard_delete_lecture が
    子テーブル・R2ファイルまで含めて明示的に削除する。
    """
    uid = _authenticate_request(request)
    admin_client = get_supabase_client()

    lec_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures")
            .select("id, user_id, deleted_at")
            .eq("id", lecture_id)
            .maybe_single()
            .execute()
    )
    lecture = lec_res.data if lec_res else None
    if not lecture or lecture["user_id"] != uid:
        raise HTTPException(status_code=404, detail="Lecture not found")
    if lecture["deleted_at"] is None:
        raise HTTPException(status_code=409, detail="Lecture is not in trash")

    try:
        await _hard_delete_lecture(admin_client, uid, lecture_id)
    except Exception as e:
        print(f"❌ Failed to hard-delete lecture {lecture_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete lecture")

    return {"success": True}


@app.post("/courses/{course_id}/hard-delete")
async def hard_delete_course_endpoint(course_id: str, request: Request):
    """ゴミ箱に入っているコース1件を、配下の講義ごと完全削除する。"""
    uid = _authenticate_request(request)
    admin_client = get_supabase_client()

    course_res = await asyncio.to_thread(
        lambda: admin_client.table("courses")
            .select("id, user_id, deleted_at")
            .eq("id", course_id)
            .maybe_single()
            .execute()
    )
    course = course_res.data if course_res else None
    if not course or course["user_id"] != uid:
        raise HTTPException(status_code=404, detail="Course not found")
    if course["deleted_at"] is None:
        raise HTTPException(status_code=409, detail="Course is not in trash")

    try:
        await _hard_delete_course(admin_client, uid, course_id)
    except Exception as e:
        print(f"❌ Failed to hard-delete course {course_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete course")

    return {"success": True}


@app.post("/trash/empty")
async def empty_trash_endpoint(request: Request):
    """
    呼び出したユーザーのゴミ箱を一括で完全削除する。
    Patrol(_patrol_hard_delete_expired_lectures)と同じく、1件ごとに
    try/exceptしてカウントし、1件の失敗が他のアイテムの削除を止めないようにする。
    失敗したidは呼び出し元(Flutter)がローカルのTrashに残せるよう返す。
    """
    uid = _authenticate_request(request)
    admin_client = get_supabase_client()

    # 1. ゴミ箱内のコースを先に処理する(配下の講義も_hard_delete_course内で一緒に消える)
    courses_res = await asyncio.to_thread(
        lambda: admin_client.table("courses")
            .select("id")
            .eq("user_id", uid)
            .not_.is_("deleted_at", "null")
            .execute()
    )
    courses_deleted = 0
    courses_failed: list[str] = []
    for row in (courses_res.data or []):
        course_id = row["id"]
        try:
            await _hard_delete_course(admin_client, uid, course_id)
            courses_deleted += 1
        except Exception as e:
            courses_failed.append(course_id)
            print(f"⚠️ Failed to hard-delete course {course_id} while emptying trash: {e}")

    # 2. 残っている(コースに紐づかない/コース削除で消えなかった)講義を処理する
    lectures_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures")
            .select("id")
            .eq("user_id", uid)
            .not_.is_("deleted_at", "null")
            .execute()
    )
    lectures_deleted = 0
    lectures_failed: list[str] = []
    for row in (lectures_res.data or []):
        lecture_id = row["id"]
        try:
            await _hard_delete_lecture(admin_client, uid, lecture_id)
            lectures_deleted += 1
        except Exception as e:
            lectures_failed.append(lecture_id)
            print(f"⚠️ Failed to hard-delete lecture {lecture_id} while emptying trash: {e}")

    # 3. 講義に紐づかない単体のお知らせ(子テーブルを持たない単純delete)
    await asyncio.to_thread(
        lambda: admin_client.table("announcements")
            .delete()
            .eq("user_id", uid)
            .is_("lecture_id", "null")
            .not_.is_("deleted_at", "null")
            .execute()
    )

    return {
        "courses_deleted": courses_deleted,
        "courses_failed": courses_failed,
        "lectures_deleted": lectures_deleted,
        "lectures_failed": lectures_failed,
    }


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


async def _patrol_renew_subscriptions() -> dict:
    """
    毎日UTC PATROL_DAILY_HOUR_UTC時付近に1回だけ、patrol()から呼ばれる
    (専用のCloud Schedulerジョブは用意しない。既存の10分おきpatrolに相乗り)。
    全ユーザー分の更新処理をこの呼び出しの中で直接行うと、ユーザー数が
    増えるほどタイムアウトのリスクが上がるため、ここでは「更新期限が
    来ているmapping_idを集めてCloud Tasksに1件ずつ積む」だけの軽い処理に
    留める。実際の更新(grant_credits + current_period_endの前進)は
    /worker/renew-subscription が1件ずつ非同期に処理し、失敗しても他の
    ユーザーの更新には影響しない。
    """
    admin_client = get_supabase_client()

    due_res = await asyncio.to_thread(
        lambda: admin_client.table("user_subscription_mappings")
            .select("id")
            .eq("status", "active")
            .lte("current_period_end", datetime.now(timezone.utc).isoformat())
            .execute()
    )
    due_mappings = due_res.data or []

    enqueued = 0
    failed = 0
    for row in due_mappings:
        try:
            await enqueue_renew_subscription_task(row["id"])
            enqueued += 1
        except Exception as e:
            failed += 1
            print(f"⚠️ Failed to enqueue renewal for mapping {row['id']}: {e}")

    return {"due": len(due_mappings), "enqueued": enqueued, "failed": failed}


async def _patrol_enqueue_audio_chunks_cleanup() -> dict:
    """
    毎日UTC PATROL_DAILY_HOUR_UTC時付近に1回だけ、patrol()から呼ばれる。
    作成から AUDIO_CHUNKS_RETENTION_DAYS (既定7日) 以上経過し、
    まだ audio_chunks_cleaned が True になっていない講義を集め、
    Cloud Tasks に 1 件ずつエンキューする。
    """
    admin_client = get_supabase_client()
    retention_threshold = (
        datetime.now(timezone.utc) - timedelta(days=AUDIO_CHUNKS_RETENTION_DAYS)
    ).isoformat()

    # created_at <= 7日前 ＆ deleted_at IS NULL ＆ metadata->>audio_chunks_cleaned が True でない講義を抽出
    due_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures")
            .select("id, user_id")
            .lte("created_at", retention_threshold)
            .is_("deleted_at", "null")
            .or_("metadata->>audio_chunks_cleaned.is.null,metadata->>audio_chunks_cleaned.eq.false")
            .execute()
    )
    due_lectures = due_res.data or []

    enqueued = 0
    failed = 0
    for row in due_lectures:
        try:
            await enqueue_cleanup_audio_chunks_task(row["user_id"], row["id"])
            enqueued += 1
        except Exception as e:
            failed += 1
            print(f"⚠️ Failed to enqueue audio chunks cleanup for lecture {row['id']}: {e}")

    return {"due": len(due_lectures), "enqueued": enqueued, "failed": failed}


@app.post("/maintenance/patrol")
async def patrol():
    """
    Cloud Schedulerから10分おきに呼ばれる、汎用メンテナンスのディスパッチャー。
    DB周回を伴う本チェック(PATROL_CHECKS)は0分・30分付近でのみ実行し、
    それ以外はコールドスタート防止のウォームアップとして起こすだけで即座に返す。
    """
    now = datetime.now(timezone.utc)
    if now.minute % 30 >= PATROL_TIME_WINDOW_TOLERANCE_MINUTES:
        return {"status": "warm"}

    results = {}
    for name, check_fn in PATROL_CHECKS:
        try:
            results[name] = await check_fn()
        except Exception as e:
            results[name] = {"error": str(e)}
            print(f"⚠️ Patrol check '{name}' failed: {e}")

    # サブスク更新および音声チャンククリーンアップは「1日1回」でよいので、
    # 実行ウィンドウ(:00付近 or :30付近)のうち、PATROL_DAILY_HOUR_UTC時台の
    # :00付近側だけを通す。:30付近側まで通すと1日2回走ってしまうため、hourに
    # 加えてminute側もtoleranceで絞っている。
    if now.hour == PATROL_DAILY_HOUR_UTC and now.minute < PATROL_TIME_WINDOW_TOLERANCE_MINUTES:
        try:
            results["renew_subscriptions"] = await _patrol_renew_subscriptions()
        except Exception as e:
            results["renew_subscriptions"] = {"error": str(e)}
            print(f"⚠️ Patrol check 'renew_subscriptions' failed: {e}")

        try:
            results["cleanup_audio_chunks"] = await _patrol_enqueue_audio_chunks_cleanup()
        except Exception as e:
            results["cleanup_audio_chunks"] = {"error": str(e)}
            print(f"⚠️ Patrol check 'cleanup_audio_chunks' failed: {e}")

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
        # GET /auth/v1/verify は "token_hash" ではなく "token" というキー名でしか
        # 読み取らない(GoTrue側の既存仕様。値はハッシュ化済みトークンでよい)。
        query = urlencode({
            "token": token_hash,
            "type": verify_type,
            "redirect_to": redirect_to,
        })
        return f"{SUPABASE_URL}/auth/v1/verify?{query}"

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

            # GoTrueはSend Email Hookの応答を5秒しか待たない。直列にawaitすると
            # 2通分の送信時間が単純合計されタイムアウトのリスクが増えるため、
            # 並行して送信する。
            send_tasks = []
            if email_data.token_hash_new:
                current_link = _verify_link(email_data.token_hash_new, "email_change")
                send_tasks.append(send_email_change_email(user_email, current_link, new_email or ""))
                recipients_notified.append(user_email)

            if new_email and email_data.token_hash:
                new_link = _verify_link(email_data.token_hash, "email_change")
                send_tasks.append(send_email_change_email(new_email, new_link, new_email))
                recipients_notified.append(new_email)

            if send_tasks:
                await asyncio.gather(*send_tasks)

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
        from app.services.email_service import send_email
        from app.services.email_template import (
            build_support_user_ack_email,
            build_support_admin_notification_email,
        )

        user_html = build_support_user_ack_email(
            display_name=display_name,
            ticket_code=ticket_code,
            category=payload.category,
            message=payload.message,
        )
        await send_email(
            to=user_email,
            subject=f"leFture Support - Inquiry Received [{ticket_code}]",
            html=user_html,
            from_address="support@lefture.com",
            from_name="leFture Support",
        )
    except Exception as e:
        print(f"⚠️ Failed to send auto-reply email to user: {e}")

    # 4. 管理者へ通知メールを送信 (To: lefture.app@gmail.com)
    # Reply-To にユーザーのメールアドレスを指定
    try:
        attachments_section = ""
        if payload.attachment_urls:
            # attachment_urls には R2 の非公開オブジェクトキー(storage_path)が入っているため、
            # そのままではメールから開けない。閲覧用の署名付きGET URLに変換して埋め込む。
            # (署名付きURLの有効期限は最大7日 = 604800秒。それを過ぎるとリンク切れになる点に注意)
            from app.core.r2_storage import storage_service
            import html as html_escape_lib
            attachments_section = "<p><strong>Attachments:</strong></p><ul>"
            for storage_path in payload.attachment_urls:
                file_label = html_escape_lib.escape(storage_path.split("/")[-1])
                try:
                    view_url = await asyncio.to_thread(
                        storage_service.generate_presigned_get_url, storage_path
                    )
                    attachments_section += f'<li><a href="{view_url}">{file_label}</a> (Link valid for 7 days)</li>'
                except Exception as e:
                    print(f"⚠️ Failed to generate presigned URL for attachment {storage_path}: {e}")
                    attachments_section += f"<li>{file_label} (Presigned link failed. Check Supabase storage_path: {html_escape_lib.escape(storage_path)})</li>"
            attachments_section += "</ul>"

        device_info_str = json.dumps(payload.device_info, indent=2, ensure_ascii=False) if payload.device_info else ""

        admin_html = build_support_admin_notification_email(
            ticket_code=ticket_code,
            user_email=user_email,
            user_id=uid,
            category=payload.category,
            message=payload.message,
            attachments_section_html=attachments_section,
            device_info_json=device_info_str,
        )
        
        await send_email(
            to="lefture.app@gmail.com",
            subject=f"[Action Required] New Support Ticket [{ticket_code}] ({payload.category})",
            html=admin_html,
            reply_to=user_email,
            from_address="support@lefture.com",
            from_name="leFture Support Desk",
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