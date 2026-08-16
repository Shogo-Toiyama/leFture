import os
import asyncio
import logging
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
from app.services.helpers.helpers import TaskLogger, _parse_detail_contents, _merge_graph_mutation, _get_sentence_review_context, _get_content_language_context, _get_student_profile, _sid_to_int, _int_to_sid, _generate_topic_node_id, _fetch_live_lecture_order_sync, _annotate_nodes_with_live_lecture_num, _prune_lecture_nodes, _course_has_running_job_sync, _try_acquire_reconstruction_lock_sync, _release_reconstruction_lock_sync
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM, CostRecord
from app.services.helpers.credits import charge_credits_for_task

from app.services.logic.transcription import TranscriptionService, ModalTranscriptionService
from app.services.logic.assemble_transcript import AssembleTranscriptService
from app.services.logic.sentence_review import SentenceReviewService
from app.services.logic.core_extraction import CoreExtractionService
from app.services.logic.role_classification import RoleClassificationService
from app.services.logic.announcement_generation import AnnouncementGenerationService
from app.services.logic.topic_mapping import TopicMappingService
from app.services.logic.topic_map_reconciliation import TopicMapReconciliationService
from app.services.logic.review_card_generation import ReviewCardGenerationService
from app.services.logic.image_generation import ImageGenerationService
from app.services.logic.image_rendering import ImageRenderingService
from app.services.logic.web_search import WebSearchService
from app.services.logic.fun_fact_brainstorming import FunFactBrainstormingService
from app.services.logic.fun_fact_generation import FunFactGenerationService
from app.services.logic.topic_details_generation import TopicDetailGenerationService

# CHECK_AND_ASSEMBLEが「チャンクが揃うまで待つ」際に、PROCESSING/TRANSCRIBINGのまま
# これ以上(分)動きが無いチャンクを「詰まっている」とみなして再enqueueする閾値。
# DAGタスク用の閾値より短くしているのは、音声チャンクの処理はずっと短時間で終わる想定のため。
CHUNK_STALE_TIMEOUT_MINUTES = int(os.getenv("CHUNK_STALE_TIMEOUT_MINUTES", "5"))

_credits_logger = logging.getLogger("credits")


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


def _update_task_status_sync(
    task_id: str,
    status: str,
    payload: dict = None,
    error_msg: str = None,
    user_id: str = None,
    job_id: str = None,
):
    supabase = get_supabase_client()
    update_data = {
        "status": status,
        "updated_at": datetime.now().isoformat()
    }
    if payload is not None:
        update_data["result_payload"] = payload
    if error_msg is not None:
        update_data["error_message"] = str(error_msg)

    # ★ COMPLETEDは終端状態として扱い、それ以降の書き込みは無視する。
    # ハングしていた古いリクエストがパトロールの再enqueue後に遅れて結末(主にFAILED)を
    # 書きに来た場合、既に新しい試行がCOMPLETEDにしていた結果を上書きしてしまう
    # レースを防ぐため。
    result = (
        supabase.table("processing_tasks")
        .update(update_data)
        .eq("id", task_id)
        .neq("status", "COMPLETED")
        .execute()
    )
    if not result.data:
        print(
            f"⏭️ Task {task_id} への status={status} 更新をスキップ"
            "(既にCOMPLETED、または対象行が存在しない)"
        )

    # billing_recordsが乗っているpayloadは、そのタスクが実際にAIコストを
    # 発生させたタスクなので、ここでクレジット消費を確定させる。
    # user_idが渡されていない呼び出し元は対象外(課金と無関係な状態更新)。
    billing_records = (payload or {}).get("billing_records")
    if billing_records and user_id:
        cost_usd = sum(r.get("cost_usd", 0.0) for r in billing_records)
        task_type = billing_records[0].get("task_type")
        try:
            charge_credits_for_task(
                user_id=user_id,
                task_id=task_id,
                task_type=task_type,
                cost_usd=cost_usd,
                cost_breakdown=billing_records,
                job_id=job_id,
            )
        except Exception:
            # 課金の失敗でパイプライン自体を止めたくない。usage_records/
            # credit_transactionsの欠損は後から突合・再計算で補える想定。
            _credits_logger.exception(
                f"Failed to charge credits for task_id={task_id} user_id={user_id}"
            )

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
async def _update_task_status(
    task_id: str,
    status: str,
    payload: dict = None,
    error_msg: str = None,
    user_id: str = None,
    job_id: str = None,
):
    await asyncio.to_thread(
        _update_task_status_sync, task_id, status, payload, error_msg, user_id, job_id
    )

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


