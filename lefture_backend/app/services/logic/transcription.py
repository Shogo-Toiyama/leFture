import json, os, time
import assemblyai as aai
from pathlib import Path

from app.services.helpers.llm_unified import CostCollector

class TranscriptionService:
    def __init__(self, collector: CostCollector):
        self.collector = collector


    def run(self, audio_file_path: Path, work_dir: Path) -> Path:
        print(f"   [Logic] Starting transcription for: {audio_file_path.name}")

        self._speach_to_text(
            audio_file=audio_file_path,
            work_dir=work_dir,
            collector=self.collector,
        )

        output_json = work_dir / "transcript_sentences.json"
        
        if not output_json.exists():
            raise FileNotFoundError(f"Transcription logic finished but {output_json} was not found.")
            
        print(f"   [Logic] Transcription finished: {output_json.name}")
        return output_json

    
    def _speach_to_text(audio_file, work_dir: Path, collector:CostCollector):
        print("\n### Lecture Audio To Text ###")
        start_time = time.time()

        aai.settings.api_key = os.environ.get("ASSEMBLYAI_API_KEY")

        aai_config = aai.TranscriptionConfig(
            speech_model=aai.SpeechModel.nano,
            punctuate=True,
            format_text=True,
            disfluencies=False,
        )

        print("Waiting for response from AssemblyAI API...")
        transcript = aai.Transcriber(config=aai_config).transcribe(str(audio_file))

        if transcript.status == "error":
            raise RuntimeError(f"Transcription failed: {transcript.error}")

        print("saving response...")
        with open(work_dir / "transcript_raw.json", "w", encoding="utf-8") as f:
            json.dump(transcript.json_response, f, ensure_ascii=False, indent=2)

        sentences = transcript.get_sentences()

        def sentence_to_dict(s, idx):
            return {
                "sid": f"s{idx:06d}",
                "text": getattr(s, "text", None),
                "start": getattr(s, "start", None),
                "end": getattr(s, "end", None),
                "confidence": getattr(s, "confidence", None),
            }

        data = [sentence_to_dict(s, idx) for idx, s in enumerate(sentences, start=1)]
        duration = transcript.audio_duration
        print(f"Cost (nano): ${duration/3600*0.12:.3f}")
        collector.add("AssemblyAI Transcription (nano)", duration/3600*0.12)
        with open(work_dir / "transcript_sentences.json", "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        end_time = time.time()
        elapsed_time = end_time - start_time
        print(f"⏰Transcribed audio to text: {elapsed_time:.2f} seconds.")