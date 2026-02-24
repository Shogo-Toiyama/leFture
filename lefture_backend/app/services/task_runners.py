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
# 0. Transcribe Chunk （Groqでリアルタイム文字起こし）
# ---------------------------------------------------------

async def run_transcribe_chunk_worker(lecture_id: str, chunk_index: int, audio_bytes: bytes):
    """
    Flutterから直接送られてきたWAVバイナリ(audio_bytes)をメモリ上で処理する。
    ダウンロード時間がゼロになるため、爆速で処理が完了する。
    """
    supabase = get_supabase_client()
    
    try:
        # DBへの PROCESSING の書き込みはFlutter側で既にやってくれているので省略！
        
        print_log(f"🎤 [In-Memory] Transcribing chunk {chunk_index} for lecture {lecture_id}")
        
        # 1. 職人を呼んで、メモリ上の音声バイナリを直接渡す
        transcriber = TranscriptionService()
        
        # 💡 [作戦1の準備] ここで将来的に「過去の文脈」や「CS用語」をprompt_keywordsとして渡せます
        result = transcriber.run_in_memory(
            audio_bytes=audio_bytes, 
            chunk_index=chunk_index,
        )

        # 2. DBを DONE に更新し、真実のテキストを書き込む
        # idではなく、lecture_idとchunk_indexの組み合わせでレコードを特定して更新する
        supabase.table("lecture_transcripts").update({
            "audio_duration": result["audio_duration"],
            "status": "DONE",
            "text": result["text"],
            "segments": result["segments"], 
            "confidence": result["segments"][0]["confidence"] if result["segments"] else 0.0
        }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()
        
        print_log(f"✅ Chunk transcription completed: Chunk {chunk_index}")
        if result["text"]:
            print_log(f"📝 Text: {result['text'][:30]}...")
        else:
            print_log(f"🔇 Text: (No speech detected, skipped Groq)")
            
    except Exception as e:
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print_log(f"❌ Chunk transcription failed: {error_msg}")
        supabase.table("lecture_transcripts").update({
            "status": "ERROR",
            "error_message": str(e)
        }).eq("lecture_id", lecture_id).eq("chunk_index", chunk_index).execute()

# ---------------------------------------------------------
# 1. Check and Assemble (文字起こしの待ち合わせ＆組み立て)
# ---------------------------------------------------------

async def run_check_and_assemble_transcript_task(job_id: str, task_id: str):
    """
    [タスク: CHECK_AND_ASSEMBLE_TRANSCRIPT]
    リアルタイム文字起こしが全て完了するのを「待ち」、
    揃ったら1つの transcript.json に組み立てて次の工程に渡す。
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
        # 1. リアルタイム職人の進捗をDBで確認 (CHECK)
        # ---------------------------------------------------------
        # 💥 ここを修正！ segments と audio_duration, status を取得する！
        res = supabase.table("lecture_transcripts")\
            .select("chunk_index, segments, status, audio_duration")\
            .eq("lecture_id", lecture_id)\
            .order("chunk_index")\
            .execute()
            
        all_chunks = res.data
        
        # DONEになっているものだけを抽出
        completed_chunks = [c for c in all_chunks if c.get("status") == "DONE"]
        
        # 待ち合わせロジック
        if len(completed_chunks) < expected_chunks:
            error_msg = f"⏳ Waiting for real-time transcripts... ({len(completed_chunks)}/{expected_chunks})"
            print_log(error_msg)
            # わざとエラーを投げることでリトライさせる
            raise Exception(error_msg)

        # ---------------------------------------------------------
        # 2. 全て揃っていたら、専用職人を呼んで組み立てる (ASSEMBLE)
        # ---------------------------------------------------------
        print_log(f"🎉 All {expected_chunks} chunks transcribed! Assembling...")
        
        # 💥 ここで新しく作った職人に丸投げする！
        assembler = AssembleTranscriptService()
        local_transcript_path = assembler.run(completed_chunks, work_dir)

        # ---------------------------------------------------------
        # 3. 出荷 (Storage保存 ＆ DB更新)
        # ---------------------------------------------------------
        remote_transcript_path = _upload_artifact(uid, lecture_id, local_transcript_path, "transcript.json")
        result_payload = {"transcript_json": remote_transcript_path}
        
        # 次の Sentence Review にバトンタッチ！
        _update_task_status(task_id, "COMPLETED", payload=result_payload)
        print_log(f"✅ CHECK_AND_ASSEMBLE Completed!")

    except Exception as e:
        if "Waiting for real-time" in str(e):
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
# 2. Sentence Review (文章校正)
# ---------------------------------------------------------

async def run_sentence_review_task(job_id: str, task_id: str):
    
    print_log(f"▶️ Starting SENTENCE_REVIEW (Task: {task_id})")
    
    # 1. 状態を RUNNING にする
    _update_task_status(task_id, "RUNNING")
    
    # 作業用ディレクトリ (Taskごとに分けるので安全！)
    work_dir = BASE_WORK_DIR / task_id
    work_dir.mkdir(parents=True, exist_ok=True)
    
    try:
        # 2. 親Jobの情報と、前工程のデータパスを取得
        job_ctx = _get_job_context(job_id)
        uid = job_ctx["owner_id"]
        lecture_id = job_ctx["lecture_id"]
        
        # 「CHECK_AND_ASSEMBLE」が終わった時に書き込まれたパスを取得する
        prev_payload = _get_dependency_payload(job_id, "CHECK_AND_ASSEMBLE")
        remote_transcript_path = prev_payload.get("transcript_json")
        
        if not remote_transcript_path:
            raise ValueError("Dependency data (transcript_json) not found!")

        # 3. 前工程のデータをダウンロード (仕入れ)
        local_transcript_path = work_dir / "transcript.json"
        _download_artifact(remote_transcript_path, local_transcript_path)

        # 4. 純粋な職人（AIロジック）を呼び出す！
        llm = UnifiedLLM(provider="gemini")
        collector = CostCollector()
        reviewer = SentenceReviewService(llm, collector)
        
        reviewed_paths = reviewer.run(local_transcript_path, work_dir)

        # 5. 結果をStorageにアップロード (出荷)
        result_payload = {}
        for path in reviewed_paths:
            is_temp = "raw" in path.name
            remote_path = _upload_artifact(uid, lecture_id, path, path.name, is_temp=is_temp)
            
            # 完成品だけを payload にメモする (次の工程に渡すため)
            if path.name == "reviewed_sentences.json":
                result_payload["reviewed_sentences_json"] = remote_path

        # 6. 大成功！DBを COMPLETED にして payload を残す (👉 指揮者が目を覚ます！)
        _update_task_status(task_id, "COMPLETED", payload=result_payload)
        print_log(f"✅ SENTENCE_REVIEW Completed!")

    except Exception as e:
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print_log(f"❌ SENTENCE_REVIEW Failed: {error_msg}")
        _update_task_status(task_id, "FAILED", error_msg=error_msg)
        raise e  # Cloud Tasks にエラーを知らせるために再送出
        
    finally:
        # お掃除
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