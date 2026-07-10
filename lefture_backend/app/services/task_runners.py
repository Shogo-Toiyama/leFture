import os
import asyncio
import shutil
import traceback
import json
import re
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Any

from app.core.config import BASE_WORK_DIR
from app.core.supabase import get_supabase_client
from app.core.r2_storage import storage_service
from app.services.helpers.helpers import TaskLogger, _parse_detail_contents, _merge_graph_mutation, _get_sentence_review_context, _get_student_profile, _sid_to_int, _int_to_sid
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM

from app.services.logic.transcription import TranscriptionService
from app.services.logic.assemble_transcript import AssembleTranscriptService
from app.services.logic.sentence_review import SentenceReviewService
from app.services.logic.core_extraction import CoreExtractionService
from app.services.logic.role_classification import RoleClassificationService
from app.services.logic.announcement_generation import AnnouncementGenerationService
from app.services.logic.topic_mapping import TopicMappingService
from app.services.logic.review_card_generation import ReviewCardGenerationService
from app.services.logic.image_generation import ImageGenerationService
from app.services.logic.image_rendering import ImageRenderingService
from app.services.logic.web_search import WebSearchService
from app.services.logic.fun_fact_generation import FunFactGenerationService
from app.services.logic.topic_details_generation import TopicDetailGenerationService

# CHECK_AND_ASSEMBLEが「チャンクが揃うまで待つ」際に、PROCESSING/TRANSCRIBINGのまま
# これ以上(分)動きが無いチャンクを「詰まっている」とみなして再enqueueする閾値。
# DAGタスク用の閾値より短くしているのは、音声チャンクの処理はずっと短時間で終わる想定のため。
CHUNK_STALE_TIMEOUT_MINUTES = int(os.getenv("CHUNK_STALE_TIMEOUT_MINUTES", "5"))


# =========================================================
# 🛠️ 共通ヘルパー関数
# =========================================================

def reconstruct_chunk_start_times(chunks: list[dict]) -> list[dict]:
    """
    Reconstructs the absolute start_time of chunks in case of client-side timer resets.
    If a chunk's start_time drops to 0 or is less than the previous chunk's start_time,
    we compute the expected start time based on the previous chunk's start_time and duration.
    """
    if not chunks:
        return chunks

    # Sort chunks by chunk_index to ensure chronological order
    sorted_chunks = sorted(chunks, key=lambda x: x.get("chunk_index", 0))

    adjusted_chunks = []
    current_offset = 0.0

    for i, chunk in enumerate(sorted_chunks):
        new_chunk = chunk.copy()
        raw_start = chunk.get("start_time")
        if raw_start is None:
            raw_start = 0.0
            
        if i > 0:
            prev_chunk = adjusted_chunks[i-1]
            prev_raw_start = sorted_chunks[i-1].get("start_time")
            if prev_raw_start is None:
                prev_raw_start = 0.0
            prev_duration = sorted_chunks[i-1].get("audio_duration")
            if prev_duration is None:
                prev_duration = 0.0
            
            # Detect timer reset: current start_time is 0 or drops below previous raw start_time
            if raw_start == 0.0 or raw_start < prev_raw_start:
                # Accumulate the offset
                expected_start = prev_chunk.get("start_time", 0.0) + prev_duration
                current_offset = expected_start - raw_start
        
        new_chunk["start_time"] = raw_start + current_offset
        adjusted_chunks.append(new_chunk)
        
    return adjusted_chunks


def _update_task_status_sync(task_id: str, status: str, payload: dict = None, error_msg: str = None):
    supabase = get_supabase_client()
    update_data = {
        "status": status,
        "updated_at": datetime.now().isoformat()
    }
    if payload is not None:
        update_data["result_payload"] = payload
    if error_msg is not None:
        update_data["error_message"] = str(error_msg)
        
    supabase.table("processing_tasks").update(update_data).eq("id", task_id).execute()

def _get_job_context_sync(job_id: str) -> dict:
    supabase = get_supabase_client()
    res = supabase.table("processing_jobs").select("lecture_id, user_id, expected_chunks").eq("id", job_id).single().execute()
    return res.data

def _get_dependency_payload_sync(job_id: str, target_task_type: str) -> dict:
    supabase = get_supabase_client()
    res = supabase.table("processing_tasks").select("result_payload")\
        .eq("job_id", job_id).eq("task_type", target_task_type).single().execute()
    return res.data.get("result_payload") or {}

def _download_from_r2_to_memory_sync(storage_path: str) -> Any:
    response = storage_service.s3.get_object(
        Bucket=storage_service.bucket_name,
        Key=storage_path
    )
    return json.loads(response["Body"].read().decode("utf-8"))

def _claim_task_sync(task_id: str) -> bool:
    """
    QUEUEDまたはFAILED状態のタスクだけをRUNNINGにアトミックに更新する。
    同じタスクが2回"同時に"走り出しても、更新できるのは1回だけ（更新0件なら
    二重実行とみなしスキップする）ため、真の同時実行だけを防げる。

    FAILEDもクレーム対象に含めているのが重要: Cloud Tasksは500応答を見て
    自動的にリトライしてくる（正当な再試行）。もしQUEUEDのみをクレーム対象にすると、
    1回目の失敗でstatusがFAILEDになった時点でこのリトライが「QUEUEDじゃないから」と
    毎回スキップされ、200 OKを返してしまう。するとCloud Tasksは「成功した」と
    誤解して以降二度とリトライしなくなり、タスクがFAILEDのまま永久に取り残される。
    """
    res = get_supabase_client().table("processing_tasks")\
        .update({"status": "RUNNING", "updated_at": datetime.now().isoformat()})\
        .eq("id", task_id).in_("status", ["QUEUED", "FAILED"]).execute()
    return len(res.data or []) > 0


# 上記5つは同期I/O（Supabase/boto3）を直接叩くため、async defの中から呼ぶ際は
# 必ずスレッドに逃がす。ラッパーをここに集約することで、呼び出し側は
# 「await するだけ」で済み、塗り漏らしを防ぐ。
async def _update_task_status(task_id: str, status: str, payload: dict = None, error_msg: str = None):
    await asyncio.to_thread(_update_task_status_sync, task_id, status, payload, error_msg)

async def _get_job_context(job_id: str) -> dict:
    return await asyncio.to_thread(_get_job_context_sync, job_id)

async def _get_dependency_payload(job_id: str, target_task_type: str) -> dict:
    return await asyncio.to_thread(_get_dependency_payload_sync, job_id, target_task_type)

async def _download_from_r2_to_memory(storage_path: str) -> Any:
    return await asyncio.to_thread(_download_from_r2_to_memory_sync, storage_path)

async def _claim_task(task_id: str) -> bool:
    return await asyncio.to_thread(_claim_task_sync, task_id)


def _parse_supabase_timestamp(raw: str) -> "datetime | None":
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (ValueError, AttributeError):
        return None


