import shutil
import traceback
import json
from pathlib import Path
from datetime import datetime

# 作成した設定とSupabaseクライアント
from app.core.config import JobStatus, PipelineSteps, PIPELINE_STEPS_NUM, BASE_WORK_DIR
from app.core.supabase import get_supabase_client
from app.services.helpers.helpers import print_log, init_logger, finalize_log_and_get_path
from app.services.helpers.llm_unified import UnifiedLLM, CostCollector

from app.services.logic.transcription import TranscriptionService
from app.services.logic.sentence_review import SentenceReviewService
from app.services.logic.role_classification import RoleClassificationService
from app.services.logic.lecture_segmentaion import LectureSegmentationService
from app.services.logic.topic_details_generation import TopicDetailGenerationService
from app.services.logic.fun_fact_generation import FunFactGenerationService


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
    init_logger(work_dir)
    llm = UnifiedLLM(provider="gemini") # 必要に応じて openai に変更
    collector = CostCollector()
    
    # 成果物のパスを一時保存する辞書
    current_artifacts = {}

    try:
        print_log(f"🚀 Job Started: {job_id}")

        # ---------------------------------------------------------
        # 0. Jobデータの取得 & Lecture情報の確認
        # ---------------------------------------------------------
        # Job情報を取得
        job_res = supabase.table("processing_jobs").select("*").eq("id", job_id).single().execute()
        job_data = job_res.data
        lecture_id = job_data["lecture_id"]
        
        if job_data["status"] != JobStatus.PENDING or job_data["current_step"] != PipelineSteps.PENDING:
            print_log(f"Job is already executed. [Status: {job_data['status']}, Step: {job_data['current_step']}]")
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
            
        print_log(f"✅ Downloaded: {local_audio_path}")


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
        # 4. ROLE CLASSIFICATION
        # ---------------------------------------------------------

        step_name = PipelineSteps.ROLE_CLASSIFYING
        _update_job_progress(supabase, job_id, JobStatus.PROCESSING, step_name, current_artifacts)

        role_classifier = RoleClassificationService(llm, collector)
        role_artifacts = await role_classifier.run(final_json_path, work_dir)

        final_sentences_path = None

        for path in role_artifacts:
            filename = path.name
            
            if filename == "sentences_final.json":
                remote_path = _upload_artifact(supabase, uid, lecture_id, path, "sentences_final.json")
                current_artifacts["sentences_final_json"] = remote_path
                final_sentences_path = path
                
            elif filename.endswith(".zip"):
                 remote_path = _upload_artifact(supabase, uid, lecture_id, path, filename, isTemp=True)
                 current_artifacts["role_batches_zip"] = remote_path

        if not final_sentences_path:
             raise ValueError("Role Classification failed to generate final JSON.")
        
        # ---------------------------------------------------------
        # 5. SEGMENTING (話題分割)
        # ---------------------------------------------------------
        step_name = PipelineSteps.SEGMENTING
        _update_job_progress(supabase, job_id, JobStatus.PROCESSING, step_name, current_artifacts)

        segmenter = LectureSegmentationService(llm, collector)
        seg_paths = await segmenter.run(final_sentences_path, work_dir)

        final_segments_path = None
        for path in seg_paths:
            if path.name == "segments.json":
                current_artifacts["segments_json"] = _upload_artifact(supabase, uid, lecture_id, path, "segments.json")
                final_segments_path = path
        
        if not final_segments_path:
             # Segmentation失敗しても次に進めない
             raise ValueError("Segmentation failed.")
        
        # ---------------------------------------------------------
        # 6. GENERATING_DETAILS (詳細解説生成)
        # ---------------------------------------------------------
        step_name = PipelineSteps.GENERATING_DETAILS
        _update_job_progress(supabase, job_id, JobStatus.PROCESSING, step_name, current_artifacts)

        detailer = TopicDetailGenerationService(llm, collector)
        # 戻り値は [segments_with_details.json]
        detail_paths = await detailer.run(final_segments_path, final_sentences_path, work_dir)

        segments_with_details_path = None # 次のステップに渡す用

        for path in detail_paths:
            if path.name == "segments_with_details.json":
                # Tempとして保存してもいいし、重要な中間データとして保存してもOK
                current_artifacts["segments_with_details_json"] = _upload_artifact(supabase, uid, lecture_id, path, "segments_with_details.json")
                segments_with_details_path = path


        # ---------------------------------------------------------
        # 7. GENERATING_FUN_FACTS (豆知識生成)
        # ---------------------------------------------------------
        step_name = PipelineSteps.GENERATING_FUN_FACTS
        _update_job_progress(supabase, job_id, JobStatus.PROCESSING, step_name, current_artifacts)

        # inputは work_dir 内の segments_with_details.json を勝手に見に行く仕様にしたので引数は work_dir だけでOK
        fun_facter = FunFactGenerationService(llm, collector)
        fun_paths = await fun_facter.run(work_dir, segments_with_details_path)

        for path in fun_paths:
            if path.name == "lecture_complete_data.json":
                # これがアプリで使う「完全版データ」！
                current_artifacts["lecture_complete_data_json"] = _upload_artifact(supabase, uid, lecture_id, path, "lecture_complete_data.json")

        # ---------------------------------------------------------
        # X. COMPLETED (完了処理)
        # ---------------------------------------------------------
        step_name = PipelineSteps.COMPLETED
        _update_job_progress(supabase, job_id, JobStatus.DONE, step_name, current_artifacts)
        
        # 最後に lectures テーブルの final_markdown_path などを更新しても良い
        # supabase.table("lectures").update({...}).eq("id", lecture_id).execute()

        print_log(f"🎉 Job Completed Successfully: {job_id}")
        print_log(collector.report())


    except Exception as e:
        # ---------------------------------------------------------
        # ERROR HANDLING (失敗時の処理)
        # ---------------------------------------------------------
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print_log(f"❌ Job Failed at {step_name}: {error_msg}")
        
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
        try:
            # ログファイルを整形してパスを取得
            log_path = finalize_log_and_get_path()
            
            if log_path and log_path.exists():
                # lecture_assets バケットの logs フォルダに保存
                # uid/lecture_id/logs/log.json として保存するのがおすすめ
                # (uidはtryブロック内で取得しているので、念の為ここで再取得するか、変数のスコープに注意)
                
                # tryブロックの外で uid が未定義の場合の安全策
                # (Job取得前にコケた場合はアップロードできないが、そこは許容範囲)
                if 'uid' in locals() and 'lecture_id' in locals():
                    _upload_artifact(supabase, uid, lecture_id, log_path, "log.json", isLog=True)
                    print(f"📝 Log uploaded to Storage: logs/log.json")
                else:
                    print("⚠️ Could not upload log: uid or lecture_id not set.")
                    
        except Exception as log_e:
            print(f"⚠️ Failed to upload log file: {log_e}")
        
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
    
    print_log(f"🔄 Progress: [{step_number}] {step_name} (Status: {status})")
    
    supabase.table("processing_jobs").update({
        "status": status,
        "current_step": step_name,
        "step_number": step_number,
        "artifact_paths": artifacts, # 最新の成果物パスリストで上書き更新
        "updated_at": datetime.now().isoformat()
    }).eq("id", job_id).execute()

def _upload_artifact(supabase, uid, lecture_id: str, local_path: Path, filename: str, isTemp: bool = False, isLog: bool = False) -> str:
    """
    ローカルの生成ファイルをSupabase Storageにアップロードし、そのパスを返す。
    """
    storage_path = f"{uid}/{lecture_id}/artifacts/{filename}"
    if isTemp:
        storage_path = f"{uid}/{lecture_id}/artifacts/temp/{filename}"
    if isLog:
        storage_path = f"{uid}/{lecture_id}/log/{filename}"
    bucket_name = "lecture_assets"

    with open(local_path, "rb") as f:
        supabase.storage.from_(bucket_name).upload(
            path=storage_path,
            file=f,
            file_options={"upsert": "true"}
        )
    
    return f"{bucket_name}/{storage_path}"