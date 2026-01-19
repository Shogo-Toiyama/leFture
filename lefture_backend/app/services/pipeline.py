import shutil
import traceback
from pathlib import Path
from app.core.supabase import get_supabase_client
from app.core.config import JobStatus, BASE_WORK_DIR

# 各ロジックのクラスをImport
from app.services.logic.transcription import TranscriptionService
# from app.services.logic.segmentation import SegmentationService ... (他も同様に)

from contents_generation.scripts.llm.llm_unified import UnifiedLLM, CostCollector

async def run_lecture_pipeline(lecture_id: str, storage_path: str):
    supabase = get_supabase_client()
    
    # 1. 作業ディレクトリの準備 (/tmp/lecture_id)
    work_dir = BASE_WORK_DIR / lecture_id
    if work_dir.exists():
        shutil.rmtree(work_dir) # 残骸があれば消す
    work_dir.mkdir(parents=True, exist_ok=True)
    
    # LLMとコスト計算機の初期化 (全ステップで共有)
    llm = UnifiedLLM(provider="gemini")
    collector = CostCollector()

    try:
        # --- PHASE 0: ダウンロード ---
        _update_status(supabase, lecture_id, JobStatus.DOWNLOADING)
        audio_local_path = work_dir / "input_audio.m4a"
        
        # Supabase Storageからダウンロード ('lectures' バケットと仮定)
        with open(audio_local_path, "wb") as f:
            res = supabase.storage.from_("lecture_assets").download(storage_path)
            f.write(res)

        # --- PHASE 1: 文字起こし & レビュー ---
        _update_status(supabase, lecture_id, JobStatus.TRANSCRIBING)
        transcriber = TranscriptionService(llm, collector)
        transcript_json_path = transcriber.run(audio_local_path, work_dir)
        
        # 途中経過をアップロード (オプション)
        _upload_artifact(supabase, lecture_id, transcript_json_path, "transcript.json")


        # --- PHASE 2: Role Classification (例) ---
        # _update_status(supabase, lecture_id, JobStatus.REVIEWING)
        # role_classifier = RoleClassificationService(llm, collector)
        # role_classifier.run(work_dir) 
        # ... 以降、既存のステップを順番に呼び出していく ...


        # --- PHASE FINAL: 完了 ---
        _update_status(supabase, lecture_id, JobStatus.COMPLETED)
        
        # コスト情報のログ出力など
        print(collector.report())

    except Exception as e:
        # エラーハンドリング
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print(f"❌ Job Failed: {error_msg}")
        
        supabase.table("lectures_assets").update({
            "status": JobStatus.ERROR,
            "error_message": error_msg  # DBにエラー詳細列を作っておくと便利
        }).eq("id", lecture_id).execute()

    finally:
        # お掃除 (Cloud Runのディスク容量節約)
        if work_dir.exists():
            shutil.rmtree(work_dir)


# --- Helper Functions ---

def _update_status(supabase, lecture_id: str, status: JobStatus):
    """DBのステータスを更新する"""
    print(f"🔄 Status Update: {lecture_id} -> {status}")
    supabase.table("lectures_assets").update({
        "status": status
    }).eq("id", lecture_id).execute()

def _upload_artifact(supabase, lecture_id: str, local_path: Path, remote_filename: str):
    """生成ファイルをSupabase Storageに戻す"""
    remote_path = f"{lecture_id}/artifacts/{remote_filename}"
    with open(local_path, "rb") as f:
        supabase.storage.from_("lectures").upload(
            path=remote_path,
            file=f,
            file_options={"upsert": "true"}
        )