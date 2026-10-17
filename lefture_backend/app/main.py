import os

# 本番(Cloud Run)は環境変数をランタイム側で直接注入するため.envを持たないが、
# ローカル実行時はlefture_backend/.envから読み込む。GCP系クライアント
# (CloudTasksClient, firebase_admin等)はこのモジュールの後続のimportで
# 即座に構築されるため、他のimportより前にここで読み込む必要がある。
from pathlib import Path
from dotenv import load_dotenv
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

import re
import json
import time
import uuid
import hmac
import calendar
import html as html_lib
import asyncio
import logging
from typing import Optional
from urllib.parse import urlencode
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from fastapi import FastAPI, HTTPException, UploadFile, Request, File, Form, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
# AuthError系の例外処理はJWT検証と一緒に app/core/auth.py へ移した。
from supabase import create_client, ClientOptions
from nltk.tokenize import sent_tokenize
from pydantic import BaseModel
from google.cloud import tasks_v2
from google.api_core.exceptions import AlreadyExists
from standardwebhooks.webhooks import Webhook, WebhookVerificationError
import stripe
import httpx

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
from app.core.internal_auth import require_internal_caller, internal_task_headers
from app.core.r2_storage import storage_service
from app.services.helpers.credits import (
    CREDITS_PER_USD,
    MAX_RECORDING_SECONDS,
    MICRO_CREDITS_PER_CREDIT,
    MIN_BALANCE_RATIO_FOR_NEW_JOB,
    resolve_duration_tier,
)
from app.services.helpers.helpers import _get_audio_duration_seconds
from app.services.helpers.plan_features import get_user_tier_level, has_feature, is_gating_disabled_for_user, FEATURE_REALTIME_TRANSCRIBE
from app.services.tutorial_content import get_tutorial_content
from app.services.knowledge_index import drain_knowledge_index_queue
from app.services.chat_service import (
    ChatRequestError,
    STREAMING_STALE_MINUTES,
    TurnTimer,
    prepare_chat_turn,
    run_chat_turn,
)
from app.services.chat_attachments import MAX_ATTACHMENT_CHARS, MAX_SELECTED_TOKENS
from app.services import chat_files
from app.services.chat_screen import SCREEN_KINDS, ScreenRef
from app.services.chat_summary import run_fold as run_chat_summary_fold
from app.services import profile_store