async def _recover_stuck_chunks(supabase, lecture_id: str, all_chunks: list, uid: str, logger: TaskLogger):
    """
    CHECK_AND_ASSEMBLEがチャンクの完了を待っている最中に呼ばれる。
    PROCESSING/TRANSCRIBING/ERRORのまま CHUNK_STALE_TIMEOUT_MINUTES 以上動きが無い
    チャンクを「詰まっている」とみなし、R2上の音声（決定的なパスで再構築可能）を
    使って文字起こしを再enqueueする。専用のスケジューラーを用意しなくても、
    CHECK_AND_ASSEMBLEの待ち合わせリトライ自体がこの回収ループを兼ねる。
    ERRORも対象に含めるのは、Cloud Tasks自体が既定のリトライ回数を使い果たして
    諦めてしまった場合、それ以降は誰もこのチャンクを再試行しないため
    （process_transcribe_chunk側のクレームはCloud Tasksがまだリトライしている間しか
    効かない）、ここが最後の回収役になる。
    """
    threshold = datetime.now(timezone.utc) - timedelta(minutes=CHUNK_STALE_TIMEOUT_MINUTES)

    stuck_chunks = []
    for c in all_chunks:
        if c.get("status") not in ("PROCESSING", "TRANSCRIBING", "ERROR"):
            continue
        updated_at = _parse_supabase_timestamp(c.get("updated_at") or "")
        if updated_at and updated_at < threshold:
            stuck_chunks.append(c)

    if not stuck_chunks:
        return

    # main.pyとの循環importを避けるためローカルimport（receive_transcribe_chunkと同じ流儀）
    from app.main import enqueue_transcribe_chunk_task

    for c in stuck_chunks:
        chunk_index = c["chunk_index"]

        # アトミックにクレームしてから再enqueue（他プロセスが直前に完了させた場合はスキップ）
        claim_res = await asyncio.to_thread(
            lambda chunk_index=chunk_index: supabase.table("lecture_transcripts")
                .update({"status": "PROCESSING", "updated_at": datetime.now().isoformat()})
                .eq("lecture_id", lecture_id).eq("chunk_index", chunk_index)
                .in_("status", ["PROCESSING", "TRANSCRIBING", "ERROR"])
                .execute()
        )
        if not (claim_res.data or []):
            continue

        seq_str = str(chunk_index).zfill(3)
        r2_audio_path = f"{uid}/{lecture_id}/audio_chunks/chunk_{seq_str}.m4a"

        try:
            await enqueue_transcribe_chunk_task(
                lecture_id=lecture_id,
                chunk_index=chunk_index,
                start_time=c.get("start_time") or 0.0,
                whisper_context="",  # Supabase側に永続化されていない一時ヒントのため空文字にフォールバック
                r2_audio_path=r2_audio_path,
                uid=uid,
            )
            logger.log(f"🩹 Recovered stuck chunk {chunk_index} (re-enqueued transcription)")
        except Exception as e:
            logger.log(f"⚠️ Failed to re-enqueue stuck chunk {chunk_index}: {e}")


# =========================================================
# 👷 現場監督たち (Task Runners)
# =========================================================

# ---------------------------------------------------------
# 1. Transcribe Chunk （Groqでリアルタイム文字起こし）
# ---------------------------------------------------------

async def receive_transcribe_chunk(lecture_id: str, chunk_index: int, start_time: float, audio_bytes: bytes, whisper_context: str = ""):
    """
    Flutterから直接送られてきたM4A(AAC)バイナリを受け取り、R2への保存とCloud Tasksへの
    enqueueだけ行って即座に返る（受付窓口）。実際の文字起こしは process_transcribe_chunk
    が非同期に行うため、Cloudflare Whisper側がハングしてもこの関数自体は詰まらない。
    """
    supabase = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: supabase.table("lectures").select("user_id").eq("id", lecture_id).single().execute()
    )
    uid = res.data["user_id"] if res.data else "unknown_user"

    # 受け取った音声バイナリをそのまま R2 に保存（バックアップ＆参照用、非同期処理側が後で読み直す）
    seqStr = str(chunk_index).zfill(3)
    audio_r2_path = await asyncio.to_thread(
        storage_service.save_binary,
        uid=uid,
        lecture_id=lecture_id,
        file_name=f"audio_chunks/chunk_{seqStr}.m4a",
        data=audio_bytes,
        content_type="audio/mp4"
    )

    # Cloud Tasksへenqueue（main.pyとの循環importを避けるためローカルimport）
    from app.main import enqueue_transcribe_chunk_task
    await enqueue_transcribe_chunk_task(
        lecture_id=lecture_id,
        chunk_index=chunk_index,
        start_time=start_time,
        whisper_context=whisper_context,
        r2_audio_path=audio_r2_path,
        uid=uid,
    )


