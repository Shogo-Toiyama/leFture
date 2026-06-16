import shutil
import traceback
import json
import re
from pathlib import Path
from datetime import datetime
from groq import Groq
from typing import Any

from app.core.config import BASE_WORK_DIR
from app.core.supabase import get_supabase_client
from app.core.r2_storage import storage_service
from app.services.helpers.helpers import TaskLogger
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


# =========================================================
# 🛠️ 共通ヘルパー関数
# =========================================================

def _update_task_status(task_id: str, status: str, payload: dict = None, error_msg: str = None):
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

def _get_job_context(job_id: str) -> dict:
    supabase = get_supabase_client()
    res = supabase.table("processing_jobs").select("lecture_id, owner_id, expected_chunks").eq("id", job_id).single().execute()
    return res.data

def _get_dependency_payload(job_id: str, target_task_type: str) -> dict:
    supabase = get_supabase_client()
    res = supabase.table("processing_tasks").select("result_payload")\
        .eq("job_id", job_id).eq("task_type", target_task_type).single().execute()
    return res.data.get("result_payload") or {}

def _download_from_r2_to_memory(storage_path: str) -> Any:
    response = storage_service.s3.get_object(
        Bucket=storage_service.bucket_name,
        Key=storage_path
    )
    return json.loads(response["Body"].read().decode("utf-8"))

# =========================================================
# 👷 現場監督たち (Task Runners)
# =========================================================

# ---------------------------------------------------------
# 1. Transcribe Chunk （Groqでリアルタイム文字起こし）
# ---------------------------------------------------------

