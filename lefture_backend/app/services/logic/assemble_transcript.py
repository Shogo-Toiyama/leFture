from pathlib import Path
from app.services.helpers.helpers import TaskLogger

class AssembleTranscriptService:
    def __init__(self, logger: TaskLogger):
        self.logger = logger
        pass

    # 戻り値を Path から list に変更！
    def run(self, completed_chunks: list) -> list:
        self.logger.log("   [Logic] Starting AssembleTranscriptService")
        
        assembled_transcript = []
        global_sid_counter = 1
        running_offset = 0.0  

        for chunk in completed_chunks:
            chunk_index = chunk.get("chunk_index")
            segments = chunk.get("segments") or []
            actual_duration = chunk.get("audio_duration", 0.0)
            
            if not segments:
                running_offset += actual_duration
                continue

            for seg in segments:
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

            running_offset += actual_duration

        self.logger.log(f"   [Logic] Assembled {len(assembled_transcript)} sentences. Total audio length: {running_offset:.2f}s")
        
        # 💡 ファイルに保存せず、組み立てたリストをそのまま返す！
        return assembled_transcript