# チュートリアル講義のトピック画像(固定4枚)。ユーザーごとに/seed-tutorialが
# R2の自分専用領域へ複製する(共有フォルダにはできない事情はseed_tutorial参照)。
_TUTORIAL_IMAGES_DIR = Path(__file__).resolve().parent / "assets" / "tutorial_images"
from app.services.email_service import (
    send_verification_email,
    send_password_reset_email,
    send_email_change_email,
    send_important_notification,
    send_trial_ending_reminder_email,
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
logger = logging.getLogger(__name__)

# webapp(app.lefture.com)からブラウザ経由で直接叩けるようにするためのCORS許可。
# モバイル(Flutter)はブラウザのCORS制約を受けないため、これはWeb版専用の設定。
_WEBAPP_CORS_ORIGINS = [
    origin.strip()
    for origin in os.environ.get(
        "WEBAPP_CORS_ORIGINS",
        "https://app.lefture.com,http://localhost:3001,http://localhost:5173,http://localhost:3000",
    ).split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_WEBAPP_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Adminダッシュボード(/admin/*)。ルーター単位でrequire_adminが掛かっており、
# 個別のルートで書き忘れても素通りしない。実装と「できてはいけないこと」の
# 一覧は app/api/admin.py の冒頭を参照。
from app.api.admin import router as admin_router
app.include_router(admin_router)


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
CHAT_QUEUE_NAME = os.getenv("CHAT_QUEUE_NAME", "lefture-chat-queue")
# /worker/chat-summaryが諦めるまでの試行回数。キュー側のMax Attemptsより小さくても、
# ここで打ち切れば無駄なLLM呼び出しは止まる(次のチャットのターンでまた積まれる)。
CHAT_SUMMARY_MAX_ATTEMPTS = int(os.getenv("CHAT_SUMMARY_MAX_ATTEMPTS", "5"))
# 観察役・まとめ役のタスクを積むキュー。別に作るまではチャットの要約と同じキューを使う。
PROFILE_QUEUE_NAME = os.getenv("PROFILE_QUEUE_NAME", CHAT_QUEUE_NAME)
PROFILE_TASK_MAX_ATTEMPTS = int(os.getenv("PROFILE_TASK_MAX_ATTEMPTS", "3"))
# patrolが1回に積む上限(導入直後や、patrolが止まっていた後の一気読みを防ぐ)
PROFILE_PATROL_MAX_THREADS = int(os.getenv("PROFILE_PATROL_MAX_THREADS", "50"))
PROFILE_OBSERVE_IDLE_MINUTES = int(os.getenv("PROFILE_OBSERVE_IDLE_MINUTES", "30"))
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
PATROL_AUDIO_CHUNKS_CLEANUP_BATCH_SIZE = int(os.getenv("PATROL_AUDIO_CHUNKS_CLEANUP_BATCH_SIZE", "100")) # Patrol1回あたりでaudio_chunksを掃除する講義数の上限
CLOUD_TASKS_MAX_ATTEMPTS = int(os.getenv("CLOUD_TASKS_MAX_ATTEMPTS", "5")) # lefture-processing-queueのRetry Config(Max Attempts)と必ず一致させる。GCP側で変更したらここも変更すること
STALE_FAILED_JOB_TIMEOUT_MINUTES = int(os.getenv("STALE_FAILED_JOB_TIMEOUT_MINUTES", "15")) # 即時判定(X-CloudTasks-TaskRetryCount)の取りこぼし対策。FAILEDのまま動きがないタスクを見て親ジョブをFAILED化するまでの分数
PATROL_TIME_WINDOW_TOLERANCE_MINUTES = int(os.getenv("PATROL_TIME_WINDOW_TOLERANCE_MINUTES", "4")) # Cloud Schedulerは10分おきに叩くが、DB周回を伴う本チェックは0分・30分付近のみ実行(それ以外はウォームアップのみ)。配信遅延の許容幅
PATROL_DAILY_HOUR_UTC = int(os.getenv("PATROL_DAILY_HOUR_UTC", "0")) # サブスク更新など「1日1回」でよいPatrolチェックを走らせるUTC時(0-23)
SEND_EMAIL_HOOK_SECRET = os.getenv("SEND_EMAIL_HOOK_SECRET", "") # Supabase Auth「Send Email Hook」の署名検証シークレット(Standard Webhooks形式)
REVENUECAT_WEBHOOK_SECRET = os.getenv("REVENUECAT_WEBHOOK_SECRET", "") # RevenueCat Webhookの検証シークレット(Authorizationヘッダーの値と一致させる)
STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "") # Web版の追加クレジット決済(RevenueCatを経由しない自前Stripe連携)用
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "") # /billing/stripe-webhook(追加クレジットのpayment_intent.succeeded、プランのinvoice.payment_succeeded)の署名検証シークレット(whsec_...)
REVENUECAT_STRIPE_PUBLIC_API_KEY = os.getenv("REVENUECAT_STRIPE_PUBLIC_API_KEY", "") # RevenueCatダッシュボード > StripeアプリのPublic API key。POST /v1/receiptsでStripeサブスクをRevenueCatに知らせる際に使う
stripe.api_key = STRIPE_SECRET_KEY

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

class ChatSummaryPayload(BaseModel):
    """Cloud Tasks から /worker/chat-summary に渡されるデータ"""
    thread_id: str

class ProfileObservePayload(BaseModel):
    """Cloud Tasks から /worker/profile-observe に渡されるデータ"""
    thread_id: str

class ProfileConsolidatePayload(BaseModel):
    """Cloud Tasks から /worker/profile-consolidate に渡されるデータ"""
    user_id: str

class ClaimPlanRequest(BaseModel):
    """Flutterから /billing/claim-plan に渡されるデータ。claim_mode='self_serve'の
    プランのみ有効化できる(store_purchaseプランはここでは弾かれる)。"""
    plan_id: str
    device_id: Optional[str] = None

class StartAnalysisRequest(BaseModel):
    lecture_id: str
    expected_chunks: int = 0
    # False(既定): アップロード完了後の自動発火用。既にこのlectureに対する
    # 未完了(!=COMPLETED)Jobがあれば新規作成せず、その既存Job IDを冪等に返す。
    # True: 「Start Over」ボタンなど、ユーザーが明示的に選んだ再実行専用。
    # 既存の未完了Jobをすべてキャンセルしてから新しいJobを作り直す(従来通りの挙動)。
    force: bool = False

class SeedTutorialRequest(BaseModel):
    """チュートリアル講義の初回投入用。固定文言を挿入するだけでLLM/クレジット
    は一切絡まない — /start-analysisとは完全に別の軽量経路。"""
    course_id: str
    display_language: str
    lecture_datetime: str  # ISO8601。ユーザーごとに一度だけ確定する日時をクライアントから受け取る

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

class AsrModelDownloadUrlRequest(BaseModel):
    model_id: str


# ---------------------------------------------------------
# 認証 (JWT検証) — 全エンドポイント共通
# ---------------------------------------------------------
# JWT検証の実装本体は app/core/auth.py に移した。Adminルーター
# (app/api/admin.py)と同じ実装を共有するため —— 認証の分岐が2箇所に
# 増えると、片方だけ直し忘れたときに片方だけ穴が開く。
# 既存の呼び出し箇所を触らずに済むよう、ここでは別名だけ残しておく。
from app.core.auth import _bearer_token, _authenticate_request


async def _get_authenticated_user(request: Request):
    """認証済みユーザー本体(email/user_metadata等)が必要な場合に使う。"""
    return await asyncio.to_thread(_authenticate_request, request)


async def _get_authenticated_user_id(request: Request) -> str:
    """認証済みユーザーのidだけが必要な場合に使う(ほとんどのエンドポイント)。

    get_user()はSupabase Authへの同期HTTP呼び出しなので、必ず
    asyncio.to_threadでイベントループの外に出す。ここを同期のまま呼ぶと、
    検証の往復(実測150ms前後)の間そのワーカーのイベントループが止まり、
    同一インスタンスに相乗りしている他のリクエストまで待たされる。
    """
    user = await asyncio.to_thread(_authenticate_request, request)
    return user.id


def _build_user_client_from_request(request: Request):
    """AuthorizationヘッダのJWTを検証し、そのユーザー権限のSupabaseクライアントを返す (RLS適用)。

    RLSを効かせた読み書きが必要なエンドポイント専用。ここだけはユーザーごとに
    Authorizationヘッダを固定したクライアントが要るため、リクエストごとに
    create_client()する(検証だけで済む他のエンドポイントは、使い回しの
    get_supabase_auth_client()を使うので新規接続を張らない)。
    """
    token = _bearer_token(request)
    user = _authenticate_request(request)
    user_client = create_client(
        SUPABASE_URL,
        SUPABASE_PUBLISHABLE_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {token}"})
    )
    return user_client, user.id


async def _get_user_client_from_request(request: Request):
    """_build_user_client_from_request()をイベントループの外で実行する版。"""
    return await asyncio.to_thread(_build_user_client_from_request, request)


async def _require_lecture_owner(admin_client, lecture_id: str, user_id: str, extra_columns: str = "") -> dict:
    """
    lecture_idの講義が認証済みユーザー自身のものであることを確認して行を返す。
    無ければ404、他人のものなら403。lecture_idはクライアント申告値なので、
    音声アップロード・分析開始のようにlecture_idだけで書き込み先が決まる
    エンドポイントでは必ずこれを通す。
    """
    select_cols = f"user_id, {extra_columns}" if extra_columns else "user_id"
    res = await asyncio.to_thread(
        lambda: admin_client.table("lectures").select(select_cols).eq("id", lecture_id).maybe_single().execute()
    )
    row = res.data if res else None
    if not row:
        raise HTTPException(status_code=404, detail=f"Lecture {lecture_id} not found")
    if row["user_id"] != user_id:
        logger.warning(f"User {user_id} attempted to access lecture {lecture_id} owned by {row['user_id']}")
        raise HTTPException(status_code=403, detail="You do not have access to this lecture")
    return row


async def _is_account_suspended(admin_client, user_id: str) -> bool:
    res = await asyncio.to_thread(
        lambda: admin_client.table("account_suspensions").select("user_id").eq("user_id", user_id).maybe_single().execute()
    )
    return bool(res and res.data)


async def _reject_if_suspended(admin_client, user_id: str) -> None:
    """
    停止中アカウントからの「閲覧以外」の操作を403で止める。録音(リアルタイム含む)・
    分析・クレジット購入・プラン変更など、新しいデータや課金を生む入口に置く。
    サブスク解約(Freeへの降格)・閲覧・サポート問い合わせ・アカウント削除には
    置かないこと —— 制限したまま課金だけ続く状態や、異議申立ての手段を
    奪う状態を作らないため。
    """
    if await _is_account_suspended(admin_client, user_id):
        logger.warning(f"Rejected request from suspended account {user_id}")
        raise HTTPException(
            status_code=403,
            detail={
                "error_code": "ACCOUNT_SUSPENDED",
                "message": "This account has been suspended. Please contact support.",
            },
        )


def _legacy_audio_upload_fallback_enabled() -> bool:
    """既定はfalse(=認証必須)。Cloud Runの環境変数で明示的に有効化したときだけ緩む。"""
    return os.getenv("LEGACY_AUDIO_UPLOAD_FALLBACK", "false").strip().lower() in ("true", "1", "yes")


async def _resolve_audio_upload_uid(request: Request, admin_client, lecture_id: str) -> str:
    """
    音声アップロード系3エンドポイント(/worker/transcribe-chunk,
    request-master-audio-upload-url, complete-master-audio-upload)の
    「誰の音声か」を決める処理。

    この3つは2026-09-20(901a68b)で無認証からJWT必須に変えた。ところが同時に
    出したクライアント更新はストア審査を通る必要があるため、それ以前のビルドは
    Authorizationヘッダを付けずに叩き続け、録音が1つもアップロードできない
    状態になる(2026-09-21以降、成功0件で4日間401が続いた)。ローカルの音声は
    端末に残りリトライも続くので復旧はできるが、その間ユーザーは録音が
    一切処理されない。

    そのため「ヘッダが無いリクエストだけ」旧挙動(lecture_idからuser_idを引く)に
    落とす一時的な逃げ道を用意する。ヘッダがある新ビルドは従来通り厳格に
    所有者チェックまで行うので、緩むのは旧ビルドの経路だけ。

    ★ これはストア審査が通るまでの暫定措置。LEGACY_AUDIO_UPLOAD_FALLBACKを
      falseにする(または環境変数を消す)だけで塞がるようにしてあるので、
      新バージョンが行き渡ったら必ず無効化すること。再デプロイは不要。
      緩めている間は、lecture_id(UUID)を知っている第三者が他人の講義へ
      音声を差し込めるのが既知のリスク(901a68b以前と同じ水準)。
      無効化の判断材料として、フォールバックを通った回数はWARNINGで残す。
    """
    if request.headers.get("Authorization"):
        uid = await _get_authenticated_user_id(request)
        await _reject_if_suspended(admin_client, uid)
        await _require_lecture_owner(admin_client, lecture_id, uid)
        return uid

    if not _legacy_audio_upload_fallback_enabled():
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    res = await asyncio.to_thread(
        lambda: admin_client.table("lectures").select("user_id").eq("id", lecture_id).maybe_single().execute()
    )
    row = res.data if res else None
    if not row:
        raise HTTPException(status_code=404, detail=f"Lecture {lecture_id} not found")

    uid = row["user_id"]
    await _reject_if_suspended(admin_client, uid)
    logger.warning(
        f"LEGACY_AUDIO_UPLOAD_FALLBACK: accepted unauthenticated audio upload for "
        f"lecture {lecture_id} (uid {uid}) — client is an app build from before 2026-09-20"
    )
    return uid


# ---------------------------------------------------------
# 分析開始 (start_analysis)
# ---------------------------------------------------------
@app.post("/start-analysis")
async def start_analysis(payload: StartAnalysisRequest, request: Request):
    print(f"🚀 Start Analysis called for Lecture: {payload.lecture_id}, Chunks: {payload.expected_chunks}")
    user_id = await _get_authenticated_user_id(request)

     # 管理者クライアントを取得 (RLSをバイパスして安全に書き込むため)
    admin_client = get_supabase_client()
    await _reject_if_suspended(admin_client, user_id)

    # 3.4 クレジット残高ゲート: 新規ジョブの受付だけをブロックする。
    # 実際の消費(consume_credits)は各タスク完了後の事後計測なので、進行中の
    # ジョブがこの時点より後に残高を0以下にしても最後まで実行され続ける
    # (オーバードラフト許容)。ここではあくまで「新しいジョブを始めさせない」
    # ゲートとしてだけ使う。
    #
    # /billing/summaryと同じget_credit_summary()を使い、credit_grantsから
    # 毎回ライブに導出する(以前はuser_credit_balancesという別キャッシュを
    # 直接読んでいたが、grantが時間経過で失効しても誰も更新しないキャッシュ
    # だったため、実際には残高0のユーザーの新規ジョブを誤って通してしまう
    # 可能性があった。真実の源をcredit_grantsの1つに統一する)。
    # has_active_plan=false(=プラン未割当、またはまだ何のプランにも
    # 加入していない)とcredit_balance<=0(=プランはあるが使い切った)は
    # Flutter側での見せ方が変わるのでerror_codeで区別する。
    summary_res = await asyncio.to_thread(
        lambda: admin_client.rpc("get_credit_summary", {"p_user_id": user_id}).execute()
    )
    summary_row = (summary_res.data or [{}])[0] if summary_res.data else {}
    if not summary_row.get("has_active_plan"):
        raise HTTPException(
            status_code=402,
            detail={
                "error_code": "NO_CREDIT_ALLOCATION",
                "message": "No credit plan has been assigned to this account yet.",
            },
        )
    credit_balance = summary_row.get("credit_balance") or 0
    if credit_balance <= 0:
        raise HTTPException(
            status_code=402,
            detail={
                "error_code": "INSUFFICIENT_CREDITS",
                "message": "Insufficient credits to start a new analysis job.",
                "credit_balance": credit_balance,
            },
        )

    # 3.5 講義がサーバーに存在するか、コースに紐付いているかを検証する。
    #
    # ★ 以前はここで`.single()`を使っていた。`.single()`は0行だと例外を投げるため、
    # 「まだ同期されていない講義」がPostgRESTの内部エラー(PGRST116 "Cannot coerce
    # the result to a single JSON object")として下のexceptに落ち、
    # `Failed to verify lecture course association: {...}`という
    # 実態と食い違うメッセージのままクライアントの画面に出ていた。
    # 実際にはコース紐付け以前に講義行そのものが存在しないケースで、
    # この文言のせいで原因の切り分けが丸1日遅れた。
    #
    # 「サーバーに講義が無い(404)」「講義はあるがコース未設定(400)」
    # 「検証自体ができなかった(503)」を明確に区別する。
    try:
        lec_res = await asyncio.to_thread(
            lambda: admin_client.table("lectures").select("user_id, course_id, audio_path").eq("id", payload.lecture_id).maybe_single().execute()
        )
    except Exception as e:
        # ここに来るのは通信断やDB障害など「待てば直るかもしれない」失敗だけ。
        # 0行はmaybe_single()が例外ではなくNoneで返すため下の分岐で扱う。
        print(f"❌ Failed to look up lecture {payload.lecture_id}: {e}")
        raise HTTPException(
            status_code=503,
            detail="Could not verify this lecture right now. Please try again in a moment."
        )

    lecture_row = lec_res.data if lec_res else None

    if not lecture_row:
        raise HTTPException(
            status_code=404,
            detail="This lecture hasn't reached the server yet. Its audio is still on your device — keep the app open until the upload finishes, then try again."
        )

    if lecture_row["user_id"] != user_id:
        logger.warning(f"User {user_id} attempted to start analysis on lecture {payload.lecture_id} owned by {lecture_row['user_id']}")
        raise HTTPException(status_code=403, detail="You do not have access to this lecture")

    if not lecture_row.get("course_id"):
        raise HTTPException(
            status_code=400,
            detail="Lecture must be assigned to a course before analysis can start."
        )

    # 3.6 同じlecture_idのjobが既にあるか確認する(COMPLETEDも含めて全件見る)。
    old_jobs_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").select("id, status, expected_chunks")
            .eq("lecture_id", payload.lecture_id)
            .order("created_at", desc=True).execute()
    )
    old_jobs = old_jobs_res.data or []

    # force=False(自動発火)で「まだ生きている」jobがある場合は、新規作成せず既存
    # jobを冪等に返す。アップロード完了直後の自動発火は、チャンクのアップロード
    # リトライ(クライアント側は成功をACKできず再送するが、サーバー側は既に
    # 成功しているケース)によって複数回呼ばれ得るため、ここでガードしないと
    # 同じlectureに対して二重にjob/taskが作られてしまう(過去に実際に発生した)。
    #
    # ★ 判定対象は「生きているjob」全般(DEAD_JOB_STATUSESは除外)で、COMPLETEDも
    # 含む。以前はCOMPLETEDをここで除外していたため、1つ目のjobが完了した後に
    # 届いた2つ目の自動発火リクエスト(クライアント側のバックグラウンド転送完了
    # イベントの重複配信や、ACK取りこぼしによる再送が原因)がこのガードを素通りし、
    # 同じlectureに対してCORE_EXTRACTION等が二重に走ってしまっていた(トピック等が
    # 名前違いで2セットできる不具合の原因)。
    # 「やり直し分析」を後で作る場合は、force=Trueを送る前にサーバー側で古いjobの
    # statusを明示的にCANCELLED等へ変更してから叩く設計にすること(現時点では
    # やり直し機能自体は未実装)。
    active_jobs = [j for j in old_jobs if j.get("status") not in DEAD_JOB_STATUSES]
    if active_jobs and not payload.force:
        existing_job = active_jobs[0]
        existing_job_id = existing_job["id"]
        if existing_job.get("status") == "COMPLETED":
            print(f"⏭️ Lecture {payload.lecture_id} already has a completed job ({existing_job_id}). Returning existing job (idempotent no-op).")
            return {"message": "Analysis already completed", "job_id": existing_job_id}
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

    # 3.9 Realtime Transcribe(録音中にリアルタイムで文字起こしする経路)は本来Maxプラン限定。
    # ただし、この時点では録音・チャンクごとの文字起こし自体は既に完了してしまっている
    # ため、ここでブロックしても「録音はしたのに解析だけ一生できない」という、それこそ
    # 一番避けたい詰み状態をユーザーに強いるだけになる。よって意図的にブロックしない
    # (実際の入口の権限管理はFlutter側— Realtimeトグルをそもそも出さない/選ばせない
    # ——に任せる)。ここでは万一そのFlutter側のガードが抜けたケースを検知できるように
    # ログだけ残す。
    if is_realtime:
        tier = await asyncio.to_thread(get_user_tier_level, user_id)
        if not has_feature(tier, FEATURE_REALTIME_TRANSCRIBE, user_id=user_id):
            print(
                f"⚠️ Realtime transcribe used without Max plan (lecture_id={payload.lecture_id}, "
                f"user_id={user_id}, tier={tier}). Proceeding anyway — see comment above."
            )

    # 3.95 音声の長さを見積もり、(a) 録音上限を超えていないか (b) 見積もりクレジットに
    # 対して残高が少なすぎないか、を確認する。
    #
    # (a) 録音上限(MAX_RECORDING_SECONDS=3時間半)は本来Flutter側(録音中/アップロード時)
    # で弾く想定だが、APIを直接叩かれた場合の保険としてバックエンドにも同じ上限を置く。
    # 既に録音・アップロードされてしまった音声を拒否するだけで、録音自体を途中で
    # 打ち切るような真似はしない(そちらは別の話で、意図的にやらないことにしている)。
    #
    # (b) 上のcredit_balance<=0チェックだけでは「明らかに0以下」しか弾けないため、
    # 音声の長さから消費予定クレジットを見積もり、その
    # MIN_BALANCE_RATIO_FOR_NEW_JOB(現在50%)未満しか残高が無ければここで止める。
    # 100%を要求しないのは、(1)進行中ジョブの実消費は元々オーバードラフトを許容する
    # 設計であり、ここだけ厳密にするのは一貫しないため、(2)この時点の見積もり自体
    # 多少ブレる(プレレコはffprobeの実測値だが、リアルタイムは録音完了時点で
    # 既に文字起こし済みのチャンクの合計であり、万一取りこぼしがあれば実際より
    # 少なく見積もられる)ため。
    #
    # (a)(b)どちらも、見積もり自体に失敗した場合(ffprobeエラー・タイムアウト等の
    # インフラ都合)はこの追加チェックだけスキップし、上のcredit_balance<=0チェックの
    # みで判断する(インフラの一時的な不調でユーザーを誤って締め出したくないため)。
    try:
        if is_realtime:
            duration_res = await asyncio.to_thread(
                lambda: admin_client.table("lecture_transcripts")
                    .select("audio_duration")
                    .eq("lecture_id", payload.lecture_id)
                    .execute()
            )
            estimated_duration_seconds = sum(
                (row.get("audio_duration") or 0.0) for row in (duration_res.data or [])
            )
        else:
            audio_path = lecture_row.get("audio_path")
            if not audio_path:
                raise ValueError(f"lecture {payload.lecture_id} is missing audio_path")
            presigned_url = storage_service.generate_presigned_get_url(audio_path)
            estimated_duration_seconds = await _get_audio_duration_seconds(presigned_url)

        if estimated_duration_seconds > MAX_RECORDING_SECONDS:
            raise HTTPException(
                status_code=400,
                detail={
                    "error_code": "RECORDING_TOO_LONG",
                    "message": "This recording exceeds the maximum supported length.",
                    "duration_seconds": estimated_duration_seconds,
                    "max_duration_seconds": MAX_RECORDING_SECONDS,
                },
            )

        estimated_credits = resolve_duration_tier(estimated_duration_seconds).credits
        min_required_micro_credits = (
            estimated_credits * MICRO_CREDITS_PER_CREDIT * MIN_BALANCE_RATIO_FOR_NEW_JOB
        )
        if credit_balance < min_required_micro_credits:
            raise HTTPException(
                status_code=402,
                detail={
                    "error_code": "INSUFFICIENT_CREDITS",
                    "message": "Estimated credit cost for this lecture exceeds your available balance.",
                    "credit_balance": credit_balance,
                    "estimated_credits": estimated_credits,
                },
            )
    except HTTPException:
        raise
    except Exception as e:
        print(f"⚠️ Failed to estimate required credits for lecture {payload.lecture_id}: {e}. Skipping this check.")

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
# 🎓 チュートリアル講義の初回投入(固定文言、LLM/クレジット不使用)
# ---------------------------------------------------------
@app.post("/seed-tutorial")
async def seed_tutorial(payload: SeedTutorialRequest, request: Request):
    user_id = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()

    try:
        # 冪等チェック: このユーザーが既にチュートリアル講義を持っていれば
        # 何も作らず既存のIDを返す(複数端末からの重複呼び出しにも安全)。
        existing_res = await asyncio.to_thread(
            lambda: admin_client.table("lectures")
            .select("id")
            .eq("user_id", user_id)
            .contains("metadata", {"is_tutorial": True})
            .limit(1)
            .execute()
        )
        if existing_res.data:
            return {"lecture_id": existing_res.data[0]["id"], "created": False}

        content = get_tutorial_content(payload.display_language)
        lecture_id = str(uuid.uuid4())

        def _insert_lecture_row():
            admin_client.table("lectures").insert({
                "id": lecture_id,
                "user_id": user_id,
                "course_id": payload.course_id,
                "title": content["lecture_title"],
                "summary": content["lecture_summary"],
                "lecture_datetime": payload.lecture_datetime,
                "sort_order": 0,
                "display_language": payload.display_language,
                "recording_language": payload.display_language,
                "metadata": {"is_tutorial": True, "tutorial_version": 1},
            }).execute()

        try:
            # このinsertは`lectures_one_tutorial_per_user`部分ユニークインデックス
            # (migrations/20260908220000_...)で守られている。上のSELECTと
            # このINSERTの間には原理的にレースウィンドウがあり(クライアント側の
            # ほぼ同時の二重呼び出しで実際に発生した)、後から来たリクエストは
            # ここで一意制約違反になる。その場合は先勝ちしたリクエストが作った
            # 行を再取得して冪等応答するだけで、サブコンテンツは一切作らない
            # (=重複したlecture_topics/deep_notes等が生まれない)。
            await asyncio.to_thread(_insert_lecture_row)
        except Exception as e:
            error_str = str(e)
            if "duplicate key" in error_str or "23505" in error_str:
                existing_res = await asyncio.to_thread(
                    lambda: admin_client.table("lectures")
                    .select("id")
                    .eq("user_id", user_id)
                    .contains("metadata", {"is_tutorial": True})
                    .limit(1)
                    .execute()
                )
                if existing_res.data:
                    return {"lecture_id": existing_res.data[0]["id"], "created": False}
            raise

        def _seed_sub_content():
            for topic in content["topics"]:
                # 固定のトピック画像を、Flutterアプリ同梱アセットではなくこの
                # ユーザー自身のR2領域({uid}/{lecture_id}/images/...)へ複製する。
                # webapp(app.lefture.com)はFlutterアセットを参照できないため、
                # マルチプラットフォームで同じ画像を見せるにはR2実体が必要。
                # artifact worker(lefture-artifact-worker)がkeyの先頭セグメントと
                # リクエストユーザーのuidの一致を必須にしているため、共有フォルダ
                # ではなく必ずこのユーザー自身のprefix配下に置く。
                image_bytes = (
                    _TUTORIAL_IMAGES_DIR / f"topic_{topic['topic_index']}.jpg"
                ).read_bytes()
                image_path = storage_service.save_binary(
                    user_id,
                    lecture_id,
                    f"images/topic_{topic['topic_index']}.jpg",
                    image_bytes,
                    content_type="image/jpeg",
                )

                admin_client.table("lecture_topics").insert({
                    "user_id": user_id,
                    "lecture_id": lecture_id,
                    "index": topic["topic_index"],
                    "topic_title": topic["title"],
                    "topic_type": "ACADEMIC",
                    "summary": topic["summary"],
                    "image_path": image_path,
                }).execute()

                admin_client.table("deep_notes").insert({
                    "user_id": user_id,
                    "lecture_id": lecture_id,
                    "topic_number": topic["topic_index"],
                    "note_contents": topic["deep_note_markdown"],
                }).execute()

                for card in topic["review_cards"]:
                    admin_client.table("review_cards").insert({
                        "user_id": user_id,
                        "lecture_id": lecture_id,
                        "topic_number": topic["topic_index"],
                        "title": card["title"],
                        "hero_emoji": card["hero_emoji"],
                        "card_type": card["card_type"],
                        "card_content": card["content_blocks"],
                    }).execute()

            for kw in content["keywords"]:
                admin_client.table("keywords").insert({
                    "user_id": user_id,
                    "lecture_id": lecture_id,
                    "topic_number": kw["topic_number"],
                    "keyword": kw["keyword"],
                    "definition": kw.get("definition"),
                }).execute()

            fun_fact = content["fun_fact"]
            admin_client.table("fun_facts").insert({
                "user_id": user_id,
                "lecture_id": lecture_id,
                "title": fun_fact["title"],
                "hook": fun_fact["hook"],
                "body": fun_fact["body"],
                "metadata": {"sources": fun_fact["sources"]} if fun_fact.get("sources") else None,
            }).execute()

            for ann in content["announcements"]:
                admin_client.table("announcements").insert({
                    "user_id": user_id,
                    "lecture_id": lecture_id,
                    "type": ann["type"],
                    "title": ann["title"],
                    "description": ann.get("description"),
                    "metadata": {"is_completed": False},
                }).execute()

        await asyncio.to_thread(_seed_sub_content)
        return {"lecture_id": lecture_id, "created": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"seed_tutorial failed for user {user_id}: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail=f"Failed to seed tutorial: {e}")


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
    user_id = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()
    await _reject_if_suspended(admin_client, user_id)

    try:
        rpc_params = {"p_user_id": user_id, "p_plan_id": payload.plan_id}
        if payload.device_id:
            rpc_params["p_device_id"] = payload.device_id.strip()

        await asyncio.to_thread(
            lambda: admin_client.rpc("claim_plan", rpc_params).execute()
        )
    except Exception as e:
        error_str = str(e)
        if "device_already_claimed" in error_str:
            raise HTTPException(status_code=409, detail={"error_code": "DEVICE_ALREADY_CLAIMED", "message": "The free trial has already been claimed on this device."})
        if "plan_not_found" in error_str:
            raise HTTPException(status_code=404, detail={"error_code": "PLAN_NOT_FOUND", "message": "Plan not found."})
        if "plan_not_self_serve" in error_str:
            raise HTTPException(status_code=403, detail={"error_code": "PLAN_NOT_SELF_SERVE", "message": "This plan cannot be claimed directly."})
        if "plan_expired" in error_str:
            raise HTTPException(status_code=410, detail={"error_code": "PLAN_EXPIRED", "message": "This plan is no longer available."})
        if "plan_already_claimed" in error_str or "duplicate key" in error_str:
            raise HTTPException(status_code=409, detail={"error_code": "PLAN_ALREADY_CLAIMED", "message": "This plan has already been claimed."})
        if "plan_already_active_other_plan" in error_str:
            raise HTTPException(status_code=409, detail={"error_code": "ANOTHER_PLAN_ALREADY_ACTIVE", "message": "You already have an active plan. This plan cannot be claimed."})
        raise HTTPException(status_code=500, detail=f"Failed to claim plan: {e}")

    return {"status": "success", "plan_id": payload.plan_id}


async def _fill_live_stripe_prices(rows: list[dict]) -> None:
    """
    price_usdがNULLだがstripe_price_idを持つ行(Stripe移行後に価格を書き戻して
    いなかった既存のsubscription_plans/credit_packs)に対し、Stripe側の実勢価格を
    ライブ取得してその場でprice_usdを埋める(rowsを直接書き換える)。
    店頭決済(Apple)専用でstripe_price_idが無い行はそのままNULLで返る
    (実価格はApp Store側が正のため)。
    1件のStripe障害で一覧全体を失敗させたくないので、失敗した行はNULLのまま
    ログだけ出して続行する。
    """
    targets = [row for row in rows if row.get("price_usd") is None and row.get("stripe_price_id")]
    if not targets:
        return

    async def _fetch(row: dict) -> None:
        try:
            # stripe-pythonの既定タイムアウトは長い(数十秒)ため、Stripe側のネットワーク
            # 障害/到達不能時にこのエンリッチ処理だけで一覧取得全体を巻き込んで
            # ハングさせないよう、ここで短いタイムアウトを切る。/billing/plansや
            # /billing/credit-packsはプラン選択・購入画面の初期表示に使われるため、
            # 遅延はprice_usd=NULLのまま返すより悪い。
            price = await asyncio.wait_for(
                asyncio.to_thread(stripe.Price.retrieve, row["stripe_price_id"]),
                timeout=5,
            )
            unit_amount = price.to_dict().get("unit_amount")
            if unit_amount is not None:
                row["price_usd"] = unit_amount / 100
        except Exception as e:
            # stripe.error.StripeError以外(ネットワーク到達不能・DNS失敗・
            # asyncio.TimeoutError等)も含めて、この行の価格取得失敗が一覧
            # エンドポイント全体を500にしてしまわないよう、ここで必ず握りつぶす。
            logger.error(f"Failed to fetch live Stripe price for {row['stripe_price_id']}: {e}", exc_info=True)

    await asyncio.gather(*(_fetch(row) for row in targets))


@app.get("/billing/plans")
async def billing_plans(request: Request):
    """
    無効化されていないクレジット配布プラン一覧(claim_mode問わず)。
    Flutter側にplan_id・クレジット量をハードコードさせないための一覧取得
    エンドポイント。claim_mode='store_purchase'のプランもここに含める
    (一覧に出すことと、このエンドポイント経由でclaimできることは別問題 —
    実際の購入操作の可否はclaim_plan() SQL関数側のclaim_modeチェックが
    引き続き担保する。store_purchaseプランの有効化はRevenueCat Webhook
    経由でのみ行われ、/billing/claim-planでは弾かれる)。

    trial_period_monthsは「このユーザーがWeb(Stripe)でこのプランの無料トライアルを
    何ヶ月受けられるか(対象外ならnull)」で、switch-planが実際に付与判定に使うのと
    同じ条件・同じ期間を返す(表示と実挙動がズレないよう、判定関数と定数を
    共有する)。Apple経由のトライアル可否はApple ID単位でStoreKitしか
    知らないため、この値はiOS側のバッジ表示には使わない(Flutter側は
    Purchases.checkTrialOrIntroductoryPriceEligibilityで自分で判定する)。
    """
    uid = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()

    # disabled_atの絞り込みはPostgRESTのor=フィルタ文字列に頼らず、ここで
    # 判定する(タイムゾーンオフセット付きISO文字列の'+'がURLエンコード時に
    # 空白と誤解釈されるリスクを避けるため。プラン数は少ないので問題ない)。
    try:
        plans_res = await asyncio.to_thread(
            lambda: admin_client.table("subscription_plans")
                .select("id, name, monthly_credit_amount, price_usd, billing_interval_months, claim_mode, store_product_id, stripe_price_id, subtitles, tier_level, disabled_at")
                .execute()
        )
    except Exception as e:
        # Supabaseが非JSON(例: ゲートウェイの503テキスト)を返すとpostgrest-py側の
        # エラーパースが失敗し例外になるため、ここで捕まえて503として返す。
        logger.error(f"Error fetching billing plans: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail="Billing service temporarily unavailable")

    now = datetime.now(timezone.utc)
    claimable = []
    for plan in (plans_res.data or []):
        disabled_at = plan.get("disabled_at")
        if disabled_at and datetime.fromisoformat(disabled_at) <= now:
            continue
        plan.pop("disabled_at", None)
        claimable.append(plan)

    has_paid_before = await _user_has_ever_had_paid_plan(admin_client, uid)
    for plan in claimable:
        eligible = (
            plan.get("tier_level") == _TRIAL_ELIGIBLE_PLAN_TIER_LEVEL
            and bool(plan.get("stripe_price_id"))
            and not has_paid_before
        )
        # 期間もサーバーから返す(「1ヶ月」という表記をクライアント側に
        # ハードコードさせないため。nullは対象外)。
        plan["trial_period_months"] = _TRIAL_PERIOD_MONTHS if eligible else None

    await _fill_live_stripe_prices(claimable)

    return {"plans": claimable}


@app.get("/billing/credit-packs")
async def billing_credit_packs(request: Request):
    """
    無効化されていない追加クレジットパック一覧(都度課金、非サブスク)。
    /billing/plansと同じ理由でFlutter側に商品ID・クレジット量をハードコード
    させないための一覧取得エンドポイント。実際の付与はRevenueCat Webhook
    (NON_RENEWING_PURCHASEイベント → grant_credit_pack_purchase())経由でのみ行う。
    """
    await _get_authenticated_user_id(request)  # 認証チェックのみ(user_idは使わない)

    admin_client = get_supabase_client()

    try:
        packs_res = await asyncio.to_thread(
            lambda: admin_client.table("credit_packs")
                .select("id, name, credit_amount, price_usd, store_product_id, stripe_price_id, disabled_at")
                .execute()
        )
    except Exception as e:
        logger.error(f"Error fetching credit packs: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail="Billing service temporarily unavailable")

    now = datetime.now(timezone.utc)
    available = []
    for pack in (packs_res.data or []):
        disabled_at = pack.get("disabled_at")
        if disabled_at and datetime.fromisoformat(disabled_at) <= now:
            continue
        pack.pop("disabled_at", None)
        available.append(pack)

    await _fill_live_stripe_prices(available)

    return {"packs": available}


@app.get("/billing/summary")
async def billing_summary(request: Request):
    """
    Flutter側のクレジット表示(プログレスバー・詳細ページ)向けの一括サマリー。
    credit_grants/user_subscription_mappingsはどれも
    RLSでクライアントから直接触れない専用テーブルなので、必ずこのエンドポイント
    経由で取得させる。credits_per_usdも一緒に返すことで、Flutter側が
    しきい値計算(例: Realtime可否の$0.1判定)のために自前でハードコードした
    レートを持たずに済むようにする。
    """
    user_id = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()

    try:
        summary_res = await asyncio.to_thread(
            lambda: admin_client.rpc("get_credit_summary", {"p_user_id": user_id}).execute()
        )
    except Exception as e:
        # Supabaseが非JSON(例: ゲートウェイの503テキスト)を返すとpostgrest-py側の
        # エラーパースが失敗し例外になるため、ここで捕まえて503として返す。
        logger.error(f"Error fetching billing summary: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail="Billing service temporarily unavailable")
    row = (summary_res.data or [{}])[0] if summary_res.data else {}

    # tier_level(機能ゲート判定用)もここで一緒に返す。Flutter側は既にこの
    # エンドポイントをアプリ全体でほぼ常時watchしているので(CustomAppBar経由)、
    # 専用の新しい取得経路・キャッシュを増やさずに済む。
    tier_level = await asyncio.to_thread(get_user_tier_level, user_id)
    # gating_disabled: このユーザーにkill-switchが効いているか(実機テスト用に
    # REAL_GATING_TEST_USER_IDSへ登録されたアカウントだけfalseになる)。実際の
    # 生成・保存の可否は常にバックエンド(has_feature)側が最終判断するので、この
    # 値がそのままクライアントに渡ってもUIロック表示のヒントとしてしか使われず、
    # 悪用の余地は無い。
    gating_disabled = is_gating_disabled_for_user(user_id)
    # suspended: 停止中かどうか。クライアントは録音・購入・プラン変更の入口を
    # 停止バナーに差し替えるヒントとしてだけ使う。実際の拒否は各エンドポイントの
    # _reject_if_suspended()が行うので、この値を改ざんしても何も通らない。
    suspended = await _is_account_suspended(admin_client, user_id)

    return {
        "suspended": suspended,
        "credit_balance": row.get("credit_balance"),
        "monthly_allocation": row.get("monthly_allocation"),
        "extra_credit_balance": row.get("extra_credit_balance"),
        "has_active_plan": bool(row.get("has_active_plan")),
        "current_period_end": row.get("current_period_end"),
        "pending_plan_id": row.get("pending_plan_id"),
        "plan_id": row.get("plan_id"),
        "credits_per_usd": CREDITS_PER_USD,
        "tier_level": tier_level,
        "gating_disabled": gating_disabled,
    }


@app.get("/billing/history")
async def billing_history(request: Request):
    """
    クレジット利用履歴のエンドポイント。
    消費(delta<0)は1時間単位のバケツにまとめて表示件数を抑える。付与(delta>0)は
    credit_transactions.deltaをそのまま信用する(台帳が完全な前提——プラン切替/
    更新時に古いクレジットをゼロ化する処理は、必ず対応するreset行を台帳に
    残すことで、grantのdeltaが目減りして見えることが無いようにしてある)。
    reset行(credit_reset_renewed/credit_reset_plan_changed)は、具体的な数字を
    見せると「クレジットを失った」という誤解を招くため、数字を出さない
    区切りエントリ(reset_reason: "renewed" | "plan_changed")として返す。
    """
    user_id = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()

    RESET_REASON_LABELS = {
        "credit_reset_renewed": "renewed",
        "credit_reset_plan_changed": "plan_changed",
        "credit_expired": "expired",
    }

    def date_time_labels(dt):
        sample_date = dt.date()
        if sample_date == today:
            date_label = "Today"
        elif sample_date == today - timedelta(days=1):
            date_label = "Yesterday"
        else:
            date_label = dt.strftime("%b %d")
        time_label = dt.strftime("%I %p").lstrip("0")
        return date_label, time_label

    try:
        # ★ 以前はorder(desc=False)のまま500件に切っており、取引が501件を
        # 超えたユーザーでは「一番古い500件」しか見えず、直近の履歴が
        # 丸ごと欠落していた(チャットの導入でユーザーごとの取引数が
        # 講義単位の頃より大きく増えるため顕在化しやすくなった)。
        # 新しい順に500件取ってから、以降の処理(hour_keyでの束ね等)が
        # 前提にしている時系列順に戻すため反転する。
        tx_res = await asyncio.to_thread(
            lambda: admin_client.table("credit_transactions")
                .select("id, created_at, delta, balance_after, reason")
                .eq("user_id", user_id)
                .order("created_at", desc=True)
                .limit(500)
                .execute()
        )

        transactions = list(reversed(tx_res.data or []))
        if not transactions:
            return {"history": []}

        MICRO_PER_CREDIT = 1000000
        now = datetime.now(timezone.utc)
        today = now.date()

        negative_hourly_buckets = {}
        positive_items = []
        reset_items = []

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

            if reason in RESET_REASON_LABELS:
                reset_items.append({
                    "id": str(tx_id) if tx_id else dt.isoformat(),
                    "dt": dt,
                    "reset_reason": RESET_REASON_LABELS[reason],
                })

            elif delta < 0:
                # ★ 表示額はbalance_afterの差分ではなく、そのバケツに属する行の
                # 実際のdeltaを合計して求める。以前はbalance_afterの差分を使って
                # おり、失効(credit_expired)のように「remaining_amountだけ静かに
                # 減ってcredit_transactionsに記録が残らない」変化があると、その分が
                # 次の消費行にまるごと乗ってしまっていた(10分の講義で-60のところ
                # -2000と表示される、等)。失効も今はmaterialize_expired_grants経由で
                # 必ずreason='credit_expired'の行を残すため(RESET_REASON_LABELSに
                # 含めて区切り線として表示)、消費行のdeltaはもう実消費額と一致する。
                hour_key = dt.strftime("%Y-%m-%d %H:00")
                if hour_key not in negative_hourly_buckets:
                    negative_hourly_buckets[hour_key] = {
                        "delta_sum_micro": 0,
                        "sample_time": dt,
                    }
                negative_hourly_buckets[hour_key]["delta_sum_micro"] += delta
                negative_hourly_buckets[hour_key]["sample_time"] = dt

            elif delta > 0:
                positive_items.append({
                    "id": str(tx_id) if tx_id else dt.isoformat(),
                    "dt": dt,
                    "delta_credits": max(round(delta / MICRO_PER_CREDIT), 1),
                })

        all_entries = []

        for hour_key, bdata in negative_hourly_buckets.items():
            sample_time = bdata["sample_time"]

            delta_credits = round(bdata["delta_sum_micro"] / MICRO_PER_CREDIT)
            if delta_credits >= 0:
                delta_credits = -1

            date_label, time_label = date_time_labels(sample_time)

            all_entries.append({
                "dt": sample_time,
                "item": {
                    "id": hour_key,
                    "kind": "transaction",
                    "date_label": date_label,
                    "time_label": time_label,
                    "timestamp": sample_time.isoformat(),
                    "delta_credits": delta_credits,
                    "formatted_delta": f"{delta_credits}",
                    "is_positive": False,
                }
            })

        for p in positive_items:
            dt = p["dt"]
            delta_credits = p["delta_credits"]
            date_label, time_label = date_time_labels(dt)

            all_entries.append({
                "dt": dt,
                "item": {
                    "id": p["id"],
                    "kind": "transaction",
                    "date_label": date_label,
                    "time_label": time_label,
                    "timestamp": dt.isoformat(),
                    "delta_credits": delta_credits,
                    "formatted_delta": f"+{delta_credits}",
                    "is_positive": True,
                }
            })

        for r in reset_items:
            dt = r["dt"]
            date_label, time_label = date_time_labels(dt)

            all_entries.append({
                "dt": dt,
                "item": {
                    "id": r["id"],
                    "kind": "reset",
                    "reset_reason": r["reset_reason"],
                    "date_label": date_label,
                    "time_label": time_label,
                    "timestamp": dt.isoformat(),
                }
            })

        all_entries.sort(key=lambda x: x["dt"], reverse=True)
        history_items = [entry["item"] for entry in all_entries]

        return {"history": history_items}
    except Exception as e:
        logger.error(f"Error processing billing history: {e}", exc_info=True)
        return {"history": []}


@app.post("/billing/revenuecat-webhook")
async def revenuecat_webhook(request: Request, authorization: str = Header(None)):
    """
    RevenueCatからのサブスクイベント通知を受け取り、store_purchaseプランの
    クレジットを付与/失効させる。クライアントから送られたレシートを自前で
    Apple/Google Server APIに問い合わせて検証する方式(このファイル冒頭の
    /billing/claim-plan付近のTODOが元々想定していたもの)は採用していない —
    RevenueCatが既にサーバー側でレシート検証を代行しており、そこから届く
    このWebhookイベント自体を信頼境界として扱う。

    認証はRevenueCatダッシュボードで設定した固定文字列をAuthorizationヘッダーで
    受け取り、定数時間比較する(/webhook/orchestrator の x-webhook-secret と
    同じ「単純な文字列比較」方式だが、あちらは素の != 比較なのに対しこちらは
    hmac.compare_digestを使う。あちらは今回touchしない)。

    冪等性・実際のクレジット付与/mapping更新ロジックは全て
    grant_store_subscription_credits() / expire_store_subscription() SQL関数側で
    アトミックに行う(同じevent_idの再送でも二重付与しない)。
    """
    # ★ 未設定時に検証をスキップしてはいけない。このエンドポイントはクレジットを
    #   付与する(=課金相当の価値を発行する)ため、素通しは「誰でも自分に好きなだけ
    #   クレジットを付与できる」ことを意味する。Stripe webhook側と同じく全拒否にする。
    if not REVENUECAT_WEBHOOK_SECRET:
        logger.error("REVENUECAT_WEBHOOK_SECRET is not configured; rejecting RevenueCat webhook")
        raise HTTPException(status_code=503, detail="Webhook is not configured")
    if not hmac.compare_digest((authorization or "").strip(), REVENUECAT_WEBHOOK_SECRET):
        logger.warning("Rejected RevenueCat webhook: bad/missing Authorization header")
        raise HTTPException(status_code=401, detail="Unauthorized webhook")

    body = await request.json()
    event = body.get("event", {})
    event_id = event.get("id")
    event_type = event.get("type")
    app_user_id = event.get("app_user_id")  # Purchases.logIn(supabaseUserId) によりSupabaseのuser idと一致する
    # RevenueCatはStripe由来のイベントでは、product_idにStripeの「Product ID」
    # (prod_xxx)を入れ、Price ID(price_xxx)はprice_idという別フィールドで送ってくる。
    # こちらのsubscription_plans/credit_packsが主に持っているのはPrice IDなので、
    # Stripe由来のときはprice_idを優先する(Apple由来のイベントにはprice_idが
    # 無いため、従来どおりproduct_idをそのまま使う)。prod_xxxしか来ない場合の
    # 取りこぼしは、SQL側のstripe_product_id列での検索が受け止める。
    product_id = event.get("price_id") or event.get("product_id")
    expiration_at_ms = event.get("expiration_at_ms")

    if not event_id or not event_type or not app_user_id:
        # リトライしても直らない不正なペイロード。ログだけ残して200で終わらせる。
        logger.error(f"Malformed RevenueCat webhook payload: {body}")
        return {"status": "ignored", "reason": "malformed_payload"}

    admin_client = get_supabase_client()

    # CANCELLATION(自動更新オフになっただけで期間終了までは有効)は、ここで
    # マッピングを失効させてもクレジットを取り消してもいけない。TRANSFER等も
    # 含め、今回のスコープでは意図的に無視する。PRODUCT_CHANGEだけは例外で、
    # 下のset_pending_plan_change経由で「予約状態」の表示用に拾う(実際の
    # クレジット付与・プラン切り替えには一切関与しない)。
    #
    # ただしAppleのCANCELLATION(event["store"] == "APP_STORE")だけは、
    # クロスプラットフォーム乗り換え(Apple→Web割引)の判定用に
    # auto_renew_disabledフラグを立てる。ステータス・クレジットには一切
    # 触れない点は変わらない。Stripeの契約もRevenueCat経由でCANCELLATIONが
    # 届く(cancel_at_period_end=trueにしただけ、ダウングレード予約含む)ため、
    # Apple由来かどうかをevent["store"]で厳密に絞る必要がある。
    #
    # UNCANCELLATION(期限切れ前に自動更新をオンに戻した)はその逆操作で、
    # フラグを下ろすだけ。クレジットは付与しない —— 期間も決済も進んで
    # いないのに満額を付与し直すと、自動更新のオフ→オン往復だけで同一期間内に
    # 残高が何度でも満額に戻ってしまう。
    #
    # BILLING_ISSUE(更新時の決済失敗)は無視してはいけない: App Store Connectで
    # Billing Grace Period(28日)を設定しているため、Appleは決済リトライ中も
    # サブスクを「有効」として扱うが、こちらの前回付与クレジットのexpires_at
    # (前回current_period_end + 6時間の猶予)はRENEWALが来ないまま過ぎてしまい、
    # 実質数時間でクレジットが消えてしまう。下のBILLING_ISSUE分岐で
    # handle_billing_issue() を呼び、Grace Period終了日までクレジットを維持する。
    GRANT_EVENT_TYPES = {"INITIAL_PURCHASE", "RENEWAL"}

    try:
        if event_type in GRANT_EVENT_TYPES:
            if not product_id or expiration_at_ms is None:
                logger.error(f"RevenueCat {event_type} missing product_id/expiration_at_ms: {event}")
                return {"status": "ignored", "reason": "missing_fields"}
            period_end_iso = datetime.fromtimestamp(expiration_at_ms / 1000, tz=timezone.utc).isoformat()
            await asyncio.to_thread(
                lambda: admin_client.rpc("grant_store_subscription_credits", {
                    "p_user_id": app_user_id,
                    "p_event_id": event_id,
                    "p_event_type": event_type,
                    "p_product_id": product_id,
                    "p_period_end": period_end_iso,
                }).execute()
            )
            if (
                event_type == "INITIAL_PURCHASE"
                and event.get("store") == "APP_STORE"
                # Sandbox(TestFlight/StoreKitのテスト購入)のイベントでこれを走らせては
                # いけない。同じapp_user_idの「本物のStripeサブスク」を即時解約して
                # 実際に返金してしまうため。クレジット付与がSandboxでも走るのは
                # 既存の挙動だが、こちらは取り返しがつかない。
                and event.get("environment") == "PRODUCTION"
            ):
                # クロスプラットフォーム乗り換え(Web→Apple)対応: Appleでの新規
                # 購入が成立した直後、ユーザーがStripe側の契約を解約し忘れて
                # 実質二重課金になっているケースをここで即座に検出・解消する。
                # Flutter側からの明示的な/billing/stripe/cancel-for-platform-switch
                # 呼び出しとは独立した経路(クライアントがApple購入後にこの
                # エンドポイントを呼べなかった場合の保険)。失敗してもwebhook
                # 自体は200を返す(_attempt_cancel_stripe_for_platform_switchが
                # 失敗をretryキューに積む)。
                try:
                    await _attempt_cancel_stripe_for_platform_switch(admin_client, app_user_id)
                except Exception as e:
                    logger.warning(f"Cross-platform Stripe cleanup failed for user {app_user_id}: {e}")
        elif event_type == "BILLING_ISSUE":
            # Grace Period中は決済がまだ成功していないため新規クレジットの
            # 積み増しは行わず、既存クレジットをGrace Period終了日
            # (expiration_at_ms、Apple/StoreKitがGrace Period分延長した値)まで
            # 維持する。冪等性・実際のロジックはhandle_billing_issue() SQL関数側で行う。
            if not product_id or expiration_at_ms is None:
                logger.error(f"RevenueCat BILLING_ISSUE missing product_id/expiration_at_ms: {event}")
                return {"status": "ignored", "reason": "missing_fields"}
            period_end_iso = datetime.fromtimestamp(expiration_at_ms / 1000, tz=timezone.utc).isoformat()
            await asyncio.to_thread(
                lambda: admin_client.rpc("handle_billing_issue", {
                    "p_user_id": app_user_id,
                    "p_event_id": event_id,
                    "p_product_id": product_id,
                    "p_period_end": period_end_iso,
                }).execute()
            )
        elif event_type == "EXPIRATION":
            if not product_id:
                logger.error(f"RevenueCat EXPIRATION missing product_id: {event}")
                return {"status": "ignored", "reason": "missing_fields"}
            await asyncio.to_thread(
                lambda: admin_client.rpc("expire_store_subscription", {
                    "p_user_id": app_user_id,
                    "p_event_id": event_id,
                    "p_product_id": product_id,
                }).execute()
            )
        elif event_type == "CANCELLATION" and event.get("store") == "APP_STORE":
            if not product_id:
                logger.error(f"RevenueCat CANCELLATION missing product_id: {event}")
                return {"status": "ignored", "reason": "missing_fields"}
            await asyncio.to_thread(
                lambda: admin_client.rpc("mark_apple_subscription_auto_renew_disabled", {
                    "p_user_id": app_user_id,
                    "p_event_id": event_id,
                    "p_product_id": product_id,
                }).execute()
            )
        elif event_type == "UNCANCELLATION" and event.get("store") == "APP_STORE":
            if not product_id:
                logger.error(f"RevenueCat UNCANCELLATION missing product_id: {event}")
                return {"status": "ignored", "reason": "missing_fields"}
            await asyncio.to_thread(
                lambda: admin_client.rpc("mark_apple_subscription_auto_renew_enabled", {
                    "p_user_id": app_user_id,
                    "p_event_id": event_id,
                    "p_product_id": product_id,
                }).execute()
            )
        elif event_type == "NON_RENEWING_PURCHASE":
            # 追加クレジットパック(都度課金、非サブスク)の購入。expiration_at_msは
            # 持たない(消費型商品のため)。冪等性・付与ロジックはgrant_credit_pack_purchase()
            # SQL関数側でアトミックに行う(同じevent_idの再送でも二重付与しない)。
            if not product_id:
                logger.error(f"RevenueCat NON_RENEWING_PURCHASE missing product_id: {event}")
                return {"status": "ignored", "reason": "missing_fields"}
            await asyncio.to_thread(
                lambda: admin_client.rpc("grant_credit_pack_purchase", {
                    "p_user_id": app_user_id,
                    "p_event_id": event_id,
                    "p_product_id": product_id,
                }).execute()
            )
        elif event_type == "PRODUCT_CHANGE":
            # ダウングレード/クロスグレードが予約された瞬間(実際の切り替えを
            # 待たず)にRevenueCatが即座に送ってくるイベント。new_product_idを
            # 「予約先」として記録するだけで、クレジット付与やプラン切り替え
            # 自体は行わない(それは後続の本物のRENEWALが担う)。
            # product_idと同様、Stripe由来ならPrice IDの方を優先する。
            # new_price_idが提供されない場合はnew_product_id(prod_xxx)のまま渡し、
            # SQL側のstripe_product_id検索に拾わせる。
            new_product_id = event.get("new_price_id") or event.get("new_product_id")
            if not new_product_id:
                logger.error(f"RevenueCat PRODUCT_CHANGE missing new_product_id: {event}")
                return {"status": "ignored", "reason": "missing_fields"}
            await asyncio.to_thread(
                lambda: admin_client.rpc("set_pending_plan_change", {
                    "p_user_id": app_user_id,
                    "p_event_id": event_id,
                    "p_new_product_id": new_product_id,
                }).execute()
            )
        else:
            logger.info(f"RevenueCat webhook: ignoring event_type={event_type} (event_id={event_id})")
            return {"status": "ignored", "event_type": event_type}
    except Exception as e:
        error_str = str(e)
        if "unknown_store_product" in error_str or "unknown_credit_pack" in error_str:
            # 恒久的な設定ミス(subscription_plans/credit_packs側に商品IDが
            # 登録されていない)。リトライしても直らないため、ログだけ残して200で止める。
            logger.error(f"RevenueCat webhook: unknown store product - {error_str} (event={event})")
            return {"status": "error_logged", "reason": "unknown_product"}
        # DB接続エラー等の一時的な失敗はRevenueCat側のリトライに委ねるため5xxを返す。
        logger.error(f"RevenueCat webhook processing failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal error processing webhook")

    return {"status": "success", "event_type": event_type}


# ---------------------------------------------------------
# Web版 追加クレジット決済 (自前Stripe、RevenueCatを経由しない)
# ---------------------------------------------------------
#
# サブスク(プラン)はStripeアカウントをRevenueCatに接続し、RevenueCat Webhook
# (上のrevenuecat_webhook)経由でgrant_store_subscription_credits()に流れる。
# 一方、追加クレジット(都度課金)はRevenueCatの外部購入追跡API
# (POST /v1/receipts)がCheckout Session経由の購入しか識別できず、webapp側で
# 完全にカスタムなPayment Element UIを使う方針とは両立しないため、ここだけ
# RevenueCatを経由せず、Stripeのwebhookを直接受ける独立した経路にする。
# grant_credit_pack_purchase() SQL関数自体はRevenueCat経由と共用(event_type引数で区別)。

class CreateCreditPackPaymentRequest(BaseModel):
    credit_pack_id: str


@app.post("/billing/stripe/create-credit-pack-payment")
async def billing_stripe_create_credit_pack_payment(payload: CreateCreditPackPaymentRequest, request: Request):
    """
    webapp側のカスタムPayment Element UIが使うPaymentIntentを発行する。
    金額はStripe側のPrice(credit_packs.stripe_price_id)から取得するので、
    クライアントから金額を受け取らない(改ざん防止)。
    """
    uid = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()
    await _reject_if_suspended(admin_client, uid)
    try:
        pack_res = await asyncio.to_thread(
            lambda: admin_client.table("credit_packs")
                .select("id, stripe_price_id, disabled_at")
                .eq("id", payload.credit_pack_id)
                .maybe_single()
                .execute()
        )
    except Exception as e:
        logger.error(f"Error fetching credit pack {payload.credit_pack_id}: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail="Billing service temporarily unavailable")

    pack = pack_res.data if pack_res else None
    if not pack or pack.get("disabled_at"):
        raise HTTPException(status_code=404, detail="Credit pack not found")
    stripe_price_id = pack.get("stripe_price_id")
    if not stripe_price_id:
        raise HTTPException(status_code=400, detail="This credit pack is not available for web purchase")

    try:
        price = await asyncio.to_thread(stripe.Price.retrieve, stripe_price_id)
        intent = await asyncio.to_thread(
            stripe.PaymentIntent.create,
            amount=price["unit_amount"],
            currency=price["currency"],
            automatic_payment_methods={"enabled": True},
            metadata={
                "supabase_user_id": uid,
                "credit_pack_id": pack["id"],
                "stripe_price_id": stripe_price_id,
            },
        )
    except stripe.error.StripeError as e:
        logger.error(f"Stripe error creating PaymentIntent for credit pack {pack['id']}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to create payment")

    return {
        "client_secret": intent["client_secret"],
        "amount_cents": intent["amount"],
        "currency": intent["currency"],
    }


# ---------------------------------------------------------
# Web版 プラン(サブスク)決済 (自前Stripe → RevenueCat連携)
# ---------------------------------------------------------
#
# 追加クレジットと違い、プランはRevenueCatに引き続き追跡させる(実際のクレジット
# 付与は既存のgrant_store_subscription_credits() / revenuecat_webhookが担う、
# ここは一切変更しない)。流れ:
#   1. ここでStripe Subscriptionをpayment_behavior='default_incomplete'で作り、
#      client_secretをwebapp側のPayment Elementに渡す。
#   2. ユーザーが決済を確定すると、Stripeからinvoice.payment_succeededが届く
#      (下のbilling_stripe_webhook)。そこでRevenueCatの外部購入追跡API
#      (POST /v1/receipts)にこのsubscription idを知らせる。
#   3. RevenueCatがそれを検知し、自前のwebhook(INITIAL_PURCHASE等)を
#      /billing/revenuecat-webhookに送ってくる → 既存経路でクレジット付与。

async def _get_or_create_stripe_customer(admin_client, uid: str) -> str:
    profile_res = await asyncio.to_thread(
        lambda: admin_client.table("user_profiles")
            .select("stripe_customer_id")
            .eq("id", uid)
            .maybe_single()
            .execute()
    )
    existing = profile_res.data.get("stripe_customer_id") if profile_res and profile_res.data else None
    if existing:
        return existing

    customer = await asyncio.to_thread(stripe.Customer.create, metadata={"supabase_user_id": uid})
    await asyncio.to_thread(
        lambda: admin_client.table("user_profiles")
            .update({"stripe_customer_id": customer["id"]})
            .eq("id", uid)
            .execute()
    )
    return customer["id"]


# Web版Maxプラン(DB上のname='Premium', tier_level=3)限定の初回無料トライアル。
# 「過去に一度もプランを持ったことがないユーザーだけ」に絞るのは
# _user_has_ever_had_paid_plan() が担う。Apple側の同種トライアルとの二重取りは
# こちらから検知できないため、規約上の許容として割り切る(コードでは防がない)。
#
# 期間は「日数」ではなく「暦月」で持つ。App Store Connectの導入オファーは
# 3日/1週間/2週間/1ヶ月/…という選択肢しか無く30日を選べないため、Stripe側を
# trial_period_days=30にすると同じ「無料トライアル」がプラットフォームで
# 28〜31日ずれる(2月なら実際28日なのに「30日間無料」と表示してしまう)。
# Stripeはtrial_endにunix timestampを直接渡せるので、そちらで暦月に揃える。
_TRIAL_ELIGIBLE_PLAN_TIER_LEVEL = 3
_TRIAL_PERIOD_MONTHS = 1


def _add_calendar_months(dt: datetime, months: int) -> datetime:
    """dtのmonthsヶ月後(暦月)。月末は繰り上げずにその月の末日へ丸める
    (1/31の1ヶ月後は2/28、App Store/Stripeの月次サブスクと同じ挙動)。"""
    month_index = dt.month - 1 + months
    year = dt.year + month_index // 12
    month = month_index % 12 + 1
    day = min(dt.day, calendar.monthrange(year, month)[1])
    return dt.replace(year=year, month=month, day=day)

# トライアル終了リマインダーメールを送るタイミング(終了の何日前か)。
# カリフォルニア州ARL等、米国複数州の自動更新法がトライアル終了3〜21日前の
# 通知を義務付けており、7日はその範囲に収まる一般的な目安値。
_TRIAL_REMINDER_DAYS_BEFORE = 7


async def _user_has_ever_had_paid_plan(admin_client, uid: str) -> bool:
    """
    このuidが過去に(プラットフォーム問わず、現在activeかどうかも問わず)
    有料プランを持ったことがあるか。claim_plan/grant_store_subscription_credits/
    このファイルのswitch-plan、いずれの経路でもuser_subscription_mappings行は
    (user_id, plan_id)へのUPSERTで、解約後もstatusが変わるだけで行は消えないため、
    「1行でも claim_mode <> 'self_serve' があるか」が履歴確認として使える。
    """
    res = await asyncio.to_thread(
        lambda: admin_client.table("user_subscription_mappings")
            .select("subscription_plans!user_subscription_mappings_plan_id_fkey!inner(claim_mode)")
            .eq("user_id", uid)
            .execute()
    )
    rows = res.data or []
    return any(row["subscription_plans"]["claim_mode"] != "self_serve" for row in rows)


async def _create_new_stripe_subscription(
    customer_id: str, uid: str, plan_id: str, stripe_price_id: str, trial_months: int | None = None
):
    trial_kwargs = {}
    if trial_months:
        # trial_period_days(日数)ではなくtrial_end(時刻)で指定する。
        # Apple側の導入オファーが暦月単位でしか設定できないため、
        # 「1ヶ月無料」の実際の長さを両プラットフォームで一致させる。
        trial_end = _add_calendar_months(datetime.now(timezone.utc), trial_months)
        trial_kwargs["trial_end"] = int(trial_end.timestamp())
        # トライアル中はpayment_behavior=default_incompleteでも$0請求のため
        # PaymentIntentが発生しない(pending_setup_intentでカードだけ登録させる)。
        # カードが結局登録されないまま試用期間が終わった場合は、無料引き延ばしを
        # 防ぐためサブスク自体を自動キャンセルする。
        trial_kwargs["trial_settings"] = {"end_behavior": {"missing_payment_method": "cancel"}}

    try:
        return await asyncio.to_thread(
            stripe.Subscription.create,
            customer=customer_id,
            items=[{"price": stripe_price_id}],
            payment_behavior="default_incomplete",
            payment_settings={"save_default_payment_method": "on_subscription"},
            expand=["latest_invoice.confirmation_secret", "pending_setup_intent"],
            metadata={
                "supabase_user_id": uid,
                "subscription_plan_id": plan_id,
            },
            **trial_kwargs,
        )
    except stripe.error.StripeError as e:
        logger.error(f"Stripe error creating Subscription for plan {plan_id}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to create subscription")


class SwitchPlanRequest(BaseModel):
    plan_id: str
    # Apple解約予約済み(auto_renew_disabled)ユーザー向けの割引プレビュー確認フラグ。
    # False(デフォルト)で叩くと課金は一切発生させず、割引額のプレビューだけ返す。
    confirm_apple_discount: bool = False


async def _mark_stripe_pending_plan(admin_client, uid: str, plan_id: str) -> None:
    """
    Stripe側でダウングレード/解約が予約された瞬間に、DB上の
    user_subscription_mappings.pending_plan_idへその予約先を書く。
    Apple側はRevenueCatのPRODUCT_CHANGE webhook(set_pending_plan_change RPC)が
    同じ列を書くので、これでプラットフォームを跨いで「予約中」バッジが
    同じ1つのフィールドから正しく出せるようになる。
    switch-plan自身がユーザーの1リクエスト内で完結する同期処理のため、
    webhookのような冪等性(イベントログ)は不要で、素直なUPDATEでよい。
    """
    await asyncio.to_thread(
        lambda: admin_client.table("user_subscription_mappings")
            .update({"pending_plan_id": plan_id})
            .eq("user_id", uid)
            .eq("status", "active")
            .execute()
    )


async def _clear_stripe_pending_plan(admin_client, uid: str) -> None:
    """予約が実行に移った(アップグレード等で即時反映された)/取り消された時に、
    pending_plan_idを空に戻す。"""
    await asyncio.to_thread(
        lambda: admin_client.table("user_subscription_mappings")
            .update({"pending_plan_id": None})
            .eq("user_id", uid)
            .eq("status", "active")
            .execute()
    )


@app.post("/billing/stripe/switch-plan")
async def billing_stripe_switch_plan(payload: SwitchPlanRequest, request: Request):
    """
    既に何らかのプラン(Free/Apple/Stripeいずれか)を持つユーザーが別のプランに
    切り替える時の統一エンドポイント。

    - Stripeで管理中のアクティブなサブスクが実際に見つかった場合だけ、
      アップグレード(即時切り替え+即時課金)/ダウングレード・解約(Subscription
      Scheduleで次回更新時に予約、Appleの同一サブスクグループの挙動に合わせる)
      を行う。二重にサブスクを作らない。
    - 見つからない場合(現在Free、またはApple経由の購読中)は、素直に
      claim_plan()(self_serve宛て)または新規Stripeサブスク作成
      (store_purchase宛て)を行う — 今までのclaim-plan/新規Stripeサブスク作成
      と同じ結果になる。Appleの購読はこちらから解約できない(既知の制限。
      ユーザーはiOS側で自分で解約する必要がある)。
    """
    uid = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()
    try:
        plan_res = await asyncio.to_thread(
            lambda: admin_client.table("subscription_plans")
                .select("id, tier_level, claim_mode, stripe_price_id, disabled_at")
                .eq("id", payload.plan_id)
                .maybe_single()
                .execute()
        )
    except Exception as e:
        logger.error(f"Error fetching subscription plan {payload.plan_id}: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail="Billing service temporarily unavailable")

    target_plan = plan_res.data if plan_res else None
    if not target_plan or target_plan.get("disabled_at"):
        raise HTTPException(status_code=404, detail="Plan not found")

    # 停止中でもFree(self_serve)への切り替え=有料サブスクの解約だけは通す。
    if target_plan["claim_mode"] != "self_serve":
        await _reject_if_suspended(admin_client, uid)

    profile_res = await asyncio.to_thread(
        lambda: admin_client.table("user_profiles")
            .select("stripe_customer_id")
            .eq("id", uid)
            .maybe_single()
            .execute()
    )
    customer_id = profile_res.data.get("stripe_customer_id") if profile_res and profile_res.data else None

    active_subscription = None
    if customer_id:
        try:
            subs = await asyncio.to_thread(stripe.Subscription.list, customer=customer_id, status="active", limit=1)
            if subs["data"]:
                active_subscription = subs["data"][0]
        except stripe.error.StripeError as e:
            logger.error(f"Failed to list Stripe subscriptions for customer {customer_id}: {e}", exc_info=True)
            raise HTTPException(status_code=502, detail="Failed to look up current subscription")

    # ケースA: 現在アクティブなStripeサブスクが無い(Free/Apple/未加入) →
    # 今までのclaim-plan/新規Stripeサブスク作成と同じことをするだけ。
    if not active_subscription:
        if target_plan["claim_mode"] == "self_serve":
            try:
                await asyncio.to_thread(
                    lambda: admin_client.rpc("claim_plan", {
                        "p_user_id": uid,
                        "p_plan_id": target_plan["id"],
                    }).execute()
                )
            except Exception as e:
                error_str = str(e)
                if "plan_already_claimed" in error_str:
                    return {"status": "already_current"}
                if "plan_already_active_other_plan" in error_str:
                    raise HTTPException(status_code=409, detail="You already have an active plan on another platform. Please cancel it there first.")
                logger.error(f"claim_plan failed for user {uid}: {e}", exc_info=True)
                raise HTTPException(status_code=400, detail="Failed to claim plan")
            return {"status": "claimed"}

        if not target_plan.get("stripe_price_id"):
            raise HTTPException(status_code=400, detail="This plan is not available for web purchase")

        # 現在のactiveなmapping(プラットフォーム問わず)をtier比較とApple判定の
        # 両方に使う。claim_modeはプラン行の属性でApple/Stripeどちらの契約かを
        # 区別できない(1tier1行でstore_product_id/stripe_price_idを両方持つ設計)
        # ため、「ここに来ている時点でStripeにアクティブなサブスクが無いことは
        # 確定済み」という消去法でのみ、claim_mode='store_purchase'ならApple経由と
        # 判断できる。この消去法はこの分岐の中でしか使えないので、他の場所で
        # 同じ判定を再利用しない。
        try:
            current_mapping_res = await asyncio.to_thread(
                lambda: admin_client.table("user_subscription_mappings")
                    .select(
                        "id, auto_renew_disabled, current_period_end, "
                        "subscription_plans!user_subscription_mappings_plan_id_fkey!inner("
                        "claim_mode, tier_level, billing_interval_months, stripe_price_id)"
                    )
                    .eq("user_id", uid)
                    .eq("status", "active")
                    # maybe_single()は使わない: Accept: application/vnd.pgrst.object+json
                    # が付くため、activeなmappingが2行以上あると406になり、それを
                    # 下のexceptが503に変えてしまう(=そのユーザーはプラン変更が
                    # 恒久的に不能になる)。「1ユーザー1active」を保証するDB制約は
                    # 存在せず(UNIQUEは(user_id, plan_id)のみ)、statusにactiveを書く
                    # 経路も多数あるため、複数行を許容して最も期間の長いものを採る。
                    .order("current_period_end", desc=True)
                    .limit(1)
                    .execute()
            )
        except Exception as e:
            logger.error(f"Error checking current active mapping for user {uid}: {e}", exc_info=True)
            raise HTTPException(status_code=503, detail="Billing service temporarily unavailable")

        current_mapping_rows = (current_mapping_res.data or []) if current_mapping_res else []
        current_mapping = current_mapping_rows[0] if current_mapping_rows else None
        current_plan_info = current_mapping["subscription_plans"] if current_mapping else None
        current_tier = current_plan_info.get("tier_level") if current_plan_info else None

        # この機能は常に「アップグレード」方向にのみ対応する(年額プランが無く、
        # 同tier/ダウングレード方向のプラットフォーム間移動は今回スコープ外)。
        # これにより割引額が新プラン価格を上回るケースも起きない。
        if current_tier is not None and target_plan["tier_level"] <= current_tier:
            raise HTTPException(status_code=403, detail="This plan is not an upgrade from your current plan.")

        if current_plan_info and current_plan_info.get("claim_mode") == "store_purchase":
            if not current_mapping.get("auto_renew_disabled"):
                # まだ解約意思が無い: こちらから強制解約できない(ユーザーが
                # iOS側で自分で解約する必要がある)ため、二重課金を避けて
                # ここで明確にブロックする。webapp側はこのerror_codeを見て
                # 案内を出す。
                raise HTTPException(
                    status_code=409,
                    detail={
                        "error_code": "APPLE_SUBSCRIPTION_ACTIVE",
                        "message": "You already have an active subscription through the App Store. Turn off auto-renew in your iOS device settings to unlock a discounted switch to this web plan.",
                    },
                )

            # 解約予約済み: Appleへの返金はできないが、こちら側の値引きとして
            # Apple残存期間分をStripe請求から割り引く。price_usdは有料プランで
            # 常にNULL(実価格はApp Store側が正)なので、代理値として自社の
            # Stripe定価(unit_amount)をライブ取得して使う。Appleの手数料
            # (15〜30%)分のスプレッドは自社負担になる、意識的な割り切り。
            apple_plan = current_plan_info
            try:
                apple_price = await asyncio.to_thread(stripe.Price.retrieve, apple_plan["stripe_price_id"])
                new_price = await asyncio.to_thread(stripe.Price.retrieve, target_plan["stripe_price_id"])
            except stripe.error.StripeError as e:
                logger.error(f"Failed to retrieve prices for Apple->Stripe switch (user {uid}): {e}", exc_info=True)
                raise HTTPException(status_code=502, detail="Failed to look up plan pricing")

            # current_period_startはRENEWAL時に更新されない既知の制限があり
            # (2ヶ月目以降、初回購入時刻に固定されたまま)、そのまま分母に使うと
            # 期間が実際より長く計算されて割引が不当に小さくなる。DBの列は
            # 直さず、この計算専用にbilling_interval_monthsから期間開始を
            # 逆算する(30日/月の近似。カレンダー精度は求めない)。
            period_end_raw = current_mapping["current_period_end"]
            period_end_dt = (
                datetime.fromisoformat(period_end_raw.replace("Z", "+00:00"))
                if isinstance(period_end_raw, str) else period_end_raw
            )
            interval_months = apple_plan.get("billing_interval_months") or 1
            period_start_est = period_end_dt - timedelta(days=30 * interval_months)
            now_dt = datetime.now(timezone.utc)

            total_seconds = (period_end_dt - period_start_est).total_seconds()
            remaining_seconds = max(0.0, (period_end_dt - now_dt).total_seconds())
            remaining_fraction = min(1.0, remaining_seconds / total_seconds) if total_seconds > 0 else 0.0

            discount_cents = round(apple_price["unit_amount"] * remaining_fraction)
            charge_cents = max(0, new_price["unit_amount"] - discount_cents)

            if not payload.confirm_apple_discount:
                # プレビューのみ。まだ何も課金・作成しない。
                return {
                    "status": "requires_confirmation",
                    "reason": "apple_pending_cancellation",
                    "discount_usd": discount_cents / 100,
                    "charge_usd": charge_cents / 100,
                }

            customer_id = customer_id or await _get_or_create_stripe_customer(admin_client, uid)

            if discount_cents > 0:
                # 冪等性: confirm_apple_discountの再送・ダブルクリック・
                # Payment Element離脱後の再試行で割引が多重生成されないよう、
                # 同じmetadataを持つ未消化のpending invoice itemが既にあれば
                # 再利用し、無ければ新規作成する。
                existing_items = await asyncio.to_thread(
                    stripe.InvoiceItem.list, customer=customer_id, pending=True, limit=100
                )
                already_pending = any(
                    item_metadata.get("purpose") == "apple_platform_switch_discount"
                    and item_metadata.get("user_id") == uid
                    for item_metadata in (item["metadata"].to_dict() for item in existing_items["data"])
                )
                if not already_pending:
                    await asyncio.to_thread(
                        stripe.InvoiceItem.create,
                        customer=customer_id,
                        amount=-discount_cents,
                        currency=new_price["currency"],
                        description="Discount for remaining time on App Store subscription",
                        metadata={"purpose": "apple_platform_switch_discount", "user_id": uid},
                    )

        customer_id = customer_id or await _get_or_create_stripe_customer(admin_client, uid)

        trial_months = None
        if (
            target_plan.get("tier_level") == _TRIAL_ELIGIBLE_PLAN_TIER_LEVEL
            and not await _user_has_ever_had_paid_plan(admin_client, uid)
        ):
            # トライアルは$0請求書が即座にpaid扱いになりRevenueCat通知→クレジット
            # 付与まで進む(invoice.payment_succeededを待つ通常課金と違い、実際の
            # 支払いなしで進む)。user_subscription_mappingsへの反映はRevenueCatの
            # 折り返しwebhookを待つため数秒ラグがあり、_user_has_ever_had_paid_plan()
            # だけでは連打(二重にトライアルsubscriptionを作られる)を防げない。
            # Stripe側は即時一貫性があるため、ここで直接確認する。
            try:
                existing_subs = await asyncio.to_thread(
                    stripe.Subscription.list, customer=customer_id, status="all", limit=10
                )
            except stripe.error.StripeError as e:
                logger.error(f"Failed to list Stripe subscriptions for trial guard (customer {customer_id}): {e}", exc_info=True)
                raise HTTPException(status_code=502, detail="Failed to look up current subscription")
            if not any(s["status"] in ("trialing", "incomplete", "active", "past_due") for s in existing_subs["data"]):
                trial_months = _TRIAL_PERIOD_MONTHS

        subscription = await _create_new_stripe_subscription(
            customer_id, uid, target_plan["id"], target_plan["stripe_price_id"], trial_months=trial_months
        )

        pending_setup_intent = subscription.to_dict().get("pending_setup_intent")
        if pending_setup_intent:
            # トライアル適用時: 初回請求が$0のためPaymentIntentは作られず、代わりに
            # カード登録用のSetupIntentが返る。フロントはconfirmPaymentではなく
            # confirmSetupでこのclient_secretを確定させる必要がある。
            return {
                "client_secret": pending_setup_intent["client_secret"],
                "client_secret_kind": "setup",
                "subscription_id": subscription["id"],
                "amount_due_cents": 0,
                "currency": subscription["items"]["data"][0]["price"]["currency"],
                "trial_period_months": trial_months,
            }

        latest_invoice = subscription["latest_invoice"]
        confirmation_secret = latest_invoice["confirmation_secret"]
        # amount_dueはApple乗り換え割引(負のInvoiceItem)適用後の「今日実際に
        # 請求される額」。チェックアウト画面の開示文(自動更新法対応)に使う。
        return {
            "client_secret": confirmation_secret["client_secret"],
            "client_secret_kind": "payment",
            "subscription_id": subscription["id"],
            "amount_due_cents": latest_invoice["amount_due"],
            "currency": latest_invoice["currency"],
        }

    # ケースB: Stripeサブスクが既にアクティブ → アップグレード/ダウングレード/解約。
    subscription_id = active_subscription["id"]

    # 前回ダウングレード予約済み等でSubscription Scheduleが付いている場合、
    # いったん解放してクリーンな状態から今回の判断をやり直す。
    schedule_id = active_subscription["schedule"]
    if schedule_id:
        try:
            await asyncio.to_thread(stripe.SubscriptionSchedule.release, schedule_id)
        except stripe.error.StripeError as e:
            logger.error(f"Failed to release schedule {schedule_id}: {e}", exc_info=True)
            raise HTTPException(status_code=502, detail="Failed to update subscription")

    # ここから先の分岐で予約を新たに作るかもしれないので、一旦まっさらに戻す
    # (即時反映されるアップグレードの場合はこれがそのまま最終状態になる)。
    await _clear_stripe_pending_plan(admin_client, uid)

    if target_plan["claim_mode"] == "self_serve":
        # Freeへの「ダウングレード」= 次回更新時に自動解約(=Appleのキャンセルと同じ挙動)。
        # 実際にEXPIRATIONが来た時のFreeフォールバックは既存のexpire_store_subscription任せ。
        try:
            await asyncio.to_thread(stripe.Subscription.modify, subscription_id, cancel_at_period_end=True)
        except stripe.error.StripeError as e:
            logger.error(f"Failed to cancel Stripe subscription {subscription_id}: {e}", exc_info=True)
            raise HTTPException(status_code=502, detail="Failed to cancel subscription")
        await _mark_stripe_pending_plan(admin_client, uid, target_plan["id"])
        return {"status": "scheduled_cancel"}

    new_price_id = target_plan.get("stripe_price_id")
    if not new_price_id:
        raise HTTPException(status_code=400, detail="This plan is not available for web purchase")

    current_price_id = active_subscription["items"]["data"][0]["price"]["id"]
    current_item_id = active_subscription["items"]["data"][0]["id"]

    if new_price_id == current_price_id:
        # 既にこのプランがアクティブ(例: DB側の反映待ちで画面が古いプランを
        # 表示している間に同じプランを再選択した)。上で予約は既に解除・
        # クリア済みなので、無駄なSubscription Scheduleは作らずそのまま終える。
        return {"status": "already_current"}

    current_plan_res = await asyncio.to_thread(
        lambda: admin_client.table("subscription_plans")
            .select("tier_level")
            .eq("stripe_price_id", current_price_id)
            .maybe_single()
            .execute()
    )
    current_tier = current_plan_res.data.get("tier_level") if current_plan_res and current_plan_res.data else None

    if current_tier is not None and target_plan["tier_level"] <= current_tier:
        # ダウングレード(または同tierへの再選択): 次回更新時に切り替わる
        # Subscription Scheduleを作る(即時の変更・課金は一切しない)。
        # https://docs.stripe.com/billing/subscriptions/subscription-schedules
        # の「Schedule an upgrade or downgrade for an existing subscription」と同じ手順。
        try:
            schedule = await asyncio.to_thread(stripe.SubscriptionSchedule.create, from_subscription=subscription_id)
            await asyncio.to_thread(
                stripe.SubscriptionSchedule.modify,
                schedule["id"],
                end_behavior="release",
                phases=[
                    {
                        "items": [{
                            "price": schedule["phases"][0]["items"][0]["price"],
                            "quantity": schedule["phases"][0]["items"][0]["quantity"],
                        }],
                        "start_date": schedule["phases"][0]["start_date"],
                        "end_date": schedule["phases"][0]["end_date"],
                    },
                    {
                        # 1回分だけdurationを与えて次の更新を新価格で迎えさせ、その後は
                        # end_behavior='release'によりスケジュールから解放された通常の
                        # サブスクとしてその価格のまま自動更新され続ける。
                        "items": [{"price": new_price_id, "quantity": 1}],
                        "duration": {"interval": "month", "interval_count": 1},
                    },
                ],
            )
        except stripe.error.StripeError as e:
            logger.error(f"Failed to schedule downgrade for subscription {subscription_id}: {e}", exc_info=True)
            raise HTTPException(status_code=502, detail="Failed to schedule plan change")
        await _mark_stripe_pending_plan(admin_client, uid, target_plan["id"])
        return {"status": "scheduled_downgrade"}

    # アップグレード: Stripe自身の日割り計算(proration_behavior)は使わず、Appleの
    # サブスクグループと同じ「経過時間ベース(消費クレジット量は無視)」の日割りを
    # 自前で計算する。
    #   請求額 = 新プラン価格 − ( 現プラン価格 × (期間終了 − 今) / (期間終了 − 期間開始) )
    # 支払いが成功して初めてプランの価格を切り替える(失敗したのに上位プランに
    # なってしまう状態を避けるため、先に課金→成功したら切り替え、の順序にする)。
    try:
        old_price = await asyncio.to_thread(stripe.Price.retrieve, current_price_id)
        new_price = await asyncio.to_thread(stripe.Price.retrieve, new_price_id)
    except stripe.error.StripeError as e:
        logger.error(f"Failed to retrieve prices for upgrade of subscription {subscription_id}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to look up plan pricing")

    if old_price["currency"] != new_price["currency"]:
        logger.error(f"Currency mismatch upgrading subscription {subscription_id}: {old_price['currency']} vs {new_price['currency']}")
        raise HTTPException(status_code=500, detail="Plan pricing misconfiguration")

    # current_period_start/endは2025年のAPIバージョン変更でSubscription直下から
    # Subscription Itemに移動している。
    current_item = active_subscription["items"]["data"][0]
    period_start = current_item["current_period_start"]
    period_end = current_item["current_period_end"]
    now_ts = time.time()

    total_seconds = period_end - period_start
    remaining_seconds = max(0, period_end - now_ts)
    remaining_fraction = (remaining_seconds / total_seconds) if total_seconds > 0 else 0

    unused_credit = old_price["unit_amount"] * remaining_fraction
    charge_amount = max(0, round(new_price["unit_amount"] - unused_credit))
    currency = new_price["currency"]

    # 新規サブスク作成時のsave_default_payment_method="on_subscription"は
    # Subscription.default_payment_methodにしかカードを残さず、Customer側の
    # invoice_settings.default_payment_methodは設定されない。この後作る単発の
    # 日割りInvoiceはCustomerに紐づくため、明示的に支払い方法を渡さないと
    # 「default_payment_methodが無い」で402になる。
    default_payment_method = active_subscription["default_payment_method"]
    if not default_payment_method:
        raise HTTPException(status_code=402, detail="No payment method on file. Please update your payment method before upgrading.")

    invoice = None
    try:
        await asyncio.to_thread(
            stripe.InvoiceItem.create,
            customer=customer_id,
            amount=charge_amount,
            currency=currency,
            description=f"Upgrade proration: {current_price_id} -> {new_price_id}",
        )
        invoice = await asyncio.to_thread(
            stripe.Invoice.create,
            customer=customer_id,
            collection_method="charge_automatically",
            pending_invoice_items_behavior="include",
            auto_advance=False,
            default_payment_method=default_payment_method,
        )
        invoice = await asyncio.to_thread(stripe.Invoice.finalize_invoice, invoice["id"])
        invoice = await asyncio.to_thread(stripe.Invoice.pay, invoice["id"])
    except stripe.error.StripeError as e:
        logger.warning(f"Upgrade payment failed for subscription {subscription_id}: {e}")
        if invoice is not None and invoice["status"] == "open":
            try:
                await asyncio.to_thread(stripe.Invoice.void_invoice, invoice["id"])
            except stripe.error.StripeError:
                pass
        raise HTTPException(status_code=402, detail="Payment for the upgrade failed")

    if invoice["status"] != "paid":
        if invoice["status"] == "open":
            try:
                await asyncio.to_thread(stripe.Invoice.void_invoice, invoice["id"])
            except stripe.error.StripeError:
                pass
        raise HTTPException(status_code=402, detail="Payment for the upgrade failed")

    # 課金が成功したので、ここで初めてプランの価格を切り替える。今回の差額は
    # 上で自前計算・請求済みなので、Stripe自身の日割り計算は一切走らせない。
    try:
        await asyncio.to_thread(
            stripe.Subscription.modify,
            subscription_id,
            items=[{"id": current_item_id, "price": new_price_id}],
            proration_behavior="none",
        )
    except stripe.error.StripeError as e:
        logger.error(f"Charged upgrade but failed to switch price for subscription {subscription_id}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Payment succeeded but failed to switch plan. Please contact support.")

    # アップグレードの差額は「サブスクに紐づかない単発Invoice」で請求しているため、
    # 新規契約時と違ってinvoice.payment_succeeded webhookがサブスクに結び付かず、
    # RevenueCatへの通知経路が存在しない(=DB上のプランが永久に切り替わらない)。
    # ここで明示的に通知して、RevenueCatに現在のサブスク状態を取り直させる。
    # 通知に失敗してもStripe側の課金・切り替えは完了しているので、ユーザーには
    # 成功を返す(次回更新時のRENEWALが通常経路でDBを追いつかせる)。
    try:
        await _notify_revenuecat_of_stripe_subscription(subscription_id, uid)
    except Exception as e:
        logger.error(f"Upgraded subscription {subscription_id} but failed to notify RevenueCat: {e}", exc_info=True)

    return {"status": "switched"}


async def _resolve_invoice_charge_id(invoice_id: str) -> str | None:
    """
    Invoiceの決済に対応するCharge IDを返す(返金対象を特定するため)。

    Invoice.charge / Invoice.payment_intent は2025-03-31.basil以降のAPIバージョンで
    削除されており(このコードベースが使うstripe-python 15系の既定は
    2026-08-26.dahlia)、invoice["charge"]は常にNoneになる。同じAPI変更で
    current_period_startがSubscription直下からSubscription Itemへ移動したのと同じ
    世代の変更。現行の参照経路は
      Invoice → InvoicePayment → payment.payment_intent → PaymentIntent.latest_charge
    なので、それを辿る。type='charge'(PaymentIntentを伴わない古い決済)の場合だけは
    payment.chargeに直接Charge IDが入る。
    """
    try:
        payments = await asyncio.to_thread(
            stripe.InvoicePayment.list, invoice=invoice_id, status="paid", limit=10
        )
    except stripe.error.StripeError as e:
        logger.error(f"Failed to list payments for invoice {invoice_id}: {e}", exc_info=True)
        return None

    for payment in payments["data"]:
        detail = payment.to_dict().get("payment") or {}
        charge_id = detail.get("charge")
        if charge_id:
            return charge_id

        payment_intent_id = detail.get("payment_intent")
        if not payment_intent_id:
            continue
        try:
            payment_intent = await asyncio.to_thread(stripe.PaymentIntent.retrieve, payment_intent_id)
        except stripe.error.StripeError as e:
            logger.error(f"Failed to retrieve payment intent {payment_intent_id}: {e}", exc_info=True)
            continue
        latest_charge = payment_intent.to_dict().get("latest_charge")
        if latest_charge:
            return latest_charge

    return None


async def _cancel_stripe_subscription_for_platform_switch(admin_client, uid: str) -> dict:
    """
    ユーザーのアクティブなStripeサブスクを即時解約し、未消化期間分を日割りで
    返金する。Apple IAP購入成功後にFlutter側から呼ばれる想定(cancel-for-
    platform-switchエンドポイント)だが、_patrol_reconcile_cross_platform_
    subscriptionsからも同じ関数を呼ぶため、ここに切り出してある。

    アクティブなStripeサブスクが既に無ければ何もせず返す(=何度呼んでも安全。
    Flutter側のリトライ・パトロールからの再実行いずれでも安全)。
    """
    profile_res = await asyncio.to_thread(
        lambda: admin_client.table("user_profiles")
            .select("stripe_customer_id")
            .eq("id", uid)
            .maybe_single()
            .execute()
    )
    customer_id = profile_res.data.get("stripe_customer_id") if profile_res and profile_res.data else None
    if not customer_id:
        return {"status": "no_active_subscription"}

    try:
        subs = await asyncio.to_thread(stripe.Subscription.list, customer=customer_id, status="active", limit=1)
    except stripe.error.StripeError as e:
        logger.error(f"Failed to list Stripe subscriptions for customer {customer_id}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to look up current subscription")

    if not subs["data"]:
        return {"status": "no_active_subscription"}

    active_subscription = subs["data"][0]
    subscription_id = active_subscription["id"]
    current_item = active_subscription["items"]["data"][0]
    current_stripe_price_id = current_item["price"]["id"]
    period_start = current_item["current_period_start"]
    period_end = current_item["current_period_end"]
    now_ts = time.time()

    total_seconds = period_end - period_start
    remaining_seconds = max(0, period_end - now_ts)
    remaining_fraction = (remaining_seconds / total_seconds) if total_seconds > 0 else 0

    try:
        current_price = await asyncio.to_thread(stripe.Price.retrieve, current_stripe_price_id)
    except stripe.error.StripeError as e:
        logger.error(f"Failed to retrieve price for subscription {subscription_id}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to look up plan pricing")

    unused_credit_cents = round(current_price["unit_amount"] * remaining_fraction)

    # 直近の「サブスク本体」のInvoiceを選ぶ。同一プラットフォーム内アップグレード
    # 直後だと、直近Invoiceが差額請求用の単発Invoiceのことがあり、その決済額は
    # 月額満額よりずっと小さいため、返金額がそれを超えないようクランプする。
    refund_amount = 0
    charge_id = None
    try:
        invoices = await asyncio.to_thread(
            stripe.Invoice.list, subscription=subscription_id, status="paid", limit=10
        )
        invoice_list = invoices["data"]
    except stripe.error.StripeError as e:
        logger.error(f"Failed to list invoices for subscription {subscription_id}: {e}", exc_info=True)
        invoice_list = []

    target_invoice = next(
        (inv for inv in invoice_list if inv.to_dict().get("billing_reason") in ("subscription_create", "subscription_cycle")),
        None,
    )
    if target_invoice is not None:
        charge_id = await _resolve_invoice_charge_id(target_invoice["id"])
        if charge_id:
            try:
                charge = await asyncio.to_thread(stripe.Charge.retrieve, charge_id)
                refundable = max(0, charge["amount"] - charge["amount_refunded"])
                refund_amount = min(unused_credit_cents, refundable)
            except stripe.error.StripeError as e:
                logger.error(f"Failed to retrieve charge {charge_id} for subscription {subscription_id}: {e}", exc_info=True)
                refund_amount = 0
        else:
            logger.error(
                f"Could not resolve a charge for invoice {target_invoice['id']} "
                f"(subscription {subscription_id}) - cancelling without refund"
            )

    if refund_amount > 0 and charge_id:
        try:
            await asyncio.to_thread(stripe.Refund.create, charge=charge_id, amount=refund_amount)
        except stripe.error.StripeError as e:
            logger.error(f"Failed to refund charge {charge_id} for subscription {subscription_id}: {e}", exc_info=True)
            # 返金に失敗しても解約自体は進める(返金漏れの方が、解約されずに
            # 課金され続けるより実害が小さい)。

    try:
        await asyncio.to_thread(stripe.Subscription.delete, subscription_id, prorate=False)
    except stripe.error.StripeError as e:
        logger.error(f"Failed to cancel subscription {subscription_id} for user {uid}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to cancel web subscription")

    # DB更新は「このStripeサブスクに対応するplan_idの行」だけをピンポイントで
    # expiredにする。Apple購入のRevenueCat webhookがまだ届いていない場合、
    # ユーザーのactiveなmappingが依然このStripeプランのままの可能性がある一方、
    # 逆にApple側のwebhookが先に届いていれば既にこの行はexpired済みのはず。
    # 「ユーザーの現在activeな行を無条件にexpiredにする」実装だと、後者の場合に
    # 誤って新しく切り替わったApple側のmappingを壊してしまうため、必ず
    # plan_idで絞り込む。
    try:
        plan_lookup_res = await asyncio.to_thread(
            lambda: admin_client.table("subscription_plans")
                .select("id")
                .eq("stripe_price_id", current_stripe_price_id)
                .maybe_single()
                .execute()
        )
        stripe_plan_id = plan_lookup_res.data.get("id") if plan_lookup_res and plan_lookup_res.data else None
    except Exception as e:
        logger.warning(f"Failed to resolve plan for stripe price {current_stripe_price_id}: {e}")
        stripe_plan_id = None

    if stripe_plan_id:
        try:
            await asyncio.to_thread(
                lambda: admin_client.table("user_subscription_mappings")
                    .update({"status": "expired"})
                    .eq("user_id", uid)
                    .eq("plan_id", stripe_plan_id)
                    .eq("status", "active")
                    .execute()
            )
        except Exception as e:
            logger.warning(f"Cancelled Stripe subscription {subscription_id} but failed to update mapping status for user {uid}: {e}")

    return {"status": "cancelled", "refunded_usd": refund_amount / 100}


async def _attempt_cancel_stripe_for_platform_switch(admin_client, uid: str) -> dict:
    """
    _cancel_stripe_subscription_for_platform_switchを呼び、失敗したら
    platform_switch_cancellation_retriesに行を積んでパトロール
    (_patrol_reconcile_cross_platform_subscriptions)に委ねる。呼び出し元
    (RevenueCat webhook、/billing/stripe/cancel-for-platform-switch)の
    処理自体は失敗させない。成功時は既存のretry行があれば掃除する。
    """
    try:
        result = await _cancel_stripe_subscription_for_platform_switch(admin_client, uid)
        try:
            await asyncio.to_thread(
                lambda: admin_client.table("platform_switch_cancellation_retries")
                    .delete()
                    .eq("user_id", uid)
                    .execute()
            )
        except Exception:
            pass
        return result
    except Exception as e:
        logger.warning(f"Failed to cancel Stripe subscription for platform switch (user {uid}), queued for retry: {e}")
        try:
            await asyncio.to_thread(
                lambda: admin_client.table("platform_switch_cancellation_retries")
                    .upsert({"user_id": uid})
                    .execute()
            )
        except Exception as e2:
            logger.error(f"Failed to queue platform-switch cancellation retry for user {uid}: {e2}", exc_info=True)
        return {"status": "cancellation_failed_queued_for_retry"}


@app.post("/billing/stripe/cancel-for-platform-switch")
async def billing_stripe_cancel_for_platform_switch(request: Request):
    """
    Apple IAP購入が成功した直後に、Flutter側から呼ばれる。ユーザーがWeb
    (Stripe)の契約を残したままAppleでも契約してしまう(=実際の二重課金が
    継続する)のを防ぐため、Stripeサブスクを即時解約し、未消化期間分を
    日割りで返金する。

    実行順序は意図的に「Apple購入が先、これは後」にしてある: 逆順(先に
    Stripeを解約・返金してからApple購入)だと、ユーザーがApple購入シートを
    キャンセルした時点で「解約・返金だけ実行され、何も買えていない」という
    損失が発生するため。この順序なら、ここが失敗しても損失は発生しない
    (失敗はretryキューに積まれ、_patrol_reconcile_cross_platform_
    subscriptionsが後から回収する。RevenueCat webhook側にも同じ処理を
    ベストエフォートで仕込んであるため、このエンドポイント自体が呼ばれ
    なくても大抵は先に解消される)。

    注意: webhook側と違い、ここには「Sandbox購入では走らせない」ガードが
    無い(呼び出し元のクライアントが購入環境を自己申告する形になり、信頼
    境界として使えないため)。StoreKit Sandbox/TestFlightでの購入テストは
    必ず開発用バックエンドに向けて行うこと — 本番バックエンドに向けると、
    そのアカウントの本物のStripeサブスクが即時解約+返金される。
    """
    uid = await _get_authenticated_user_id(request)
    admin_client = get_supabase_client()
    return await _attempt_cancel_stripe_for_platform_switch(admin_client, uid)


@app.get("/billing/stripe/has-active-subscription")
async def billing_stripe_has_active_subscription(request: Request):
    """
    Flutter側がApple IAP購入前に「今Stripeがアクティブか」を確認するための
    軽量エンドポイント。claim_modeはApple/Stripeを区別できない(1tier1行の
    設計)ため、常にStripe APIへライブ問い合わせして答える — この値を
    /billing/summaryのような頻繁にポーリングされるエンドポイントの恒久
    フィールドにはしない。
    """
    uid = await _get_authenticated_user_id(request)
    admin_client = get_supabase_client()

    profile_res = await asyncio.to_thread(
        lambda: admin_client.table("user_profiles")
            .select("stripe_customer_id")
            .eq("id", uid)
            .maybe_single()
            .execute()
    )
    customer_id = profile_res.data.get("stripe_customer_id") if profile_res and profile_res.data else None
    if not customer_id:
        return {"active": False}

    try:
        subs = await asyncio.to_thread(stripe.Subscription.list, customer=customer_id, status="active", limit=1)
    except stripe.error.StripeError as e:
        logger.error(f"Failed to list Stripe subscriptions for customer {customer_id}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to look up current subscription")

    return {"active": bool(subs["data"])}


@app.post("/billing/stripe/resume-plan")
async def billing_stripe_resume_plan(request: Request):
    """
    Stripeで予約された解約(scheduled_cancel)やダウングレード(scheduled_downgrade)を
    取り消し、現在のプランのまま自動更新を続ける状態に戻す。引数は不要 —
    ユーザーの「今アクティブなStripeサブスク」に対して、予約を解除するだけ。

    Apple(RevenueCat)経由の予約はこちらから取り消せない(switch-planと同じ既知の
    制限: Appleの公式サブスク管理APIには「予約を取り消す」操作が存在せず、
    ユーザー本人がiOS端末のApp Store設定から操作する以外に手段が無い)。
    そのため、Stripe側に実際に予約されている形跡(スケジュール or
    cancel_at_period_end)が見つからない場合は、Apple経由の予約だと判断して
    APPLE_MANAGED_SUBSCRIPTIONを返す。
    """
    uid = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()
    await _reject_if_suspended(admin_client, uid)

    profile_res = await asyncio.to_thread(
        lambda: admin_client.table("user_profiles")
            .select("stripe_customer_id")
            .eq("id", uid)
            .maybe_single()
            .execute()
    )
    customer_id = profile_res.data.get("stripe_customer_id") if profile_res and profile_res.data else None

    active_subscription = None
    if customer_id:
        try:
            subs = await asyncio.to_thread(stripe.Subscription.list, customer=customer_id, status="active", limit=1)
            if subs["data"]:
                active_subscription = subs["data"][0]
        except stripe.error.StripeError as e:
            logger.error(f"Failed to list Stripe subscriptions for customer {customer_id}: {e}", exc_info=True)
            raise HTTPException(status_code=502, detail="Failed to look up current subscription")

    def apple_managed_error() -> HTTPException:
        return HTTPException(
            status_code=409,
            detail={
                "error_code": "APPLE_MANAGED_SUBSCRIPTION",
                "message": "This change was scheduled through the App Store and can only be undone in your iOS device's account settings.",
            },
        )

    if not active_subscription:
        raise apple_managed_error()

    subscription_id = active_subscription["id"]
    schedule_id = active_subscription["schedule"]
    resumed = False

    if schedule_id:
        try:
            await asyncio.to_thread(stripe.SubscriptionSchedule.release, schedule_id)
        except stripe.error.StripeError as e:
            logger.error(f"Failed to release schedule {schedule_id}: {e}", exc_info=True)
            raise HTTPException(status_code=502, detail="Failed to resume subscription")
        resumed = True

    if active_subscription["cancel_at_period_end"]:
        try:
            await asyncio.to_thread(stripe.Subscription.modify, subscription_id, cancel_at_period_end=False)
        except stripe.error.StripeError as e:
            logger.error(f"Failed to un-cancel Stripe subscription {subscription_id}: {e}", exc_info=True)
            raise HTTPException(status_code=502, detail="Failed to resume subscription")
        resumed = True

    if not resumed:
        # Stripe側には予約の形跡が無い = pending_plan_idはApple由来。
        raise apple_managed_error()

    await _clear_stripe_pending_plan(admin_client, uid)
    return {"status": "resumed"}


async def _notify_revenuecat_of_stripe_subscription(subscription_id: str, uid: str) -> None:
    """
    RevenueCatの外部購入追跡API。実際のクレジット付与はここでは行わない
    (RevenueCatが後追いで送ってくる/billing/revenuecat-webhookのINITIAL_PURCHASE/
    RENEWALが既存経路でgrant_store_subscription_credits()を呼ぶ)。
    """
    if not REVENUECAT_STRIPE_PUBLIC_API_KEY:
        logger.error("REVENUECAT_STRIPE_PUBLIC_API_KEY not set - cannot notify RevenueCat of Stripe subscription")
        raise RuntimeError("revenuecat_not_configured")

    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.post(
            "https://api.revenuecat.com/v1/receipts",
            headers={
                "Authorization": f"Bearer {REVENUECAT_STRIPE_PUBLIC_API_KEY}",
                "X-Platform": "stripe",
            },
            json={"app_user_id": uid, "fetch_token": subscription_id},
        )
        response.raise_for_status()


async def _handle_stripe_subscription_invoice_paid(event: dict) -> dict:
    """
    invoice.payment_succeeded受信時の処理。RevenueCatへの通知が成功した後にだけ
    冪等性マーカーを記録する(先に記録してしまうと、通知が失敗した時にStripeの
    再送を「処理済み」として誤って無視してしまうため)。RevenueCatの
    POST /v1/receipts自体は同じsubscription idを複数回送っても安全な設計
    (レシート確認と同じ考え方)なので、ごく稀な同時配信による多重呼び出しは許容する。
    """
    event_id = event["id"]
    admin_client = get_supabase_client()

    existing = await asyncio.to_thread(
        lambda: admin_client.table("revenuecat_webhook_events")
            .select("event_id")
            .eq("event_id", event_id)
            .maybe_single()
            .execute()
    )
    if existing and existing.data:
        return {"status": "already_processed", "event_type": "invoice.payment_succeeded"}

    invoice = event["data"]["object"]
    # 2025年のAPIバージョン変更(Basil)でInvoice.subscriptionは
    # parent.subscription_details.subscriptionへ移動している。
    parent = invoice["parent"]
    subscription_details = parent["subscription_details"] if parent else None
    subscription_id = subscription_details["subscription"] if subscription_details else None
    if not subscription_id:
        # サブスクに紐づかない請求(単発invoice等)。今回のスコープ外なので無視する。
        return {"status": "ignored", "reason": "not_a_subscription_invoice"}

    try:
        subscription = await asyncio.to_thread(stripe.Subscription.retrieve, subscription_id)
    except stripe.error.StripeError as e:
        logger.error(f"Failed to retrieve Stripe subscription {subscription_id}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to look up subscription")

    uid = subscription["metadata"].to_dict().get("supabase_user_id")
    if not uid:
        logger.error(f"Stripe subscription {subscription_id} missing supabase_user_id metadata")
        return {"status": "ignored", "reason": "missing_metadata"}

    # save_default_payment_method="on_subscription"(サブスク作成時に指定)は
    # Subscription.default_payment_methodにしかカードを残さない。後で単発の
    # Invoice(アップグレード日割り請求等)を作る際にCustomer側の既定カードが
    # 必要になるため、初回決済成功のタイミングでCustomerにも書き戻しておく。
    default_payment_method = subscription["default_payment_method"]
    if default_payment_method:
        try:
            await asyncio.to_thread(
                stripe.Customer.modify,
                subscription["customer"],
                invoice_settings={"default_payment_method": default_payment_method},
            )
        except stripe.error.StripeError as e:
            logger.warning(f"Failed to set default payment method on customer for subscription {subscription_id}: {e}")

    try:
        await _notify_revenuecat_of_stripe_subscription(subscription_id, uid)
    except Exception as e:
        logger.error(f"Failed to notify RevenueCat of Stripe subscription {subscription_id}: {e}", exc_info=True)
        raise HTTPException(status_code=502, detail="Failed to notify RevenueCat")

    try:
        await asyncio.to_thread(
            lambda: admin_client.table("revenuecat_webhook_events")
                .insert({"event_id": event_id, "event_type": "STRIPE_INVOICE_PAYMENT_SUCCEEDED"})
                .execute()
        )
    except Exception as e:
        # 既に他プロセスが同時に処理し終えていた場合のunique制約違反等。
        # RevenueCatへの通知自体は成功しているので致命的ではない。
        logger.warning(f"Could not record idempotency marker for stripe event {event_id}: {e}")

    return {"status": "success", "event_type": "invoice.payment_succeeded"}


@app.post("/billing/stripe-webhook")
async def billing_stripe_webhook(request: Request, stripe_signature: str = Header(None, alias="Stripe-Signature")):
    """
    2種類のイベントを扱う:
    - payment_intent.succeeded: create-credit-pack-paymentで作られたPaymentIntentの
      完了通知。grant_credit_pack_purchase()で追加クレジットを直接付与する。
    - invoice.payment_succeeded: switch-planで作られたSubscriptionの
      請求が確定した通知。ここではクレジットを付与せず、RevenueCatの外部購入追跡API
      に知らせるだけ(実際の付与はRevenueCatが送り返してくる/billing/revenuecat-webhook
      が既存経路で行う)。

    冪等性はrevenuecat_webhook_events.event_idへの記録で担保する(テーブル名は
    歴史的経緯でrevenuecat_webhook_eventsのままだが、event_id text primary keyの
    汎用的な冪等性台帳として問題なく共用できる)。
    """
    if not STRIPE_WEBHOOK_SECRET:
        logger.warning("STRIPE_WEBHOOK_SECRET not set - rejecting Stripe webhook")
        raise HTTPException(status_code=401, detail="Webhook not configured")

    raw_body = await request.body()
    try:
        event = stripe.Webhook.construct_event(raw_body, stripe_signature, STRIPE_WEBHOOK_SECRET)
    except (ValueError, stripe.error.SignatureVerificationError) as e:
        logger.warning(f"Rejected Stripe webhook: invalid signature - {e}")
        raise HTTPException(status_code=401, detail="Invalid webhook signature")

    event_id = event["id"]
    event_type = event["type"]

    if event_type == "invoice.payment_succeeded":
        return await _handle_stripe_subscription_invoice_paid(event)

    if event_type == "invoice.paid":
        # トライアル開始時の$0請求書はamount_due=0のまま自動的にpaid扱いになり、
        # invoice.payment_succeededは発火しない(invoice.paidだけが飛んでくる)。
        # 通常の課金はinvoice.payment_succeeded側で既に処理しているので、ここは
        # $0請求書(トライアル開始)だけを拾う。それ以外のinvoice.paidは無視する
        # (invoice.payment_succeededと二重にRevenueCat通知を送らないため)。
        invoice = event["data"]["object"]
        if invoice.to_dict().get("amount_due") == 0:
            return await _handle_stripe_subscription_invoice_paid(event)
        return {"status": "ignored", "reason": "non_zero_invoice_paid_handled_by_payment_succeeded"}

    if event_type != "payment_intent.succeeded":
        return {"status": "ignored", "event_type": event_type}

    intent = event["data"]["object"]
    metadata = intent["metadata"].to_dict()
    uid = metadata.get("supabase_user_id")
    stripe_price_id = metadata.get("stripe_price_id")

    if not uid or not stripe_price_id:
        # サブスクの初回課金・アップグレード差額の請求もpayment_intent.succeededを
        # 発火させるが、それらにこのmetadataは載らない(載せているのは
        # create-credit-pack-paymentだけ)。つまりこれは異常ではなく
        # 「クレジットパック購入ではない」という判別結果なので、エラーとして
        # 記録しない —— ここをERRORで出していると毎回のサブスク課金でログが汚れ、
        # 本物の設定ミスが埋もれる。
        return {"status": "ignored", "reason": "not_a_credit_pack_payment"}

    admin_client = get_supabase_client()
    try:
        await asyncio.to_thread(
            lambda: admin_client.rpc("grant_credit_pack_purchase", {
                "p_user_id": uid,
                "p_event_id": event_id,
                "p_product_id": stripe_price_id,
                "p_event_type": "STRIPE_PAYMENT_INTENT_SUCCEEDED",
            }).execute()
        )
    except Exception as e:
        error_str = str(e)
        if "unknown_credit_pack" in error_str:
            # 恒久的な設定ミス(credit_packs.stripe_price_idが未登録)。リトライしても
            # 直らないため、ログだけ残して200で止める(revenuecat_webhookと同じ方針)。
            logger.error(f"Stripe webhook: unknown credit pack - {error_str} (price_id={stripe_price_id})")
            return {"status": "error_logged", "reason": "unknown_product"}
        logger.error(f"Stripe webhook processing failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal error processing webhook")

    return {"status": "success", "event_type": event_type}


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


async def _load_task_and_job(admin_client, task_id: str) -> tuple[dict, dict]:
    """task_idからタスク行と、それが属するジョブ行を引く。無ければ404。

    所有者チェックはここではしない —— 呼び出し側の文脈で違うため
    (/retry-task は本人であることを要求し、Adminダッシュボードは要求しない)。
    """
    task_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_tasks").select("id, job_id, task_type, status")
            .eq("id", task_id).single().execute()
    )
    if not task_res.data:
        raise HTTPException(status_code=404, detail="Task not found")
    task = task_res.data

    job_res = await asyncio.to_thread(
        lambda: admin_client.table("processing_jobs").select("id, user_id, lecture_id")
            .eq("id", task["job_id"]).single().execute()
    )
    if not job_res.data:
        raise HTTPException(status_code=404, detail="Job not found")
    return task, job_res.data


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
    user_id = await _get_authenticated_user_id(request)

    admin_client = get_supabase_client()
    await _reject_if_suspended(admin_client, user_id)

    task, job = await _load_task_and_job(admin_client, payload.task_id)

    # タスク→ジョブ経由で所有者を検証（他人のタスクを操作できないように）
    if job["user_id"] != user_id:
        raise HTTPException(status_code=403, detail="Not authorized to retry this task")

    return await _perform_task_retry(admin_client, task, job)


async def _perform_task_retry(admin_client, task: dict, job: dict) -> dict:
    """
    リトライ本体(所有者チェックより後ろの部分)。/retry-task と
    Adminダッシュボードの /admin/tasks/{id}/retry が同じ実装を共有するために
    切り出してある —— 復旧手順が2箇所に分かれると、片方だけ直したときに
    もう片方が壊れた状態のまま残るため。
    """
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
    uid, lecture_id = job["user_id"], job["lecture_id"]
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
        "task_id": task["id"],
        "affected_task_types": sorted(affected_types),
    }

# ---------------------------------------------------------
# 司令塔 (orchestrator)
# ---------------------------------------------------------
@app.post("/webhook/orchestrator")
async def orchestrator_webhook(request: Request, x_webhook_secret: str = Header(None)):
    # 0. セキュリティチェック: SupabaseのWebhookからのリクエストか検証
    #
    # ★ 以前は `if WEBHOOK_SECRET and ...` だったため、WEBHOOK_SECRETが未設定の
    #   環境ではこのエンドポイントが誰でも叩ける状態になっていた。「設定漏れなら
    #   素通し」はフェイルオープンで、最も危険な失敗の仕方。未設定なら全拒否にする。
    if not WEBHOOK_SECRET:
        logger.error("WEBHOOK_SECRET is not configured; rejecting orchestrator webhook")
        raise HTTPException(status_code=503, detail="Webhook is not configured")
    if not x_webhook_secret or not hmac.compare_digest(x_webhook_secret, WEBHOOK_SECRET):
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
    request: Request,
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
    admin_client = get_supabase_client()
    await _resolve_audio_upload_uid(request, admin_client, lecture_id)

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
@app.post("/worker/transcribe-chunk-process", dependencies=[Depends(require_internal_caller)])
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
async def worker_request_master_audio_upload_url(payload: MasterAudioUploadUrlRequest, request: Request):
    """マスター音声をR2へ直接PUTするための署名付きURLを発行する。"""
    admin_client = get_supabase_client()
    uid = await _resolve_audio_upload_uid(request, admin_client, payload.lecture_id)

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
async def worker_complete_master_audio_upload(payload: MasterAudioUploadCompleteRequest, request: Request):
    """
    Flutterが直接R2へのPUTを終えた後に呼ぶ。クライアントの自己申告を鵜呑みにせず、
    実際にR2上にファイルが存在することを確認してからaudio_pathを更新する。
    """
    supabase = get_supabase_client()
    uid = await _resolve_audio_upload_uid(request, supabase, payload.lecture_id)

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
# R2上のASRモデル自体はユーザーに紐付かない共有アセットだが、他エンドポイントと
# 同様、ログイン済みユーザーからの呼び出しであることだけは確認しておく。


@app.post("/asr-models/manifest")
async def get_asr_models_manifest(request: Request):
    """録音言語ごとのオンデバイスASRモデル一覧(engineCompatVersion/modelVersion
    込みのマニフェスト)を返す。R2の asr_models/manifest.json をそのまま返すだけ。"""
    await _get_authenticated_user_id(request)  # 認証チェックのみ(user_idは使わない)

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
    await _get_authenticated_user_id(request)  # 認証チェックのみ(user_idは使わない)

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
@app.post("/enqueue-task", status_code=202, dependencies=[Depends(require_internal_caller)])
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
            "headers": {"Content-Type": "application/json", **internal_task_headers()},
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
            "headers": {"Content-Type": "application/json", **internal_task_headers()},
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
            "headers": {"Content-Type": "application/json", **internal_task_headers()},
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
            "headers": {"Content-Type": "application/json", **internal_task_headers()},
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


async def enqueue_chat_summary_task(thread_id: str, next_block_index: int) -> None:
    """
    /worker/chat-summary を叩くCloud Tasksタスクをenqueueする(スレッド要約、
    app/services/chat_summary.py)。チャットの返答が終わった後に呼ばれる。

    畳むのが追いつくまでは毎ターン呼ばれるので、name を thread_id + 次に作る
    ブロック番号 + 時間バケットで決め、同じ畳みの二重enqueueはCloud Tasks側で弾く。
    すり抜けて2つ走っても、chat_summary_blocksの一意制約で二重には畳まれない。
    """
    if not (PROJECT_ID and CLOUD_RUN_URL and SERVICE_ACCOUNT_EMAIL):
        raise RuntimeError("❌ Missing Environment Variables for Cloud Tasks enqueue!")

    parent = client.queue_path(PROJECT_ID, REGION, CHAT_QUEUE_NAME)
    task = {
        "name": client.task_path(
            PROJECT_ID, REGION, CHAT_QUEUE_NAME,
            f"chat-summary-{thread_id}-{next_block_index}-{_dedup_bucket()}",
        ),
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": f"{CLOUD_RUN_URL}/worker/chat-summary",
            "headers": {"Content-Type": "application/json", **internal_task_headers()},
            "body": json.dumps({"thread_id": thread_id}).encode(),
            "oidc_token": {
                "service_account_email": SERVICE_ACCOUNT_EMAIL,
                "audience": CLOUD_RUN_URL,
            }
        }
    }

    try:
        response = await asyncio.to_thread(client.create_task, request={"parent": parent, "task": task})
        print(f"✅ Enqueued chat_summary for thread {thread_id} (block {next_block_index}): {response.name}")
    except AlreadyExists:
        print(f"⏭️ Chat summary for thread {thread_id} (block {next_block_index}) already enqueued.")


async def _enqueue_profile_task(path: str, body: dict, name_suffix: str) -> None:
    """自分像プロフィールの観察役・まとめ役のタスクを積む。同じ対象・同じ時間帯の二重enqueueは名前で弾く。"""
    if not (PROJECT_ID and CLOUD_RUN_URL and SERVICE_ACCOUNT_EMAIL):
        raise RuntimeError("❌ Missing Environment Variables for Cloud Tasks enqueue!")
    parent = client.queue_path(PROJECT_ID, REGION, PROFILE_QUEUE_NAME)
    task = {
        "name": client.task_path(PROJECT_ID, REGION, PROFILE_QUEUE_NAME, f"{name_suffix}-{_dedup_bucket()}"),
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": f"{CLOUD_RUN_URL}{path}",
            "headers": {"Content-Type": "application/json", **internal_task_headers()},
            "body": json.dumps(body).encode(),
            "oidc_token": {"service_account_email": SERVICE_ACCOUNT_EMAIL, "audience": CLOUD_RUN_URL},
        },
    }
    try:
        await asyncio.to_thread(client.create_task, request={"parent": parent, "task": task})
    except AlreadyExists:
        pass


async def enqueue_profile_observe_task(thread_id: str) -> None:
    await _enqueue_profile_task("/worker/profile-observe", {"thread_id": thread_id}, f"profile-observe-{thread_id}")


async def enqueue_profile_consolidate_task(user_id: str) -> None:
    await _enqueue_profile_task("/worker/profile-consolidate", {"user_id": user_id}, f"profile-consolidate-{user_id}")


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

@app.post("/worker/check-and-assemble", dependencies=[Depends(require_internal_caller)])
async def worker_check_and_assemble(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_check_and_assemble_transcript_task)

@app.post("/worker/transcribe-master", dependencies=[Depends(require_internal_caller)])
async def worker_transcribe_master(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_transcribe_master_task)

@app.post("/worker/role-classification", dependencies=[Depends(require_internal_caller)])
async def worker_role_classification(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_role_classification_task)

@app.post("/worker/core-extraction", dependencies=[Depends(require_internal_caller)])
async def worker_core_extraction(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_core_extraction_task)

@app.post("/worker/announcement-generation", dependencies=[Depends(require_internal_caller)])
async def worker_announcement_generation(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_announcement_generation_task)

@app.post("/worker/topic-mapping", dependencies=[Depends(require_internal_caller)])
async def worker_topic_mapping(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_topic_mapping_task)

@app.post("/worker/review-card", dependencies=[Depends(require_internal_caller)])
async def worker_review_card(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_review_card_task)

@app.post("/worker/image-prompt-generation", dependencies=[Depends(require_internal_caller)])
async def worker_image_prompt_generation(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_image_prompt_generation_task)

@app.post("/worker/image-rendering", dependencies=[Depends(require_internal_caller)])
async def worker_image_rendering(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_image_rendering_task)

@app.post("/worker/fun-fact-brainstorming", dependencies=[Depends(require_internal_caller)])
async def worker_fun_fact_brainstorming(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_fun_fact_brainstorming_task)

@app.post("/worker/fun-fact-search", dependencies=[Depends(require_internal_caller)])
async def worker_fun_fact_search(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_fun_fact_search_task)

@app.post("/worker/fun-facts-generation", dependencies=[Depends(require_internal_caller)])
async def worker_fun_facts_generation(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_fun_facts_task)

@app.post("/worker/detail-contents", dependencies=[Depends(require_internal_caller)])
async def worker_detail_contents(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_detail_contents_task)

@app.post("/worker/finalize-job", dependencies=[Depends(require_internal_caller)])
async def worker_finalize_job(payload: WorkerPayload, request: Request):
    return await _run_worker_task(request, payload, run_finalize_job_task)


@app.post("/worker/renew-subscription", dependencies=[Depends(require_internal_caller)])
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


@app.post("/worker/chat-summary", dependencies=[Depends(require_internal_caller)])
async def worker_chat_summary(payload: ChatSummaryPayload, request: Request):
    """
    enqueue_chat_summary_task がenqueueしたタスクを処理する(スレッドの古い往復を要約に畳む)。
    失敗したらCloud Tasksの自動リトライに任せるが、CHAT_SUMMARY_MAX_ATTEMPTS回目で
    打ち切る(要約役の出力が壊れ続ける場合に、LLM呼び出しを繰り返さないため)。
    打ち切っても、次のチャットのターンで条件を満たしていればまた積まれる。
    """
    try:
        created = await run_chat_summary_fold(payload.thread_id)
    except Exception as e:
        retry_count = int(request.headers.get("X-CloudTasks-TaskRetryCount", "0"))
        if retry_count >= CHAT_SUMMARY_MAX_ATTEMPTS - 1:
            print(f"❌ [chat-summary] giving up on thread {payload.thread_id} after {retry_count + 1} attempts: {e}")
            return {"status": "gave_up"}
        raise
    return {"status": "success", "blocks_created": created}


@app.post("/worker/profile-observe", dependencies=[Depends(require_internal_caller)])
async def worker_profile_observe(payload: ProfileObservePayload, request: Request):
    """
    自分像プロフィールの観察役(app/services/profile_store.py)。1スレッドのまだ読んでいない部分を観察する。
    まとめ役に渡していない観察がたまったら、そのユーザーのまとめ役のタスクを積む。
    失敗はCloud Tasksのリトライに任せ、PROFILE_TASK_MAX_ATTEMPTS回目で打ち切る(急ぎの処理ではない)。
    """
    try:
        result = await profile_store.observe_thread_task(payload.thread_id)
    except Exception as e:
        retry_count = int(request.headers.get("X-CloudTasks-TaskRetryCount", "0"))
        if retry_count >= PROFILE_TASK_MAX_ATTEMPTS - 1:
            print(f"❌ [profile-observe] giving up on thread {payload.thread_id} after {retry_count + 1} attempts: {e}")
            return {"status": "gave_up"}
        raise
    if result.get("consolidate_user_id"):
        try:
            await enqueue_profile_consolidate_task(result["consolidate_user_id"])
        except Exception as e:
            # 積めなくても、patrolが「たまっているユーザー」を拾い直す
            print(f"⚠️ [profile-observe] failed to enqueue consolidation: {e}")
    return result


@app.post("/worker/profile-consolidate", dependencies=[Depends(require_internal_caller)])
async def worker_profile_consolidate(payload: ProfileConsolidatePayload, request: Request):
    """自分像プロフィールのまとめ役(+必要なら表紙の書き直し)。"""
    try:
        return await profile_store.consolidate_user_task(payload.user_id)
    except Exception as e:
        retry_count = int(request.headers.get("X-CloudTasks-TaskRetryCount", "0"))
        if retry_count >= PROFILE_TASK_MAX_ATTEMPTS - 1:
            print(f"❌ [profile-consolidate] giving up on user {payload.user_id} after {retry_count + 1} attempts: {e}")
            return {"status": "gave_up"}
        raise


@app.post("/worker/cleanup-audio-chunks", dependencies=[Depends(require_internal_caller)])
async def worker_cleanup_audio_chunks(payload: CleanupAudioChunksPayload):
    """
    _patrol_enqueue_audio_chunks_cleanup がenqueueしたタスクを実際に処理する。
    指定講義の R2 audio_chunks/ 配下を一括削除し、
    lectures テーブルの audio_chunks_cleaned カラムおよび metadata (jsonb) に True を記録する。
    """
    admin_client = get_supabase_client()
    from app.core.r2_storage import storage_service

    # 1. R2 の audio_chunks/ 配下を全削除
    prefix = f"{payload.user_id}/{payload.lecture_id}/audio_chunks/"
    deleted_count = await asyncio.to_thread(storage_service.delete_prefix, prefix)
    print(f"🧹 Cleaned up {deleted_count} audio chunks in R2 for lecture {payload.lecture_id}")

    # 2. Supabase の lectures (audio_chunks_cleaned カラム ＆ metadata) にフラグを記録
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
            .update({
                "audio_chunks_cleaned": True,
                "metadata": current_metadata,
            })
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

async def _require_course_owner(admin_client, course_id: str, user_id: str) -> None:
    """course_idがそのユーザー自身のCourseであることを確認する。

    course_idはクライアント申告値なので、それだけで書き込み先が決まる
    エンドポイント(/topic-map/*)では必ずこれを通すこと。
    """
    res = await asyncio.to_thread(
        lambda: admin_client.table("courses").select("user_id").eq("id", course_id).maybe_single().execute()
    )
    row = res.data if res else None
    if not row:
        raise HTTPException(status_code=404, detail=f"Course {course_id} not found")
    if row["user_id"] != user_id:
        logger.warning(f"User {user_id} attempted to access course {course_id} owned by {row['user_id']}")
        raise HTTPException(status_code=403, detail="You do not have access to this course")


@app.post("/topic-map/mark-stale")
async def topic_map_mark_stale(payload: TopicMapMarkStaleRequest, request: Request):
    """
    Lectureの削除・Course移動が起きた瞬間にFlutterから呼ばれる。LLMは呼ばず、
    pending_removals/pending_additionsに記録してis_staleを立てるだけ。
    実際のグラフ修復は「Recreate Topic Map」操作かPatrolのアイドルタイムアウトが行う。

    ★ 以前はこのエンドポイントに認証が無く、course_id/lecture_idさえ知っていれば
      誰でも他人のTopic Mapをstaleにできる(=他人のグラフを壊せる)状態だった。
      クライアント(Flutter/webapp)は元からAuthorizationヘッダを送っているので、
      検証を足してもクライアント側の変更は要らない。
    """
    user_id = await _get_authenticated_user_id(request)
    admin_client = get_supabase_client()
    await _require_course_owner(admin_client, payload.course_id, user_id)
    await _require_lecture_owner(admin_client, payload.lecture_id, user_id)

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
async def topic_map_reconstruct(payload: TopicMapReconstructRequest, request: Request):
    """
    「Recreate Topic Map」ボタンから呼ばれる。pending_removals/pending_additionsを
    まとめて消化し、Phase A(決定的除去)→Phase B(LLMによる修復)を同期的に実行する。

    ★ 以前は認証が無かった。LLMを1回叩く=実費が出る処理なので、course_idを
      総当たりするだけで無制限にコストを発生させられる状態でもあった。
    """
    user_id = await _get_authenticated_user_id(request)
    admin_client = get_supabase_client()
    await _require_course_owner(admin_client, payload.course_id, user_id)
    await _reject_if_suspended(admin_client, user_id)

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

    # 4.5 横断チャットボットの会話(要約→メッセージ→スレッドの順)と検索インデックス。
    #     どれもuser_idのON DELETE CASCADEでauth.users削除時に消えるが、
    #     他のテーブルと同じくカスケードに依存せず明示的に消す。
    #     自分像プロフィールも同じ(根拠のつながり→項目→観察の順。どれもuser_idでCASCADEする)。
    for profile_table in ("profile_item_evidence", "profile_item_versions", "profile_items", "profile_observations",
                          "profile_categories", "ai_memos", "profile_hypotheses", "profile_blocked_areas",
                          "profile_cover_proposals", "profile_extraction_state"):
        await asyncio.to_thread(
            lambda t=profile_table: admin_client.table(t).delete().eq("user_id", uid).execute()
        )
    for chat_table in ("chat_summary_blocks", "chat_attachments", "chat_messages", "chat_threads", "knowledge_chunks"):
        await asyncio.to_thread(
            lambda t=chat_table: admin_client.table(t).delete().eq("user_id", uid).execute()
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
    uid = await _get_authenticated_user_id(request)
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

    cancelled = await _cancel_jobs_for_lecture(admin_client, lecture_id)
    return {"success": True, "cancelled_jobs": cancelled}


async def _cancel_jobs_for_lecture(admin_client, lecture_id: str) -> int:
    """
    講義の未完了ジョブとそのタスクをCANCELLEDにする本体(所有者チェックより
    後ろの部分)。/lectures/{id}/cancel-jobs と Adminダッシュボードの
    /admin/lectures/{id}/cancel-jobs が同じ実装を共有するために切り出してある。
    """
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
    return len(job_ids)


@app.post("/lectures/{lecture_id}/hard-delete")
async def hard_delete_lecture_endpoint(lecture_id: str, request: Request):
    """
    ゴミ箱(Trash)に入っている講義1件を完全削除する。
    Supabase側のカスケード設定に依存せず、_hard_delete_lecture が
    子テーブル・R2ファイルまで含めて明示的に削除する。
    """
    uid = await _get_authenticated_user_id(request)
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
    uid = await _get_authenticated_user_id(request)
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
    uid = await _get_authenticated_user_id(request)
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


KNOWLEDGE_INDEX_QUEUE_PATROL_BATCH_SIZE = int(os.getenv("KNOWLEDGE_INDEX_QUEUE_PATROL_BATCH_SIZE", "200"))


async def _patrol_drain_knowledge_index_queue() -> dict:
    """
    横断チャットボット用knowledge_chunksの取りこぼし回収。
    FINALIZE_JOBは講義処理完了直後に同じ関数をその場で呼んでいるので、
    ここで拾うのは主にFlutterからの直接編集(outbox経由でSupabaseに
    直接書き込まれ、バックエンドを通らないもの)。
    patrol()の中でPATROL_CHECKS(30分おき)とは別枠で毎回(10分おき)
    呼ばれているので、最悪でも10分以内にチャットの検索対象へ反映される。
    """
    return await drain_knowledge_index_queue(limit=KNOWLEDGE_INDEX_QUEUE_PATROL_BATCH_SIZE)


async def _patrol_fail_stale_chat_messages() -> dict:
    """
    生成中(streaming)のまま取り残されたチャットの返答をerrorにする。
    run_chat_turnは失敗時にも自分でerrorにするが、インスタンスごと落ちた場合
    (Cloud Runのスケールイン等)はそれすら走らない。streamingのままだと
    画面が「生成中」のまま固まり続けるため、ここで確定させる。課金はしない
    (課金は締め処理でしか行わないので、ここに来た返答は元々未課金)。
    送信の二重ロック判定も同じSTREAMING_STALE_MINUTESを使っているので、
    ロックはこのpatrolを待たずに外れる。
    """
    admin_client = get_supabase_client()
    cutoff = (datetime.now(timezone.utc) - timedelta(minutes=STREAMING_STALE_MINUTES)).isoformat()
    res = await asyncio.to_thread(
        lambda: admin_client.table("chat_messages")
            .update({"status": "error"})
            .eq("status", "streaming")
            .lt("created_at", cutoff)
            .execute()
    )
    # 同じ理由で、審査の途中(processing)のまま残った添付資料もfailedにする
    # (processingはスレッドの資料の上限の数に入るので、残り続けると添付できる数が減る)
    att = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments")
            .update({"status": "failed"})
            .eq("status", "processing")
            .lt("created_at", cutoff)
            .execute()
    )
    # 送られなかったファイル(draft)は、行もR2のファイルも消す
    draft_cutoff = (datetime.now(timezone.utc) - timedelta(hours=chat_files.DRAFT_TTL_HOURS)).isoformat()
    drafts = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments").select("id, storage_prefix")
            .eq("status", "draft").lt("created_at", draft_cutoff).limit(200).execute()
    )
    for row in drafts.data or []:
        if row.get("storage_prefix") and "/chat_attachments/" in row["storage_prefix"]:
            try:
                await asyncio.to_thread(storage_service.delete_prefix, row["storage_prefix"])
            except Exception as e:
                print(f"⚠️ [chat] failed to delete draft files {row['storage_prefix']}: {e}")
                continue
        await asyncio.to_thread(
            lambda: admin_client.table("chat_attachments").delete().eq("id", row["id"]).eq("status", "draft").execute())
    return {"failed_stale": len(res.data or []), "failed_stale_attachments": len(att.data or []),
            "expired_drafts": len(drafts.data or [])}


async def _patrol_enqueue_profile_extraction() -> dict:
    """
    自分像プロフィール: しばらく止まっていて、まだ観察していない発言があるスレッドの観察役と、
    観察がたまっている(または古くなった)ユーザーのまとめ役を積む。
    まとめ役は観察役のワーカーが件数を見て積むが、積み損ねや「件数は少ないが1週間たった」はここで拾う。
    """
    admin_client = get_supabase_client()
    threads = await asyncio.to_thread(lambda: admin_client.rpc("list_threads_pending_profile_observation", {
        "idle_minutes": PROFILE_OBSERVE_IDLE_MINUTES, "max_count": PROFILE_PATROL_MAX_THREADS,
    }).execute())
    users = await asyncio.to_thread(lambda: admin_client.rpc("list_users_pending_profile_consolidation", {
        "min_new": profile_store.CONSOLIDATE_MIN_NEW_OBSERVATIONS,
        "max_wait_days": profile_store.CONSOLIDATE_MAX_WAIT_DAYS,
    }).execute())
    observe, consolidate_ = 0, 0
    for row in threads.data or []:
        await enqueue_profile_observe_task(row["thread_id"])
        observe += 1
    for row in users.data or []:
        await enqueue_profile_consolidate_task(row["user_id"])
        consolidate_ += 1
    return {"observe_enqueued": observe, "consolidate_enqueued": consolidate_}


# 将来ここに追加していく（例）:
# async def _patrol_collect_error_reports() -> dict: ...


async def _patrol_materialize_dormant_expired_grants() -> dict:
    """
    クレジットの失効は本来、grant/consume/webhook/更新の各RPC呼び出しの先頭で
    materialize_expired_grants()により即座に実体化される(lazy materialization)。
    このパトロールは、しばらくアプリを開かない等の理由でそれらの経路が
    一切呼ばれないユーザーのための、日次ではなく通常の30分おきPATROL_CHECKS
    ループに乗せるバックストップに過ぎない。credit_grants_expiring_idx
    (user_id, expires_at) where remaining_amount > 0 を使うため、対象が
    いなければ実質コスト0。ユーザーごとに独立してmaterialize_expired_grants
    をRPC呼び出しするので、consume_credits等のロック順と衝突しない
    (一括UPDATEによるスイープは意図的に避けている)。
    """
    admin_client = get_supabase_client()

    stale_res = await asyncio.to_thread(
        lambda: admin_client.table("credit_grants")
            .select("user_id")
            .gt("remaining_amount", 0)
            .lte("expires_at", (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat())
            .execute()
    )
    user_ids = sorted({row["user_id"] for row in (stale_res.data or [])})

    materialized = 0
    failed = 0
    for user_id in user_ids:
        try:
            await asyncio.to_thread(
                lambda user_id=user_id: admin_client.rpc(
                    "materialize_expired_grants", {"p_user_id": user_id}
                ).execute()
            )
            materialized += 1
        except Exception as e:
            failed += 1
            print(f"⚠️ Failed to materialize expired grants for user {user_id}: {e}")

    return {"users_checked": len(user_ids), "materialized": materialized, "failed": failed}


async def _patrol_renew_subscriptions() -> dict:
    """
    以前は「1日1回だけ」patrol()の日次ブロックから呼ばれていたが、
    renew_subscription()自体は既に冪等(current_period_end > nowなら
    即returnするだけ)なので、通常の30分おきPATROL_CHECKSに乗せても安全。
    Freeプラン等self_serveプランの更新が最大24時間遅れる問題(その間
    grant_credits前のcredit_grantsが失効したままになり得る)を解消するため、
    通常のPATROL_CHECKSループに移した。
    全ユーザー分の更新処理をこの呼び出しの中で直接行うと、ユーザー数が
    増えるほどタイムアウトのリスクが上がるため、ここでは「更新期限が
    来ているmapping_idを集めてCloud Tasksに1件ずつ積む」だけの軽い処理に
    留める。実際の更新(grant_credits + current_period_endの前進)は
    /worker/renew-subscription が1件ずつ非同期に処理し、失敗しても他の
    ユーザーの更新には影響しない。
    """
    admin_client = get_supabase_client()

    # claim_mode='store_purchase'のmappingはここで拾ってはいけない —
    # その更新はRevenueCat Webhook経由(grant_store_subscription_credits)
    # でのみ行われるべきで、このパトロールに乗せるとWebhookと二重に
    # current_period_endを進めてしまう。subscription_plansとの埋め込み
    # フィルタ(!inner)でself_serveのみに絞る(renew_subscription()側にも
    # 同種のガードを二重防御として入れてある)。
    due_res = await asyncio.to_thread(
        lambda: admin_client.table("user_subscription_mappings")
            .select("id, subscription_plans!user_subscription_mappings_plan_id_fkey!inner(claim_mode)")
            .eq("status", "active")
            .eq("subscription_plans.claim_mode", "self_serve")
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


async def _patrol_reconcile_cross_platform_subscriptions() -> dict:
    """
    Stripe→Apple乗り換え(Apple購入成功後にStripeを即時解約+返金する設計、
    _cancel_stripe_subscription_for_platform_switch参照)の解約呼び出しが
    失敗した場合の再試行。platform_switch_cancellation_retriesに積まれた
    ユーザーだけを対象にする(全ユーザーをStripe APIでスキャンして「現在の
    契約と食い違うプラン」を機械的に検出する方式は、同一プラットフォーム内
    アップグレード直後の伝播待ちの数秒〜数十秒を誤検出し、正常なStripe
    サブスクを誤解約・誤返金するリスクがあるため採用しない)。
    """
    admin_client = get_supabase_client()

    retry_res = await asyncio.to_thread(
        lambda: admin_client.table("platform_switch_cancellation_retries")
            .select("user_id")
            .execute()
    )
    pending = retry_res.data or []

    reconciled = 0
    failed = 0
    for row in pending:
        uid = row["user_id"]
        try:
            result = await _attempt_cancel_stripe_subscription_for_platform_switch_retry(admin_client, uid)
            if result:
                reconciled += 1
            else:
                failed += 1
        except Exception as e:
            failed += 1
            print(f"⚠️ Failed to reconcile queued platform-switch cancellation for user {uid}: {e}")

    return {"pending": len(pending), "reconciled": reconciled, "failed": failed}


async def _attempt_cancel_stripe_subscription_for_platform_switch_retry(admin_client, uid: str) -> bool:
    """パトロール専用の薄いラッパー。成功したらretry行を消してTrueを返す。
    失敗したら行を残したままFalseを返す(次回パトロールで再試行)。"""
    try:
        await _cancel_stripe_subscription_for_platform_switch(admin_client, uid)
    except Exception as e:
        print(f"⚠️ Retry of platform-switch cancellation still failing for user {uid}: {e}")
        return False

    try:
        await asyncio.to_thread(
            lambda: admin_client.table("platform_switch_cancellation_retries")
                .delete()
                .eq("user_id", uid)
                .execute()
        )
    except Exception:
        pass
    return True


# このプロジェクトの管理者向けメールは全てABUSE_ALERT_EMAIL
# (lefture.app@gmail.com)に固定しているので、専用のenv変数は作らずそれを使う。
# 1日2回(UTC 0時 / 12時固定)。patrol自体が:00付近と:30付近に走るので、
# ここで時だけ見ればよく、タイムゾーン計算は一切要らない。
ERROR_DIGEST_HOURS_UTC = [0, 12]
ERROR_EVENT_RETENTION_DAYS = 30
# 管理者ダッシュボードのURL。ドメイン(app.lefture.com)は決まっているが、
# クライアントエラー一覧ページのパスがまだ無いため、今は空にしてメール本文の
# 「ダッシュボードを開く」ボタン自体を出さない(email_templateはdashboard_urlが
# 空ならボタンを描画しない)。パスが決まったらここに1行足すだけでよい。
#   例: ADMIN_DASHBOARD_URL = "https://app.lefture.com/admin/client-errors"
ADMIN_DASHBOARD_URL = ""


async def _patrol_send_client_error_digest() -> dict:
    """クライアントエラーのダイジェストメールを送る(1日2回)。

    載せるのは「新規 or 前回通知時よりカウントが増えた」グループだけ。
    グループ自体は永続だが、通知は差分でしか出さないので、直っていない
    既知のエラーが毎回受信箱を埋めることはない。
    status='ignored' のグループは完全に除外する。

    新規もカウント増もゼロなら**何も送らない**。ただしそれだと「静か」と
    「パイプラインが壊れた」の区別が付かないので、日曜だけハートビートを送る。
    """
    admin_client = get_supabase_client()
    now = datetime.now(timezone.utc)

    res = await asyncio.to_thread(
        lambda: admin_client.table("client_error_groups")
            .select("*")
            .neq("status", "ignored")
            .order("total_count", desc=True)
            .limit(50)
            .execute()
    )
    all_groups = res.data or []

    changed = []
    for g in all_groups:
        total = g.get("total_count") or 0
        last_notified_count = g.get("count_at_last_notify") or 0
        if g.get("last_notified_at") is None:
            g["is_new"] = True
            g["delta"] = total
            changed.append(g)
        elif total > last_notified_count:
            g["is_new"] = False
            g["delta"] = total - last_notified_count
            changed.append(g)

    # 新規を先に、その中で発生回数の多い順
    changed.sort(key=lambda g: (not g["is_new"], -g["delta"]))

    window_hours = 24 // max(1, len(ERROR_DIGEST_HOURS_UTC))

    if not changed:
        # 日曜のダイジェスト枠でだけハートビートを送る
        if now.weekday() == 6 and now.hour == ERROR_DIGEST_HOURS_UTC[0]:
            try:
                from app.services.email_service import send_email
                from app.services.email_template import build_client_error_heartbeat_email
                await send_email(
                    to=ABUSE_ALERT_EMAIL,
                    subject="[leFture] No new client errors this week",
                    html=build_client_error_heartbeat_email(168),
                    from_address="support@lefture.com",
                    from_name="leFture Error Digest",
                )
                return {"sent": "heartbeat"}
            except Exception as e:
                print(f"⚠️ Failed to send error heartbeat: {e}")
                return {"error": str(e)}
        return {"sent": 0, "reason": "nothing new"}

    total_events = sum(g["delta"] for g in changed)
    new_count = sum(1 for g in changed if g["is_new"])

    try:
        from app.services.email_service import send_email
        from app.services.email_template import build_client_error_digest_email

        subject = (
            f"[leFture] {new_count} new group(s) / {total_events} event(s) "
            f"(last {window_hours}h)"
            if new_count
            else f"[leFture] {total_events} new event(s) in {len(changed)} known group(s)"
        )

        await send_email(
            to=ABUSE_ALERT_EMAIL,
            subject=subject,
            html=build_client_error_digest_email(
                groups=changed,
                window_hours=window_hours,
                total_events=total_events,
                dashboard_url=ADMIN_DASHBOARD_URL,
            ),
            from_address="support@lefture.com",
            from_name="leFture Error Digest",
        )
    except Exception as e:
        # 送信に失敗したら last_notified を進めない —— 次回に持ち越す。
        print(f"❌ Failed to send client error digest: {e}")
        return {"error": str(e)}

    # 送信できた分だけ「通知済み」を進める。
    for g in changed:
        try:
            await asyncio.to_thread(
                lambda fp=g["fingerprint"], c=g.get("total_count") or 0:
                    admin_client.table("client_error_groups").update({
                        "last_notified_at": now.isoformat(),
                        "count_at_last_notify": c,
                    }).eq("fingerprint", fp).execute()
            )
        except Exception as e:
            print(f"⚠️ Failed to mark group {g['fingerprint'][:8]}… as notified: {e}")

    return {"sent": len(changed), "new": new_count, "events": total_events}


async def _patrol_purge_old_client_errors() -> dict:
    """個別サンプル(client_error_events)を保持期間で刈る。

    グループ(集計)は残す —— 「いつから出ているか」は消したくないため。
    容量を食うのは全文コンテキストを持つeventの方なので、そちらだけ消す。
    """
    admin_client = get_supabase_client()
    cutoff = (datetime.now(timezone.utc) - timedelta(days=ERROR_EVENT_RETENTION_DAYS)).isoformat()
    try:
        res = await asyncio.to_thread(
            lambda: admin_client.table("client_error_events")
                .delete().lt("received_at", cutoff).execute()
        )
        return {"deleted_events": len(res.data or [])}
    except Exception as e:
        return {"error": str(e)}


# このプロジェクトの管理者向け通知メールは全てこのアドレスに固定している。
ABUSE_ALERT_EMAIL = os.getenv("ABUSE_ALERT_EMAIL", "lefture.app@gmail.com")


PATROL_CHECKS = [
    ("reap_stale_dag_tasks", _patrol_reap_stale_dag_tasks),
    ("advance_stalled_dags", _patrol_advance_stalled_dags),
    ("wake_waiting_check_and_assemble", _patrol_wake_waiting_check_and_assemble),
    ("fail_stuck_jobs", _patrol_fail_stuck_jobs),
    ("reconstruct_stale_topic_maps", _patrol_reconstruct_stale_topic_maps),
    ("hard_delete_expired_lectures", _patrol_hard_delete_expired_lectures),
    ("materialize_dormant_expired_grants", _patrol_materialize_dormant_expired_grants),
    ("renew_subscriptions", _patrol_renew_subscriptions),
    ("reconcile_cross_platform_subscriptions", _patrol_reconcile_cross_platform_subscriptions),
    ("fail_stale_chat_messages", _patrol_fail_stale_chat_messages),
    ("enqueue_profile_extraction", _patrol_enqueue_profile_extraction),
]


UPGRADE_CYCLING_WINDOW_DAYS = int(os.getenv("UPGRADE_CYCLING_WINDOW_DAYS", "60"))
UPGRADE_CYCLING_MIN_GRANTS = int(os.getenv("UPGRADE_CYCLING_MIN_GRANTS", "3"))


async def _patrol_detect_upgrade_cycling() -> dict:
    """
    毎日1回、detect_upgrade_cycling_suspects()で「短期間にストア課金の付与が
    集中しているアカウント」を拾い、ABUSE_ALERT_EMAILへ判断材料をメールする。
    閾値判定はSQL側、人が見て警告/停止を決める前提なのでここでは何もしない。
    過去24時間に付与が無いユーザーはSQL側で除外されるため、同じ人が毎日
    通知されることはない。
    """
    admin_client = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: admin_client.rpc("detect_upgrade_cycling_suspects", {
            "p_window_days": UPGRADE_CYCLING_WINDOW_DAYS,
            "p_min_grants": UPGRADE_CYCLING_MIN_GRANTS,
            "p_recent_hours": 24,
        }).execute()
    )
    suspects = res.data or []
    if not suspects:
        return {"suspects": 0}

    def credits(micro) -> str:
        return "-" if micro is None else f"{int(micro) / 1_000_000:,.0f}"

    def fmt_ts(value) -> str:
        return (value or "")[:16].replace("T", " ")

    sections = []
    for s in suspects:
        rows = "".join(
            f"<tr><td>{fmt_ts(g.get('granted_at'))}</td><td>{g.get('plan_name') or '?'}</td>"
            f"<td>{'initial' if (g.get('source') or '').endswith('initial_store') else 'renewal'}</td>"
            f"<td align='right'>{credits(g.get('amount'))}</td>"
            f"<td align='right'>{credits(g.get('reset_amount'))}</td></tr>"
            for g in (s.get("grants") or [])
        )
        sections.append(
            f"<h3>{html_lib.escape(s.get('email') or '(no email)')}</h3>"
            f"<p><code>{s['user_id']}</code><br>"
            f"registered: {fmt_ts(s.get('user_created_at'))}<br>"
            f"current plan: {s.get('current_plan_name') or '-'}"
            f"{' → pending downgrade to ' + s['pending_plan_name'] if s.get('pending_plan_name') else ''}<br>"
            f"grants in {UPGRADE_CYCLING_WINDOW_DAYS}d: <b>{s['grant_count']}</b> "
            f"(granted {credits(s.get('granted_in_window'))} / consumed {credits(s.get('consumed_in_window'))} credits)</p>"
            "<table border='1' cellpadding='4' cellspacing='0'>"
            "<tr><th>granted at (UTC)</th><th>plan</th><th>kind</th><th>granted</th><th>old plan left at switch</th></tr>"
            f"{rows}</table>"
        )

    html = (
        f"<p>{len(suspects)} account(s) had {UPGRADE_CYCLING_MIN_GRANTS}+ store subscription grants "
        f"within {UPGRADE_CYCLING_WINDOW_DAYS} days, with at least one in the last 24h.</p>"
        "<p><i>\"old plan left at switch\" = credits zeroed from the previous plan at that grant. "
        "\"-\" means nothing was left to zero (used up before upgrading), which is the strongest signal.</i></p>"
        + "<hr>".join(sections)
    )
    subject = f"[Lefture] Upgrade cycling suspects: {len(suspects)} account(s)"
    try:
        await send_important_notification(ABUSE_ALERT_EMAIL, subject, html)
    except Exception as e:
        logger.error(f"Failed to send upgrade cycling alert: {e}", exc_info=True)
        return {"suspects": len(suspects), "email_error": str(e)}
    return {"suspects": len(suspects), "notified": ABUSE_ALERT_EMAIL}


def _format_trial_reminder_date(unix_ts: int, lang: str) -> str:
    """トライアル終了リマインダーメール本文用の日付表示。ロケール差はこの
    2パターンのみなので、標準ライブラリのlocaleモジュール(OS依存の
    ロケールデータが必要で環境によって壊れやすい)には頼らず、直接組み立てる。"""
    dt = datetime.fromtimestamp(unix_ts, tz=timezone.utc)
    if lang and lang.lower().startswith("ja"):
        return f"{dt.year}年{dt.month}月{dt.day}日"
    return dt.strftime("%B %d, %Y")


async def _patrol_send_trial_ending_reminders() -> dict:
    """
    毎日1回、_TRIAL_REMINDER_DAYS_BEFORE日後にトライアルが終わるStripeサブスクを
    検出してリマインダーメールを送る。米国複数州の自動更新法(カリフォルニア州ARL等、
    トライアル終了の3〜21日前の通知を義務付け)への対応。

    トライアル中かどうかの判定はStripe自体(status='trialing')を直接見る
    ——このアプリのDB(user_subscription_mappings)はStripe/Apple問わず
    'active'としか記録しないため、トライアル中か通常課金中かをDBだけでは
    区別できない。Apple経由のトライアルはそもそもStripeを経由しないため、
    ここには出てこない(Apple側の同種の通知はApple自身が担う)。

    冪等性はrevenuecat_webhook_eventsを「送った/送っていない」の汎用台帳として
    流用する(テーブル名は歴史的経緯だが、event_id text主キーの単純な冪等性
    チェックとして安全に共用できる。20260909000000のコメント参照)。
    サブスクIDから作った合成キーで、同じサブスクに二度送らないようにする。
    """
    admin_client = get_supabase_client()

    try:
        trialing_subs = await asyncio.to_thread(
            lambda: list(stripe.Subscription.list(status="trialing", limit=100).auto_paging_iter())
        )
    except stripe.error.StripeError as e:
        logger.error(f"Failed to list trialing subscriptions for reminder patrol: {e}", exc_info=True)
        return {"error": str(e)}

    now = datetime.now(timezone.utc)
    target_date = (now + timedelta(days=_TRIAL_REMINDER_DAYS_BEFORE)).date()

    sent = 0
    already_sent = 0
    errors = 0

    for sub in trialing_subs:
        trial_end = sub.to_dict().get("trial_end")
        if not trial_end:
            continue
        if datetime.fromtimestamp(trial_end, tz=timezone.utc).date() != target_date:
            continue

        subscription_id = sub["id"]
        reminder_key = f"trial_reminder:{subscription_id}"

        try:
            existing = await asyncio.to_thread(
                lambda: admin_client.table("revenuecat_webhook_events")
                    .select("event_id")
                    .eq("event_id", reminder_key)
                    .maybe_single()
                    .execute()
            )
            if existing and existing.data:
                already_sent += 1
                continue
        except Exception as e:
            logger.error(f"Failed to check trial reminder idempotency for {subscription_id}: {e}", exc_info=True)
            errors += 1
            continue

        metadata = sub["metadata"].to_dict()
        uid = metadata.get("supabase_user_id")
        plan_id = metadata.get("subscription_plan_id")
        if not uid or not plan_id:
            logger.error(f"Trialing subscription {subscription_id} missing metadata for reminder")
            errors += 1
            continue

        try:
            user_res = await asyncio.to_thread(admin_client.auth.admin.get_user_by_id, uid)
            user = user_res.user if user_res else None
            if not user or not user.email:
                raise RuntimeError("user or email not found")
        except Exception as e:
            logger.error(f"Failed to look up user {uid} for trial reminder: {e}", exc_info=True)
            errors += 1
            continue

        user_metadata = user.user_metadata or {}
        display_name = user_metadata.get("display_name", "")
        lang = user_metadata.get("display_language", "en")

        try:
            plan_res = await asyncio.to_thread(
                lambda: admin_client.table("subscription_plans")
                    .select("name")
                    .eq("id", plan_id)
                    .maybe_single()
                    .execute()
            )
            plan_name = (plan_res.data or {}).get("name") or "Max"
        except Exception as e:
            logger.error(f"Failed to look up plan name for {plan_id}: {e}", exc_info=True)
            plan_name = "Max"

        price_item = sub["items"]["data"][0]["price"].to_dict()
        unit_amount = price_item.get("unit_amount")
        renewal_price = f"${unit_amount / 100:,.2f}" if unit_amount is not None else "-"
        interval = (price_item.get("recurring") or {}).get("interval") or "month"
        if lang and lang.lower().startswith("ja"):
            renewal_interval = {"month": "毎月", "year": "毎年"}.get(interval, interval)
        else:
            renewal_interval = {"month": "every month", "year": "every year"}.get(interval, f"every {interval}")

        end_date_str = _format_trial_reminder_date(trial_end, lang)

        try:
            await send_trial_ending_reminder_email(
                to=user.email,
                plan_name=plan_name,
                end_date=end_date_str,
                renewal_price=renewal_price,
                renewal_interval=renewal_interval,
                manage_plan_link="https://app.lefture.com/account/plans",
                display_name=display_name,
                lang=lang,
            )
        except Exception as e:
            logger.error(f"Failed to send trial ending reminder for {subscription_id}: {e}", exc_info=True)
            errors += 1
            continue

        try:
            await asyncio.to_thread(
                lambda: admin_client.table("revenuecat_webhook_events")
                    .insert({"event_id": reminder_key, "event_type": "TRIAL_REMINDER_SENT"})
                    .execute()
            )
        except Exception as e:
            # 既に他プロセスが同時に処理し終えていた場合のunique制約違反等。
            # メール送信自体は成功しているので致命的ではない。
            logger.warning(f"Could not record trial reminder idempotency marker for {subscription_id}: {e}")
        sent += 1

    return {"sent": sent, "already_sent": already_sent, "errors": errors, "target_date": target_date.isoformat()}


async def _patrol_enqueue_audio_chunks_cleanup() -> dict:
    """
    毎日UTC PATROL_DAILY_HOUR_UTC時付近に1回だけ、patrol()から呼ばれる。
    作成から AUDIO_CHUNKS_RETENTION_DAYS (既定7日) 以上経過し、
    まだ audio_chunks_cleaned が False の講義を集め、
    Cloud Tasks に 1 件ずつエンキューする。
    ゴミ箱(deleted_at IS NOT NULL)に入っている講義も対象に含む。
    """
    admin_client = get_supabase_client()
    retention_threshold = (
        datetime.now(timezone.utc) - timedelta(days=AUDIO_CHUNKS_RETENTION_DAYS)
    ).isoformat()

    # created_at <= 7日前 ＆ audio_chunks_cleaned == False の講義を抽出 (deleted_atの有無は問わない)
    due_res = await asyncio.to_thread(
        lambda: admin_client.table("lectures")
            .select("id, user_id")
            .lte("created_at", retention_threshold)
            .eq("audio_chunks_cleaned", False)
            .limit(PATROL_AUDIO_CHUNKS_CLEANUP_BATCH_SIZE)
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


async def _patrol_sweep_r2_audio_chunks() -> dict:
    """
    毎月1回、R2バケット全体を直接ストリーミング走査し、
    7日以上前の /audio_chunks/ を一括削除するバックストップ処理。
    DBに紐づかない孤児（Orphan）データも一掃する。
    """
    from app.core.r2_storage import storage_service
    return await asyncio.to_thread(
        storage_service.sweep_stale_audio_chunks,
        retention_days=AUDIO_CHUNKS_RETENTION_DAYS,
    )


@app.post("/maintenance/sweep-r2-audio-chunks", dependencies=[Depends(require_internal_caller)])
async def sweep_r2_audio_chunks_endpoint():
    """
    R2バケット全体を直接走査して7日以上前の audio_chunks を一括削除する手動実行用エンドポイント。
    """
    return await _patrol_sweep_r2_audio_chunks()


@app.post("/maintenance/patrol", dependencies=[Depends(require_internal_caller)])
async def patrol():
    """
    Cloud Schedulerから10分おきに呼ばれる、汎用メンテナンスのディスパッチャー。
    DB周回を伴う本チェック(PATROL_CHECKS)は0分・30分付近でのみ実行し、
    それ以外はコールドスタート防止のウォームアップとして起こすだけで即座に返す。

    knowledge_index_queueのdrainだけは例外で、この早期return判定より前、
    毎回(10分おき)無条件で呼ぶ。他のPatrolチェックと違って「PENDING行が
    あるかをFOR UPDATE SKIP LOCKEDで1回引くだけ」の軽いインデックス
    スキャンなので、キューが空の間はコストがほぼ増えない。これにより
    アプリでの直接編集がチャットの検索対象に反映されるまでの遅延を
    最大30分→最大10分に縮められる(処理すべき件数自体は変わらず、
    より細かい間隔で分割されるだけ)。
    """
    now = datetime.now(timezone.utc)

    try:
        knowledge_index_result = await _patrol_drain_knowledge_index_queue()
    except Exception as e:
        knowledge_index_result = {"error": str(e)}
        print(f"⚠️ Patrol check 'drain_knowledge_index_queue' failed: {e}")

    if now.minute % 30 >= PATROL_TIME_WINDOW_TOLERANCE_MINUTES:
        return {"status": "warm", "drain_knowledge_index_queue": knowledge_index_result}

    results = {"drain_knowledge_index_queue": knowledge_index_result}
    for name, check_fn in PATROL_CHECKS:
        try:
            results[name] = await check_fn()
        except Exception as e:
            results[name] = {"error": str(e)}
            print(f"⚠️ Patrol check '{name}' failed: {e}")

    # 音声チャンククリーンアップは「1日1回」でよいので、実行ウィンドウ
    # (:00付近 or :30付近)のうち、PATROL_DAILY_HOUR_UTC時台の:00付近側だけを
    # 通す。:30付近側まで通すと1日2回走ってしまうため、hourに加えてminute側も
    # toleranceで絞っている。
    # ★ renew_subscriptionsは以前ここ(1日1回)にあったが、既に冪等なので
    # PATROL_CHECKS(30分おき)に移した — Freeプラン更新の遅延を最大24時間から
    # 最大30分に短縮するため。
    if now.hour == PATROL_DAILY_HOUR_UTC and now.minute < PATROL_TIME_WINDOW_TOLERANCE_MINUTES:
        try:
            results["cleanup_audio_chunks"] = await _patrol_enqueue_audio_chunks_cleanup()
        except Exception as e:
            results["cleanup_audio_chunks"] = {"error": str(e)}
            print(f"⚠️ Patrol check 'cleanup_audio_chunks' failed: {e}")

        try:
            results["detect_upgrade_cycling"] = await _patrol_detect_upgrade_cycling()
        except Exception as e:
            results["detect_upgrade_cycling"] = {"error": str(e)}
            print(f"⚠️ Patrol check 'detect_upgrade_cycling' failed: {e}")

        try:
            results["send_trial_ending_reminders"] = await _patrol_send_trial_ending_reminders()
        except Exception as e:
            results["send_trial_ending_reminders"] = {"error": str(e)}
            print(f"⚠️ Patrol check 'send_trial_ending_reminders' failed: {e}")

        try:
            results["purge_old_client_errors"] = await _patrol_purge_old_client_errors()
        except Exception as e:
            results["purge_old_client_errors"] = {"error": str(e)}
            print(f"⚠️ Patrol check 'purge_old_client_errors' failed: {e}")

        # 毎月1日(:00付近)に1回だけ、R2バケット全体の直接スイープを走らせる(孤児チャンクのバックストップ)
        if now.day == 1:
            try:
                results["sweep_orphan_r2_chunks"] = await _patrol_sweep_r2_audio_chunks()
            except Exception as e:
                results["sweep_orphan_r2_chunks"] = {"error": str(e)}
                print(f"⚠️ Patrol check 'sweep_orphan_r2_chunks' failed: {e}")

    # クライアントエラーのダイジェストは1日2回(既定 UTC 0時/12時)なので、
    # PATROL_DAILY_HOUR_UTC の日次枠とは別に判定する。:00付近側だけを通して
    # 1つの枠で2回走らないようにするのは日次枠と同じ考え方。
    if now.hour in ERROR_DIGEST_HOURS_UTC and now.minute < PATROL_TIME_WINDOW_TOLERANCE_MINUTES:
        try:
            results["client_error_digest"] = await _patrol_send_client_error_digest()
        except Exception as e:
            results["client_error_digest"] = {"error": str(e)}
            print(f"⚠️ Patrol check 'client_error_digest' failed: {e}")

    return results


# ---------------------------------------------------------
# 📧 メール送信エンドポイント
# ---------------------------------------------------------
# /email/send-verification, /email/send-password-reset, /email/send-notification
# の3本は削除した。
#
# 理由: 認証が一切なく、宛先・件名・HTML本文を呼び出し側が自由に指定できる
# 「誰でも使える公開メールリレー」になっていた。URLを知った第三者が、検証済みの
# 自社ドメインから任意のHTMLメールを送れる(=フィッシングの踏み台にされ、
# 送信ドメインのレピュテーションを焼かれる)状態だった。
#
# しかもこの3本はリポジトリ内のどこからも呼ばれていない。実際のメール送信は
# Supabase Authの「Send Email Hook」を署名検証付きで受ける /auth/send-email に
# 一本化済みで、この3本は移行時の残骸。認証を足すより消すのが正しい。
#
# 内部からメールを送りたい場合は app/services/email_service.py の
# send_verification_email() / send_important_notification() を直接呼ぶこと
# (HTTPエンドポイントとして外に出す必要はない)。

# ---------------------------------------------------------
# 📱 Push通知 — デバイストークン登録
# ---------------------------------------------------------
class RegisterDeviceRequest(BaseModel):
    device_token: str
    platform: str  # "ios" | "android"


# ---------------------------------------------------------
# 🐞 クライアントエラー収集
# ---------------------------------------------------------
# Flutter側で起きた「予期せぬエラー」を受け取り、fingerprint単位で集計する。
# ダイジェストメール(_patrol_send_client_error_digest)と管理者ダッシュボードが
# ここに溜まったものを読む。
#
# 設計上の約束:
#   * 認証は任意。サインイン画面のエラーこそ一番知りたいので、未ログインでも
#     受け付ける(その場合 user_id は NULL、device_id だけで識別する)。
#   * 失敗しても必ず2xxを返す。レート制限で捨てた場合も202。クライアントは
#     2xxならローカルキューを消してよい —— 「エラー報告が失敗したエラー」を
#     再送し続けるループを作らないため。
#   * 生の本文にはuidやストレージパス、まれにトークン断片が混ざり得るので、
#     保存前に _mask_error_text() でマスクする。

CLIENT_ERROR_RATE_LIMIT_PER_HOUR = 200
CLIENT_ERROR_SAMPLES_PER_GROUP = 5
CLIENT_ERROR_SAMPLE_WINDOW_HOURS = 12


class ClientErrorReport(BaseModel):
    fingerprint: str
    ref_code: str | None = None
    code: str
    origin: str
    occurrence_count: int = 1
    first_seen_at: str | None = None
    last_seen_at: str | None = None
    error: dict = {}
    route: str | None = None
    breadcrumbs: list[str] = []
    suppressed: int = 0


class ClientErrorBatch(BaseModel):
    device_id: str
    app_version: str | None = None
    platform: str | None = None
    os_version: str | None = None
    locale: str | None = None
    is_authenticated: bool = False
    dropped_distinct: int = 0
    reports: list[ClientErrorReport] = []


# JWT・署名付きURL・メールアドレスなど、エラー本文に紛れ込むと困るものを潰す。
# 完全な防御ではなく「うっかり保存してしまう」のを防ぐための最低限。
_ERROR_MASK_PATTERNS = [
    (re.compile(r"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"), "<jwt>"),
    (re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"), "<email>"),
    (re.compile(r"(?i)(signature|token|key|secret|password)=[^&\s\"]+"), r"\1=<redacted>"),
]


def _mask_error_text(text):
    if not text:
        return text
    out = str(text)
    for pattern, replacement in _ERROR_MASK_PATTERNS:
        out = pattern.sub(replacement, out)
    return out[:4000]


def _merge_unique(existing, value, limit=20):
    """配列カラムに値を足す(重複なし・上限あり)。"""
    items = list(existing or [])
    if value and value not in items:
        items.append(value)
    return items[-limit:]


@app.post("/client-errors/report")
async def client_errors_report(payload: ClientErrorBatch, request: Request):
    """クライアントのエラーレポートをまとめて受け取る。常に2xxを返す。"""
    if not payload.reports:
        return {"accepted": 0}

    admin_client = get_supabase_client()
    now = datetime.now(timezone.utc)

    # 認証は任意。付いていれば user_id を紐づけるが、検証に失敗しても
    # 匿名として受け付ける(報告を落とさないことを優先する)。
    user_id = None
    if payload.is_authenticated:
        try:
            user = await asyncio.to_thread(_authenticate_request, request)
            user_id = user.id
        except Exception:
            user_id = None

    # --- レート制限(device_id単位) ---
    # 専用のミドルウェアは用意せず、直近1時間のevent数を数えるだけで足りる
    # (client_error_events_device_idx があるので安い)。
    try:
        since = (now - timedelta(hours=1)).isoformat()
        recent = await asyncio.to_thread(
            lambda: admin_client.table("client_error_events")
                .select("id", count="exact")
                .eq("device_id", payload.device_id)
                .gte("received_at", since)
                .limit(1)
                .execute()
        )
        if (recent.count or 0) >= CLIENT_ERROR_RATE_LIMIT_PER_HOUR:
            print(f"🚧 client-errors: rate limited device={payload.device_id[:8]}…")
            return {"accepted": 0, "rate_limited": True}
    except Exception as e:
        print(f"⚠️ client-errors: rate limit check failed (accepting anyway): {e}")

    accepted = 0
    for report in payload.reports:
        try:
            err = report.error or {}
            raw = _mask_error_text(err.get("raw"))
            occurrences = max(1, report.occurrence_count) + max(0, report.suppressed)

            # --- グループのupsert ---
            existing_res = await asyncio.to_thread(
                lambda fp=report.fingerprint: admin_client.table("client_error_groups")
                    .select("*").eq("fingerprint", fp).maybe_single().execute()
            )
            existing = existing_res.data if existing_res else None

            if existing:
                group_patch = {
                    "last_seen_at": now.isoformat(),
                    "total_count": (existing.get("total_count") or 0) + occurrences,
                    "sample_message": raw or existing.get("sample_message"),
                    "affected_device_ids": _merge_unique(
                        existing.get("affected_device_ids"), payload.device_id
                    ),
                    "app_versions": _merge_unique(existing.get("app_versions"), payload.app_version),
                    "platforms": _merge_unique(existing.get("platforms"), payload.platform),
                }
                if user_id:
                    group_patch["affected_user_ids"] = _merge_unique(
                        existing.get("affected_user_ids"), user_id, limit=100
                    )
                await asyncio.to_thread(
                    lambda fp=report.fingerprint, patch=group_patch:
                        admin_client.table("client_error_groups")
                            .update(patch).eq("fingerprint", fp).execute()
                )
            else:
                await asyncio.to_thread(
                    lambda r=report, raw=raw, occ=occurrences:
                        admin_client.table("client_error_groups").insert({
                            "fingerprint": r.fingerprint,
                            "code": r.code,
                            "origin": r.origin,
                            "sample_message": raw,
                            "first_seen_at": now.isoformat(),
                            "last_seen_at": now.isoformat(),
                            "total_count": occ,
                            "affected_user_ids": [user_id] if user_id else [],
                            "affected_device_ids": [payload.device_id],
                            "app_versions": [payload.app_version] if payload.app_version else [],
                            "platforms": [payload.platform] if payload.platform else [],
                        }).execute()
                )

            # --- サンプル(event)を保存するか ---
            # 1グループ CLIENT_ERROR_SAMPLE_WINDOW_HOURS 時間あたり
            # CLIENT_ERROR_SAMPLES_PER_GROUP 件まで。これを超えた分は
            # グループのカウントにだけ反映され、全文は保存しない。
            window_start = (now - timedelta(hours=CLIENT_ERROR_SAMPLE_WINDOW_HOURS)).isoformat()
            samples = await asyncio.to_thread(
                lambda fp=report.fingerprint: admin_client.table("client_error_events")
                    .select("id", count="exact")
                    .eq("fingerprint", fp)
                    .gte("received_at", window_start)
                    .limit(1)
                    .execute()
            )
            if (samples.count or 0) < CLIENT_ERROR_SAMPLES_PER_GROUP:
                await asyncio.to_thread(
                    lambda r=report, e=err, raw=raw, occ=occurrences:
                        admin_client.table("client_error_events").insert({
                            "fingerprint": r.fingerprint,
                            "user_id": user_id,
                            "device_id": payload.device_id,
                            "occurred_at": r.last_seen_at or now.isoformat(),
                            "occurrence_count": occ,
                            "code": r.code,
                            "origin": r.origin,
                            "raw_message": raw,
                            "stack": _mask_error_text(e.get("stack")),
                            "breadcrumbs": [_mask_error_text(b) for b in (r.breadcrumbs or [])][-40:],
                            "http_status": e.get("http"),
                            "backend_code": e.get("backend_code"),
                            "route": r.route,
                            "app_version": payload.app_version,
                            "platform": payload.platform,
                            "os_version": payload.os_version,
                            "locale": payload.locale,
                            "is_authenticated": payload.is_authenticated,
                            "ref_code": r.ref_code,
                        }).execute()
                )

            accepted += 1
        except Exception as e:
            # 1件の失敗で残りを落とさない。
            print(f"⚠️ client-errors: failed to store {report.fingerprint[:8]}…: {e}")

    if payload.dropped_distinct:
        print(f"🚧 client-errors: device dropped {payload.dropped_distinct} distinct group(s) locally")

    return {"accepted": accepted}


@app.post("/devices/register")
async def register_device(payload: RegisterDeviceRequest, request: Request):
    """FCMデバイストークンを登録する。device_tokenはUNIQUEなので、
    別ユーザーが同じ端末で使っていた場合は所有者が自動的に付け替わる。"""
    if payload.platform not in ("ios", "android"):
        raise HTTPException(status_code=400, detail="platform must be 'ios' or 'android'")

    _, user_id = await _get_user_client_from_request(request)
    try:
        # UPSERTでdevice_tokenが別ユーザーの既存行と衝突する場合、そのUPDATEは
        # 「今のユーザーが既に所有する行」しか許さないRLS(user_devices_update_own)
        # に阻まれてしまう。所有者の付け替えは正規の挙動なので、JWT検証はユーザー
        # クライアントで行った上で、実際の書き込みは管理者クライアントで行う
        # (他のエンドポイントと同じパターン)。
        admin_client = get_supabase_client()
        now = datetime.now(timezone.utc).isoformat()
        admin_client.table("user_devices").upsert({
            "user_id": user_id,
            "device_token": payload.device_token,
            "platform": payload.platform,
            "updated_at": now,
            "last_used_at": now,
        }, on_conflict="device_token").execute()
        return {"success": True}
    except Exception as e:
        print(f"❌ Failed to register device: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to register device: {str(e)}")


@app.post("/devices/unregister")
async def unregister_device(payload: RegisterDeviceRequest, request: Request):
    """ログアウト時などにデバイストークンを削除する"""
    user_client, user_id = await _get_user_client_from_request(request)
    try:
        user_client.table("user_devices").delete().eq("device_token", payload.device_token).eq("user_id", user_id).execute()
        return {"success": True}
    except Exception as e:
        print(f"❌ Failed to unregister device: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to unregister device: {str(e)}")


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
    値は Supabase Dashboard > Authentication > Hooks の Send Email Hook に
    表示される "v1,whsec_..." 形式のシークレットをそのまま使う。

    ★ 未設定時は検証をスキップせず全拒否する。スキップすると、このエンドポイントが
      「任意の宛先へ確認メール/パスワードリセットメールを送らせられる窓口」になる。
    """
    if not SEND_EMAIL_HOOK_SECRET:
        logger.error("SEND_EMAIL_HOOK_SECRET is not configured; rejecting Supabase auth email hook")
        raise HTTPException(status_code=503, detail="Email hook is not configured")

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
    display_lang  = payload.user.user_metadata.get("display_language", "en")
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
            await send_verification_email(user_email, link, display_name, lang=display_lang)
            print(f"✅ Sent {action_type} email to {user_email} (lang: {display_lang})")

        elif action_type == "recovery":
            link = _verify_link(email_data.token_hash, "recovery")
            await send_password_reset_email(user_email, link, display_name, lang=display_lang)
            print(f"✅ Sent {action_type} email to {user_email} (lang: {display_lang})")

        elif action_type == "email_change":
            new_email = payload.user.new_email
            recipients_notified = []

            # GoTrueはSend Email Hookの応答を5秒しか待たない。直列にawaitすると
            # 2通分の送信時間が単純合計されタイムアウトのリスクが増えるため、
            # 並行して送信する。
            send_tasks = []
            if email_data.token_hash_new:
                current_link = _verify_link(email_data.token_hash_new, "email_change")
                send_tasks.append(send_email_change_email(user_email, current_link, new_email or "", lang=display_lang))
                recipients_notified.append(user_email)

            if new_email and email_data.token_hash:
                new_link = _verify_link(email_data.token_hash, "email_change")
                send_tasks.append(send_email_change_email(new_email, new_link, new_email, lang=display_lang))
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
    uid = await _get_authenticated_user_id(request)

    from app.services.task_runners import storage_service
    upload_url, storage_path = await asyncio.to_thread(
        storage_service.generate_presigned_support_url,
        uid=uid,
        file_name=payload.file_name,
        content_type=payload.content_type,
    )
    return {"upload_url": upload_url, "storage_path": storage_path}


class AvatarUploadUrlRequest(BaseModel):
    file_name: str
    content_type: str = "image/png"


@app.post("/profile/request-avatar-upload-url")
async def profile_request_avatar_upload_url(
    payload: AvatarUploadUrlRequest,
    request: Request,
):
    """ユーザーカスタムアバター画像用の R2 署名付きアップロードURLを発行する"""
    uid = await _get_authenticated_user_id(request)
    await _reject_if_suspended(get_supabase_client(), uid)

    from app.services.task_runners import storage_service
    upload_url, storage_path = await asyncio.to_thread(
        storage_service.generate_presigned_avatar_url,
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
    user = await _get_authenticated_user(request)
    uid = user.id
    user_email = user.email
    display_name = (user.user_metadata or {}).get("display_name", "")

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

    # ユーザーの表示言語(display_language)を取得
    display_lang = "en"
    try:
        user_prof_res = await asyncio.to_thread(
            lambda: admin_client.table("user_profiles").select("metadata").eq("id", uid).maybe_single().execute()
        )
        if user_prof_res and user_prof_res.data and isinstance(user_prof_res.data.get("metadata"), dict):
            display_lang = user_prof_res.data["metadata"].get("display_language", "en")
    except Exception as e:
        print(f"⚠️ Failed to fetch display_language for support email: {e}")

    # 3. ユーザーへ自動確認メールを送信 (From: support@lefture.com)
    try:
        from app.services.email_service import send_email
        from app.services.email_template import (
            build_support_user_ack_email,
            build_support_admin_notification_email,
        )
        from app.services.email_content import get_email_content

        user_content = get_email_content(display_lang)
        user_html = build_support_user_ack_email(
            display_name=display_name,
            ticket_code=ticket_code,
            category=payload.category,
            message=payload.message,
            lang=display_lang,
        )
        await send_email(
            to=user_email,
            subject=user_content.SUPPORT_ACK_SUBJECT.format(ticket_code=ticket_code),
            html=user_html,
            from_address="support@lefture.com",
            from_name=user_content.SUPPORT_APP_NAME,
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
    uid = await _get_authenticated_user_id(request)

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

# ---------------------------------------------------------
# 💬 横断チャットボット (段階1 MVP)
#
# 処理の中身は app/services/chat_service.py。ここは入口(認証・事前チェックの
# HTTPエラー化・SSEの配信)だけ。スレッド一覧や過去のメッセージは、
# クライアントがsupabase-js / supabase_flutterでRLS越しに直接読む
# (chat_threads / chat_messages は本人のみSELECT可、書き込みはここ経由のみ)。
# ---------------------------------------------------------
class ChatScreenRef(BaseModel):
    """
    見ているページ(本文はバックエンドがDBから読む。chat_screen.py)。
    deep_note / fun_fact: idがその行。review_card: idが表示中のカード、表紙を見ているときは
    idが無くtopic_number(講義はcontext.lecture_id)。
    """
    kind: str
    id: Optional[str] = None
    topic_number: Optional[int] = None


class ChatMessageContext(BaseModel):
    lecture_id: Optional[str] = None
    selected_text: Optional[str] = None
    # 選択の直前・直後の文字(ページの中で選択箇所を特定するためだけに使う)
    selection_before: Optional[str] = None
    selection_after: Optional[str] = None
    screen: Optional[ChatScreenRef] = None
    # 会話の中のAIの回答の一部を選んで返信するとき、その回答のメッセージID(selected_textがその中の文章)
    reply_to_message_id: Optional[str] = None


class ChatAttachmentRequest(BaseModel):
    """
    送信と一緒に添付する・指す資料。
    text: 本文を送る(上限はchat_attachments.pyとprepare_chat_turnが確かめる)。refは本文の印 ⟦att:ref⟧ で
      使う端末の仮のid(保存するときに本物のidに直す)。
    file: 送る前にアップロードして取り出したファイル(draft)のattachment_idを送る(chat_files.py)。
    existing: このスレッドの資料を指す。mode=full なら全文で添付(全文で読む枠に入れる)、mention なら指すだけ。
    新しく添付する資料(text / file)は、いつも全文で添付する。
    """
    kind: str = "text"
    title: Optional[str] = None
    content: str = ""
    attachment_id: Optional[str] = None
    ref: Optional[str] = None
    mode: Optional[str] = None


class ChatAttachmentUploadRequest(BaseModel):
    """ファイルを添付する前に、アップロード先を頼む。file_sizeは端末で縮めた後の大きさ。"""
    file_name: str
    file_size: int


class ChatMessageRequest(BaseModel):
    thread_id: Optional[str] = None
    client_message_id: str
    # 資料だけを送るときは空でよい
    content: str = ""
    context: Optional[ChatMessageContext] = None
    attachments: Optional[list[ChatAttachmentRequest]] = None
    # 端末のIANAタイムゾーン名(例: Asia/Tokyo)。「昨日の授業」「今学期」をユーザーの日付で
    # 解決するため。古いクライアントは送らないので任意(無ければUTC、不正な名前もUTC)。
    timezone: Optional[str] = None


class ChatThreadUpdateRequest(BaseModel):
    title: str


class ChatAttachmentUpdateRequest(BaseModel):
    """資料を全文で読ませるか(選択)。"""
    selected: bool


class ProfileItemRejectRequest(BaseModel):
    reason: Optional[str] = None


class ProfileItemEditRequest(BaseModel):
    content: str


class ProfileItemsSeenRequest(BaseModel):
    item_ids: list[str]


# 返答の生成はリクエストとは別のasyncioタスクで走らせる(クライアントが
# 途中で切断しても保存・課金まで走り切るため)。タスクへの参照をどこかに
# 持っておかないとGCで途中で消されることがあるので、ここに保持する。
_CHAT_BACKGROUND_TASKS: set = set()


def _parse_uuid_or_422(value: Optional[str], field_name: str) -> Optional[str]:
    if value is None:
        return None
    try:
        return str(uuid.UUID(value))
    except (ValueError, AttributeError, TypeError):
        raise HTTPException(status_code=422, detail={"error_code": "INVALID_ID", "message": f"{field_name} must be a UUID."})


@app.post("/chat/messages")
async def post_chat_message(payload: ChatMessageRequest, request: Request):
    """
    チャットに1メッセージ送り、返答をSSE(text/event-stream)で返す。

    事前チェックで弾くもの(文字数超過413 / 資料の数・長さの超過413 / スレッドの資料の上限409 /
    残高不足402 / 送信頻度429 / 断られ過ぎ429 / 再送の重複409 / 生成中の二重送信409 /
    スレッド無し404)はストリームを開く前に通常のHTTPエラーとして返す。

    イベント: meta / status / sources / delta / replace / done / error
    (EventSourceはPOSTとAuthorizationヘッダを扱えないため、クライアントは
    fetchのReadableStreamで読む)。
    """
    timer = TurnTimer()
    user_client, uid = await _get_user_client_from_request(request)
    timer.mark("auth_user")  # トークン検証(GoTrueへの往復) + ユーザー用クライアントの作成
    admin_client = get_supabase_client()
    await _reject_if_suspended(admin_client, uid)
    timer.mark("auth")

    thread_id = _parse_uuid_or_422(payload.thread_id, "thread_id")
    client_message_id = _parse_uuid_or_422(payload.client_message_id, "client_message_id")
    context = payload.context or ChatMessageContext()
    context_lecture_id = _parse_uuid_or_422(context.lecture_id, "context.lecture_id")
    screen_ref = None
    if context.screen and context.screen.kind in SCREEN_KINDS:
        screen_ref = ScreenRef(
            kind=context.screen.kind,
            id=_parse_uuid_or_422(context.screen.id, "context.screen.id"),
            topic_number=context.screen.topic_number,
        )

    attachments = payload.attachments or []
    if any(a.kind not in ("text", "file", "existing") for a in attachments):
        raise HTTPException(status_code=422, detail={"error_code": "UNSUPPORTED_ATTACHMENT",
                                                     "message": "Unsupported attachment kind."})
    for a in attachments:
        if a.kind in ("file", "existing"):
            if not a.attachment_id:
                raise HTTPException(status_code=422, detail={"error_code": "INVALID_ID", "message": "attachment_id is required."})
            a.attachment_id = _parse_uuid_or_422(a.attachment_id, "attachment_id")
        if a.ref is not None and not re.fullmatch(r"[0-9A-Za-z-]{1,64}", a.ref):
            raise HTTPException(status_code=422, detail={"error_code": "INVALID_ID", "message": "ref is invalid."})

    try:
        turn = await prepare_chat_turn(
            uid, thread_id, client_message_id, payload.content,
            context_lecture_id, context.selected_text, timer, payload.timezone,
            screen_ref=screen_ref,
            selection_before=context.selection_before,
            selection_after=context.selection_after,
            attachments=attachments,
            reply_to_message_id=_parse_uuid_or_422(context.reply_to_message_id, "context.reply_to_message_id"),
        )
    except ChatRequestError as e:
        raise HTTPException(
            status_code=e.status_code,
            detail={"error_code": e.error_code, "message": e.message, **e.extra},
        )

    queue: asyncio.Queue = asyncio.Queue()
    task = asyncio.create_task(run_chat_turn(turn, user_client, queue, enqueue_summary=enqueue_chat_summary_task))
    _CHAT_BACKGROUND_TASKS.add(task)
    task.add_done_callback(_CHAT_BACKGROUND_TASKS.discard)

    async def event_stream():
        while True:
            item = await queue.get()
            if item is None:
                break
            yield item

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


async def _require_own_chat_thread(admin_client, thread_id: str, uid: str) -> dict:
    res = await asyncio.to_thread(
        lambda: admin_client.table("chat_threads").select("id, user_id, deleted_at")
            .eq("id", thread_id).maybe_single().execute()
    )
    row = res.data if res else None
    if not row or row.get("user_id") != uid or row.get("deleted_at"):
        raise HTTPException(status_code=404, detail={"error_code": "THREAD_NOT_FOUND", "message": "Thread not found."})
    return row


@app.patch("/chat/threads/{thread_id}")
async def update_chat_thread(thread_id: str, payload: ChatThreadUpdateRequest, request: Request):
    """スレッド名の変更。"""
    uid = await _get_authenticated_user_id(request)
    thread_id = _parse_uuid_or_422(thread_id, "thread_id")
    title = (payload.title or "").strip()
    if not title or len(title) > 100:
        raise HTTPException(status_code=422, detail={"error_code": "INVALID_TITLE", "message": "Title must be 1-100 characters."})

    admin_client = get_supabase_client()
    await _require_own_chat_thread(admin_client, thread_id, uid)
    await asyncio.to_thread(
        lambda: admin_client.table("chat_threads").update({"title": title}).eq("id", thread_id).execute()
    )
    return {"success": True}


@app.delete("/chat/threads/{thread_id}")
async def delete_chat_thread(thread_id: str, request: Request):
    """スレッドの削除(論理削除。中のメッセージも同時に論理削除する)。"""
    uid = await _get_authenticated_user_id(request)
    thread_id = _parse_uuid_or_422(thread_id, "thread_id")

    admin_client = get_supabase_client()
    await _require_own_chat_thread(admin_client, thread_id, uid)
    now_iso = datetime.now(timezone.utc).isoformat()
    await asyncio.to_thread(
        lambda: admin_client.table("chat_messages").update({"deleted_at": now_iso})
            .eq("thread_id", thread_id).is_("deleted_at", "null").execute()
    )
    removed = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments").update({"deleted_at": now_iso})
            .eq("thread_id", thread_id).is_("deleted_at", "null").execute()
    )
    await asyncio.to_thread(
        lambda: admin_client.table("chat_threads").update({"deleted_at": now_iso}).eq("id", thread_id).execute()
    )
    # 添付したファイル(R2)はその場で消す(行は論理削除のまま残る)
    for row in removed.data or []:
        _delete_attachment_files_later(row.get("storage_prefix"))
    # 自分像プロフィール: このスレッドの観察も消し、根拠が無くなったAI由来の項目は使わないようにする
    try:
        await profile_store.on_thread_deleted(uid, thread_id)
    except Exception as e:
        print(f"⚠️ [profile] failed to follow the deletion of thread {thread_id}: {e}")
    return {"success": True}


@app.patch("/chat/attachments/{attachment_id}")
async def update_chat_attachment(attachment_id: str, payload: ChatAttachmentUpdateRequest, request: Request):
    """
    資料を選ぶ(全文で回答役・確かめ役に渡す)/選択を外す(目次と検索で読む)。選ぶときは、同じ会話で
    選択中の資料と合わせてMAX_SELECTED_TOKENSに収まるかを確かめ、収まらなければ理由を返す。
    """
    uid = await _get_authenticated_user_id(request)
    attachment_id = _parse_uuid_or_422(attachment_id, "attachment_id")
    admin_client = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments").select("id, user_id, thread_id, status, token_count, deleted_at")
            .eq("id", attachment_id).maybe_single().execute()
    )
    row = res.data if res else None
    if not row or row.get("user_id") != uid or row.get("deleted_at"):
        raise HTTPException(status_code=404, detail={"error_code": "ATTACHMENT_NOT_FOUND", "message": "Attachment not found."})
    if payload.selected:
        if row.get("status") != "ready":
            raise HTTPException(status_code=409, detail={"error_code": "ATTACHMENT_NOT_READY",
                                                         "message": "This attachment cannot be read."})
        if row["token_count"] > MAX_SELECTED_TOKENS:
            raise HTTPException(status_code=413, detail={
                "error_code": "ATTACHMENT_TOO_LONG_TO_SELECT", "message": "This attachment is too long to read in full.",
                "max_tokens": MAX_SELECTED_TOKENS, "token_count": row["token_count"]})
        others = await asyncio.to_thread(
            lambda: admin_client.table("chat_attachments").select("token_count")
                .eq("thread_id", row["thread_id"]).eq("selected", True).is_("deleted_at", "null")
                .neq("id", attachment_id).execute()
        )
        selected_tokens = sum(r["token_count"] for r in others.data or [])
        if selected_tokens + row["token_count"] > MAX_SELECTED_TOKENS:
            raise HTTPException(status_code=409, detail={
                "error_code": "ATTACHMENT_SELECTION_LIMIT",
                "message": "Selected attachments would exceed the limit.",
                "max_tokens": MAX_SELECTED_TOKENS, "selected_tokens": selected_tokens, "token_count": row["token_count"]})
    # 全文で読み始めた時刻(枠を超えたら古いものから外す。chat_attachments.plan_pins)
    update = {"selected": True, "selected_at": datetime.now(timezone.utc).isoformat()} if payload.selected \
        else {"selected": False}
    await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments").update(update).eq("id", attachment_id).execute()
    )
    return {"success": True}


@app.delete("/chat/attachments/{attachment_id}")
async def remove_chat_attachment(attachment_id: str, request: Request):
    """
    資料を外す(論理削除)。以降のターンでは回答役・探索役に渡らない。送った後の中身の編集はできない
    (審査を通った中身だけを使うため)。中身は一覧から読める(本人のみSELECT可)。
    """
    uid = await _get_authenticated_user_id(request)
    attachment_id = _parse_uuid_or_422(attachment_id, "attachment_id")
    admin_client = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments").select("id, user_id, status, storage_prefix, deleted_at")
            .eq("id", attachment_id).maybe_single().execute()
    )
    row = res.data if res else None
    if not row or row.get("user_id") != uid or row.get("deleted_at"):
        raise HTTPException(status_code=404, detail={"error_code": "ATTACHMENT_NOT_FOUND", "message": "Attachment not found."})
    if row.get("status") == "draft":
        # 送る前に外したファイルは、行ごと消す(どの会話にも属していない)
        await asyncio.to_thread(
            lambda: admin_client.table("chat_attachments").delete().eq("id", attachment_id).eq("status", "draft").execute()
        )
    else:
        await asyncio.to_thread(
            lambda: admin_client.table("chat_attachments")
                .update({"deleted_at": datetime.now(timezone.utc).isoformat()}).eq("id", attachment_id).execute()
        )
    _delete_attachment_files_later(row.get("storage_prefix"))
    return {"success": True}


# 返答を待たせずに走らせるR2の後片付け。参照を持っておかないとGCで途中で消える
_ATTACHMENT_FILE_TASKS: set = set()


def _delete_attachment_files_later(prefix: Optional[str]) -> None:
    """添付ファイルのR2のフォルダを消す(失敗しても、アカウント削除の {uid}/ 一括削除で最後は消える)。"""
    if not prefix or "/chat_attachments/" not in prefix:
        return

    async def run() -> None:
        try:
            await asyncio.to_thread(storage_service.delete_prefix, prefix)
        except Exception as e:
            print(f"⚠️ [chat] failed to delete attachment files {prefix}: {e}")

    task = asyncio.create_task(run())
    _ATTACHMENT_FILE_TASKS.add(task)
    task.add_done_callback(_ATTACHMENT_FILE_TASKS.discard)


def _file_error(status: int, e: "chat_files.FileError") -> HTTPException:
    return HTTPException(status_code=status, detail={"error_code": e.code, "message": e.message, **e.extra})


@app.post("/chat/attachments/uploads")
async def create_chat_attachment_upload(payload: ChatAttachmentUploadRequest, request: Request):
    """
    ファイルを添付する1歩目: 種類と大きさを確かめ、draftの行を作り、R2へ直接PUTする署名付きURLを返す
    (chat_files.py)。端末は返したcontent_typeでPUTし、終わったら /chat/attachments/{id}/extract を呼ぶ。
    """
    uid = await _get_authenticated_user_id(request)
    admin_client = get_supabase_client()
    await _reject_if_suspended(admin_client, uid)

    file_name = chat_files.clean_file_name(payload.file_name)
    kind = chat_files.kind_for(file_name)
    if not kind:
        raise HTTPException(status_code=415, detail={"error_code": "UNSUPPORTED_FILE_TYPE",
                                                     "message": "This file type is not supported."})
    max_bytes = chat_files.MAX_UPLOAD_BYTES[kind]
    if payload.file_size <= 0:
        raise HTTPException(status_code=400, detail={"error_code": "FILE_EMPTY", "message": "The file is empty."})
    if payload.file_size > max_bytes:
        raise HTTPException(status_code=413, detail={"error_code": "FILE_TOO_LARGE", "message": "The file is too large.",
                                                     "max_bytes": max_bytes})

    since = (datetime.now(timezone.utc) - timedelta(hours=chat_files.DRAFT_TTL_HOURS)).isoformat()
    drafts = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments").select("id", count="exact")
            .eq("user_id", uid).eq("status", "draft").gte("created_at", since).limit(1).execute()
    )
    if (drafts.count or 0) >= chat_files.MAX_DRAFTS_PER_USER:
        raise HTTPException(status_code=429, detail={"error_code": "TOO_MANY_DRAFTS",
                                                     "message": "Too many files are waiting to be sent.",
                                                     "max_drafts": chat_files.MAX_DRAFTS_PER_USER})

    attachment_id = str(uuid.uuid4())
    prefix = chat_files.storage_prefix(uid, attachment_id)
    content_type = chat_files.UPLOAD_CONTENT_TYPES[kind]
    await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments").insert({
            "id": attachment_id, "user_id": uid, "kind": kind, "status": "draft",
            "content": "", "char_count": 0, "token_count": 0,
            "storage_prefix": prefix, "file_name": file_name, "mime_type": content_type,
            "file_size": payload.file_size,
        }).execute()
    )
    upload_url = await asyncio.to_thread(
        storage_service.generate_presigned_put_url_for_key, chat_files.upload_key(prefix, kind), content_type)
    return {"attachment_id": attachment_id, "upload_url": upload_url, "content_type": content_type,
            "kind": kind, "max_bytes": max_bytes}


# 取り出し(ダウンロード + 解析 + 画像のR2保存)を、1つのインスタンスで同時に何件まで走らせるか。
# 100MBのスキャンPDFで1件あたり約300MB使う(/tmpもメモリに数える。2026-10-07に実測: 99MB・23ページで
# 処理のメモリ+約195MB)。インスタンスはメモリ2GiBで、講義の分析やチャットも同じプロセスで動くので、
# 大きなファイルが重なってもメモリ不足で落ちないように絞る。3件目以降は前の取り出しが終わるまで待つ
# (1件は数秒で終わる)。uvicornは1コンテナ1プロセスなので、この数がそのままインスタンスあたりの上限になる。
EXTRACT_MAX_CONCURRENT = 2
_EXTRACT_SEMAPHORE = asyncio.Semaphore(EXTRACT_MAX_CONCURRENT)


async def _require_own_draft(admin_client, attachment_id: str, uid: str) -> dict:
    res = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments")
            .select("id, user_id, kind, status, file_name, file_size, page_count, storage_prefix, extraction, deleted_at")
            .eq("id", attachment_id).maybe_single().execute()
    )
    row = res.data if res else None
    if not row or row.get("user_id") != uid or row.get("deleted_at") or row.get("status") != "draft":
        raise HTTPException(status_code=404, detail={"error_code": "ATTACHMENT_NOT_FOUND", "message": "Attachment not found."})
    return row


@app.post("/chat/attachments/{attachment_id}/extract")
async def extract_chat_attachment(attachment_id: str, request: Request):
    """
    ファイルを添付する2歩目(アップロードの後): LLMを使わずに中身を取り出し、送る前に分かること
    (ページ数・文字数・画像として読む数)を返す。取り出せない・上限を超えるファイルは、draftを消して
    理由(error_code)を返す。同じdraftに2回呼ばれたら、前の結果をそのまま返す。
    """
    uid = await _get_authenticated_user_id(request)
    attachment_id = _parse_uuid_or_422(attachment_id, "attachment_id")
    admin_client = get_supabase_client()
    row = await _require_own_draft(admin_client, attachment_id, uid)
    if row.get("extraction"):
        return chat_files.draft_info(row)

    kind, prefix = row["kind"], row["storage_prefix"]
    key = chat_files.upload_key(prefix, kind)

    async def discard(status: int, e: chat_files.FileError) -> HTTPException:
        await asyncio.to_thread(
            lambda: admin_client.table("chat_attachments").delete().eq("id", attachment_id).execute())
        _delete_attachment_files_later(prefix)
        return _file_error(status, e)

    async with _EXTRACT_SEMAPHORE:
        return await _extract_draft(admin_client, attachment_id, row, key, discard)


async def _extract_draft(admin_client, attachment_id: str, row: dict, key: str, discard) -> dict:
    """extract_chat_attachmentの本体(同時実行の上限_EXTRACT_SEMAPHOREの中で動く)。"""
    import tempfile

    kind, prefix = row["kind"], row["storage_prefix"]
    size = await asyncio.to_thread(storage_service.object_size, key)
    if size is None:
        raise HTTPException(status_code=409, detail={"error_code": "FILE_NOT_UPLOADED",
                                                     "message": "The file has not been uploaded yet."})
    if size > chat_files.MAX_UPLOAD_BYTES[kind]:
        raise await discard(413, chat_files.FileError("FILE_TOO_LARGE", "The file is too large.",
                                                      {"max_bytes": chat_files.MAX_UPLOAD_BYTES[kind]}))

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / key.rsplit("/", 1)[-1]
        await asyncio.to_thread(storage_service.download_file, key, path)
        try:
            ex = await asyncio.wait_for(asyncio.to_thread(chat_files.extract_file, kind, path),
                                        timeout=chat_files.EXTRACT_TIMEOUT_SECONDS)
        except chat_files.FileError as e:
            raise await discard(422, e)
        except asyncio.TimeoutError:
            raise await discard(422, chat_files.FileError("FILE_TOO_COMPLEX", "The file took too long to read."))
    if ex.estimated_chars > MAX_ATTACHMENT_CHARS:
        raise await discard(413, chat_files.FileError(
            "ATTACHMENT_TOO_LONG", f"The file has more than {MAX_ATTACHMENT_CHARS} characters.",
            {"max_chars": MAX_ATTACHMENT_CHARS, "estimated_chars": ex.estimated_chars}))

    # 画像として読む部分(縮めたJPEG)をR2に置く。画像の資料は、端末が送ったファイルを消し、
    # 作り直した画像(EXIFを消したもの)だけを残す
    image_keys = {k: f"{prefix}img/{k}.jpg" for k in ex.images}
    await asyncio.gather(*[asyncio.to_thread(storage_service.put_bytes, image_keys[k], data, "image/jpeg")
                           for k, data in ex.images.items()])
    if kind == "image":
        await asyncio.to_thread(lambda: storage_service.s3.delete_object(Bucket=storage_service.bucket_name, Key=key))

    extraction = chat_files.extraction_json(ex, image_keys)
    updated = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments").update({
            "extraction": extraction, "page_count": ex.page_count, "char_count": ex.text_chars,
            "token_count": extraction["estimated_tokens"],
            **({"image_path": image_keys["main"]} if kind == "image" else {}),
        }).eq("id", attachment_id).eq("status", "draft").execute()
    )
    if not updated.data:
        raise HTTPException(status_code=404, detail={"error_code": "ATTACHMENT_NOT_FOUND", "message": "Attachment not found."})
    return chat_files.draft_info(updated.data[0])


@app.get("/chat/attachments/{attachment_id}/file")
async def get_chat_attachment_file(attachment_id: str, request: Request):
    """添付したファイルを開くための短い署名付きURL(本人のみ。PDF・画像はブラウザでそのまま表示できる)。"""
    uid = await _get_authenticated_user_id(request)
    attachment_id = _parse_uuid_or_422(attachment_id, "attachment_id")
    admin_client = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: admin_client.table("chat_attachments")
            .select("id, user_id, kind, storage_prefix, image_path, file_name, mime_type, deleted_at")
            .eq("id", attachment_id).maybe_single().execute()
    )
    row = res.data if res else None
    if not row or row.get("user_id") != uid or row.get("deleted_at") or not row.get("storage_prefix"):
        raise HTTPException(status_code=404, detail={"error_code": "ATTACHMENT_NOT_FOUND", "message": "Attachment not found."})
    kind = row["kind"]
    if kind == "image":
        key, content_type = row.get("image_path"), "image/jpeg"
    else:
        key, content_type = chat_files.upload_key(row["storage_prefix"], kind), chat_files.UPLOAD_CONTENT_TYPES[kind]
    if not key:
        raise HTTPException(status_code=404, detail={"error_code": "ATTACHMENT_NOT_FOUND", "message": "Attachment not found."})
    file_name = row.get("file_name") or "file"
    if kind == "image" and not file_name.lower().endswith((".jpg", ".jpeg")):
        file_name = Path(file_name).stem + ".jpg"
    url = await asyncio.to_thread(storage_service.generate_presigned_view_url, key, file_name, content_type)
    return {"url": url, "file_name": file_name, "kind": kind, "content_type": content_type}


# ---------------------------------------------------------
# 🪞 自分像プロフィール: 本人の操作(ロードマップ9章)
# 読み出しはwebappが本人のJWTでSupabaseから直接行う(各テーブルにSELECTのRLSがある)。
# 書き込みはすべてここを通す(テーブルには本人向けの書き込みポリシーを置いていない)。
# ---------------------------------------------------------

PROFILE_ITEM_MAX_CHARS = 500


def _profile_item_not_found() -> HTTPException:
    return HTTPException(status_code=404, detail={"error_code": "PROFILE_ITEM_NOT_FOUND", "message": "Item not found."})


@app.get("/profile/self-portrait")
async def get_self_portrait(request: Request):
    """自分像ページ: いまのわたし(表紙)・書き直し案・カテゴリと項目(確認待ちを含む)・最近わかったこと。"""
    uid = await _get_authenticated_user_id(request)
    return await asyncio.to_thread(profile_store.self_portrait, uid)


@app.get("/profile/items/{item_id}")
async def get_profile_item(item_id: str, request: Request):
    """項目を開いたとき: 根拠になった会話と、書き直しの履歴。"""
    uid = await _get_authenticated_user_id(request)
    item_id = _parse_uuid_or_422(item_id, "item_id")
    detail = await asyncio.to_thread(profile_store.item_detail, uid, item_id)
    if detail is None:
        raise _profile_item_not_found()
    return detail


@app.get("/profile/ai-memory")
async def get_ai_memory(request: Request):
    """AIチャット設定: 覚え書きと、会話ごとのAIのメモ(観察)。仮説は返さない。"""
    uid = await _get_authenticated_user_id(request)
    return await asyncio.to_thread(profile_store.ai_memory, uid)


@app.delete("/profile/observations/{observation_id}")
async def delete_profile_observation(observation_id: str, request: Request):
    """AIのメモを1件消す。"""
    uid = await _get_authenticated_user_id(request)
    observation_id = _parse_uuid_or_422(observation_id, "observation_id")
    if not await profile_store.delete_observation(uid, observation_id):
        raise HTTPException(status_code=404, detail={"error_code": "OBSERVATION_NOT_FOUND", "message": "Not found."})
    return {"success": True}


@app.post("/profile/items/{item_id}/reject")
async def reject_profile_item(item_id: str, payload: ProfileItemRejectRequest, request: Request):
    """「違う」: 項目を rejected にし、同じ意味の項目を作り直させない。"""
    uid = await _get_authenticated_user_id(request)
    item_id = _parse_uuid_or_422(item_id, "item_id")
    try:
        await profile_store.reject_item(uid, item_id, payload.reason)
    except profile_store.ProfileItemNotFound:
        raise _profile_item_not_found()
    return {"success": True}


@app.patch("/profile/items/{item_id}")
async def edit_profile_item(item_id: str, payload: ProfileItemEditRequest, request: Request):
    """「直す」: 本人の文にする。以後AIはこの文を書き換えない。"""
    uid = await _get_authenticated_user_id(request)
    item_id = _parse_uuid_or_422(item_id, "item_id")
    content = (payload.content or "").strip()
    if not content or len(content) > PROFILE_ITEM_MAX_CHARS:
        raise HTTPException(status_code=422, detail={"error_code": "INVALID_CONTENT",
                                                     "message": f"Content must be 1-{PROFILE_ITEM_MAX_CHARS} characters."})
    try:
        await profile_store.edit_item(uid, item_id, content)
    except profile_store.ProfileItemNotFound:
        raise _profile_item_not_found()
    return {"success": True}


@app.post("/profile/items/{item_id}/discard")
async def discard_profile_item(item_id: str, request: Request):
    """「残したくない」(確認トレイの「残さない」も同じ): 中身と根拠を消す。センシティブなら分野だけ覚える。"""
    uid = await _get_authenticated_user_id(request)
    item_id = _parse_uuid_or_422(item_id, "item_id")
    try:
        blocked_area = await profile_store.discard_item(uid, item_id)
    except profile_store.ProfileItemNotFound:
        raise _profile_item_not_found()
    return {"success": True, "blocked_area": blocked_area}


@app.post("/profile/items/{item_id}/keep")
async def keep_profile_item(item_id: str, request: Request):
    """確認トレイの「残す」。"""
    uid = await _get_authenticated_user_id(request)
    item_id = _parse_uuid_or_422(item_id, "item_id")
    try:
        await profile_store.keep_pending_item(uid, item_id)
    except profile_store.ProfileItemNotFound:
        raise _profile_item_not_found()
    return {"success": True}


@app.post("/profile/items/seen")
async def mark_profile_items_seen(payload: ProfileItemsSeenRequest, request: Request):
    """「新しい」印を消す(画面に表示した項目)。"""
    uid = await _get_authenticated_user_id(request)
    ids = [_parse_uuid_or_422(i, "item_ids") for i in payload.item_ids[:200]]
    await profile_store.mark_items_seen(uid, ids)
    return {"success": True}


@app.delete("/profile/memos/{memo_id}")
async def delete_ai_memo(memo_id: str, request: Request):
    """AIチャット設定: 覚え書きを1つ消す。"""
    uid = await _get_authenticated_user_id(request)
    memo_id = _parse_uuid_or_422(memo_id, "memo_id")
    if not await profile_store.delete_memo(uid, memo_id):
        raise HTTPException(status_code=404, detail={"error_code": "MEMO_NOT_FOUND", "message": "Memo not found."})
    return {"success": True}


@app.post("/profile/ai-notes/forget")
async def forget_ai_notes(request: Request):
    """AIチャット設定: AIのメモ(観察メモと仮説)を全部消す。見えている自分像と覚え書きは残す。"""
    uid = await _get_authenticated_user_id(request)
    await profile_store.forget_ai_notes(uid)
    return {"success": True}


@app.post("/profile/cover-proposals/{proposal_id}/{decision}")
async def decide_profile_cover_proposal(proposal_id: str, decision: str, request: Request):
    """表紙の書き直し案を反映する(accept)か、今のままにする(reject)。"""
    uid = await _get_authenticated_user_id(request)
    proposal_id = _parse_uuid_or_422(proposal_id, "proposal_id")
    if decision not in ("accept", "reject"):
        raise HTTPException(status_code=404, detail={"error_code": "NOT_FOUND", "message": "Unknown decision."})
    if not await profile_store.decide_cover_proposal(uid, proposal_id, decision == "accept"):
        raise HTTPException(status_code=404, detail={"error_code": "PROPOSAL_NOT_FOUND", "message": "Proposal not found."})
    return {"success": True}
