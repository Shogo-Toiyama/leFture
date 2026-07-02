from app.services.helpers.helpers import TaskLogger


class AssembleTranscriptService:
    def __init__(self, logger: TaskLogger):
        self.logger = logger

    def run(self, completed_chunks: list) -> list:
        self.logger.log("   [Logic] Starting AssembleTranscriptService")

        assembled_transcript = []

        # SID is intentionally 1-indexed.
        # Downstream tasks parse SID with int(sid[1:]) and expect IDs like:
        #   s000001, s000002, ...
        # Do not change this to 0-indexed unless all downstream SID parsing is updated.
        global_sid_counter = 1

        for chunk in completed_chunks:
            chunk_index = chunk.get("chunk_index")
            segments = chunk.get("segments_reviewed")
            is_absolute = True
            if segments is None:
                segments = chunk.get("segments_groq") or []
                is_absolute = False

            if not isinstance(segments, list):
                raise ValueError(
                    f"CRITICAL: chunk (index={chunk_index}) has invalid segments type: "
                    f"{type(segments).__name__}. Expected list."
                )

            # Flutterが計算した完璧な絶対時間を使う！(running_offsetは廃止)
            chunk_start_time = chunk.get("start_time")
            if chunk_start_time is None:
                raise ValueError(
                    f"CRITICAL: chunk (index={chunk_index}) is missing start_time. "
                    "Cannot assemble transcript."
                )

            if not segments:
                continue
            for seg in segments:
                if is_absolute:
                    # REVIEWEDなチャンクはすでに絶対時間になっているため、そのまま使用する！
                    absolute_start = seg.get("start", 0.0)
                    absolute_end = seg.get("end", 0.0)
                else:
                    # チャンク内の相対時間(0.0~34.0)に、チャンクの絶対開始時間を足す！
                    absolute_start = chunk_start_time + seg.get("start", 0.0)
                    absolute_end = chunk_start_time + seg.get("end", 0.0)

                assembled_transcript.append({
                    "sid": f"s{global_sid_counter:06d}",
                    "text": seg.get("text", "").strip(),
                    "confidence": seg.get("confidence", 0.99),
                    "start": round(absolute_start, 2),
                    "end": round(absolute_end, 2),
                    "chunk_index": chunk_index
                })

                global_sid_counter += 1

        self.logger.log(f"   [Logic] Assembled {len(assembled_transcript)} sentences.")
        return assembled_transcript