async def run_transcribe_chunk_worker(lecture_id: str, chunk_index: int, start_time: float, audio_bytes: bytes):
    """
    Flutterから直接送られてきたWAVバイナリ(audio_bytes)をメモリ上で処理する。
    ダウンロード時間がゼロになるため、爆速で処理が完了する。
    """
    supabase = get_supabase_client()
    res = supabase.table("lectures").select("owner_id").eq("id", lecture_id).single().execute()
    uid = res.data["owner_id"] if res.data else "unknown_user"
    logger = TaskLogger(uid, lecture_id, f"TRANSCRIBE_CHUNK_{chunk_index:03d}")
    billing = BillingEngine()
    
    try:
        logger.log(f"🎤 [In-Memory] Transcribing chunk {chunk_index} for lecture {lecture_id}")
        
        # 1. 職人を呼んで、メモリ上の音声バイナリを直接渡す
        transcriber = TranscriptionService(logger, billing)
        
        result = transcriber.run_in_memory(
            audio_bytes=audio_bytes, 
            chunk_index=chunk_index,
            prompt_keywords = "UCLA, lecture, Computer Science"
        )

        # 2. 受け取った音声バイナリをそのまま R2 に保存（バックアップ＆参照用）
        seqStr = str(chunk_index).zfill(3)
        audio_r2_path = storage_service.save_binary(
            uid=uid,
            lecture_id=lecture_id,
            file_name=f"audio_chunks/chunk_{seqStr}.wav",
            data=audio_bytes,
            content_type="audio/wav"
        )
        logger.log(f"💾 Audio chunk saved to R2: {audio_r2_path}")

        # 3. DBを DONE に更新し、真実のテキストを書き込む
        # idではなく、lecture_idとchunk_indexの組み合わせでレコードを特定して更新する
        is_silent = len(result["segments"]) == 0
        new_status = "REVIEWED" if is_silent else "TRANSCRIBED"
        supabase.table("lecture_transcripts").update({
            "audio_duration": result["audio_duration"],
            "status": new_status,
            "text": result["text"],
            "segments": result["segments"], 
            "confidence": result["segments"][0]["confidence"] if result["segments"] else 0.0,
            "storage_path": audio_r2_path,
        }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()
        
        logger.log(f"✅ Chunk transcription completed: Chunk {chunk_index}")
        if result["text"]:
            logger.log(f"📝 Text: {result['text'][:30]}...")
        else:
            logger.log(f"🔇 Text: (No speech detected, skipped Groq)")

        # =========================================================
        # Sentence Review のトリガー
        # =========================================================
        
        # 1. 現在 TRANSCRIBED 状態になっているチャンクを全て取得
        res = supabase.table("lecture_transcripts")\
            .select("*")\
            .eq("lecture_id", lecture_id)\
            .eq("status", "TRANSCRIBED")\
            .order("chunk_index")\
            .execute()
        
        pending_chunks = res.data
        
        # 2. 4つ以上溜まっていたらReview
        if len(pending_chunks) >= 4:
            # 今回レビューする4つを切り出す
            chunks_to_review = pending_chunks[:4]
            first_chunk_index = chunks_to_review[0]["chunk_index"]
            chunk_ids = [c["id"] for c in chunks_to_review]
            supabase.table("lecture_transcripts").update({"status": "REVIEWING"}).in_("id", chunk_ids).execute()
            
            # 3. 文脈を繋ぐため、1つ前のチャンク（REVIEWED）を取得
            prev_chunk = None
            if first_chunk_index > 0:
                prev_res = supabase.table("lecture_transcripts")\
                    .select("*")\
                    .eq("lecture_id", lecture_id)\
                    .eq("chunk_index", first_chunk_index - 1)\
                    .execute()
                if prev_res.data:
                    prev_chunk = prev_res.data[0]
            
            logger.log(f"🚀 Triggering Sentence Review for chunks {first_chunk_index} to {first_chunk_index + 3}")
            
            # 4. SentenceReviewService を呼び出し
            llm = UnifiedLLM(billing)
            reviewer = SentenceReviewService(llm, logger)
            reviewed_chunks = await reviewer.run_from_memory(
                chunks_to_review=chunks_to_review,
                previous_chunk=prev_chunk,
                course_title="Computer Science",
                keywords_list=""
            )
            
            # 5. 返ってきた綺麗なデータを DB に UPSERT (上書き)
            for rc in reviewed_chunks:
                supabase.table("lecture_transcripts").update({
                    "status": "REVIEWED",
                    "text": rc["text"],
                    "segments": rc["segments"]
                }).eq("lecture_id", lecture_id).eq("chunk_index", rc["chunk_index"]).execute()
                
            logger.log("✅ 4 chunks successfully REVIEWED and updated in DB!")
            
        # 📊 レポートの出力とログの保存
        logger.log(billing.report())
        logger.save_to_r2(storage_service)
            
    except Exception as e:
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ Chunk transcription failed: {error_msg}")
        supabase.table("lecture_transcripts").update({
            "status": "ERROR",
        }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()
        logger.save_to_r2(storage_service)

# ---------------------------------------------------------
# 2. Check and Assemble (文字起こしの待ち合わせ＆組み立て)
# ---------------------------------------------------------

async def run_check_and_assemble_transcript_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    
    logger = TaskLogger(uid, lecture_id, "CHECK_AND_ASSEMBLE")
    logger.log(f"▶️ Starting CHECK_AND_ASSEMBLE (Task: {task_id})")
    billing = BillingEngine()
    _update_task_status(task_id, "RUNNING")
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
        res = supabase.table("lecture_transcripts")\
            .select("*")\
            .eq("lecture_id", lecture_id)\
            .order("chunk_index")\
            .execute()
            
        all_chunks = res.data
        
        # 処理済みのチャンク（Whisperが終わっているもの）をカウント
        processed_chunks = [c for c in all_chunks if c.get("status") in ["TRANSCRIBED", "REVIEWED"]]
        
        # 待ち合わせロジック
        if len(processed_chunks) < expected_chunks:
            error_msg = f"⏳ Waiting for Whisper transcripts... ({len(processed_chunks)}/{expected_chunks})"
            logger.log(error_msg)
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
            supabase.table("lecture_transcripts").update({"status": "REVIEWING"}).in_("id", chunk_ids).execute()
            logger.log(f"🧹 Running final Sentence Review for {len(chunks_to_review)} leftover chunks (Starting at {first_leftover_idx})...")
            
            # 1つ前のチャンク（REVIEWED）を取得して文脈として渡す
            prev_chunk = None
            if first_leftover_idx > 0:
                prev_res = supabase.table("lecture_transcripts")\
                    .select("*")\
                    .eq("lecture_id", lecture_id)\
                    .eq("chunk_index", first_leftover_idx - 1)\
                    .execute()
                if prev_res.data and prev_res.data[0].get("status") == "REVIEWED":
                    prev_chunk = prev_res.data[0]

            # LLM職人を呼び出す
            llm = UnifiedLLM(billing)
            reviewer = SentenceReviewService(llm, logger)
            reviewed_leftovers = await reviewer.run_from_memory(
                chunks_to_review=chunks_to_review,
                previous_chunk=prev_chunk,
                course_title="Computer Science", # ※必要に応じてjob_ctxから取得
                keywords_list=""
            )
            
            # レビュー結果をDBに書き込み、REVIEWED に昇格
            for rc in reviewed_leftovers:
                supabase.table("lecture_transcripts").update({
                    "status": "REVIEWED",
                    "text": rc["text"],
                    "segments": rc["segments"]
                }).eq("lecture_id", lecture_id).eq("chunk_index", rc["chunk_index"]).execute()
                
            logger.log("✅ Final leftover chunks successfully REVIEWED!")

        # ---------------------------------------------------------
        # C. 全て揃っていたら、専用職人を呼んで組み立てる (ASSEMBLE)
        # ---------------------------------------------------------
        # 最新のデータをDBから再度取得し、すべてが REVIEWED になっているか確認
        final_res = supabase.table("lecture_transcripts")\
            .select("*")\
            .eq("lecture_id", lecture_id)\
            .order("chunk_index")\
            .execute()
            
        completed_chunks = [c for c in final_res.data if c.get("status") == "REVIEWED"]
        
        if len(completed_chunks) < expected_chunks:
             raise Exception(f"Mismatch in expected chunks after review. ({len(completed_chunks)}/{expected_chunks})")

        logger.log(f"🎉 All {expected_chunks} chunks REVIEWED! Assembling transcript.json...")
        
        # 組み立てる (AssembleTranscriptService には completed_chunks をそのまま渡せばOK)
        assembler = AssembleTranscriptService(logger)
        assembled_data = assembler.run(completed_chunks)

        # ---------------------------------------------------------
        # D. Storage保存 ＆ DB更新
        # ---------------------------------------------------------
        remote_transcript_path = storage_service.save_json_log(uid, lecture_id, "transcript_assembled", assembled_data)
        
        result_payload = {"transcript_json_path": remote_transcript_path, "billing_records": [vars(r) for r in billing.records]}
        
        _update_task_status(task_id, "COMPLETED", payload=result_payload)
        logger.log(f"✅ CHECK_AND_ASSEMBLE Completed!")
        logger.save_to_r2(storage_service)

    except Exception as e:
        if "Waiting for" in str(e):
            _update_task_status(task_id, "PENDING") 
            raise e
            
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ CHECK_AND_ASSEMBLE Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
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
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "CORE_EXTRACTION")
    logger.log(f"▶️ Starting CORE_EXTRACTION (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    
    # 💡 このタスク専用のお財布（コスト計算機）を用意
    billing = BillingEngine()
    
    try:
        prev_payload = _get_dependency_payload(job_id, "CHECK_AND_ASSEMBLE")
        transcript_data = _download_from_r2_to_memory(prev_payload["transcript_json_path"])

        # UnifiedLLMを初期化して職人に渡す
        llm = UnifiedLLM(billing)
        extractor = CoreExtractionService(llm, logger)
        
        # メモリ上で処理
        extraction_result = await extractor.run_from_memory(transcript_data)

        # ログをR2に保存
        r2_path = storage_service.save_json_log(uid, lecture_id, "core_extraction", extraction_result)

        _update_task_status(task_id, "COMPLETED", payload={"core_extraction_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        # 📊 最後に今回のタスクのコストレポートを出力！
        logger.log(billing.report())
        logger.log(f"✅ CORE_EXTRACTION Completed!")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ CORE_EXTRACTION Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e
    
# ---------------------------------------------------------
# Phase 3: ROLE_CLASSIFICATION
# ---------------------------------------------------------
async def run_role_classification_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "ROLE_CLASSIFICATION")

    logger.log(f"▶️ Starting ROLE_CLASSIFICATION (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    
    # 💡 このタスク専用のお財布を用意
    billing = BillingEngine()
    
    try:
        # 1. 必要な前工程のデータをR2からメモリにダウンロード
        # (CHECK_AND_ASSEMBLE から transcript_data を取得)
        transcript_payload = _get_dependency_payload(job_id, "CHECK_AND_ASSEMBLE")
        transcript_data = _download_from_r2_to_memory(transcript_payload["transcript_json_path"])
        
        # (CORE_EXTRACTION から topics を取得するために core_data を取得)
        core_payload = _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = _download_from_r2_to_memory(core_payload["core_extraction_path"])

        # 2. 新しい職人を呼ぶ
        classifier = RoleClassificationService(billing, logger)
        
        classified_data = await classifier.run_from_memory(
            transcript_data=transcript_data, 
            core_data=core_data,
            theme=core_data.get("title") or "Computer Science"
        )

        # 3. フルログをR2に保存
        r2_path = storage_service.save_json_log(uid, lecture_id, "role_classification", classified_data)

        # 4. 次へバケツリレー
        _update_task_status(task_id, "COMPLETED", payload={"role_classification_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        # 📊 最後にコストレポートを出力
        logger.log(billing.report())
        logger.log(f"✅ ROLE_CLASSIFICATION Completed!")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ ROLE_CLASSIFICATION Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 4-A: ANNOUNCEMENT_GENERATION (事務連絡の抽出)
# ---------------------------------------------------------
async def run_announcement_generation_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "ANNOUNCEMENT_GENERATION")

    logger.log(f"▶️ Starting ANNOUNCEMENT_GENERATION (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    
    billing = BillingEngine()
    
    # 💡 1. Safety Net 用の正規表現コンパイル
    # \b で単語の境界を指定し、s? などで複数形にも対応させています
    critical_keywords_pattern = re.compile(
        r'\b(office hours?|exams?|midterms?|finals?|assignments?|homeworks?|quiz|quizzes|due|deadlines?|projects?|syllabus|grading|grades?|prerequisites?|plagiarism)\b', 
        re.IGNORECASE
    )
    
    try:        
        # 1. 必要な全データをメモリに読み込む
        transcript_data = _download_from_r2_to_memory(_get_dependency_payload(job_id, "CHECK_AND_ASSEMBLE")["transcript_json_path"])
        core_data = _download_from_r2_to_memory(_get_dependency_payload(job_id, "CORE_EXTRACTION")["core_extraction_path"])
        classified_data = _download_from_r2_to_memory(_get_dependency_payload(job_id, "ROLE_CLASSIFICATION")["role_classification_path"])

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
                
                try:
                    start_idx = int(start_sid[1:])
                    end_idx = int(end_sid[1:])
                    
                    block_lines = [f"[Topic: {topic_title}]"]
                    for i in range(start_idx, end_idx + 1):
                        sid = f"s{i:06d}"
                        if sid in sid_to_text:
                            block_lines.append(f"{sid}: {sid_to_text[sid]}")
                            
                    formatted_blocks.append("\n".join(block_lines))
                except Exception as e:
                    logger.log(f"⚠️ Failed to parse SID in LOGISTICS topic: {e}")

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
                mid_sid_num = int(classified_data[mid_idx]["sid"][1:])
                
                topic_title = "Embedded Announcement"
                for topic in core_data.get("topics", []):
                    try:
                        t_start = int(topic["start_sid"][1:])
                        t_end = int(topic["end_sid"][1:])
                        if t_start <= mid_sid_num <= t_end:
                            topic_title = topic.get("title", "Embedded Announcement")
                            break
                    except: pass
                
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
        storage_service.save_json_log(uid, lecture_id, "input_announcement_generation", {"formatted_transcript": formatted_transcript})
        
        llm = UnifiedLLM(billing)
        announcer = AnnouncementGenerationService(llm, logger)
        
        announcements_json = await announcer.run_from_memory(formatted_transcript)
        
        # 4. フルログを R2 に保存
        r2_path = storage_service.save_json_log(uid, lecture_id, "announcements", announcements_json)

        # 5. TODO: Supabaseの `announcements` テーブルに書き込む処理（必要に応じて）

        _update_task_status(task_id, "COMPLETED", payload={"announcements_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        logger.log(billing.report())
        logger.log(f"✅ ANNOUNCEMENT_GENERATION Completed!")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ ANNOUNCEMENT_GENERATION Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 4-B: TOPIC_MAPPING (知識グラフの差分更新)
# ---------------------------------------------------------
async def run_topic_mapping_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "TOPIC_MAPPING")

    logger.log(f"▶️ Starting TOPIC_MAPPING (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    
    billing = BillingEngine()
    
    try:        
        # 1. 今日のトピックデータをR2から取得 (CORE_EXTRACTION の結果を使用)
        core_payload = _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = _download_from_r2_to_memory(core_payload["core_extraction_path"])
        
        # 今日のマクロトピック（ACADEMICのみ）を抽出
        academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]
        
        # 最初の週 (Week 1, Lecture 1) と仮定し、ACADEMICトピックのみの連番で node_wk1_i を付与
        # (元データを汚さないようにコピーを作って加工)
        todays_topics_list = []
        for i, t in enumerate(academic_topics, start=1):
            topic_copy = t.copy()
            topic_copy["topic_id"] = f"node_wk1_{i}"
            todays_topics_list.append(topic_copy)
            
        todays_macro_topics = {
            "lecture_title": core_data.get("title"),
            "topics": todays_topics_list
        }

        # 2. TODO: 過去のグラフ状態の取得
        # 現時点では保存・取得ロジックが未実装のため、空の配列を持つオブジェクトを作成
        current_graph_state = {
            "clusters": [],
            "nodes": [],
            "edges": [],
            "ghost_nodes": []
        }

        # 3. 職人を呼ぶ
        llm = UnifiedLLM(billing)
        mapper = TopicMappingService(llm, logger)
        
        # メモリ上でマッピング実行
        mapping_result = await mapper.run_from_memory(
            current_graph=current_graph_state,
            todays_topics=todays_macro_topics
        )

        # 4. フルログをR2に保存
        r2_path = storage_service.save_json_log(uid, lecture_id, "topic_mapping", mapping_result)

        # 5. ステータス更新
        _update_task_status(task_id, "COMPLETED", payload={"topic_mapping_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        # 📊 コストレポート出力
        logger.log(billing.report())
        logger.log(f"✅ TOPIC_MAPPING Completed!")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ TOPIC_MAPPING Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e
    
# ---------------------------------------------------------
# Phase 5: REVIEW_CARD_GENERATION (最新の知識マップを元にカード生成)
# ---------------------------------------------------------
async def run_review_card_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "REVIEW_CARD_GENERATION")
    logger.log(f"▶️ Starting REVIEW_CARD_GENERATION (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    
    billing = BillingEngine()
    
    try:
        # 1. 依存データの読み込み (Role Classification, Core Extraction, Topic Mapping)
        classified_payload = _get_dependency_payload(job_id, "ROLE_CLASSIFICATION")
        classified_data = _download_from_r2_to_memory(classified_payload["role_classification_path"])
        
        core_payload = _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = _download_from_r2_to_memory(core_payload["core_extraction_path"])
        
        mapping_payload = _get_dependency_payload(job_id, "TOPIC_MAPPING")
        mapping_result = _download_from_r2_to_memory(mapping_payload["topic_mapping_path"])

        # 2. 職人を呼ぶ
        llm = UnifiedLLM(billing)
        generator = ReviewCardGenerationService(llm, logger)
        
        # 💡 メモリ駆動でトピックごとの一括生成を実行
        review_cards_results = await generator.run_from_memory(
            role_classified_data=classified_data,
            core_data=core_data,
            mapping_result=mapping_result
        )

        # 3. フルログをR2に保存
        r2_path = storage_service.save_json_log(uid, lecture_id, "review_cards", review_cards_results)

        # 4. ステータス更新
        _update_task_status(task_id, "COMPLETED", payload={"review_cards_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        # 📊 3Dコストレポートの出力
        logger.log(billing.report())
        logger.log(f"✅ REVIEW_CARD_GENERATION Completed! Generated cards for {len(review_cards_results)} topics.")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ REVIEW_CARD_GENERATION Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e
    
# ---------------------------------------------------------
# Phase 6-A-1: IMAGE_GENERATION (Review Cardの内容を元に生成)
# ---------------------------------------------------------
async def run_image_prompt_generation_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "IMAGE_GENERATION")
    logger.log(f"▶️ Starting IMAGE_GENERATION (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    billing = BillingEngine()
    
    try:
        review_payload = _get_dependency_payload(job_id, "REVIEW_CARD_GENERATION")
        review_results = _download_from_r2_to_memory(review_payload["review_cards_path"])

        llm = UnifiedLLM(billing)
        service = ImageGenerationService(llm, logger)
        image_prompts = await service.run_from_memory(review_results)

        r2_path = storage_service.save_json_log(uid, lecture_id, "image_prompts", image_prompts)
        _update_task_status(task_id, "COMPLETED", payload={"image_prompts_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        logger.log(billing.report())
        logger.log(f"✅ IMAGE_GENERATION Completed!")
        logger.save_to_r2(storage_service)
    except Exception as e:
        _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 6-A-2: IMAGE_RENDERING
# ---------------------------------------------------------
async def run_image_rendering_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "IMAGE_RENDERING")
    logger.log(f"▶️ Starting IMAGE_RENDERING (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    billing = BillingEngine()
    
    try:
        # 前工程 (6-A-1) で作成したプロンプトJSONをR2から読み込む
        prompt_payload = _get_dependency_payload(job_id, "IMAGE_PROMPT_GENERATION")
        image_prompts = _download_from_r2_to_memory(prompt_payload["image_prompts_path"])

        # レンダリング職人を呼ぶ
        renderer = ImageRenderingService(logger, billing)
        rendering_results = await renderer.run(uid, lecture_id, image_prompts)

        # 結果のパスリストを保存
        r2_path = storage_service.save_json_log(uid, lecture_id, "rendered_images_manifest", rendering_results)
        
        _update_task_status(task_id, "COMPLETED", payload={"rendered_images_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        
        logger.log(billing.report())
        logger.log(f"✅ IMAGE_RENDERING Completed!")
        logger.save_to_r2(storage_service)
    except Exception as e:
        _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 6-B-1: FUN_FACT_SEARCH 
# ---------------------------------------------------------
async def run_fun_fact_search_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "FUN_FACT_SEARCH")
    
    logger.log(f"▶️ Starting FUN_FACT_SEARCH (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    billing = BillingEngine()

    try:
        # 1. Core Extraction の結果を読み込む
        core_payload = _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = _download_from_r2_to_memory(core_payload["core_extraction_path"])
        fun_fact_seed = core_data.get("fun_fact_idea", {})

        # 2. 検索実行
        search_service = WebSearchService(logger, billing)
        search_results = await search_service.run(fun_fact_seed)

        # 3. 結果を R2 に保存 (空でも保存する)
        r2_path = storage_service.save_json_log(uid, lecture_id, "web_search_results", search_results)

        _update_task_status(task_id, "COMPLETED", payload={
            "search_results_path": r2_path, 
            "billing_records": [vars(r) for r in billing.records]
        })
        
        logger.log(billing.report())
        logger.save_to_r2(storage_service)
    except Exception as e:
        # ここでコケても後続を止めないよう、空の結果で完了させる
        logger.log(f"❌ FUN_FACT_SEARCH Fatal Error: {e}. Proceeding with empty results.")
        _update_task_status(task_id, "COMPLETED", payload={"search_results_path": None, "billing_records": []})
        logger.save_to_r2(storage_service)

# ---------------------------------------------------------
# Phase 6-B-2: FUN_FACTS_GENERATION
# ---------------------------------------------------------
async def run_fun_facts_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "FUN_FACTS_GENERATION")
    logger.log(f"▶️ Starting FUN_FACTS (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    billing = BillingEngine()
    
    try:
        # 必要なデータをすべてダウンロード
        core_payload = _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = _download_from_r2_to_memory(core_payload["core_extraction_path"])
        
        classified_payload = _get_dependency_payload(job_id, "ROLE_CLASSIFICATION")
        classified_data = _download_from_r2_to_memory(classified_payload["role_classification_path"])

        # FUN_FACT_SEARCH の結果を読み込む
        search_payload = _get_dependency_payload(job_id, "FUN_FACT_SEARCH")
        search_results = []
        search_results_path = search_payload.get("search_results_path")
        if search_results_path:
            search_results = _download_from_r2_to_memory(search_results_path)

        # 職人を呼んで丸投げ
        llm = UnifiedLLM(billing)
        service = FunFactGenerationService(llm, logger)
        
        # 💡 メモリ上の分類済みデータと検索結果を渡す！
        fun_fact = await service.run_from_memory(
            role_classified_data=classified_data,
            core_data=core_data,
            search_results=search_results
        )

        r2_path = storage_service.save_json_log(uid, lecture_id, "fun_fact", fun_fact)
        _update_task_status(task_id, "COMPLETED", payload={"fun_fact_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        logger.log(billing.report())
        logger.save_to_r2(storage_service)
    except Exception as e:
        _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 6-C: DETAIL_CONTENTS_GENERATION
# ---------------------------------------------------------
async def run_detail_contents_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    logger = TaskLogger(uid, lecture_id, "DETAIL_CONTENTS_GENERATION")
    logger.log(f"▶️ Starting DETAIL_CONTENTS (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    billing = BillingEngine()
    
    try:
        # データの読み込み
        classified_payload = _get_dependency_payload(job_id, "ROLE_CLASSIFICATION")
        classified_data = _download_from_r2_to_memory(classified_payload["role_classification_path"])
        
        core_payload = _get_dependency_payload(job_id, "CORE_EXTRACTION")
        core_data = _download_from_r2_to_memory(core_payload["core_extraction_path"])

        # 職人を呼んで丸投げ
        llm = UnifiedLLM(billing)
        service = TopicDetailGenerationService(llm, logger)
        
        # 💡 Review Cardと同じく、全データを渡して中でループ・フィルタリングしてもらう！
        all_details = await service.run_from_memory(classified_data, core_data)

        r2_path = storage_service.save_json_log(uid, lecture_id, "detail_contents", all_details)
        _update_task_status(task_id, "COMPLETED", payload={"details_path": r2_path, "billing_records": [vars(r) for r in billing.records]})
        logger.log(billing.report())
        logger.save_to_r2(storage_service)
    except Exception as e:
        _update_task_status(task_id, "FAILED", error_msg=str(e))
        logger.save_to_r2(storage_service)
        raise e

# ---------------------------------------------------------
# Phase 7: FINALIZE_JOB (全タスクのコスト集計とジョブ完了)
# ---------------------------------------------------------
async def run_finalize_job_task(job_id: str, task_id: str):
    job_ctx = _get_job_context(job_id)
    uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
    
    logger = TaskLogger(uid, lecture_id, "FINALIZE_JOB")
    logger.log(f"▶️ Starting FINAL COST AGGREGATION (Task: {task_id})")
    
    _update_task_status(task_id, "RUNNING")
    supabase = get_supabase_client()
    master_billing = BillingEngine() # 全データを合算するためのマスターお財布
    
    try:
        # 1. このJobに紐づく全タスクの実行結果をDBから取得
        res = supabase.table("processing_tasks").select("task_type, result_payload").eq("job_id", job_id).execute()
        
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
        final_report = master_billing.report()
        logger.log("✅ All task costs aggregated successfully.")
        logger.log(final_report)

        # 3. R2に「最終原価レポート」を保存 (ログとしての永久保存)
        report_storage_path = storage_service.save_json_log(uid, lecture_id, "total_cost_report", {
            "total_usd": master_billing.total_usd(),
            "detailed_records": [vars(r) for r in master_billing.records],
            "report_text": final_report,
            "finalized_at": datetime.now().isoformat()
        })

        # 4. Job全体の統計を更新 (オプション: processing_jobsテーブルに直接書き込む)
        supabase.table("processing_jobs").update({
            "total_cost_usd": master_billing.total_usd(),
            "status": "COMPLETED",
            "completed_at": datetime.now().isoformat()
        }).eq("id", job_id).execute()

        _update_task_status(task_id, "COMPLETED", payload={"report_path": report_storage_path})
        logger.log("🏁 Job finalized and cost report archived.")
        logger.save_to_r2(storage_service)
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        logger.log(f"❌ FINALIZE_JOB Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        logger.save_to_r2(storage_service)
        raise e