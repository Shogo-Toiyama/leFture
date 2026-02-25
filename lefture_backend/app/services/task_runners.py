import shutil
import traceback
import json
from pathlib import Path
from datetime import datetime
from groq import Groq

# 作成した設定とSupabaseクライアント
from app.core.config import BASE_WORK_DIR
from app.core.supabase import get_supabase_client
from app.services.helpers.helpers import print_log, init_logger, finalize_log_and_get_path
from app.services.helpers.llm_unified import UnifiedLLM, CostCollector

from app.services.logic.transcription import TranscriptionService
from app.services.logic.transcription_debug import TranscriptionDebugService
from app.services.logic.assemble_transcript import AssembleTranscriptService
from app.services.logic.sentence_review import SentenceReviewService
from app.services.logic.role_classification import RoleClassificationService
from app.services.logic.lecture_segmentaion import LectureSegmentationService
from app.services.logic.topic_details_generation import TopicDetailGenerationService
from app.services.logic.fun_fact_generation import FunFactGenerationService


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

def _upload_artifact(uid: str, lecture_id: str, local_path: Path, filename: str, is_temp: bool = False) -> str:
    supabase = get_supabase_client()
    folder = "temp" if is_temp else "artifacts"
    storage_path = f"{uid}/{lecture_id}/{folder}/{filename}"
    
    with open(local_path, "rb") as f:
        supabase.storage.from_("lecture_assets").upload(
            path=storage_path,
            file=f,
            file_options={"upsert": "true"}
        )
    return storage_path

def _download_artifact(storage_path: str, save_to: Path):
    supabase = get_supabase_client()
    res = supabase.storage.from_("lecture_assets").download(storage_path)
    with open(save_to, "wb") as f:
        f.write(res)


# =========================================================
# 👷 現場監督たち (Task Runners)
# =========================================================

# ---------------------------------------------------------
# 1. Transcribe Chunk （Groqでリアルタイム文字起こし）
# ---------------------------------------------------------

