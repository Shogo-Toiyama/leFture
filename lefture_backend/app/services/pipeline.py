import shutil
import traceback
import json
from pathlib import Path
from datetime import datetime

# 作成した設定とSupabaseクライアント
from app.core.config import JobStatus, PipelineSteps, PIPELINE_STEPS_NUM, BASE_WORK_DIR
from app.core.supabase import get_supabase_client
from app.services.helpers.llm_unified import UnifiedLLM, CostCollector

from app.services.logic.transcription import TranscriptionService
from app.services.logic.sentence_review import SentenceReviewService


async def run_lecture_pipeline(job_id: str):
    """
    バックグラウンドで実行されるメイン処理。
    processing_jobs テーブルの job_id を受け取り、最後まで処理を行う。
    """
    supabase = get_supabase_client()
    
    # 作業用ディレクトリの作成 (/tmp/job_id/)
    work_dir = BASE_WORK_DIR / job_id
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)

    # 共通ツールの初期化
    llm = UnifiedLLM(provider="gemini") # 必要に応じて openai に変更
    collector = CostCollector()
    
    # 成果物のパスを一時保存する辞書
    current_artifacts = {}

    try:
        print(f"🚀 Job Started: {job_id}")

        # ---------------------------------------------------------
        # 0. Jobデータの取得 & Lecture情報の確認
        # ---------------------------------------------------------
        # Job情報を取得
        job_res = supabase.table("processing_jobs").select("*").eq("id", job_id).single().execute()
        job_data = job_res.data
        lecture_id = job_data["lecture_id"]
        
        if job_data["status"] != JobStatus.PENDING or job_data["current_step"] != PipelineSteps.PENDING:
            print(f"Job is already executed. [Status: {job_data['status']}, Step: {job_data['current_step']}]")
            return

        # ステータスを PROCESSING に変更
        _update_job_progress(supabase, job_id, JobStatus.PROCESSING, "READY", current_artifacts)

        # Lectureテーブルから音声ファイルのパスを取得
        lecture_res = supabase.table("lecture_assets").select("storage_path").eq("lecture_id", lecture_id).single().execute()
        storage_path = lecture_res.data["storage_path"]
        uid = storage_path.split("/", 1)[0]


        # ---------------------------------------------------------
        # 1. DOWNLOADING (音声のダウンロード)
        # ---------------------------------------------------------
        step_name = PipelineSteps.DOWNLOADING
        _update_job_progress(supabase, job_id, JobStatus.PROCESSING, step_name, current_artifacts)
        
        local_audio_path = work_dir / "input_audio.m4a"
        
        # Supabase Storage ('lecture_assets') からダウンロード
        with open(local_audio_path, "wb") as f:
            res = supabase.storage.from_("lecture_assets").download(storage_path)
            f.write(res)
            
        print(f"✅ Downloaded: {local_audio_path}")


        # ---------------------------------------------------------
        # 2. TRANSCRIBING (文字起こし)
        # ---------------------------------------------------------
        step_name = PipelineSteps.TRANSCRIBING
        _update_job_progress(supabase, job_id, JobStatus.PROCESSING, step_name, current_artifacts)

        transcriber = TranscriptionService(collector)
        transcript_path = transcriber.run(local_audio_path, work_dir)
        
        # 成果物をSupabase Storageにバックアップ＆パス記録
        remote_trans_path = _upload_artifact(supabase, uid, lecture_id, transcript_path, "transcript.json")
        current_artifacts["transcript_json"] = remote_trans_path


        # ---------------------------------------------------------
        # 3. SENTENCE_REVIEWING (文章校正)
        # ---------------------------------------------------------
        step_name = PipelineSteps.SENTENCE_REVIEWING
        _update_job_progress(supabase, job_id, JobStatus.PROCESSING, step_name, current_artifacts)

        reviewer = SentenceReviewService(llm, collector)
        reviewed_paths = reviewer.run(transcript_path, work_dir)
        
        final_json_path = None

        for path in reviewed_paths:
            # ファイル名で判断して振り分ける
            filename = path.name
            
            if filename == "reviewed_sentences_raw.json":
                # これは「途中経過 (Temp)」
                remote_path = _upload_artifact(supabase, uid, lecture_id, path, filename, isTemp=True)
                current_artifacts["reviewed_sentences_raw_json"] = remote_path
            
            elif filename == "reviewed_sentences.json":
                # これが「完成品」
                remote_path = _upload_artifact(supabase, uid, lecture_id, path, filename)
                current_artifacts["reviewed_sentences_json"] = remote_path
                final_json_path = path
                
            elif filename == "reviewed_sentences_raw_text.txt":
                # これは「失敗時のログ (Temp)」
                remote_path = _upload_artifact(supabase, uid, lecture_id, path, filename, isTemp=True)
                current_artifacts["reviewed_sentences_error_text"] = remote_path

        # もし完成品(final_json_path)がなければ、ここでエラーにする
        if not final_json_path:
            raise ValueError("Sentence Review failed to generate final JSON. Check temp artifacts for raw text.")


        # ---------------------------------------------------------
        # X. COMPLETED (完了処理)
        # ---------------------------------------------------------
        step_name = PipelineSteps.COMPLETED
        _update_job_progress(supabase, job_id, JobStatus.DONE, step_name, current_artifacts)
        
        # 最後に lectures テーブルの final_markdown_path などを更新しても良い
        # supabase.table("lectures").update({...}).eq("id", lecture_id).execute()

        print(f"🎉 Job Completed Successfully: {job_id}")
        print(collector.report())

    except Exception as e:
        # ---------------------------------------------------------
        # ERROR HANDLING (失敗時の処理)
        # ---------------------------------------------------------
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print(f"❌ Job Failed at {step_name}: {error_msg}")
        
        # エラーログを作成
        error_data = {
            "message": str(error_msg),
            "step": step_name,
            "timestamp": datetime.now().isoformat(),
            "traceback": traceback.format_exc()
        }

        # DB更新: Status=ERROR, Step=失敗したステップのまま
        supabase.table("processing_jobs").update({
            "status": JobStatus.ERROR,
            "error_message": json.dumps(error_data), # JSONB対応
            "updated_at": datetime.now().isoformat()
        }).eq("id", job_id).execute()

    finally:
        # クリーンアップ (Cloud Runの容量確保)
        if work_dir.exists():
            shutil.rmtree(work_dir)


