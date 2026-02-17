import os, json, time, sys
import assemblyai as aai
from dotenv import load_dotenv
from pathlib import Path

# ルートディレクトリのモジュールをインポートできるようにパスを通す
sys.path.append(str(Path(__file__).resolve().parents[1]))
# 型ヒント用 (実行時にはダックタイピングで動くので必須ではないですが念のため)
from cost_tracker import CostCollector

def lecture_audio_to_text(audio_file, lecture_dir: Path, collector: CostCollector):
    print("\n### Lecture Audio To Text ###")
    start_time_audio_to_text = time.time()

    load_dotenv()
    aai.settings.api_key = os.getenv("ASSEMBLYAI_API_KEY")

    # Universal model ($0.15/h) + Speaker Diarization ($0.02/h) = $0.17/h
    HOURLY_RATE = 0.17

    aai_config = aai.TranscriptionConfig(
        speech_model=aai.SpeechModel.universal,
        speaker_labels=True
    )

    print("Waiting for response from AssemblyAI API...")
    transcript = aai.Transcriber(config=aai_config).transcribe(str(audio_file))

    if transcript.status == "error":
        raise RuntimeError(f"Transcription failed: {transcript.error}")

    # --- コスト計算 & 集計 ---
    duration_sec = getattr(transcript, "audio_duration", 0) or 0
    cost_usd = (duration_sec / 3600.0) * HOURLY_RATE
    
    collector.add("AssemblyAI Transcription", cost_usd)
    print(f"\n[Usage: AssemblyAI]")
    print(f"  ⏳ Duration: {duration_sec:.2f} sec")
    print(f"  💵 Cost    : ${cost_usd:.6f} (@ ${HOURLY_RATE}/h)")
    # -----------------------

    print("saving response...")
    with open(lecture_dir / "transcript_raw.json", "w", encoding="utf-8") as f:
        json.dump(transcript.json_response, f, ensure_ascii=False, indent=2)

    sentences = transcript.get_sentences()

    def sentence_to_dict(s, idx):
        return {
            "sid": f"s{idx:06d}",
            "text": getattr(s, "text", None),
            "start": getattr(s, "start", None),
            "end": getattr(s, "end", None),
            "speaker": getattr(s, "speaker", None),
            "confidence": getattr(s, "confidence", None),
        }

    data = [sentence_to_dict(s, idx) for idx, s in enumerate(sentences, start=1)]
    with open(lecture_dir / "transcript_sentences.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    
    end_time_audio_to_text = time.time()
    elapsed_time_audio_to_text = end_time_audio_to_text - start_time_audio_to_text
    print(f"⏰Transcribed audio to text: {elapsed_time_audio_to_text:.2f} seconds.")