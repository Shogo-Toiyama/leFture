# app/services/logic/transcription.py
from pathlib import Path
from contents_generation.scripts.lecture_audio_to_text import lecture_audio_to_text
# ↑ 既存のスクリプトをimport (パスは適宜調整してください)
from contents_generation.scripts.llm.llm_unified import UnifiedLLM, CostCollector

class TranscriptionService:
    def __init__(self, llm: UnifiedLLM, cost_collector: CostCollector):
        self.llm = llm
        self.collector = cost_collector

    def run(self, audio_path: Path, work_dir: Path) -> Path:
        """
        音声をテキスト化し、transcript_sentences.jsonのパスを返す
        """
        # 既存の関数を呼び出す
        # lecture_audio_to_text関数が内部で work_dir にファイルを出力する前提
        lecture_audio_to_text(
            audio_file=audio_path,
            lecture_dir=work_dir,
            llm=self.llm,
            model_alias="2_5_flash", # モデル名は設定ファイルに出してもOK
            collector=self.collector
        )
        
        output_json = work_dir / "reviewed_sentences.json" # 最終成果物
        if not output_json.exists():
            raise FileNotFoundError(f"Transcription failed, {output_json} not found.")
            
        return output_json