# --- Helper Functions (コードを見やすくするための道具) ---

def _update_job_progress(supabase, job_id: str, status: JobStatus, step_name: str, artifacts: dict):
    """
    DBの進捗状況を更新する。
    step_name から自動的に step_number を割り出す。
    """
    step_number = PIPELINE_STEPS_NUM.get(step_name, 0)
    
    print(f"🔄 Progress: [{step_number}] {step_name} (Status: {status})")
    
    supabase.table("processing_jobs").update({
        "status": status,
        "current_step": step_name,
        "step_number": step_number,
        "artifact_paths": artifacts, # 最新の成果物パスリストで上書き更新
        "updated_at": datetime.now().isoformat()
    }).eq("id", job_id).execute()

def _upload_artifact(supabase, uid, lecture_id: str, local_path: Path, filename: str, isTemp: bool = False) -> str:
    """
    ローカルの生成ファイルをSupabase Storageにアップロードし、そのパスを返す。
    """
    storage_path = f"{uid}/{lecture_id}/artifacts/{filename}"
    if isTemp:
        storage_path = f"{uid}/{lecture_id}/artifacts/temp/{filename}"
    bucket_name = "lecture_assets"

    with open(local_path, "rb") as f:
        supabase.storage.from_(bucket_name).upload(
            path=storage_path,
            file=f,
            file_options={"upsert": "true"}
        )
    
    return f"{bucket_name}/{storage_path}"