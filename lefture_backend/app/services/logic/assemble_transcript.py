from pathlib import Path
import json
from app.services.helpers.helpers import print_log

class AssembleTranscriptService:
    def __init__(self):
        pass

    def run(self, completed_chunks: list, work_dir: Path) -> Path:
        print_log("   [Logic] Starting AssembleTranscriptService")
        
        assembled_transcript = []
        global_sid_counter = 1
        running_offset = 0.0  # これが「前のチャンクまでの累積時間」

        # チャンク順に処理
        for chunk in completed_chunks:
            chunk_index = chunk.get("chunk_index")
            segments = chunk.get("segments") or []
            
            # 🌟 DBに保存された「実際のWAVの長さ」を取得 (もし無ければ一旦0で計算)
            actual_duration = chunk.get("audio_duration", 0.0)
            
            if not segments:
                # 文字起こし結果が空でも、音声の長さ分だけオフセットは進める！
                running_offset += actual_duration
                continue

            for seg in segments:
                # チャンク内の相対時間を、全体での絶対時間に変換！
                absolute_start = running_offset + seg.get("start", 0.0)
                absolute_end = running_offset + seg.get("end", 0.0)

                assembled_transcript.append({
                    "sid": f"s{global_sid_counter:06d}",
                    "text": seg.get("text", "").strip(),
                    "confidence": seg.get("confidence", 0.99),
                    "start": round(absolute_start, 2),
                    "end": round(absolute_end, 2),
                    "chunk_index": chunk_index
                })
                
                global_sid_counter += 1

            # 💥 最後の文字の終了時間ではなく、実際のWAVの長さをオフセットに足す！
            # これにより、チャンク末尾の無音が無視されてズレる問題を完全に防ぐ！
            running_offset += actual_duration

        local_transcript_path = work_dir / "transcript.json"
        with open(local_transcript_path, "w", encoding="utf-8") as f:
            json.dump(assembled_transcript, f, ensure_ascii=False, indent=2)

        print_log(f"   [Logic] Assembled {len(assembled_transcript)} sentences. Total audio length: {running_offset:.2f}s")
        return local_transcript_path