async def process_transcribe_chunk(lecture_id: str, chunk_index: int, start_time: float, whisper_context: str, r2_audio_path: str, uid: str):
    """
    receive_transcribe_chunk がenqueueしたタスクを実際に処理する（Cloud Tasksから呼ばれる）。
    R2から音声を取得し、Cloudflare Whisperで文字起こしし、DBを更新、4チャンクごとの
    Sentence Reviewバッチをアトミックにトリガーする。
    """
    supabase = get_supabase_client()
    logger = TaskLogger(uid, lecture_id, f"TRANSCRIBE_CHUNK_{chunk_index:03d}")
    billing = BillingEngine(task_type="TRANSCRIBE_CHUNK")

    try:
        logger.log(f"🎤 [Queued] Transcribing chunk {chunk_index} for lecture {lecture_id}")

        # 0. PROCESSING または ERROR 状態のチャンクだけをアトミックにTRANSCRIBINGへクレームする。
        # Cloud Tasksのリトライ等で同じチャンクが2回"同時に"走り出しても、
        # 実際に処理を進められるのは1回だけ（Cloudflareへの二重課金・二重書き込みを防ぐ）。
        # ERRORも対象に含めるのが重要: この関数は失敗時に例外を再送出して500を返し、
        # Cloud Tasksの自動リトライに任せる設計。もしPROCESSINGのみをクレーム対象にすると、
        # 1回目の失敗でstatusがERRORになった時点で、その後の正当なリトライが
        # 毎回「PROCESSINGじゃないから」とスキップされ200 OKを返してしまい、
        # Cloud Tasksが「成功した」と誤解して二度とリトライしなくなる。
        claim_res = await asyncio.to_thread(
            lambda: supabase.table("lecture_transcripts")
                .update({"status": "TRANSCRIBING"})
                .eq("lecture_id", lecture_id).eq("chunk_index", chunk_index)
                .in_("status", ["PROCESSING", "ERROR"])
                .execute()
        )
        if not (claim_res.data or []):
            logger.log(f"⏭️ Chunk {chunk_index} is not in PROCESSING/ERROR state. Skipping duplicate execution.")
            return

        # 1. R2から音声バイナリを取得
        audio_bytes = await asyncio.to_thread(storage_service.download_binary, r2_audio_path)

        # 2. 職人を呼んで、音声バイナリを直接渡す
        transcriber = TranscriptionService(logger, billing)

        result = await transcriber.run_in_memory(
            audio_bytes=audio_bytes,
            chunk_index=chunk_index,
            prompt_keywords=whisper_context,
        )

        # 3. DBを更新し、真実のテキストを書き込む（R2への保存は受付側で完了済み）
        # idではなく、lecture_idとchunk_indexの組み合わせでレコードを特定して更新する
        is_silent = len(result["segments"]) == 0
        new_status = "REVIEWED" if is_silent else "TRANSCRIBED"
        await asyncio.to_thread(
            lambda: supabase.table("lecture_transcripts").update({
                "audio_duration": result["audio_duration"],
                "status": new_status,
                "text_stt": result["text"],
                "segments_stt": result["segments"],
                "confidence": result["segments"][0]["confidence"] if result["segments"] else 0.0,
                "storage_path": r2_audio_path,
            }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()
        )

        logger.log(f"✅ Chunk transcription completed: Chunk {chunk_index}")
        if result["text"]:
            logger.log(f"📝 Text: {result['text'][:30]}...")
        else:
            logger.log(f"🔇 Text: (No speech detected, skipped Groq)")

        # =========================================================
        # Sentence Review のトリガー (4枚区切りでアトミックに並行制御)
        # =========================================================

        # 1. 自分が所属するバッチ（4つ区切り）を特定
        batch_start = (chunk_index // 4) * 4
        batch_indices = [batch_start + i for i in range(4)]

        logger.log(f"🔍 Checking progressive Sentence Review batch starting at {batch_start} (Chunks: {batch_indices})")

        try:
            # 2. バッチの4つのチャンクの状態を確認
            check_res = await asyncio.to_thread(
                lambda: supabase.table("lecture_transcripts")
                    .select("chunk_index, status")
                    .eq("lecture_id", lecture_id)
                    .in_("chunk_index", batch_indices)
                    .execute()
            )

            chunks_status = {c["chunk_index"]: c["status"] for c in check_res.data or []}
            all_ready = len(chunks_status) == 4 and all(status == "TRANSCRIBED" for status in chunks_status.values())

            if all_ready:
                # 3. 4つのチャンクをアトミックに 'REVIEWING' に更新 (TRANSCRIBED であるもののみ)
                # 同時実行された場合、先に更新に成功した1プロセスのみが更新件数4を獲得する
                lock_res = await asyncio.to_thread(
                    lambda: supabase.table("lecture_transcripts")
                        .update({"status": "REVIEWING"})
                        .eq("lecture_id", lecture_id)
                        .in_("chunk_index", batch_indices)
                        .eq("status", "TRANSCRIBED")
                        .execute()
                )

                updated_chunks = lock_res.data or []

                if len(updated_chunks) == 4:
                    logger.log(f"🔒 Lock acquired for batch {batch_start}! Executing Sentence Review...")

                    # 最新のデータを再度取得してインデックス順にソート
                    batch_res = await asyncio.to_thread(
                        lambda: supabase.table("lecture_transcripts")
                            .select("*")
                            .eq("lecture_id", lecture_id)
                            .in_("chunk_index", batch_indices)
                            .order("chunk_index")
                            .execute()
                    )

                    chunks_to_review = batch_res.data or []

                    # タイムライン再構築のために、このバッチまでのすべての履歴を取得
                    history_res = await asyncio.to_thread(
                        lambda: supabase.table("lecture_transcripts")
                            .select("*")
                            .eq("lecture_id", lecture_id)
                            .lte("chunk_index", batch_start + 3)
                            .order("chunk_index")
                            .execute()
                    )

                    adjusted_history = reconstruct_chunk_start_times(history_res.data or [])

                    # 補正済みのリストから chunks_to_review と prev_chunk を抽出
                    adjusted_review_map = {c["chunk_index"]: c for c in adjusted_history}
                    chunks_to_review = [adjusted_review_map[c["chunk_index"]] for c in chunks_to_review if c["chunk_index"] in adjusted_review_map]

                    prev_chunk = adjusted_review_map.get(batch_start - 1) if batch_start > 0 else None

                    logger.log(f"🚀 Triggering Sentence Review for chunks {batch_start} to {batch_start + 3}")

                    # SentenceReviewService を呼び出し
                    course_title, keywords_list = await asyncio.to_thread(_get_sentence_review_context, lecture_id)

                    llm = UnifiedLLM(billing)
                    reviewer = SentenceReviewService(llm, logger)
                    reviewed_chunks = await reviewer.run_from_memory(
                        chunks_to_review=chunks_to_review,
                        previous_chunk=prev_chunk,
                        course_title=course_title,
                        keywords_list=keywords_list
                    )

                    # 返ってきた綺麗なデータを DB に書き込み REVIEWED に更新
                    def _write_reviewed_chunks_sync():
                        for rc in reviewed_chunks:
                            supabase.table("lecture_transcripts").update({
                                "status": "REVIEWED",
                                "text_reviewed": rc["text"],
                                "segments_reviewed": rc["segments"]
                            }).eq("lecture_id", lecture_id).eq("chunk_index", rc["chunk_index"]).execute()

                    await asyncio.to_thread(_write_reviewed_chunks_sync)

                    logger.log(f"✅ Batch {batch_start} (4 chunks) successfully REVIEWED and updated in DB!")
                else:
                    logger.log(f"⚠️ Lock contention: another worker acquired the lock for batch {batch_start}. Skipping review.")
            else:
                logger.log(f"⏳ Batch starting at {batch_start} is not fully ready yet (statuses: {chunks_status}). Skipping review.")
        except Exception as review_trigger_error:
            logger.log(f"⚠️ Error in progressive Sentence Review trigger: {review_trigger_error}")

        # 📊 レポートの出力とログの保存
        logger.log(billing.report())
        logger.save_to_r2(storage_service)

    except Exception as e:
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ Chunk transcription failed: {error_msg}")
        await asyncio.to_thread(
            lambda: supabase.table("lecture_transcripts").update({
                "status": "ERROR",
                "updated_at": datetime.now().isoformat(),
            }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()
        )
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# 2. Check and Assemble (文字起こしの待ち合わせ＆組み立て)
# ---------------------------------------------------------

async def run_check_and_assemble_transcript_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    
    logger = TaskLogger(uid, lecture_id, "CHECK_AND_ASSEMBLE")
    logger.log(f"▶️ Starting CHECK_AND_ASSEMBLE (Task: {task_id})")
    billing = BillingEngine(task_type="CHECK_AND_ASSEMBLE")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    work_dir = BASE_WORK_DIR / task_id
    work_dir.mkdir(parents=True, exist_ok=True)
    supabase = get_supabase_client()
    
    try:
        expected_chunks = job_ctx.get("expected_chunks", 0)

        if expected_chunks == 0:
            raise ValueError("expected_chunks is 0. Nothing to assemble!")

        # ---------------------------------------------------------
        # A. リアルタイム職人の進捗をDBで確認 (CHECK)
        # ---------------------------------------------------------
        res = await asyncio.to_thread(
            lambda: supabase.table("lecture_transcripts")
                .select("*")
                .eq("lecture_id", lecture_id)
                .order("chunk_index")
                .execute()
        )

        all_chunks = reconstruct_chunk_start_times(res.data or [])
        
        # 処理済みのチャンク（Whisperが終わっているもの）をカウント
        processed_chunks = [c for c in all_chunks if c.get("status") in ["TRANSCRIBED", "REVIEWED"]]
        
        # 待ち合わせロジック
        if len(processed_chunks) < expected_chunks:
            error_msg = f"⏳ Waiting for Whisper transcripts... ({len(processed_chunks)}/{expected_chunks})"
            logger.log(error_msg)

            # 詰まっているチャンクが無いか確認し、あれば再enqueueする。
            # CHECK_AND_ASSEMBLEはチャンクが揃うまでこの関数が繰り返しリトライされる
            # ため、専用のスケジューラーやポーリングを別途用意しなくても、この
            # 待ち合わせループ自体が「音声チャンクの詰まり」の回収役を兼ねられる。
            await _recover_stuck_chunks(supabase, lecture_id, all_chunks, uid, logger)

            # わざとエラーを投げることでリトライさせる
            raise Exception(error_msg)

        # ---------------------------------------------------------
        # B. 端数の Sentence Review
        # ---------------------------------------------------------
        # まだ REVIEWED になっていない（LLMを通っていない）端数チャンクを抽出
        chunks_to_review = [c for c in all_chunks if c.get("status") == "TRANSCRIBED"]

        if chunks_to_review:
            first_leftover_idx = chunks_to_review[0]["chunk_index"]
            chunk_ids = [c["id"] for c in chunks_to_review]
            await asyncio.to_thread(
                lambda: supabase.table("lecture_transcripts").update({"status": "REVIEWING"}).in_("id", chunk_ids).execute()
            )
            logger.log(f"🧹 Running final Sentence Review for {len(chunks_to_review)} leftover chunks (Starting at {first_leftover_idx})...")
            
            # 1つ前のチャンク（REVIEWED）を取得して文脈として渡す
            prev_chunk = next((c for c in all_chunks if c["chunk_index"] == first_leftover_idx - 1), None)

            # LLM職人を呼び出す
            course_title, keywords_list = await asyncio.to_thread(_get_sentence_review_context, lecture_id)
            
            llm = UnifiedLLM(billing)
            reviewer = SentenceReviewService(llm, logger)
            reviewed_leftovers = await reviewer.run_from_memory(
                chunks_to_review=chunks_to_review,
                previous_chunk=prev_chunk,
                course_title=course_title,
                keywords_list=keywords_list
            )
            
            # レビュー結果をDBに書き込み、REVIEWED に昇格
            for rc in reviewed_leftovers:
                await asyncio.to_thread(
                    lambda rc=rc: supabase.table("lecture_transcripts").update({
                        "status": "REVIEWED",
                        "text_reviewed": rc["text"],
                        "segments_reviewed": rc["segments"]
                    }).eq("lecture_id", lecture_id).eq("chunk_index", rc["chunk_index"]).execute()
                )

            logger.log("✅ Final leftover chunks successfully REVIEWED!")

        # ---------------------------------------------------------
        # C. 全て揃っていたら、専用職人を呼んで組み立てる (ASSEMBLE)
        # ---------------------------------------------------------
        # 最新のデータをDBから再度取得し、すべてが REVIEWED になっているか確認
        final_res = await asyncio.to_thread(
            lambda: supabase.table("lecture_transcripts")
                .select("*")
                .eq("lecture_id", lecture_id)
                .order("chunk_index")
                .execute()
        )
            
        adjusted_final = reconstruct_chunk_start_times(final_res.data or [])
        completed_chunks = [c for c in adjusted_final if c.get("status") == "REVIEWED"]
        
        if len(completed_chunks) < expected_chunks:
             raise Exception(f"Mismatch in expected chunks after review. ({len(completed_chunks)}/{expected_chunks})")

        logger.log(f"🎉 All {expected_chunks} chunks REVIEWED! Assembling transcript.json...")
        
        # 組み立てる (AssembleTranscriptService には completed_chunks をそのまま渡せばOK)
        assembler = AssembleTranscriptService(logger)
        assembled_data = assembler.run(completed_chunks)

        # ---------------------------------------------------------
        # D. Storage保存 ＆ DB更新
        # ---------------------------------------------------------
        remote_transcript_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "transcript_assembled", assembled_data)
        
        result_payload = {"transcript_json_path": remote_transcript_path, "billing_records": [vars(r) for r in billing.records]}
        
        await _update_task_status(task_id, "COMPLETED", payload=result_payload)
        logger.log(f"✅ CHECK_AND_ASSEMBLE Completed!")
        logger.save_to_r2(storage_service)

    except Exception as e:
        if "Waiting for" in str(e):
            await _update_task_status(task_id, "PENDING") 
            raise e
            
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ CHECK_AND_ASSEMBLE Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e
        
    finally:
        # ローカルの一時ファイルはお掃除
        if work_dir.exists():
            shutil.rmtree(work_dir)

# ---------------------------------------------------------
# Phase 2: CORE_EXTRACTION
# ---------------------------------------------------------
async def run_core_extraction_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "CORE_EXTRACTION")
    logger.log(f"▶️ Starting CORE_EXTRACTION (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    
    # 💡 このタスク専用のお財布（コスト計算機）を用意
    billing = BillingEngine(task_type="CORE_EXTRACTION")
    
    try:
        prev_payload = await _get_dependency_payload(job_id, "CHECK_AND_ASSEMBLE")
        transcript_data = await _download_from_r2_to_memory(prev_payload["transcript_json_path"])

        # 学生プロフィールの取得
        student_profile = await asyncio.to_thread(_get_student_profile, uid)

        # UnifiedLLMを初期化して職人に渡す
        llm = UnifiedLLM(billing)
        extractor = CoreExtractionService(llm, logger)
        
        # メモリ上で処理
        extraction_result = await extractor.run_from_memory(transcript_data, student_profile)

        # ログをR2に保存
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "core_extraction", extraction_result)

        # Supabaseの `lectures` テーブルを更新 (title_generated と summary)
        supabase = get_supabase_client()
        await asyncio.to_thread(
            lambda: supabase.table("lectures").update({
                "title_generated": extraction_result.get("title"),
                "summary": extraction_result.get("summary"),
                "updated_at": datetime.now().isoformat()
            }).eq("id", lecture_id).execute()
        )

        # 各トピックのキーワードを `keywords` テーブルに保存
        # 冪等性のため、書き込み前にこの講義分の既存キーワードを削除しておく
        # （Cloud Tasksのリトライでこの関数が2回走っても重複しない）
        def _insert_keywords_sync():
            supabase.table("keywords").delete().eq("lecture_id", lecture_id).execute()
            for topic in extraction_result.get("topics", []):
                topic_idx = topic.get("idx")
                topic_keywords = topic.get("keywords", [])
                for kw in topic_keywords:
                    kw_data = {
                        "user_id": uid,
                        "lecture_id": lecture_id,
                        "topic_number": topic_idx,
                        "keyword": kw,
                        "definition": None
                    }
                    supabase.table("keywords").insert(kw_data).execute()

        await asyncio.to_thread(_insert_keywords_sync)

        await _update_task_status(task_id, "COMPLETED", payload={"core_extraction_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        # 📊 最後に今回のタスクのコストレポートを出力！
        logger.log(billing.report())
        logger.log(f"✅ CORE_EXTRACTION Completed!")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ CORE_EXTRACTION Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e
    
# ---------------------------------------------------------
# Phase 3: ROLE_CLASSIFICATION
# ---------------------------------------------------------
async def run_role_classification_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "ROLE_CLASSIFICATION")

    logger.log(f"▶️ Starting ROLE_CLASSIFICATION (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    
    # 💡 このタスク専用のお財布を用意
    billing = BillingEngine(task_type="ROLE_CLASSIFICATION")
    
    try:
        # 1. 必要な前工程のデータをR2からメモリにダウンロード
        # (CHECK_AND_ASSEMBLE から transcript_data を取得)
        transcript_payload = await _get_dependency_payload(job_id, "CHECK_AND_ASSEMBLE")
        transcript_data = await _download_from_r2_to_memory(transcript_payload["transcript_json_path"])
        
        # (CORE_EXTRACTION から topics を取得するために core_data を取得)
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])

        # 2. 新しい職人を呼ぶ
        classifier = RoleClassificationService(billing, logger)
        
        # コースタイトルを取得してテーマのフォールバックにする
        course_title, _ = await asyncio.to_thread(_get_sentence_review_context, lecture_id)

        classified_data = await classifier.run_from_memory(
            transcript_data=transcript_data, 
            core_data=core_data,
            theme=core_data.get("title") or course_title
        )

        # 3. フルログをR2に保存
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "role_classification", classified_data)

        # 4. 次へバケツリレー
        await _update_task_status(task_id, "COMPLETED", payload={"role_classification_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        # 📊 最後にコストレポートを出力
        logger.log(billing.report())
        logger.log(f"✅ ROLE_CLASSIFICATION Completed!")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ ROLE_CLASSIFICATION Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 4-A: ANNOUNCEMENT_GENERATION (事務連絡の抽出)
# ---------------------------------------------------------
async def run_announcement_generation_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "ANNOUNCEMENT_GENERATION")

    logger.log(f"▶️ Starting ANNOUNCEMENT_GENERATION (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    
    billing = BillingEngine(task_type="ANNOUNCEMENT_GENERATION")
    
    # 💡 1. Safety Net 用の正規表現コンパイル
    # \b で単語の境界を指定し、s? などで複数形にも対応させています
    critical_keywords_pattern = re.compile(
        r'\b(office hours?|exams?|midterms?|finals?|assignments?|homeworks?|quiz|quizzes|due|deadlines?|projects?|syllabus|grading|grades?|prerequisites?|plagiarism)\b', 
        re.IGNORECASE
    )
    
    try:        
        # 1. 必要な全データをメモリに読み込む
        # ※ (await _get_dependency_payload(...))["key"] のように必ず括弧で先にawaitを
        # 完了させる。await X(...)["key"] と書くと、Pythonの演算子優先順位により
        # 「X(...)["key"]（coroutineオブジェクトの添字アクセス）」が先に評価されて
        # TypeErrorになる。
        transcript_data = await _download_from_r2_to_memory((await _get_dependency_payload(job_id, "CHECK_AND_ASSEMBLE"))["transcript_json_path"])
        core_data = await _download_from_r2_to_memory((await _get_dependency_payload(job_id, "CORE_EXTRACTION"))["core_extraction_path"])
        classified_data = await _download_from_r2_to_memory((await _get_dependency_payload(job_id, "ROLE_CLASSIFICATION"))["role_classification_path"])

        # 検索しやすくするための辞書を作成
        sid_to_text = {item["sid"]: item["text"] for item in transcript_data if "sid" in item}
        formatted_blocks = []

        # ==========================================
        # ① CORE_EXTRACTION で丸ごと LOGISTICS と判定されたブロック
        # ==========================================
        for topic in core_data.get("topics", []):
            if topic.get("topic_type") == "LOGISTICS":
                topic_title = topic.get("title", "General Logistics")
                start_sid = topic.get("start_sid")
                end_sid = topic.get("end_sid")
                
                start_idx = _sid_to_int(start_sid) if isinstance(start_sid, str) else None
                end_idx = _sid_to_int(end_sid) if isinstance(end_sid, str) else None
                if start_idx is None or end_idx is None:
                    logger.log(f"⚠️ Failed to parse SID in LOGISTICS topic: start_sid={start_sid}, end_sid={end_sid}")
                else:
                    block_lines = [f"[Topic: {topic_title}]"]
                    for i in range(start_idx, end_idx + 1):
                        sid = _int_to_sid(i)
                        if sid in sid_to_text:
                            block_lines.append(f"{sid}: {sid_to_text[sid]}")

                    formatted_blocks.append("\n".join(block_lines))

        # ==========================================
        # ② ROLE_CLASSIFICATION & Safety Net (キーワード抽出)
        # ==========================================
        logistics_indices = []
        safety_net_catch_count = 0 # ログ出力用
        
        for i, sentence in enumerate(classified_data):
            text = sentence.get("text", "")
            
            # 1. AIによる判定
            is_logistics_role = (sentence.get("role") == "LOGISTICS")
            
            # 2. 正規表現による Safety Net 判定
            is_safety_net_match = bool(critical_keywords_pattern.search(text))
            
            # どちらかに引っかかれば「事務連絡の種」として採用！
            if is_logistics_role or is_safety_net_match:
                logistics_indices.append(i)
                
                # デバッグ用に、Safety Net「だけ」で救われた文をカウント
                if not is_logistics_role and is_safety_net_match:
                    safety_net_catch_count += 1
                    
        if safety_net_catch_count > 0:
            logger.log(f"   [Logic] 🛟 Safety Net successfully caught {safety_net_catch_count} sentences that AI missed!")
        
        if logistics_indices:
            blocks = []
            current_block = [logistics_indices[0]]
            
            # ブリッジ処理: 間が3文以内（インデックス差が4以下）なら結合
            for i in range(1, len(logistics_indices)):
                if logistics_indices[i] - logistics_indices[i-1] <= 4:
                    current_block.append(logistics_indices[i])
                else:
                    blocks.append(current_block)
                    current_block = [logistics_indices[i]]
            blocks.append(current_block)

            # マージン処理とテキスト化
            for block in blocks:
                start_idx = max(0, block[0] - 3)
                end_idx = min(len(classified_data) - 1, block[-1] + 3)
                
                # このブロックが元々どのトピックに属していたか推測（真ん中の文を基準にする）
                mid_idx = block[len(block)//2]
                mid_sid_num = _sid_to_int(classified_data[mid_idx].get("sid"))

                topic_title = "Embedded Announcement"
                if mid_sid_num is not None:
                    for topic in core_data.get("topics", []):
                        t_start = _sid_to_int(topic.get("start_sid"))
                        t_end = _sid_to_int(topic.get("end_sid"))
                        if t_start is not None and t_end is not None and t_start <= mid_sid_num <= t_end:
                            topic_title = topic.get("title", "Embedded Announcement")
                            break
                
                block_lines = [f"[Topic: {topic_title}]"]
                for i in range(start_idx, end_idx + 1):
                    sid = classified_data[i]["sid"]
                    text = classified_data[i]["text"]
                    block_lines.append(f"{sid}: {text}")
                    
                formatted_blocks.append("\n".join(block_lines))

        # ==========================================
        # ③ 結合して LLM (職人) を呼ぶ
        # ==========================================
        formatted_transcript = "\n\n".join(formatted_blocks)
        await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "input_announcement_generation", {"formatted_transcript": formatted_transcript})
        
        llm = UnifiedLLM(billing)
        announcer = AnnouncementGenerationService(llm, logger)
        
        announcements_json = await announcer.run_from_memory(formatted_transcript)
        
        # 4. フルログを R2 に保存
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "announcements", announcements_json)

        # 5. Supabaseの `announcements` テーブルに書き込む処理
        supabase = get_supabase_client()
        valid_sids = set(sid_to_text.keys())

        def _normalize_announcement_sid_range(start_sid, end_sid):
            """
            LLMが返したstart_sid/end_sidを検証する。announcementの内容自体は
            SIDが壊れていても価値があるかもしれないため、この関数は常に
            announcementを保存させる前提で「位置情報だけ」を正規化する:
            - start/endが逆転していれば入れ替えて正しい順序に直す
            - フォーマットが崩れていれば正規形に直す
            - それでも実在しないSIDなら、位置情報無しとして (None, None) を返す
              （announcement自体は後続で必ず保存される。ユーザーが後から見て
              不要なら削除できるため、位置がズレていても情報を失うよりはまし）
            """
            start_num = _sid_to_int(start_sid) if isinstance(start_sid, str) else None
            end_num = _sid_to_int(end_sid) if isinstance(end_sid, str) else None
            if start_num is None or end_num is None:
                return None, None

            if start_num > end_num:
                logger.log(f"⚠️ Announcement SID range was reversed, swapping: {start_sid} <-> {end_sid}")
                start_num, end_num = end_num, start_num

            normalized_start, normalized_end = _int_to_sid(start_num), _int_to_sid(end_num)
            if normalized_start not in valid_sids or normalized_end not in valid_sids:
                logger.log(
                    f"⚠️ Announcement SID range does not exist in transcript, saving without SID: "
                    f"start_sid={start_sid}, end_sid={end_sid}"
                )
                return None, None

            return normalized_start, normalized_end

        # 冪等性のため、書き込み前にこの講義分の既存announcementsを削除しておく
        def _insert_announcements_sync():
            supabase.table("announcements").delete().eq("lecture_id", lecture_id).execute()
            for announcement in announcements_json.get("announcements", []):
                start_sid, end_sid = _normalize_announcement_sid_range(
                    announcement.get("start_sid"), announcement.get("end_sid")
                )
                ann_data = {
                    "user_id": uid,
                    "lecture_id": lecture_id,
                    "type": announcement.get("type"),
                    "title": announcement.get("title"),
                    "description": announcement.get("description"),
                    "location": announcement.get("location"),
                    "start_sid": start_sid,
                    "end_sid": end_sid,
                    "related_topic_title": announcement.get("related_topic_title"),
                    "datetime_parameters": announcement.get("datetime_parameters"),
                    "metadata": {"is_completed": False}
                }
                # SIDが壊れていても、announcement自体の情報は必ず保存する。
                supabase.table("announcements").insert(ann_data).execute()

        await asyncio.to_thread(_insert_announcements_sync)

        await _update_task_status(task_id, "COMPLETED", payload={"announcements_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        logger.log(billing.report())
        logger.log(f"✅ ANNOUNCEMENT_GENERATION Completed!")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ ANNOUNCEMENT_GENERATION Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 4-B: TOPIC_MAPPING (知識グラフの差分更新)
# ---------------------------------------------------------
async def run_topic_mapping_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "TOPIC_MAPPING")

    logger.log(f"▶️ Starting TOPIC_MAPPING (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    
    billing = BillingEngine(task_type="TOPIC_MAPPING")
    
    try:        
        # 1. 今日のトピックデータをR2から取得 (CORE_EXTRACTION の結果を使用)
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])
        
        # 今日のマクロトピック（ACADEMICのみ）を抽出
        academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]
        
        # コースIDと講義番号の取得
        supabase = get_supabase_client()

        def _fetch_course_and_lecture_num_sync():
            lec_res = supabase.table("lectures").select("course_id").eq("id", lecture_id).single().execute()
            course_id = lec_res.data.get("course_id") if lec_res.data else None

            lecture_num = 1
            if course_id:
                lectures_res = supabase.table("lectures")\
                    .select("id")\
                    .eq("course_id", course_id)\
                    .is_("deleted_at", "null")\
                    .order("created_at")\
                    .execute()
                if lectures_res.data:
                    lecture_ids = [l["id"] for l in lectures_res.data]
                    if lecture_id in lecture_ids:
                        lecture_num = lecture_ids.index(lecture_id) + 1
            return course_id, lecture_num

        course_id, lecture_num = await asyncio.to_thread(_fetch_course_and_lecture_num_sync)

        # ACADEMICトピックのみの連番で node_lcX_Y を付与
        todays_topics_list = []
        for i, t in enumerate(academic_topics, start=1):
            topic_copy = t.copy()
            topic_copy["topic_id"] = f"node_lc{lecture_num}_{i}"
            todays_topics_list.append(topic_copy)
            
        todays_macro_topics = {
            "lecture_title": core_data.get("title"),
            "topics": todays_topics_list
        }

        # 2. 過去のグラフ状態を Supabase から取得
        current_graph_state = {
            "clusters": [],
            "nodes": [],
            "edges": [],
            "ghost_nodes": []
        }
        
        if course_id:
            def _fetch_existing_map_sync():
                return supabase.table("topic_maps").select("map").eq("course_id", course_id).execute()

            map_res = await asyncio.to_thread(_fetch_existing_map_sync)
            if map_res.data:
                db_map = map_res.data[0].get("map")
                if db_map and isinstance(db_map, dict):
                    current_graph_state["clusters"] = db_map.get("clusters") or []
                    current_graph_state["nodes"] = db_map.get("nodes") or []
                    current_graph_state["edges"] = db_map.get("edges") or []
                    current_graph_state["ghost_nodes"] = db_map.get("ghost_nodes") or []

        # 3. 職人を呼ぶ
        llm = UnifiedLLM(billing)
        mapper = TopicMappingService(llm, logger)
        
        # メモリ上でマッピング実行
        mapping_result = await mapper.run_from_memory(
            current_graph=current_graph_state,
            todays_topics=todays_macro_topics
        )

        # 4. フルログをR2に保存
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "topic_mapping", mapping_result)

        # 5. 差分を Full Map にマージ
        mutations = mapping_result.get("graph_mutations") or {}
        new_graph = _merge_graph_mutation(current_graph_state, mutations, todays_topics_list, logger=logger)

        # 6. Supabase の `topic_maps` テーブルに更新保存
        # course_id にUNIQUE制約がある前提で upsert する。update/insertを手動で
        # 分岐していた従来方式は、リトライで2プロセスが同時に「新規」と判定すると
        # 重複行を作ってしまうため、DB側のUNIQUE制約に守られたupsertに統一した。
        if course_id:
            map_data = {
                "user_id": uid,
                "course_id": course_id,
                "map": new_graph,
                "updated_at": datetime.now().isoformat()
            }
            await asyncio.to_thread(
                lambda: supabase.table("topic_maps").upsert(map_data, on_conflict="course_id").execute()
            )
            logger.log(f"💾 Upserted topic map for course {course_id} in Supabase")

        # 7. ステータス更新
        await _update_task_status(task_id, "COMPLETED", payload={"topic_mapping_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        # 📊 コストレポート出力
        logger.log(billing.report())
        logger.log(f"✅ TOPIC_MAPPING Completed!")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ TOPIC_MAPPING Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e
    
# ---------------------------------------------------------
# Phase 5: REVIEW_CARD_GENERATION (最新の知識マップを元にカード生成)
# ---------------------------------------------------------
async def run_review_card_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "REVIEW_CARD_GENERATION")
    logger.log(f"▶️ Starting REVIEW_CARD_GENERATION (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    
    billing = BillingEngine(task_type="REVIEW_CARD_GENERATION")
    
    try:
        # 1. 依存データの読み込み (Role Classification, Core Extraction, Topic Mapping)
        classified_payload = await _get_dependency_payload(job_id, "ROLE_CLASSIFICATION")
        classified_data = await _download_from_r2_to_memory(classified_payload["role_classification_path"])
        
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])
        
        mapping_payload = await _get_dependency_payload(job_id, "TOPIC_MAPPING")
        mapping_result = await _download_from_r2_to_memory(mapping_payload["topic_mapping_path"])

        # 2. 職人を呼ぶ
        llm = UnifiedLLM(billing)
        generator = ReviewCardGenerationService(llm, logger)
        
        # 💡 メモリ駆動でトピックごとの一括生成を実行
        review_cards_results = await generator.run_from_memory(
            role_classified_data=classified_data,
            core_data=core_data,
            mapping_result=mapping_result,
            uid=uid,
            lecture_id=lecture_id
        )

        # 3. フルログをR2に保存
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "review_cards", review_cards_results)

        # Supabaseに1枚ずつカードを保存
        supabase = get_supabase_client()

        # 冪等性のため、書き込み前にこの講義分の既存review_cardsを削除しておく
        def _insert_review_cards_sync():
            supabase.table("review_cards").delete().eq("lecture_id", lecture_id).execute()
            for res in review_cards_results:
                topic_idx = res.get("topic_idx")
                for card in res.get("review_cards", []):
                    card_data = {
                        "user_id": uid,
                        "lecture_id": lecture_id,
                        "topic_number": topic_idx,
                        "title": card.get("title"),
                        "hero_emoji": card.get("hero_emoji"),
                        "card_type": card.get("card_type"),
                        "card_content": card.get("content_blocks")  # jsonb
                    }
                    supabase.table("review_cards").insert(card_data).execute()

        await asyncio.to_thread(_insert_review_cards_sync)

        # 4. ステータス更新
        await _update_task_status(task_id, "COMPLETED", payload={"review_cards_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        # 📊 3Dコストレポートの出力
        logger.log(billing.report())
        logger.log(f"✅ REVIEW_CARD_GENERATION Completed! Generated cards for {len(review_cards_results)} topics.")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ REVIEW_CARD_GENERATION Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e
    
# ---------------------------------------------------------
# Phase 6-A-1: IMAGE_GENERATION (Review Cardの内容を元に生成)
# ---------------------------------------------------------
async def run_image_prompt_generation_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "IMAGE_GENERATION")
    logger.log(f"▶️ Starting IMAGE_GENERATION (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    billing = BillingEngine(task_type="IMAGE_PROMPT_GENERATION")
    
    try:
        review_payload = await _get_dependency_payload(job_id, "REVIEW_CARD_GENERATION")
        review_results = await _download_from_r2_to_memory(review_payload["review_cards_path"])

        # アカデミックトピックタイトルを取得するために CORE_EXTRACTION データをロード
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])

        llm = UnifiedLLM(billing)
        service = ImageGenerationService(llm, logger)
        image_prompts = await service.run_from_memory(review_results, core_data)

        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "image_prompts", image_prompts)
        await _update_task_status(task_id, "COMPLETED", payload={"image_prompts_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        logger.log(billing.report())
        logger.log(f"✅ IMAGE_GENERATION Completed!")
        logger.save_to_r2(storage_service)
    except Exception as e:
        await _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 6-A-2: IMAGE_RENDERING
# ---------------------------------------------------------
async def run_image_rendering_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "IMAGE_RENDERING")
    logger.log(f"▶️ Starting IMAGE_RENDERING (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    billing = BillingEngine(task_type="IMAGE_RENDERING")
    
    try:
        # 前工程 (6-A-1) で作成したプロンプトJSONをR2から読み込む
        prompt_payload = await _get_dependency_payload(job_id, "IMAGE_PROMPT_GENERATION")
        prompt_data = await _download_from_r2_to_memory(prompt_payload["image_prompts_path"])

        # style_suffixと各トピックのscene_descriptionを結合してレンダリング用リストを作成
        style_suffix = (
            prompt_data.get("global_art_direction", {}).get("flux_style_suffix", "")
            or prompt_data.get("world_building", {}).get("flux_style_suffix", "")
        )
        raw_prompts = prompt_data.get("image_prompts", [])

        image_rendering_inputs = []
        for p in raw_prompts:
            scene_desc = p.get("flux_scene_description", "")
            combined_prompt = f"{scene_desc}, {style_suffix}".strip().strip(",")
            
            image_rendering_inputs.append({
                "topic_idx": p.get("topic_idx"),
                "flux_prompt": combined_prompt
            })

        # レンダリング職人を呼ぶ
        renderer = ImageRenderingService(logger, billing)
        rendering_results = await renderer.run(uid, lecture_id, image_rendering_inputs)

        # 結果のパスリストを保存
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "rendered_images_manifest", rendering_results)
        
        await _update_task_status(task_id, "COMPLETED", payload={"rendered_images_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        logger.log(billing.report())
        logger.log(f"✅ IMAGE_RENDERING Completed!")
        logger.save_to_r2(storage_service)
    except Exception as e:
        await _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 6-B-1: FUN_FACT_SEARCH 
# ---------------------------------------------------------
async def run_fun_fact_search_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "FUN_FACT_SEARCH")
    
    logger.log(f"▶️ Starting FUN_FACT_SEARCH (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    billing = BillingEngine(task_type="FUN_FACT_SEARCH")

    try:
        # 1. Core Extraction の結果を読み込む
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])
        fun_fact_seed = core_data.get("fun_fact_idea", {})

        # 2. 検索実行
        search_service = WebSearchService(logger, billing)
        search_results = await search_service.run(fun_fact_seed)

        # 3. 結果を R2 に保存 (空でも保存する)
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "web_search_results", search_results)

        await _update_task_status(task_id, "COMPLETED", payload={
            "search_results_path": r2_path, 
            "billing_records": [vars(r) for r in billing.records]
        })
        
        logger.log(billing.report())
        logger.save_to_r2(storage_service)
    except Exception as e:
        # ここでコケても後続を止めないよう、空の結果で完了させる
        logger.log(f"❌ FUN_FACT_SEARCH Fatal Error: {e}. Proceeding with empty results.")
        await _update_task_status(task_id, "COMPLETED", payload={"search_results_path": None, "billing_records": []})
        logger.save_to_r2(storage_service)