async def run_transcribe_chunk_worker(lecture_id: str, chunk_index: int, audio_bytes: bytes):
    """
    Flutterから直接送られてきたWAVバイナリ(audio_bytes)をメモリ上で処理する。
    ダウンロード時間がゼロになるため、爆速で処理が完了する。
    """
    supabase = get_supabase_client()
    
    try:
        print_log(f"🎤 [In-Memory] Transcribing chunk {chunk_index} for lecture {lecture_id}")
        
        # 1. 職人を呼んで、メモリ上の音声バイナリを直接渡す
        # transcriber = TranscriptionService()
        transcriber = TranscriptionDebugService()
        
        result = transcriber.run_in_memory_debug(
            lecture_id=lecture_id,
            audio_bytes=audio_bytes, 
            chunk_index=chunk_index,
            prompt_keywords = "UCLA, lecture, Computer Science, Architecture, Programming Languages, Git, Turing Machine"
        )

        # 2. DBを DONE に更新し、真実のテキストを書き込む
        # idではなく、lecture_idとchunk_indexの組み合わせでレコードを特定して更新する
        is_silent = len(result["segments"]) == 0
        new_status = "REVIEWED" if is_silent else "TRANSCRIBED"
        supabase.table("lecture_transcripts").update({
            "audio_duration": result["audio_duration"],
            "status": new_status,
            "text": result["text"],
            "segments": result["segments"], 
            "confidence": result["segments"][0]["confidence"] if result["segments"] else 0.0
        }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()
        
        print_log(f"✅ Chunk transcription completed: Chunk {chunk_index}")
        if result["text"]:
            print_log(f"📝 Text: {result['text'][:30]}...")
        else:
            print_log(f"🔇 Text: (No speech detected, skipped Groq)")

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
            
            print_log(f"🚀 Triggering Sentence Review for chunks {first_chunk_index} to {first_chunk_index + 3}")
            
            # 4. SentenceReviewService を呼び出し
            reviewer = SentenceReviewService()
            reviewed_chunks = reviewer.run(
                chunks_to_review=chunks_to_review,
                previous_chunk=prev_chunk,
                course_title="Computer Science",  # TODO
                keywords_list=""
            )
            
            # 5. 返ってきた綺麗なデータを DB に UPSERT (上書き)
            for rc in reviewed_chunks:
                supabase.table("lecture_transcripts").update({
                    "status": "REVIEWED",
                    "text": rc["text"],
                    "segments": rc["segments"]
                }).eq("lecture_id", lecture_id).eq("chunk_index", rc["chunk_index"]).execute()
                
            print_log("✅ 4 chunks successfully REVIEWED and updated in DB!")
            
    except Exception as e:
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print_log(f"❌ Chunk transcription failed: {error_msg}")
        supabase.table("lecture_transcripts").update({
            "status": "ERROR",
        }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()

# ---------------------------------------------------------
# 2. Check and Assemble (文字起こしの待ち合わせ＆組み立て)
# ---------------------------------------------------------

async def run_check_and_assemble_transcript_task(job_id: str, task_id: str):
    """
    [タスク: CHECK_AND_ASSEMBLE_TRANSCRIPT]
    リアルタイム文字起こしが全て完了するのを「待ち」、
    端数のチャンクがあれば最後の Sentence Review を行い、
    全てが REVIEWED に揃ったら1つの transcript.json に組み立てる。
    """
    print_log(f"▶️ Starting CHECK_AND_ASSEMBLE (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    
    work_dir = BASE_WORK_DIR / task_id
    work_dir.mkdir(parents=True, exist_ok=True)
    supabase = get_supabase_client()
    
    try:
        job_ctx = _get_job_context(job_id)
        uid = job_ctx["owner_id"]
        lecture_id = job_ctx["lecture_id"]
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
            print_log(error_msg)
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
            print_log(f"🧹 Running final Sentence Review for {len(chunks_to_review)} leftover chunks (Starting at {first_leftover_idx})...")
            
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
            reviewer = SentenceReviewService()
            reviewed_leftovers = reviewer.run(
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
                
            print_log("✅ Final leftover chunks successfully REVIEWED!")

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

        print_log(f"🎉 All {expected_chunks} chunks REVIEWED! Assembling transcript.json...")
        
        # 組み立てる (AssembleTranscriptService には completed_chunks をそのまま渡せばOK)
        assembler = AssembleTranscriptService()
        local_transcript_path = assembler.run(completed_chunks, work_dir)

        # ---------------------------------------------------------
        # D. Storage保存 ＆ DB更新
        # ---------------------------------------------------------
        remote_transcript_path = _upload_artifact(uid, lecture_id, local_transcript_path, "transcript.json")
        result_payload = {"transcript_json": remote_transcript_path}
        
        _update_task_status(task_id, "COMPLETED", payload=result_payload)
        print_log(f"✅ CHECK_AND_ASSEMBLE Completed!")

    except Exception as e:
        if "Waiting for" in str(e):
            _update_task_status(task_id, "PENDING") # リトライ待ち状態に戻す
            raise e
            
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print_log(f"❌ CHECK_AND_ASSEMBLE Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        raise e
        
    finally:
        if work_dir.exists():
            shutil.rmtree(work_dir)

# ---------------------------------------------------------
# 3. ROLE_CLASSIFICATION (役割分類)
# ---------------------------------------------------------
async def run_role_classification_task(job_id: str, task_id: str):
    print_log(f"▶️ Starting ROLE_CLASSIFICATION (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    work_dir = BASE_WORK_DIR / task_id
    work_dir.mkdir(parents=True, exist_ok=True)
    try:
        job_ctx = _get_job_context(job_id)
        uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
        
        # 依存元: SENTENCE_REVIEW (課金ユーザー) または CHECK_AND_ASSEMBLE (無料ユーザー)
        # ※実際は指揮者が正しくルーティングするので、両方探すか固定するかします。ここではREVIEWと仮定
        prev_payload = _get_dependency_payload(job_id, "SENTENCE_REVIEW")
        if not prev_payload:
            prev_payload = _get_dependency_payload(job_id, "CHECK_AND_ASSEMBLE")
            
        remote_path = prev_payload.get("reviewed_sentences_json") or prev_payload.get("transcript_json")
        if not remote_path: raise ValueError("Dependency data not found!")

        local_input_path = work_dir / "input_sentences.json"
        _download_artifact(remote_path, local_input_path)

        # 職人を呼ぶ (モック)
        llm = UnifiedLLM(provider="gemini")
        collector = CostCollector()
        classifier = RoleClassificationService(llm, collector)
        result_paths = await classifier.run(local_input_path, work_dir)

        result_payload = {}
        for path in result_paths:
            remote = _upload_artifact(uid, lecture_id, path, path.name)
            if path.name == "sentences_final.json":
                result_payload["sentences_final_json"] = remote

        _update_task_status(task_id, "COMPLETED", payload=result_payload)
        print_log(f"✅ ROLE_CLASSIFICATION Completed!")
    except Exception as e:
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        raise e
    finally:
        if work_dir.exists(): shutil.rmtree(work_dir)

# ---------------------------------------------------------
# 4. CORE_EXTRACTION (コア抽出: セグメント分け等)
# ---------------------------------------------------------
async def run_core_extraction_task(job_id: str, task_id: str):
    print_log(f"▶️ Starting CORE_EXTRACTION (Task: {task_id})")
    _update_task_status(task_id, "RUNNING")
    work_dir = BASE_WORK_DIR / task_id
    work_dir.mkdir(parents=True, exist_ok=True)
    try:
        job_ctx = _get_job_context(job_id)
        uid, lecture_id = job_ctx["owner_id"], job_ctx["lecture_id"]
        
        prev_payload = _get_dependency_payload(job_id, "ROLE_CLASSIFICATION")
        remote_path = prev_payload.get("sentences_final_json")
        local_input_path = work_dir / "sentences_final.json"
        _download_artifact(remote_path, local_input_path)

        # 職人を呼ぶ (旧 LectureSegmentationService 相当)
        llm = UnifiedLLM(provider="gemini")
        collector = CostCollector()
        segmenter = LectureSegmentationService(llm, collector)
        result_paths = await segmenter.run(local_input_path, work_dir)

        result_payload = {}
        for path in result_paths:
            remote = _upload_artifact(uid, lecture_id, path, path.name)
            if path.name == "segments.json":
                result_payload["segments_json"] = remote

        _update_task_status(task_id, "COMPLETED", payload=result_payload)
        print_log(f"✅ CORE_EXTRACTION Completed!")
    except Exception as e:
        _update_task_status(task_id, "FAILED", error_msg=str(e))
        raise e
    finally:
        if work_dir.exists(): shutil.rmtree(work_dir)

# ---------------------------------------------------------
# 5〜9. 並列タスク群 (CORE_EXTRACTIONに依存するもの)
# ---------------------------------------------------------
# ※ ここからは形がほぼ同じなので、1つの共通ジェネレーター関数を作ってスマートに回すこともできますが、
# 後で職人ごとの微調整がしやすいように、愚直に並べておきます！

async def run_announcement_generation_task(job_id: str, task_id: str):
    """ (省略: ROLE_CLASSIFICATION に依存して処理を行う) """
    _update_task_status(task_id, "COMPLETED", payload={"dummy": "ok"})

async def run_topic_mapping_task(job_id: str, task_id: str):
    """ (省略: CORE_EXTRACTION に依存) """
    _update_task_status(task_id, "COMPLETED", payload={"dummy": "ok"})

async def run_review_card_task(job_id: str, task_id: str):
    """ (省略: CORE_EXTRACTION に依存) """
    _update_task_status(task_id, "COMPLETED", payload={"dummy": "ok"})

async def run_fun_facts_task(job_id: str, task_id: str):
    """ (省略: CORE_EXTRACTION に依存) """
    _update_task_status(task_id, "COMPLETED", payload={"dummy": "ok"})

async def run_detail_contents_task(job_id: str, task_id: str):
    """ (省略: CORE_EXTRACTION に依存) """
    _update_task_status(task_id, "COMPLETED", payload={"dummy": "ok"})

# ---------------------------------------------------------
# 10. IMAGE_GENERATION (画像生成)
# ---------------------------------------------------------
async def run_image_generation_task(job_id: str, task_id: str):
    """ (省略: REVIEW_CARD に依存) """
    _update_task_status(task_id, "COMPLETED", payload={"dummy": "ok"})