async def _recover_stuck_reviewing_chunks(supabase, lecture_id: str, all_chunks: list, logger: TaskLogger):
    """
    trigger_sentence_review_for_batch_if_ready は4チャンクをアトミックに
    REVIEWING にロックしてからLLMレビューを行い、成功時はREVIEWED、例外時は
    TRANSCRIBED に戻す設計になっている。しかしプロセスが例外を投げずに
    強制終了された場合（デプロイでの旧リビジョン強制終了、OOM、クラッシュ等）は
    この巻き戻しが実行されず、行が REVIEWING のまま永久に取り残されてしまう。
    さらに厄介なのは、REVIEWING の行は CHECK_AND_ASSEMBLE の「処理済みチャンク」
    カウント（TRANSCRIBED/REVIEWEDのみ）に入らないため、それ以降のバッチも
    「前のバッチがREVIEWEDになるまで待つ」ゲートに引っかかって全体が詰まる。
    ここで CHUNK_STALE_TIMEOUT_MINUTES 以上 REVIEWING のまま動きが無い行を
    検出し、TRANSCRIBED に戻す（既に文字起こし自体は完了しているため再enqueueは
    不要。次のCHECK_AND_ASSEMBLEの「端数のSentence Review」が自然に拾い直す）。
    """
    threshold = datetime.now(timezone.utc) - timedelta(minutes=CHUNK_STALE_TIMEOUT_MINUTES)

    stuck_reviewing_ids = []
    for c in all_chunks:
        if c.get("status") != "REVIEWING":
            continue
        updated_at = _parse_supabase_timestamp(c.get("updated_at") or "")
        if updated_at and updated_at < threshold:
            stuck_reviewing_ids.append(c["id"])

    if not stuck_reviewing_ids:
        return

    # アトミックにリセット（他プロセスが直前にREVIEWEDへ完了させた場合はeq("status","REVIEWING")で弾かれる）
    reset_res = await asyncio.to_thread(
        lambda: supabase.table("lecture_transcripts")
            .update({"status": "TRANSCRIBED", "updated_at": datetime.now().isoformat()})
            .in_("id", stuck_reviewing_ids)
            .eq("status", "REVIEWING")
            .execute()
    )
    for c in (reset_res.data or []):
        logger.log(f"🩹 Recovered stuck REVIEWING chunk {c.get('chunk_index')} (reset to TRANSCRIBED for re-review)")


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
    REVIEWING で詰まったチャンクは _recover_stuck_reviewing_chunks が別途回収する
    （再enqueueすべきは文字起こしではなく再レビューのため、対象を分けている）。
    """
    await _recover_stuck_reviewing_chunks(supabase, lecture_id, all_chunks, logger)

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
        lambda: supabase.table("lectures").select("user_id, recording_language").eq("id", lecture_id).single().execute()
    )
    uid = res.data["user_id"] if res.data else "unknown_user"
    language = res.data.get("recording_language") if res.data else None

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
        language=language,
    )


async def trigger_sentence_review_for_batch_if_ready(
    supabase,
    lecture_id: str,
    batch_start: int,
    uid: str,
    logger: TaskLogger,
    billing: BillingEngine
) -> bool:
    """
    指定されたバッチ (batch_start から 4つのチャンク) の Sentence Review 実行可否を確認し、
    条件を満たしていればアトミックにロックを取って Sentence Review を実行する。
    また、処理完了後は次のバッチを連鎖的（カスケード）にチェック＆実行する。
    """
    batch_indices = [batch_start + i for i in range(4)]

    # 1. 前方のすべてのチャンクが 'REVIEWED' になっているか確認
    # (順序制御: 前のバッチがまだ完了していなければ、このバッチの進行を抑止する)
    if batch_start > 0:
        prev_res = await asyncio.to_thread(
            lambda: supabase.table("lecture_transcripts")
                .select("chunk_index, status")
                .eq("lecture_id", lecture_id)
                .lt("chunk_index", batch_start)
                .execute()
        )
        prev_chunks = prev_res.data or []
        not_reviewed = [c for c in prev_chunks if c["status"] != "REVIEWED"]
        if not_reviewed:
            logger.log(f"⏭️ Progressive review for batch {batch_start} waiting for previous chunks to be REVIEWED: {[(c['chunk_index'], c['status']) for c in not_reviewed]}")
            return False

    # 2. 対象バッチの4つのチャンクの状態を確認
    check_res = await asyncio.to_thread(
        lambda: supabase.table("lecture_transcripts")
            .select("chunk_index, status")
            .eq("lecture_id", lecture_id)
            .in_("chunk_index", batch_indices)
            .execute()
    )

    chunks_status = {c["chunk_index"]: c["status"] for c in check_res.data or []}
    all_ready = len(chunks_status) == 4 and all(status == "TRANSCRIBED" for status in chunks_status.values())

    if not all_ready:
        logger.log(f"⏭️ Batch {batch_start} is not fully TRANSCRIBED yet. Statuses: {chunks_status}")
        return False

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

    if updated_chunks and len(updated_chunks) != 4:
        # 想定外(重複行やレースコンディション等)で4件ちょうどロックできなかった場合。
        # 何もせず return すると、更新できてしまった分だけ REVIEWING のまま永久に
        # 取り残され、以降のバッチが「前のバッチが REVIEWED になるまで進めない」
        # ゲートに引っかかって全体が詰まってしまう。取れてしまった分は必ず
        # TRANSCRIBED に戻し、次回また正常な状態からリトライできるようにする。
        logger.log(f"⚠️ Lock mismatch for batch {batch_start}: expected 4 rows, got {len(updated_chunks)}. Reverting to TRANSCRIBED. IDs: {[c.get('id') for c in updated_chunks]}")
        updated_ids = [c["id"] for c in updated_chunks]
        await asyncio.to_thread(
            lambda: supabase.table("lecture_transcripts")
                .update({"status": "TRANSCRIBED"})
                .in_("id", updated_ids)
                .execute()
        )
        return False

    if len(updated_chunks) == 4:
        logger.log(f"🔒 Lock acquired for batch {batch_start}! Executing Sentence Review...")

        try:
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
            course_title, keywords_list, recording_language = await asyncio.to_thread(_get_sentence_review_context, lecture_id)

            review_billing = BillingEngine(task_type="SENTENCE_REVIEW")
            llm = UnifiedLLM(review_billing)
            reviewer = SentenceReviewService(llm, logger)
            reviewed_chunks = await reviewer.run_with_retry(
                chunks_to_review=chunks_to_review,
                previous_chunk=prev_chunk,
                course_title=course_title,
                keywords_list=keywords_list,
                recording_language=recording_language
            )

            # 返ってきた綺麗なデータを DB に書き込み REVIEWED に更新
            def _write_reviewed_chunks_sync():
                from app.services.helpers.llm_unified import CostRecord
                
                # 今回のレビュー費用を4等分に分配して割り当てる
                allocated_records = []
                for r in review_billing.records:
                    allocated_r = CostRecord(
                        dimension=r.dimension,
                        resource=r.resource,
                        usage={k: v / 4.0 for k, v in r.usage.items()} if r.usage else {},
                        cost_usd=r.cost_usd / 4.0,
                        task_type=r.task_type,
                        note=f"{r.note} (Batch allocated)"
                    )
                    allocated_records.append(vars(allocated_r))

                for rc in reviewed_chunks:
                    # 既存の billing_records を取得して合体させる
                    curr = supabase.table("lecture_transcripts").select("billing_records")\
                        .eq("lecture_id", lecture_id).eq("chunk_index", rc["chunk_index"]).single().execute()
                    curr_records = (curr.data or {}).get("billing_records") or []
                    
                    new_billing_records = curr_records + allocated_records

                    supabase.table("lecture_transcripts").update({
                        "status": "REVIEWED",
                        "text_reviewed": rc["text"],
                        "segments_reviewed": rc["segments"],
                        "billing_records": new_billing_records
                    }).eq("lecture_id", lecture_id).eq("chunk_index", rc["chunk_index"]).execute()

            await asyncio.to_thread(_write_reviewed_chunks_sync)
            logger.log(f"✅ Batch {batch_start} (4 chunks) successfully REVIEWED and updated in DB (costs allocated)!")

            # このバッチのSENTENCE_REVIEWコストは、4チャンクへ表示用に配分する前の
            # 合計金額でここ1回だけ課金する(配分後の値で4回課金すると同額になるはず
            # だが、丸め処理を分散させないためにも合計側で一度だけ行う)。
            try:
                charge_credits_for_task(
                    user_id=uid,
                    task_id=None,
                    task_type="SENTENCE_REVIEW",
                    cost_usd=review_billing.total_usd(),
                    cost_breakdown=[vars(r) for r in review_billing.records],
                    job_id=None,
                )
            except Exception:
                _credits_logger.exception(
                    f"Failed to charge credits for SENTENCE_REVIEW lecture_id={lecture_id} batch_start={batch_start}"
                )

            # ★ 「全チャンクが揃った」を成立させ得るイベントは2種類ある:
            # (a) 個々のチャンクの文字起こし完了(process_transcribe_chunk側で呼んでいる)
            # (b) このバッチのレビュー完了(TRANSCRIBED→REVIEWEDへの遷移もカウント対象)
            # 最後のチャンクが先にTRANSCRIBEDになっても、直前のバッチがまだ
            # REVIEWING中だとその時点では「揃った」と判定されない。その後(b)で
            # このバッチがREVIEWEDになって初めて揃うケースがあるため、ここでも
            # 起こす。
            await _maybe_wake_check_and_assemble(supabase, lecture_id, uid, logger)

            # 4. カスケードトリガー: 自分が完了したので、次のバッチが準備完了なら連鎖的にレビューを実行する
            next_batch_start = batch_start + 4
            logger.log(f"🔗 Cascade triggering Sentence Review check for next batch {next_batch_start}...")
            asyncio.create_task(
                trigger_sentence_review_for_batch_if_ready(
                    supabase=supabase,
                    lecture_id=lecture_id,
                    batch_start=next_batch_start,
                    uid=uid,
                    logger=logger,
                    billing=billing
                )
            )
            return True

        except Exception as review_err:
            logger.log(f"❌ Error in progressive Sentence Review for batch {batch_start}: {review_err}\n{traceback.format_exc()}")
            # エラー時は状態を TRANSCRIBED に戻して再試行できるようにする
            await asyncio.to_thread(
                lambda: supabase.table("lecture_transcripts")
                    .update({"status": "TRANSCRIBED"})
                    .eq("lecture_id", lecture_id)
                    .in_("chunk_index", batch_indices)
                    .execute()
            )
            return False

    return False


async def process_transcribe_chunk(lecture_id: str, chunk_index: int, start_time: float, whisper_context: str, r2_audio_path: str, uid: str, language: str | None = None):
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
            language=language,
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
                "billing_records": [vars(r) for r in billing.records],
            }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()
        )

        # このチャンクのTRANSCRIBE_CHUNKコストはここが唯一の課金ポイント。
        # CHECK_AND_ASSEMBLEは後でこのbilling_recordsを合算してレポートに
        # 使うだけなので、そちらでは絶対に二重課金しないこと。
        try:
            charge_credits_for_task(
                user_id=uid,
                task_id=None,
                task_type="TRANSCRIBE_CHUNK",
                cost_usd=billing.total_usd(),
                cost_breakdown=[vars(r) for r in billing.records],
                job_id=None,
            )
        except Exception:
            _credits_logger.exception(
                f"Failed to charge credits for TRANSCRIBE_CHUNK lecture_id={lecture_id} chunk_index={chunk_index}"
            )

        logger.log(f"✅ Chunk transcription completed: Chunk {chunk_index}")
        if result["text"]:
            logger.log(f"📝 Text: {result['text'][:30]}...")
        else:
            logger.log(f"🔇 Text: (No speech detected, skipped Groq)")

        # =========================================================
        # Sentence Review のトリガー (4枚区切りでアトミックに並行制御)
        # =========================================================
        batch_start = (chunk_index // 4) * 4
        await trigger_sentence_review_for_batch_if_ready(
            supabase=supabase,
            lecture_id=lecture_id,
            batch_start=batch_start,
            uid=uid,
            logger=logger,
            billing=billing
        )

        # このチャンクの完了で「全チャンクが揃った」ならCHECK_AND_ASSEMBLEを
        # 必要な時にだけ起こす(イベント駆動。busy-retryの代わり)。
        await _maybe_wake_check_and_assemble(supabase, lecture_id, uid, logger)

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

async def _maybe_wake_check_and_assemble(supabase, lecture_id: str, uid: str, logger: TaskLogger):
    """
    チャンクが1つ完了する(TRANSCRIBED/REVIEWEDになる)たびに呼ばれる。
    CHECK_AND_ASSEMBLEは、まだチャンクが揃っていなければ例外を投げずに黙って
    WAITING(専用の中間ステータス)へ戻るだけの設計にしてある(busy-retryをやめた
    ため)。WAITINGは通常のDAG状態機械(PENDING/QUEUED/RUNNING/COMPLETED/FAILED/
    CANCELLED)には含まれない、CHECK_AND_ASSEMBLEだけが意味を知っている状態
    ——orchestrator_webhookのDAG判定は`status == 'PENDING'`のタスクしか見ないため、
    WAITINGのタスクには一切反応しない(＝他タスク種別のRUNNING→PENDING遷移による
    即時クラッシュ復旧を犠牲にせずに済む)。
    ここでは「実際にチャンクが1つ揃った」というこのイベントで初めて、必要な時
    にだけCHECK_AND_ASSEMBLEを起こす。全チャンクがまだ揃っていなければ何もしない
    （WAITINGタスクを放置するだけで、ポーリングも例外も発生しない）。
    """
    job_res = await asyncio.to_thread(
        lambda: supabase.table("processing_jobs").select("id, expected_chunks")
            .eq("lecture_id", lecture_id).in_("status", ["PENDING", "RUNNING"])
            .order("created_at", desc=True).limit(1).execute()
    )
    jobs = job_res.data or []
    if not jobs:
        return
    job = jobs[0]
    expected_chunks = job.get("expected_chunks") or 0
    if expected_chunks == 0:
        return

    count_res = await asyncio.to_thread(
        lambda: supabase.table("lecture_transcripts").select("id", count="exact")
            .eq("lecture_id", lecture_id).in_("status", ["TRANSCRIBED", "REVIEWED"]).execute()
    )
    if (count_res.count or 0) < expected_chunks:
        return

    task_res = await asyncio.to_thread(
        lambda: supabase.table("processing_tasks").select("id, status")
            .eq("job_id", job["id"]).eq("task_type", "CHECK_AND_ASSEMBLE").single().execute()
    )
    task = task_res.data
    # WAITINGからのみ起こす。FAILEDは本当のエラー(assemble失敗等)を意味するため、
    # チャンク完了という無関係のイベントで自動リトライせず、Cloud Tasksの
    # 通常リトライや/retry-taskでの明示的な再実行に委ねる。
    if not task or task.get("status") != "WAITING":
        return

    # アトミックにQUEUED化。他プロセス(patrolや別チャンクの完了通知)が同時に
    # 拾っていた場合はupdated件数0件になるので、二重enqueueは起きない。
    update_res = await asyncio.to_thread(
        lambda: supabase.table("processing_tasks")
            .update({"status": "QUEUED", "updated_at": datetime.now().isoformat()})
            .eq("id", task["id"]).eq("status", "WAITING").execute()
    )
    if not (update_res.data or []):
        return

    # main.pyとの循環importを避けるためローカルimport（他の関数と同じ流儀）
    from app.main import enqueue_task, EnqueuePayload
    try:
        await enqueue_task(EnqueuePayload(job_id=job["id"], task_id=task["id"], task_type="CHECK_AND_ASSEMBLE"))
        logger.log(f"🔔 All {expected_chunks} chunks ready — woke CHECK_AND_ASSEMBLE (event-driven, no busy-retry).")
    except Exception as e:
        logger.log(f"⚠️ Failed to wake CHECK_AND_ASSEMBLE: {e}")


def _aggregate_billing_records(records: list) -> list:
    """
    個々のCostRecordを (task_type, dimension, resource) 単位で合算する。
    チャンク数分(数百件)の個別記録をそのままJSON化するとresult_payloadが
    肥大化し、Supabase Database Webhook(pg_net)の固定10秒タイムアウトに
    引っかかって配信が失われる(実際に起きた不具合)。合計金額の正しさは
    保ったまま、内訳を「どのタスク種別が・どのリソースに・合計いくら」の
    粒度まで圧縮する。
    """
    grouped: dict[tuple, CostRecord] = {}
    for r in records:
        key = (r.task_type, r.dimension, r.resource)
        agg = grouped.get(key)
        if agg is None:
            agg = CostRecord(dimension=r.dimension, resource=r.resource, usage={}, cost_usd=0.0, task_type=r.task_type, note=None)
            grouped[key] = agg
        agg.cost_usd += r.cost_usd
        for k, v in (r.usage or {}).items():
            agg.usage[k] = agg.usage.get(k, 0) + v

    return list(grouped.values())


def _log_chunk_state_snapshot(logger: TaskLogger, all_chunks: list, expected_chunks: int):
    """
    CHECK_AND_ASSEMBLE周りはPROCESSING/TRANSCRIBING/TRANSCRIBED/REVIEWING/
    REVIEWED/ERRORという状態遷移が複雑に絡み合い、エラーを吐かずに中途半端な
    状態のまま止まる不具合が起きやすい箇所。run_check_and_assemble_transcript_task
    が呼ばれるたびに(イベント駆動のwakeでもpatrolの強制起こしでも)必ずこれを
    呼び、その時点の全チャンクの状態を詳細にログへ残す。事後にログだけを見て
    「どのchunk_indexが・どの状態で・どれくらいの時間・止まっていたか」が
    一目で追えるようにするための計測用。挙動は一切変えない。
    """
    from collections import Counter
    now = datetime.now(timezone.utc)

    status_counts = Counter(c.get("status") for c in all_chunks)
    logger.log(f"🔬 [ChunkState] {len(all_chunks)} row(s) / expected {expected_chunks}. Status histogram: {dict(status_counts)}")

    # 期待されるchunk_indexの欠番・重複検出(取りこぼし/二重挿入の疑いを即座に見える化)
    seen_indices: dict[int, list] = {}
    for c in all_chunks:
        seen_indices.setdefault(c.get("chunk_index"), []).append(c.get("id"))
    missing = [i for i in range(expected_chunks) if i not in seen_indices]
    if missing:
        logger.log(f"⚠️ [ChunkState] Missing chunk_index row(s) entirely: {missing}")
    duplicates = {i: ids for i, ids in seen_indices.items() if len(ids) > 1}
    if duplicates:
        logger.log(f"⚠️ [ChunkState] Duplicate row(s) for chunk_index: {duplicates}")

    # REVIEWED(=完了)以外の行を、状態と滞留時間つきで個別に列挙
    not_done = sorted(
        (c for c in all_chunks if c.get("status") != "REVIEWED"),
        key=lambda c: c.get("chunk_index") if c.get("chunk_index") is not None else -1,
    )
    if not_done:
        details = []
        for c in not_done:
            updated_at = _parse_supabase_timestamp(c.get("updated_at") or "")
            age_sec = (now - updated_at).total_seconds() if updated_at else None
            details.append(
                f"idx={c.get('chunk_index')} status={c.get('status')} "
                f"age={f'{age_sec:.0f}s' if age_sec is not None else '?'} id={c.get('id')}"
            )
        logger.log(f"🔬 [ChunkState] {len(not_done)} chunk(s) not yet REVIEWED:\n  " + "\n  ".join(details))

    # REVIEWEDなのに肝心のデータが欠けている行(書き込みレースによる破損の疑い)。
    # 無音チャンクは正規のフローでもsegments_reviewed/text_reviewedが空のまま
    # REVIEWEDになるため、STT自体に中身があった行だけを対象にする。
    corrupted = [
        c for c in all_chunks
        if c.get("status") == "REVIEWED"
        and (c.get("segments_stt") or c.get("text_stt"))
        and not c.get("segments_reviewed") and not c.get("text_reviewed")
    ]
    if corrupted:
        logger.log(f"🚨 [ChunkState] REVIEWED but missing segments_reviewed/text_reviewed (possible write race): {[c.get('chunk_index') for c in corrupted]}")


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

        # 🔬 呼ばれるたびに必ず詳細スナップショットを残す(原因調査用、挙動は変えない)
        _log_chunk_state_snapshot(logger, all_chunks, expected_chunks)

        # 処理済みのチャンク（Whisperが終わっているもの）をカウント
        processed_chunks = [c for c in all_chunks if c.get("status") in ["TRANSCRIBED", "REVIEWED"]]

        # 待ち合わせロジック
        if len(processed_chunks) < expected_chunks:
            logger.log(f"⏳ Waiting for Whisper transcripts... ({len(processed_chunks)}/{expected_chunks})")

            # 詰まっているチャンクが無いか確認し、あれば再enqueueする。
            await _recover_stuck_chunks(supabase, lecture_id, all_chunks, uid, logger)

            # ★ ここで例外を投げてCloud Tasksにリトライさせる(busy-retry)のは
            # やめている。代わりに、DAGの通常状態機械には含まれない専用の
            # WAITINGステータスへ黙って戻って200を返すだけにする。
            # WAITINGはorchestrator_webhookのDAG判定(status=='PENDING'のみ対象)
            # から完全に見えないため、「揃うまで待っている」だけで無限に
            # 再キューされることがない(以前はdependenciesが空なせいでPENDINGに
            # 戻すたびに即「実行可能」と誤判定され、録音終盤のチャンク密集
            # タイミングでリクエストstormを起こし、Cloud Run側のevent loop
            # 詰まり経由でpg_net webhookのタイムアウトを誘発していた)。
            # 実際の再起動は「最後のチャンクが揃った」タイミングで
            # process_transcribe_chunk側の _maybe_wake_check_and_assemble が
            # イベント駆動で1回だけ、WAITING→QUEUEDへアトミックに起こす。
            # 万一そのイベントを取りこぼしても(音声チャンク自体が詰まって二度と
            # 完了しない等)、_patrol_wake_waiting_check_and_assembleが数分おきに
            # WAITINGのまま動きが無いタスクを見つけて強制的に一度起こし直す。
            await _update_task_status(task_id, "WAITING")
            logger.save_to_r2(storage_service)
            return

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
            course_title, keywords_list, recording_language = await asyncio.to_thread(_get_sentence_review_context, lecture_id)

            llm = UnifiedLLM(billing)
            reviewer = SentenceReviewService(llm, logger)
            reviewed_leftovers = await reviewer.run_with_retry(
                chunks_to_review=chunks_to_review,
                previous_chunk=prev_chunk,
                course_title=course_title,
                keywords_list=keywords_list,
                recording_language=recording_language
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
        
        # 💰 各チャンクの文字起こし／ progressive review の請求データを Supabase から取得して集計に合流させる
        logger.log("💰 Merging individual chunk billing records from DB...")
        for c in completed_chunks:
            records_data = c.get("billing_records") or []
            for r_data in records_data:
                record = CostRecord(**r_data)
                billing.records.append(record)

        # ★ ここでチャンクごとの個別記録(178チャンク×2件前後 = 数百件)をそのまま
        # result_payloadに書き込んでいたのが原因で、result_payloadが100KB超に
        # 肥大化していた。processing_tasksのUPDATEに反応するSupabase Database
        # Webhook(pg_net)は更新後の行全体をペイロードとして送るため、この行だけ
        # 極端に大きくなり、pg_netの固定10秒タイムアウトに引っかかって配信が
        # 失われ、CORE_EXTRACTION以降が一切起動しなくなる不具合の直接原因だった
        # (実測: 161,251 bytes / 794レコード)。
        # 個別チャンクの生データは lecture_transcripts.billing_records に残るため
        # 失われない。ここでは(task_type, dimension, resource)単位で合算し、
        # FINALIZE_JOBが後で読む合計金額の正しさは保ったまま件数だけ大幅に減らす。
        aggregated_records = _aggregate_billing_records(billing.records)

        result_payload = {"transcript_json_path": remote_transcript_path, "billing_records": [vars(r) for r in aggregated_records]}
        logger.log(f"💰 Aggregated {len(billing.records)} billing records down to {len(aggregated_records)} for result_payload ({len(json.dumps(result_payload))} bytes).")

        # ⚠️ ここでは絶対に user_id を渡さないこと。billing_records は
        # process_transcribe_chunk / SENTENCE_REVIEW バッチ側で既に課金済みの
        # 記録を集約しているだけなので、user_id を渡すと二重課金になる。
        await _update_task_status(task_id, "COMPLETED", payload=result_payload)
        logger.log(f"✅ CHECK_AND_ASSEMBLE Completed!")
        logger.save_to_r2(storage_service)

    except Exception as e:
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
# Phase 1-B: TRANSCRIBE_MASTER
# ---------------------------------------------------------
async def run_transcribe_master_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    expected_chunks = job_ctx.get("expected_chunks", 0)
    is_realtime = expected_chunks > 0

    logger = TaskLogger(uid, lecture_id, "TRANSCRIBE_MASTER")
    logger.log(f"▶️ Starting TRANSCRIBE_MASTER (Task: {task_id}, Mode: {'Realtime' if is_realtime else 'PreRecorded'})")
    billing = BillingEngine(task_type="TRANSCRIBE_MASTER")

    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state. Skipping duplicate execution.")
        return

    work_dir = BASE_WORK_DIR / task_id
    work_dir.mkdir(parents=True, exist_ok=True)
    supabase = get_supabase_client()

    try:
        # 1. 講義情報を取得して audio_path を確認
        # 注: whisper_context は Supabase の lectures テーブルに永続化されていないため取得しない。
        #     プリレコ（マスター音声）はコンテキスト不要のため空文字で処理する。
        lec_res = await asyncio.to_thread(
            lambda: supabase.table("lectures")
                .select("audio_path, recording_language")
                .eq("id", lecture_id)
                .single()
                .execute()
        )
        lec_data = lec_res.data or {}
        audio_path = lec_data.get("audio_path")
        language = lec_data.get("recording_language")
        whisper_context = ""

        # Fail-fast: audio_path が無い場合は R2 ダウンロード前に検査
        if not audio_path:
            raise ValueError(f"Lecture {lecture_id} is missing audio_path. Cannot transcribe.")

        # 3. Realtime/PreRecorded に応じて適切な Whisper API を選択
        if is_realtime:
            # Realtime（チャンク）モード: Cloudflare Whisper を使用
            # 34秒程度の小さいチャンクなのでメモリに載せても問題ない
            logger.log(f"   Using Cloudflare Whisper for Realtime mode")
            logger.log(f"🎤 [Master] Downloading master audio from R2: {audio_path}")
            audio_bytes = await asyncio.to_thread(storage_service.download_binary, audio_path)
            transcriber = TranscriptionService(logger, billing)
            result = await transcriber.run_in_memory(
                audio_bytes=audio_bytes,
                chunk_index=0,
                prompt_keywords=whisper_context,
                language=language,
            )
        else:
            # PreRecorded（マスター）モード: Modal Faster Whisper を使用
            # マスター音声は3時間超になり得るため、bytesとしてメモリに載せず
            # ディスクにストリーミングダウンロードしてからファイルのまま送信する
            logger.log(f"   Using Modal Faster Whisper for PreRecorded mode")
            logger.log(f"🎤 [Master] Downloading master audio from R2 to disk: {audio_path}")
            local_audio_path = work_dir / "master_audio.m4a"
            await asyncio.to_thread(storage_service.download_file, audio_path, local_audio_path)
            transcriber = ModalTranscriptionService(logger, billing)
            result = await transcriber.transcribe_file(
                audio_path=local_audio_path,
                chunk_index=0,
                prompt_keywords=whisper_context,
                language=language,
            )

        raw_segments = result.get("segments") or []

        # 4. AssembleTranscriptServiceを使用してアセンブリ（重複コード削減）
        # プレレコ用の単一チャンク構造を作成
        single_chunk = {
            "id": f"chunk_0_{task_id}",
            "lecture_id": lecture_id,
            "chunk_index": 0,
            "status": "REVIEWED",
            "text_stt": result.get("text", ""),
            "text_reviewed": result.get("text", ""),
            "segments_stt": raw_segments,
            "segments_reviewed": raw_segments,
            "confidence": raw_segments[0].get("confidence", 0.99) if raw_segments else 0.99,
            "audio_duration": result.get("audio_duration", 0.0),
            "start_time": 0.0,
        }
        assembler = AssembleTranscriptService(logger)
        assembled_data = assembler.run([single_chunk])
            
        logger.log(f"🎉 Transcription completed! Generated {len(assembled_data)} sentences. Saving to R2...")

        # 5. R2に保存
        remote_transcript_path = await asyncio.to_thread(
            storage_service.save_json_log,
            uid,
            lecture_id,
            "transcript_assembled",
            assembled_data
        )

        # 6. lecture_transcripts に登録（Realtime モードのみ）
        # Pre-recorded モード（expected_chunks=0）では R2 に保存済みなので DB 登録は不要
        if is_realtime:
            logger.log("📝 Registering chunk 0 into lecture_transcripts DB...")
            await asyncio.to_thread(
                lambda: supabase.table("lecture_transcripts").upsert({
                    "lecture_id": lecture_id,
                    "chunk_index": 0,
                    "audio_duration": result.get("audio_duration", 0.0),
                    "status": "REVIEWED",
                    "text_stt": result.get("text", ""),
                    "text_reviewed": result.get("text", ""),
                    "segments_stt": raw_segments,
                    "segments_reviewed": raw_segments,
                    "confidence": raw_segments[0].get("confidence", 0.99) if raw_segments else 0.99,
                    "storage_path": audio_path,
                    "start_time": 0.0,
                    "billing_records": [vars(r) for r in billing.records],
                }, on_conflict="lecture_id,chunk_index").execute()
            )
        else:
            logger.log("⏭️ Skipping lecture_transcripts registration (Pre-recorded mode, already in R2)")
        
        # 7. 請求データの合算と保存
        aggregated_records = _aggregate_billing_records(billing.records)
        result_payload = {
            "transcript_json_path": remote_transcript_path,
            "billing_records": [vars(r) for r in aggregated_records]
        }

        # TRANSCRIBE_MASTERはプレレコ専用のDAGタスク(realtimeジョブではそもそも
        # スケジュールされない)なので、ここが唯一の課金ポイント。
        await _update_task_status(task_id, "COMPLETED", payload=result_payload, user_id=uid, job_id=job_id)
        logger.log(f"✅ TRANSCRIBE_MASTER Completed!")
        logger.save_to_r2(storage_service)
        
    except (Exception, asyncio.CancelledError) as e:
        # CancelledError(Python 3.8+はBaseException)を拾わないと、Modal/Cloud Run側の
        # タイムアウトでリクエストが打ち切られた際にFAILEDへの更新がスキップされ、
        # タスクがRUNNINGのまま20分のstale patrolを待つまで詰まってしまう。
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ TRANSCRIBE_MASTER Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e
        
    finally:
        if work_dir.exists():
            shutil.rmtree(work_dir)

# ---------------------------------------------------------
# Phase 2: CORE_EXTRACTION
# ---------------------------------------------------------
async def run_core_extraction_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    expected_chunks = job_ctx.get("expected_chunks", 0)
    logger = TaskLogger(uid, lecture_id, "CORE_EXTRACTION")
    logger.log(f"▶️ Starting CORE_EXTRACTION (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return

    # 💡 このタスク専用のお財布（コスト計算機）を用意
    billing = BillingEngine(task_type="CORE_EXTRACTION")

    try:
        # リアルタイム(expected_chunks > 0)ではCHECK_AND_ASSEMBLE、プレレコ(expected_chunks == 0)ではTRANSCRIBE_MASTERから取得
        first_task_type = "CHECK_AND_ASSEMBLE" if expected_chunks > 0 else "TRANSCRIBE_MASTER"
        prev_payload = await _get_dependency_payload(job_id, first_task_type)
        transcript_data = await _download_from_r2_to_memory(prev_payload["transcript_json_path"])

        # 出力言語の解決 (表示言語/録音言語)
        content_language, transcript_language, is_bilingual = await asyncio.to_thread(
            _get_content_language_context, lecture_id
        )

        # UnifiedLLMを初期化して職人に渡す
        llm = UnifiedLLM(billing)
        extractor = CoreExtractionService(llm, logger)

        # メモリ上で処理
        extraction_result = await extractor.run_from_memory(
            transcript_data,
            content_language=content_language,
            transcript_language=transcript_language,
            is_bilingual=is_bilingual,
        )

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
                if topic.get("topic_type") != "ACADEMIC":
                    # LOGISTICSはidxがNoneのため対象外（そもそもkeywordsも
                    # 生成されない想定だが念のため明示的にスキップする）。
                    continue
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

        await _update_task_status(task_id, "COMPLETED", payload={"core_extraction_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
        
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
    expected_chunks = job_ctx.get("expected_chunks", 0)
    logger = TaskLogger(uid, lecture_id, "ROLE_CLASSIFICATION")

    logger.log(f"▶️ Starting ROLE_CLASSIFICATION (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return

    # 💡 このタスク専用のお財布を用意
    billing = BillingEngine(task_type="ROLE_CLASSIFICATION")

    try:
        # 1. 必要な前工程のデータをR2からメモリにダウンロード
        # リアルタイム(expected_chunks > 0)ではCHECK_AND_ASSEMBLE、プレレコ(expected_chunks == 0)ではTRANSCRIBE_MASTERから取得
        first_task_type = "CHECK_AND_ASSEMBLE" if expected_chunks > 0 else "TRANSCRIBE_MASTER"
        transcript_payload = await _get_dependency_payload(job_id, first_task_type)
        transcript_data = await _download_from_r2_to_memory(transcript_payload["transcript_json_path"])
        
        # (CORE_EXTRACTION から topics を取得するために core_data を取得)
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])

        # 2. 新しい職人を呼ぶ
        classifier = RoleClassificationService(billing, logger)
        
        # コースタイトルを取得してテーマのフォールバックにする
        course_title, _, _ = await asyncio.to_thread(_get_sentence_review_context, lecture_id)

        classified_data = await classifier.run_from_memory(
            transcript_data=transcript_data, 
            core_data=core_data,
            theme=core_data.get("title") or course_title
        )

        # 3. フルログをR2に保存
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "role_classification", classified_data)

        # 4. 次へバケツリレー
        await _update_task_status(task_id, "COMPLETED", payload={"role_classification_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
        
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
    expected_chunks = job_ctx.get("expected_chunks", 0)
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
        # リアルタイム(expected_chunks > 0)ではCHECK_AND_ASSEMBLE、プレレコ(expected_chunks == 0)ではTRANSCRIBE_MASTERから取得
        first_task_type = "CHECK_AND_ASSEMBLE" if expected_chunks > 0 else "TRANSCRIBE_MASTER"

        # 1. 必要な全データをメモリに読み込む
        # ※ (await _get_dependency_payload(...))["key"] のように必ず括弧で先にawaitを
        # 完了させる。await X(...)["key"] と書くと、Pythonの演算子優先順位により
        # 「X(...)["key"]（coroutineオブジェクトの添字アクセス）」が先に評価されて
        # TypeErrorになる。
        transcript_data = await _download_from_r2_to_memory((await _get_dependency_payload(job_id, first_task_type))["transcript_json_path"])
        core_data = await _download_from_r2_to_memory((await _get_dependency_payload(job_id, "CORE_EXTRACTION"))["core_extraction_path"])
        classified_data = await _download_from_r2_to_memory((await _get_dependency_payload(job_id, "ROLE_CLASSIFICATION"))["role_classification_path"])

        # 検索しやすくするための辞書を作成
        # 検索しやすくするための辞書を作成
        sid_to_text = {item["sid"]: item["text"] for item in transcript_data if "sid" in item}
        formatted_blocks = []
        seen_sids = set()
        duplicate_count = 0

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
                            if sid in seen_sids:
                                duplicate_count += 1
                                continue
                            block_lines.append(f"{sid}: {sid_to_text[sid]}")
                            seen_sids.add(sid)

                    if len(block_lines) > 1:
                        formatted_blocks.append("\n".join(block_lines))

        # ==========================================
        # ② ROLE_CLASSIFICATION & Safety Net (キーワード抽出)
        # ==========================================
        logistics_indices = []
        safety_net_catch_count = 0 # ログ出力用
        
        for i, sentence in enumerate(classified_data):
            sid = sentence.get("sid")
            if sid in seen_sids:
                continue

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
                    if sid in seen_sids:
                        duplicate_count += 1
                        continue
                    seen_sids.add(sid)
                    text = classified_data[i]["text"]
                    block_lines.append(f"{sid}: {text}")
                    
                if len(block_lines) > 1:
                    formatted_blocks.append("\n".join(block_lines))

        if duplicate_count > 0:
            logger.log(f"   [Logic] 🧹 Filtered out {duplicate_count} duplicate sentence line(s) before sending to LLM.")

        # ==========================================
        # ③ 結合して LLM (職人) を呼ぶ
        # ==========================================
        formatted_transcript = "\n\n".join(formatted_blocks)
        await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "input_announcement_generation", {"formatted_transcript": formatted_transcript})
        
        content_language, _, _ = await asyncio.to_thread(_get_content_language_context, lecture_id)

        llm = UnifiedLLM(billing)
        announcer = AnnouncementGenerationService(llm, logger)

        announcements_json = await announcer.run_from_memory(formatted_transcript, content_language=content_language)
        
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

        await _update_task_status(task_id, "COMPLETED", payload={"announcements_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
        
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

        # コースIDと、コース内Lectureの現在の並び順（非削除・created_at昇順）を取得
        supabase = get_supabase_client()

        def _fetch_course_and_lecture_order_sync():
            lec_res = supabase.table("lectures").select("course_id").eq("id", lecture_id).single().execute()
            course_id = lec_res.data.get("course_id") if lec_res.data else None
            lecture_ids = _fetch_live_lecture_order_sync(supabase, course_id) if course_id else []
            return course_id, lecture_ids

        course_id, lecture_ids = await asyncio.to_thread(_fetch_course_and_lecture_order_sync)
        lecture_num_by_id = {lid: i + 1 for i, lid in enumerate(lecture_ids)}
        lecture_num = lecture_num_by_id.get(lecture_id, 1)

        # ACADEMICトピックのみの連番(idx)を使い、Lecture内では不変の
        # topic_index_in_lecture として持たせる。ノードIDはLecture位置ではなく
        # lecture_id+この値から決定的なハッシュで生成する（詳細は _generate_topic_node_id）。
        todays_topics_list = []
        for t in academic_topics:
            topic_idx = t.get("idx")
            topic_copy = t.copy()
            topic_copy["topic_id"] = _generate_topic_node_id(lecture_id, topic_idx)
            topic_copy["source_lecture_id"] = lecture_id
            topic_copy["topic_index_in_lecture"] = topic_idx
            todays_topics_list.append(topic_copy)

        # 2. 過去のグラフ状態と、Topic Mapのstale状態をSupabaseから取得
        current_graph_state = {
            "clusters": [],
            "nodes": [],
            "edges": [],
            "ghost_nodes": []
        }
        is_stale = False
        reconstruction_in_progress = False
        pending_additions: list[dict] = []

        if course_id:
            def _fetch_existing_map_sync():
                return supabase.table("topic_maps")\
                    .select("map, is_stale, pending_additions, metadata")\
                    .eq("course_id", course_id)\
                    .execute()

            map_res = await asyncio.to_thread(_fetch_existing_map_sync)
            if map_res.data:
                row = map_res.data[0]
                db_map = row.get("map")
                if db_map and isinstance(db_map, dict):
                    current_graph_state["clusters"] = db_map.get("clusters") or []
                    current_graph_state["nodes"] = db_map.get("nodes") or []
                    current_graph_state["edges"] = db_map.get("edges") or []
                    current_graph_state["ghost_nodes"] = db_map.get("ghost_nodes") or []
                is_stale = bool(row.get("is_stale"))
                pending_additions = row.get("pending_additions") or []
                # Recreate Topic Map(run_topic_map_reconstruction_task)が今まさに
                # このCourseを処理中かどうか。ここでチェックせずmapを直接upsertすると、
                # 再構成側が読んだ後・書く前のこのタイミングで割り込んで書き込んだ場合、
                # どちらか一方の結果が後勝ちで丸ごと消えてしまう(lost update)。
                # is_stale同様、そのままpending_additionsへ退避して次のRecreateに委ねる。
                reconstruction_in_progress = bool((row.get("metadata") or {}).get("reconstruction_locked_at"))

        if is_stale or reconstruction_in_progress:
            # このCourseのTopic Mapは削除/移動待ちで一時的に不整合な状態(is_stale)か、
            # ちょうど再構成が進行中(reconstruction_in_progress)。
            # 壊れた/書き換わっている最中の地図にそのままLLMで足すとハルシネーションや
            # lost updateを誘発しやすいため、ここではLLMを呼ばず、今日のトピックを
            # pending_additions に積んで「Recreate Topic Map」(手動 or アイドルタイムアウト)
            # がまとめて消化するのを待つ。他のタスク(REVIEW_CARD_GENERATION等)を
            # ブロックしないよう、このタスク自体は正常にCOMPLETEDとして扱う。
            reason = "stale" if is_stale else "being reconstructed"
            logger.log(f"⏸️ Topic map for course {course_id} is {reason}. Deferring lecture {lecture_id}'s topics into pending_additions instead of calling the mapping LLM.")

            pending_additions.append({
                "lecture_id": lecture_id,
                "lecture_title": core_data.get("title"),
                "topics": todays_topics_list
            })

            def _defer_into_pending_sync():
                supabase.table("topic_maps").update({
                    "pending_additions": pending_additions,
                    "updated_at": datetime.now().isoformat()
                }).eq("course_id", course_id).execute()

            await asyncio.to_thread(_defer_into_pending_sync)

            # REVIEW_CARD_GENERATIONは topic_mapping_path から result_payload を
            # 直接キー参照するため、中身が空でも既存と同じ形( graph_mutations 無し=
            # 「今日は何も繋がなかった」)のペイロードを必ず保存しておく。
            deferred_result = {"graph_mutations": {}}
            r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "topic_mapping", deferred_result)

            await _update_task_status(task_id, "COMPLETED", payload={"topic_mapping_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
            logger.log(f"✅ TOPIC_MAPPING deferred (course topic map is stale)!")
            logger.save_to_r2(storage_service)
            return

        todays_macro_topics = {
            "lecture_title": core_data.get("title"),
            "lecture_num": lecture_num,
            "topics": todays_topics_list
        }

        # 3. LLMに渡す直前だけ、過去ノードに「現時点の」Lecture順序を注記する。
        # これは揮発的な値でtopic_maps.mapには保存しない（保存すると位置が固定化され、
        # 以後の削除・移動のたびに腐っていくため、呼び出しの都度計算し直す）。
        annotated_graph_for_llm = dict(current_graph_state)
        annotated_graph_for_llm["nodes"] = _annotate_nodes_with_live_lecture_num(
            current_graph_state.get("nodes", []), lecture_num_by_id
        )

        # 4. 職人を呼ぶ
        content_language, _, _ = await asyncio.to_thread(_get_content_language_context, lecture_id)
        llm = UnifiedLLM(billing)
        mapper = TopicMappingService(llm, logger)

        # メモリ上でマッピング実行
        mapping_result = await mapper.run_from_memory(
            current_graph=annotated_graph_for_llm,
            todays_topics=todays_macro_topics,
            content_language=content_language,
        )

        # 5. フルログをR2に保存
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "topic_mapping", mapping_result)

        # 6. 差分を Full Map にマージ（保存されるのは注記前の生のcurrent_graph_state）
        mutations = mapping_result.get("graph_mutations") or {}
        new_graph = _merge_graph_mutation(current_graph_state, mutations, todays_topics_list, logger=logger)

        # 7. Supabase の `topic_maps` テーブルに更新保存
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

        # 8. ステータス更新
        await _update_task_status(task_id, "COMPLETED", payload={"topic_mapping_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
        
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
# Topic Map: 移動先Course用に、既に処理済みのLectureのCORE_EXTRACTION結果から
# pending_additions用のトピックリストを組み立てる
# ---------------------------------------------------------
async def build_pending_addition_for_lecture(lecture_id: str) -> dict:
    """
    Lectureが別Courseへ移動された時、そのLectureは既にCORE_EXTRACTION済みのはず。
    そのR2上の結果を読み直し、pending_additionsに積める形（run_topic_mapping_taskの
    todays_topics_list相当）に変換する。job_idは録音時のパイプラインのものをそのまま
    たどるだけで、LLMを再度呼ぶ必要はない。
    """
    supabase = get_supabase_client()

    def _sync():
        job_res = supabase.table("processing_jobs").select("id")\
            .eq("lecture_id", lecture_id).order("created_at", desc=True).limit(1).execute()
        if not job_res.data:
            raise ValueError(f"No processing_jobs row found for lecture_id={lecture_id}")
        return job_res.data[0]["id"]

    job_id = await asyncio.to_thread(_sync)
    core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
    core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])

    academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]
    topics = []
    for t in academic_topics:
        topic_idx = t.get("idx")
        topic_copy = t.copy()
        topic_copy["topic_id"] = _generate_topic_node_id(lecture_id, topic_idx)
        topic_copy["source_lecture_id"] = lecture_id
        topic_copy["topic_index_in_lecture"] = topic_idx
        topics.append(topic_copy)

    return {"lecture_title": core_data.get("title"), "topics": topics}


# ---------------------------------------------------------
# Topic Map: Lecture削除/移動でstaleになったCourseのマーキング
# ---------------------------------------------------------
async def mark_topic_map_stale(course_id: str, action: str, lecture_id: str, lecture_topics: list[dict] | None = None, lecture_title: str | None = None) -> dict:
    """
    Lectureの削除・移動が起きた瞬間はLLMを一切呼ばず、その事実をtopic_mapsに
    記録するだけの軽量な処理。実際のグラフ修復(Phase A/B)はここでは行わず、
    ユーザーの「Recreate Topic Map」操作か、Patrolのアイドルタイムアウトが
    まとめて処理する（削除・移動が連続しても無駄なLLM呼び出しや競合を起こさないため）。

    action:
      - "remove": lecture_idの所属先からこのLectureのノードを除去待ちにする
                  (削除、または移動元Courseからの除去)
      - "add":    lecture_idのトピックをこのCourseへの追加待ちにする
                  (移動先Courseへの統合。lecture_topics/lecture_titleが必須)

    このLectureがそもそもそのCourseのTopic Mapに一度も反映されていない場合
    (録音中/分析中に削除された、CORE_EXTRACTION未完了のうちに移動した、等で
    トピックが1件も存在しない)は、is_stale化してもPhase A/Bで何も見つからず
    無意味に「Recreate Topic Map」を要求するだけになる。そのため
    "remove"は現在のmap.nodesに、"add"はlecture_topicsに何も無ければ
    is_stale/pending_*を一切変更せずスキップする。
    """
    supabase = get_supabase_client()
    now_iso = datetime.now().isoformat()

    def _sync():
        res = supabase.table("topic_maps").select("id, is_stale, stale_since, pending_removals, pending_additions, user_id, map")\
            .eq("course_id", course_id).execute()

        if not res.data:
            if action == "remove":
                # このCourseにまだTopic Map自体が無いなら、除去すべきノードも無い。
                return {"status": "skipped", "reason": "no_map_row"}
            if not lecture_topics:
                return {"status": "skipped", "reason": "lecture_has_no_topics"}
            # 移動先にまだTopic Mapが無い場合は、is_stale状態で新規行を作っておく。
            # user_idはこの時点では分からない可能性があるため、後続のreconstructionが
            # 分かる範囲で補う（lecturesテーブルから引ける）。
            lec_res = supabase.table("lectures").select("user_id").eq("id", lecture_id).single().execute()
            uid = lec_res.data.get("user_id") if lec_res.data else None
            supabase.table("topic_maps").insert({
                "course_id": course_id,
                "user_id": uid,
                "map": {"clusters": [], "nodes": [], "edges": [], "ghost_nodes": []},
                "is_stale": True,
                "stale_since": now_iso,
                "pending_removals": [],
                "pending_additions": [{"lecture_id": lecture_id, "lecture_title": lecture_title, "topics": lecture_topics or []}],
                "updated_at": now_iso
            }).execute()
            return {"status": "created_stale"}

        row = res.data[0]
        pending_removals = row.get("pending_removals") or []
        pending_additions = row.get("pending_additions") or []
        stale_since = row.get("stale_since")

        if action == "remove":
            existing_nodes = (row.get("map") or {}).get("nodes", [])
            if not any(n.get("source_lecture_id") == lecture_id for n in existing_nodes):
                # このLectureのノードはこのCourseのmapに元々存在しない
                # (削除待ちのpending_removalsに積んでも消化するものが無い)。
                return {"status": "skipped", "reason": "lecture_has_no_topics_in_map"}
            if not any(r.get("lecture_id") == lecture_id for r in pending_removals):
                pending_removals.append({"lecture_id": lecture_id, "reason": "removed"})
        elif action == "add":
            if not lecture_topics:
                return {"status": "skipped", "reason": "lecture_has_no_topics"}
            if not any(a.get("lecture_id") == lecture_id for a in pending_additions):
                pending_additions.append({"lecture_id": lecture_id, "lecture_title": lecture_title, "topics": lecture_topics or []})

        supabase.table("topic_maps").update({
            "is_stale": True,
            "stale_since": stale_since or now_iso,
            "pending_removals": pending_removals,
            "pending_additions": pending_additions,
            "updated_at": now_iso
        }).eq("course_id", course_id).execute()
        return {"status": "marked_stale"}

    return await asyncio.to_thread(_sync)


# ---------------------------------------------------------
# Topic Map: 削除/移動後の一括再構成（Recreate Topic Map / Patrol由来）
# ---------------------------------------------------------
async def run_topic_map_reconstruction_task(course_id: str) -> dict:
    """
    pending_removals / pending_additions をまとめて消化し、Topic Mapを修復する。
    Phase A（決定的除去、LLM不要: _prune_lecture_nodes）→
    Phase B（LLMによる修復＋pending_additions統合: TopicMapReconciliationService）→ upsert。
    「Recreate Topic Map」のユーザー操作、またはPatrolの1時間アイドルタイムアウトから呼ばれる。

    開始前に2つのガードを掛ける:
    1. このCourse配下のLectureにRUNNING状態のprocessing_jobsが無いことを確認する。
       録音直後のTOPIC_MAPPING(DAGタスク)がtopic_maps.mapに直接書き込むため、
       同時に走らせるとどちらかの書き込みが後勝ちで相手を丸ごと上書きしてしまう
       (lost update)。ここで弾けば、そのウィンドウ自体を避けられる。
    2. topic_maps.metadata(jsonb)を使った簡易ロックを取得する。手動の連打や、
       手動Recreateと自動Patrolが同じCourseに対してほぼ同時に走るケースを防ぐ。
    どちらかで弾かれた場合は例外を投げず、status="blocked"を返す(呼び出し元の
    エンドポイント/Patrolがそれぞれ適切に扱う)。
    """
    supabase = get_supabase_client()

    if await asyncio.to_thread(_course_has_running_job_sync, supabase, course_id):
        return {"status": "blocked", "reason": "lecture_processing_in_progress"}

    lock_id = await asyncio.to_thread(_try_acquire_reconstruction_lock_sync, supabase, course_id)
    if lock_id is None:
        return {"status": "blocked", "reason": "reconstruction_already_in_progress"}

    try:
        def _fetch_map_row_sync():
            return supabase.table("topic_maps").select("*").eq("course_id", course_id).execute()

        map_res = await asyncio.to_thread(_fetch_map_row_sync)
        if not map_res.data:
            return {"status": "skipped", "reason": "no_map_row"}

        row = map_res.data[0]
        uid = row.get("user_id") or "unknown_user"
        current_graph = row.get("map") or {"clusters": [], "nodes": [], "edges": [], "ghost_nodes": []}
        pending_removals = row.get("pending_removals") or []
        pending_additions = row.get("pending_additions") or []

        logger = TaskLogger(uid, course_id, "TOPIC_MAP_RECONSTRUCTION")
        logger.log(f"▶️ Starting TOPIC_MAP_RECONSTRUCTION for course {course_id} ({len(pending_removals)} pending removal(s), {len(pending_additions)} pending addition(s))")

        if not pending_removals and not pending_additions:
            logger.log("⏭️ Nothing pending; clearing stale flag only.")
            await asyncio.to_thread(
                lambda: supabase.table("topic_maps").update({
                    "is_stale": False, "stale_since": None, "updated_at": datetime.now().isoformat()
                }).eq("course_id", course_id).execute()
            )
            return {"status": "no_op"}

        try:
            # Phase A: 決定的除去（LLM不要）。除去前に、LLMへの文脈用として
            # 消えるトピックの情報(タイトル/種別/元クラスタ)を控えておく。
            pruned_graph = current_graph
            removed_topics_context = []
            for removal in pending_removals:
                target_lecture_id = removal.get("lecture_id")
                for n in pruned_graph.get("nodes", []):
                    if n.get("source_lecture_id") == target_lecture_id:
                        removed_topics_context.append({
                            "title": n.get("title"),
                            "topic_type": n.get("topic_type"),
                            "former_cluster_id": n.get("cluster_id"),
                        })
                pruned_graph = _prune_lecture_nodes(pruned_graph, target_lecture_id, logger=logger)

            flat_pending_topics = []
            for batch in pending_additions:
                flat_pending_topics.extend(batch.get("topics", []))

            # 現在のLecture順序を取得し、生存ノード・pending topicsの両方に注記する
            # (保存はしない揮発的な値。詳細はrun_topic_mapping_task内の同種処理を参照)
            lecture_ids = await asyncio.to_thread(_fetch_live_lecture_order_sync, supabase, course_id)
            lecture_num_by_id = {lid: i + 1 for i, lid in enumerate(lecture_ids)}

            # コース全体の出力言語は代表として最新のLectureの表示言語を使う
            content_language = "English"
            if lecture_ids:
                content_language, _, _ = await asyncio.to_thread(
                    _get_content_language_context, lecture_ids[-1]
                )

            billing = BillingEngine(task_type="TOPIC_MAP_RECONSTRUCTION")
            llm = UnifiedLLM(billing)

            if not pending_removals:
                # 除去が1件も無ければ、既存構造の修復(孤立エッジの再接続やクラスタ再編)は
                # 一切不要 -- pending_additionsは単に「is_staleの間に溜まった、まだ
                # マップに統合されていないLectureの分」でしかない。この場合は巨大な
                # current_graph全体+除去コンテキスト+全additionsを1回のLLM呼び出しに
                # 詰め込むReconciliationではなく、普段のTOPIC_MAPPINGタスクと全く同じ
                # TopicMappingService(topic_mapping_prompt.txt)をLecture 1件ずつ順番に
                # 呼ぶ。このプロンプトはnode/lecture_numを前提に「今日のトピックが
                # 必ずしも最新とは限らない」ケース(Backfilling Exception)も元々
                # 扱える設計なので、統合先が末尾でなくても問題ない。1件ごとに
                # マージしてから次のLectureへ進めることで、各呼び出しが常に
                # 「その時点までの最新状態」を見られるようにしている。
                logger.log(f"➕ No pending removals; integrating {len(pending_additions)} pending addition(s) via the normal incremental TopicMappingService instead of Reconciliation.")
                mapper = TopicMappingService(llm, logger)

                ordered_batches = sorted(
                    pending_additions,
                    key=lambda b: lecture_num_by_id.get(b.get("lecture_id"), float("inf")),
                )

                new_graph = pruned_graph
                for batch in ordered_batches:
                    batch_lecture_id = batch.get("lecture_id")
                    todays_topics = {
                        "lecture_title": batch.get("lecture_title"),
                        "lecture_num": lecture_num_by_id.get(batch_lecture_id, 1),
                        "topics": batch.get("topics", []),
                    }
                    annotated_graph = dict(new_graph)
                    annotated_graph["nodes"] = _annotate_nodes_with_live_lecture_num(
                        new_graph.get("nodes", []), lecture_num_by_id
                    )
                    mapping_result = await mapper.run_from_memory(
                        current_graph=annotated_graph,
                        todays_topics=todays_topics,
                        content_language=content_language,
                    )
                    mutations = mapping_result.get("graph_mutations") or {}
                    new_graph = _merge_graph_mutation(new_graph, mutations, batch.get("topics", []), logger=logger)
            else:
                annotated_graph = dict(pruned_graph)
                annotated_graph["nodes"] = _annotate_nodes_with_live_lecture_num(pruned_graph.get("nodes", []), lecture_num_by_id)
                annotated_pending_topics = [
                    {**t, "lecture_num": lecture_num_by_id.get(t.get("source_lecture_id"))}
                    for t in flat_pending_topics
                ]

                # Phase B: LLMによる修復＋統合（除去があるので、除去だけでもクラスタ
                # 再編が必要になり得るため、pending_additionsが空でも呼ぶ）
                reconciler = TopicMapReconciliationService(llm, logger)
                reconciliation_result = await reconciler.run_from_memory(
                    current_graph=annotated_graph,
                    removed_topics=removed_topics_context,
                    pending_additions=annotated_pending_topics,
                    content_language=content_language,
                )

                mutations = reconciliation_result.get("graph_mutations") or {}
                new_graph = _merge_graph_mutation(pruned_graph, mutations, flat_pending_topics, logger=logger)

            await asyncio.to_thread(
                lambda: supabase.table("topic_maps").update({
                    "map": new_graph,
                    "is_stale": False,
                    "stale_since": None,
                    "pending_removals": [],
                    "pending_additions": [],
                    "updated_at": datetime.now().isoformat()
                }).eq("course_id", course_id).execute()
            )

            logger.log(billing.report())
            logger.log(f"✅ TOPIC_MAP_RECONSTRUCTION completed for course {course_id}!")
            logger.save_to_r2(storage_service)

            # このタスクはCourse単位のバックグラウンド処理でprocessing_tasks行を
            # 持たない(task_id/job_idが存在しない)ため、_update_task_status経由の
            # 課金ではなくここで直接消費する。
            try:
                await asyncio.to_thread(
                    charge_credits_for_task,
                    uid,
                    None,
                    "TOPIC_MAP_RECONSTRUCTION",
                    billing.total_usd(),
                    [vars(r) for r in billing.records],
                    None,
                )
            except Exception:
                _credits_logger.exception(
                    f"Failed to charge credits for TOPIC_MAP_RECONSTRUCTION course_id={course_id}"
                )

            return {"status": "completed", "removed_lectures": len(pending_removals), "integrated_topics": len(flat_pending_topics)}

        except Exception as e:
            import traceback
            error_msg = f"{str(e)}\n{traceback.format_exc()}"
            logger.log(f"❌ TOPIC_MAP_RECONSTRUCTION Failed: {error_msg}")
            logger.save_to_r2(storage_service)
            raise e
    finally:
        await asyncio.to_thread(_release_reconstruction_lock_sync, supabase, course_id, lock_id)


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
        # 1. 依存データの読み込み (Role Classification, Core Extraction)
        classified_payload = await _get_dependency_payload(job_id, "ROLE_CLASSIFICATION")
        classified_data = await _download_from_r2_to_memory(classified_payload["role_classification_path"])
        
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])

        # 2. 職人を呼ぶ
        content_language, transcript_language, is_bilingual = await asyncio.to_thread(
            _get_content_language_context, lecture_id
        )
        llm = UnifiedLLM(billing)
        generator = ReviewCardGenerationService(llm, logger)

        # 💡 メモリ駆動でトピックごとの一括生成を実行
        review_cards_results = await generator.run_from_memory(
            role_classified_data=classified_data,
            core_data=core_data,
            uid=uid,
            lecture_id=lecture_id,
            content_language=content_language,
            transcript_language=transcript_language,
            is_bilingual=is_bilingual,
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
        await _update_task_status(task_id, "COMPLETED", payload={"review_cards_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
        
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
        await _update_task_status(task_id, "COMPLETED", payload={"image_prompts_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
        
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
        
        await _update_task_status(task_id, "COMPLETED", payload={"rendered_images_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
        
        logger.log(billing.report())
        logger.log(f"✅ IMAGE_RENDERING Completed!")
        logger.save_to_r2(storage_service)
    except Exception as e:
        await _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 6-B-0: FUN_FACT_BRAINSTORMING
# ---------------------------------------------------------
async def run_fun_fact_brainstorming_task(job_id: str, task_id: str):
    job_ctx = await _get_job_context(job_id)
    uid, lecture_id = job_ctx["user_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "FUN_FACT_BRAINSTORMING")

    logger.log(f"▶️ Starting FUN_FACT_BRAINSTORMING (Task: {task_id})")
    if not await _claim_task(task_id):
        logger.log(f"⏭️ Task {task_id} is not in QUEUED state (already running/completed elsewhere). Skipping duplicate execution.")
        return
    billing = BillingEngine(task_type="FUN_FACT_BRAINSTORMING")

    try:
        # 1. Core Extraction が選んだトピック/概念を読み込む
        core_payload = await _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = await _download_from_r2_to_memory(core_payload["core_extraction_path"])
        fun_fact_selection = core_data.get("fun_fact_selection", {})

        selected_topic_idx = fun_fact_selection.get("selected_topic_idx")
        concept_focus = fun_fact_selection.get("concept_focus", "")
        concept_intro_line = fun_fact_selection.get("concept_intro_line", "")
        selected_topic = next(
            (t for t in core_data.get("topics", []) if t.get("idx") == selected_topic_idx),
            {},
        )
        topic_title = selected_topic.get("title", "")

        course_title, _, _ = await asyncio.to_thread(_get_sentence_review_context, lecture_id)
        student_profile = await asyncio.to_thread(_get_student_profile, uid)

        # 2. アイデア出しを実行
        llm = UnifiedLLM(billing)
        service = FunFactBrainstormingService(llm, logger)
        brainstorming_result = await service.run_from_memory(
            student_profile=student_profile,
            topic_title=topic_title,
            concept_focus=concept_focus,
            course_title=course_title,
            concept_intro_line=concept_intro_line,
        )

        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "fun_fact_brainstorming", brainstorming_result)

        await _update_task_status(task_id, "COMPLETED", payload={
            "fun_fact_brainstorming_path": r2_path,
            "billing_records": [vars(r) for r in billing.records]
        }, user_id=uid, job_id=job_id)

        logger.log(billing.report())
        logger.log(f"✅ FUN_FACT_BRAINSTORMING Completed!")
        logger.save_to_r2(storage_service)
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ FUN_FACT_BRAINSTORMING Failed: {error_msg}")
        await _update_task_status(task_id, "FAILED", error_msg=error_msg)
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
        # 1. Fun Fact Brainstorming の結果(検索要否・クエリ)を読み込む
        brainstorming_payload = await _get_dependency_payload(job_id, "FUN_FACT_BRAINSTORMING")
        fun_fact_seed = {}
        brainstorming_path = brainstorming_payload.get("fun_fact_brainstorming_path")
        if brainstorming_path:
            fun_fact_seed = await _download_from_r2_to_memory(brainstorming_path)

        # 2. 検索実行
        search_service = WebSearchService(logger, billing)
        search_results = await search_service.run(fun_fact_seed)

        # 3. 結果を R2 に保存 (空でも保存する)
        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "web_search_results", search_results)

        await _update_task_status(task_id, "COMPLETED", payload={
            "search_results_path": r2_path,
            "billing_records": [vars(r) for r in billing.records]
        }, user_id=uid, job_id=job_id)
        
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

        # FUN_FACT_BRAINSTORMING の結果(seed)を読み込む
        brainstorming_payload = await _get_dependency_payload(job_id, "FUN_FACT_BRAINSTORMING")
        seed_data = {}
        brainstorming_path = brainstorming_payload.get("fun_fact_brainstorming_path")
        if brainstorming_path:
            seed_data = await _download_from_r2_to_memory(brainstorming_path)

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

        # 出力言語の解決
        content_language, _, _ = await asyncio.to_thread(_get_content_language_context, lecture_id)

        # 💡 Core Extractionの選定結果とBrainstormingの種、検索結果を渡す！
        fun_fact = await service.run_from_memory(
            core_data=core_data,
            seed_data=seed_data,
            search_results=search_results,
            student_profile=student_profile,
            content_language=content_language,
        )

        r2_path = await asyncio.to_thread(storage_service.save_json_log, uid, lecture_id, "fun_fact", fun_fact)

        # SupabaseにFun Factを保存
        supabase = get_supabase_client()
        fun_fact_sources = fun_fact.get("sources") or []
        fact_data = {
            "user_id": uid,
            "lecture_id": lecture_id,
            "title": fun_fact.get("title"),
            "hook": fun_fact.get("hook"),
            "body": fun_fact.get("body"),
            # 参照したWeb検索結果のURLがあればmetadataに残す。無ければ今まで通りNull。
            "metadata": {"sources": fun_fact_sources} if fun_fact_sources else None,
        }
        # 冪等性のため、書き込み前にこの講義分の既存fun_factを削除しておく
        def _insert_fun_fact_sync():
            supabase.table("fun_facts").delete().eq("lecture_id", lecture_id).execute()
            supabase.table("fun_facts").insert(fact_data).execute()

        await asyncio.to_thread(_insert_fun_fact_sync)

        await _update_task_status(task_id, "COMPLETED", payload={"fun_fact_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
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
        content_language, transcript_language, is_bilingual = await asyncio.to_thread(
            _get_content_language_context, lecture_id
        )
        llm = UnifiedLLM(billing)
        service = TopicDetailGenerationService(llm, logger)

        # 💡 Review Cardと同じく、全データを渡して中でループ・フィルタリングしてもらう！
        all_details = await service.run_from_memory(
            classified_data, core_data,
            uid=uid,
            lecture_id=lecture_id,
            content_language=content_language,
            transcript_language=transcript_language,
            is_bilingual=is_bilingual,
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

        await _update_task_status(task_id, "COMPLETED", payload={"details_path": r2_path, "billing_records": [vars(r) for r in billing.records]}, user_id=uid, job_id=job_id)
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