# ---------------------------------------------------------
# Phase 6-B-2: FUN_FACTS_GENERATION
# ---------------------------------------------------------
async def run_fun_facts_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "FUN_FACTS_GENERATION")
    logger.log(f"▶️ Starting FUN_FACTS (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    billing = BillingEngine(task_type="FUN_FACTS_GENERATION")
    
    try:
        # 必要なデータをすべてダウンロード
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])
        
        classified_payload = await _get_dependency_payload(job_id, "ROLE_CLASSIFICATION")
        classified_data = await _download_from_r2_to_memory(classified_payload["role_classification_path"])

        # FUN_FACT_SEARCH の結果を読み込む
        search_payload = await _get_dependency_payload(job_id, "FUN_FACT_SEARCH")
        search_results = []
        search_results_path = search_payload.get("search_results_path")
        if search_results_path:
            search_results = await _download_from_r2_to_memory(search_results_path)

        # 職人を呼んで丸投げ
        llm = UnifiedLLM(billing)
        service = FunFactGenerationService(llm, logger)
        
        # 学生プロフィールの取得
        student_profile = await asyncio.to_thread(_get_student_profile, uid)
        
        # 💡 メモリ上の分類済みデータと検索結果を渡す！
        fun_fact = await service.run_from_memory(
            role_classified_data=classified_data,
            core_data=core_data,
            search_results=search_results,
            student_profile=student_profile
        )

        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "fun_fact", fun_fact)

        # SupabaseにFun Factを保存
        supabase = get_supabase_client()
        fact_data = {
            "user_id": uid,
            "lecture_id": lecture_id,
            "title": fun_fact.get("title"),
            "hook": fun_fact.get("hook"),
            "body": fun_fact.get("body"),
            "metadata": None  # 将来のために今はNullで保存
        }
        # 冪等性のため、書き込み前にこの講義分の既存fun_factを削除しておく
        def _insert_fun_fact_sync():
            supabase.table("fun_facts").delete().eq("lecture_id", lecture_id).execute()
            supabase.table("fun_facts").insert(fact_data).execute()

        await asyncio.to_thread(_insert_fun_fact_sync)

        await _update_task_status(task_id, "COMPLETED", payload={"fun_fact_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        logger.log(billing.report())
        logger.save_to_r2(storage_service)
    except Exception as e:
        await _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 6-C: DETAIL_CONTENTS_GENERATION
# ---------------------------------------------------------
async def run_detail_contents_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "DETAIL_CONTENTS_GENERATION")
    logger.log(f"▶️ Starting DETAIL_CONTENTS (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    billing = BillingEngine(task_type="DETAIL_CONTENTS_GENERATION")
    
    try:
        # データの読み込み
        classified_payload = await _get_dependency_payload(job_id, "ROLE_CLASSIFICATION")
        classified_data = await _download_from_r2_to_memory(classified_payload["role_classification_path"])
        
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])

        # 職人を呼んで丸投げ
        llm = UnifiedLLM(billing)
        service = TopicDetailGenerationService(llm, logger)
        
        # 💡 Review Cardと同じく、全データを渡して中でループ・フィルタリングしてもらう！
        all_details = await service.run_from_memory(
            classified_data, core_data,
            uid=uid,
            lecture_id=lecture_id
        )

        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "detail_contents", all_details)

        # Supabaseに1トピックずつ詳細ノートとトピック情報を保存
        supabase = get_supabase_client()
        core_topics = {t.get("idx"): t for t in core_data.get("topics", [])}

        # 冪等性のため、書き込み前にこの講義分の既存lecture_topics/deep_notesを削除しておく
        def _insert_details_sync():
            supabase.table("lecture_topics").delete().eq("lecture_id", lecture_id).execute()
            supabase.table("deep_notes").delete().eq("lecture_id", lecture_id).execute()
            for detail in all_details:
                topic_idx = detail.get("topic_idx")
                raw_content = detail.get("content")
                if topic_idx is None or not raw_content:
                    continue

                # タイトルとサマリーの分離
                summary, clean_contents = _parse_detail_contents(raw_content)

                # A. lecture_topics にトピック情報を保存
                core_topic = core_topics.get(topic_idx, {})
                topic_data = {
                    "user_id": uid,
                    "lecture_id": lecture_id,
                    "index": topic_idx,
                    "topic_title": core_topic.get("title", f"Topic {topic_idx}"),
                    "topic_type": core_topic.get("topic_type", "ACADEMIC"),
                    "summary": summary,
                    "start_sid": core_topic.get("start_sid"),
                    "end_sid": core_topic.get("end_sid")
                }
                supabase.table("lecture_topics").insert(topic_data).execute()

                # B. deep_notes にクリーンな詳細ノートを保存
                note_data = {
                    "user_id": uid,
                    "lecture_id": lecture_id,
                    "topic_number": topic_idx,
                    "note_contents": clean_contents
                }
                supabase.table("deep_notes").insert(note_data).execute()

        await asyncio.to_thread(_insert_details_sync)

        await _update_task_status(task_id, "COMPLETED", payload={"details_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        logger.log(billing.report())
        logger.save_to_r2(storage_service)
    except Exception as e:
        await _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 7: FINALIZE_JOB (全タスクのコスト集計とジョブ完了)
# ---------------------------------------------------------
async def run_finalize_job_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    
    logger = TaskLogger(uid, lecture_id, "FINALIZE_JOB")
    logger.log(f"▶️ Starting FINAL COST AGGREGATION (Task: {task_id})")
    
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    supabase = get_supabase_client()
    master_billing = BillingEngine() # 全データを合算するためのマスターお財布
    
    try:
        # 1. このJobに紐づく全タスクの実行結果をDBから取得
        res = await asyncio.to_thread(
            lambda: supabase.table("processing_tasks").select("task_type, result_payload").eq("job_id", job_id).execute()
        )
        
        all_tasks = res.data or []
        logger.log(f"📊 Aggregating costs from {len(all_tasks)} tasks...")

        for t in all_tasks:
            payload = t.get("result_payload") or {}
            records_data = payload.get("billing_records", [])
            
            # 各タスクが持っていた個別の記録をマスターに統合
            for r_data in records_data:
                # 辞書からCostRecordオブジェクトを復元して追加
                from app.services.helpers.llm_unified import CostRecord
                record = CostRecord(**r_data)
                master_billing.records.append(record)

        # 2. 最終レポートの生成
        final_report = master_billing.report_by_task()
        logger.log("✅ All task costs aggregated successfully.")
        logger.log(final_report)

        # 2.5 IMAGE_RENDERING の結果を取得し、lecture_topics に画像パスを書き込む
        try:
            logger.log("🖼️ Linking rendered images to lecture_topics...")
            rendering_payload = await _get_dependency_payload(job_id, "IMAGE_RENDERING")
            manifest_path = rendering_payload.get("rendered_images_path")
            if manifest_path:
                rendering_results = await _download_from_r2_to_memory(manifest_path)
                if isinstance(rendering_results, list):
                    def _link_images_sync():
                        for item in rendering_results:
                            topic_idx = item.get("topic_idx")
                            img_path = item.get("image_path")
                            if topic_idx is not None and img_path:
                                supabase.table("lecture_topics")\
                                    .update({"image_path": img_path})\
                                    .eq("lecture_id", lecture_id)\
                                    .eq("index", topic_idx)\
                                    .execute()

                    await asyncio.to_thread(_link_images_sync)
                    logger.log(f"✅ Successfully linked {len(rendering_results)} image path(s) to lecture_topics.")
                else:
                    logger.log("⚠️ Rendered images manifest is not a list. Skipping image linking.")
            else:
                logger.log("⚠️ Rendered images manifest path not found in payload. Skipping image linking.")
        except Exception as img_link_error:
            logger.log(f"⚠️ Failed to link images to lecture_topics: {img_link_error}")

        # 3. R2に「最終原価レポート」を保存 (ログとしての永久保存)
        report_storage_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "total_cost_report", {
            "total_usd": master_billing.total_usd(),
            "detailed_records": [vars(r) for r in master_billing.records],
            "report_text": final_report,
            "finalized_at": datetime.now().isoformat()
        })

        # 4. Job全体の統計を更新 (オプション: processing_jobsテーブルに直接書き込む)
        await asyncio.to_thread(
            lambda: supabase.table("processing_jobs").update({"status": "COMPLETED"}).eq("id", job_id).execute()
        )

        await _update_task_status(task_id, "COMPLETED", payload={"report_path": report_storage_path})
        logger.log("🏁 Job finalized and cost report archived.")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ FINALIZE_JOB Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e