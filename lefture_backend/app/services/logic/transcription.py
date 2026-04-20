import io
import math
import time
from groq import Groq
from pydub import AudioSegment
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine

class TranscriptionService:
    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.client = Groq()
        self.logger = logger
        self.billing = billing
        self.model = "whisper-large-v3-turbo"

    def run_in_memory(self, audio_bytes: bytes, chunk_index: int, prompt_keywords: str = "") -> dict:
        """
        [究極のシンプルパイプライン]
        Flutterから送られてきた34秒（オーバーラップ込み）のRAWデータを、
        無加工でそのままGroq Whisperに投げ込む。
        """
        self.logger.log(f"   [Logic] Loading audio into memory for chunk {chunk_index}")
        
        # バイナリから音声を展開（長さを取得するためだけに読み込む）
        audio = AudioSegment.from_file(io.BytesIO(audio_bytes), format="wav")
        actual_duration = len(audio) / 1000.0
        
        # ---------------------------------------------------------
        # ✨ Groq Whisper への送信（無加工）
        # ---------------------------------------------------------
        self.logger.log(f"   [Logic] Calling Groq API directly...")
        start_time = time.perf_counter()
        try:
            res = self.client.audio.transcriptions.create(
                file=(f"chunk_{chunk_index}.wav", audio_bytes), # 送られてきたバイナリをそのまま送る
                model=self.model,
                response_format="verbose_json",
                language="en",
                prompt=prompt_keywords
            )
        except Exception as e:
            self.logger.log(f"   [Logic] ❌ Groq API Error: {e}")
            # APIエラー時は空データを返す
            return {
                "text": "",
                "segments": [],
                "audio_duration": actual_duration
            }
        elapsed_time = time.perf_counter() - start_time
        self.billing.add_time_cost("groq/whisper-large-v3-turbo", actual_duration, note="Audio transcription")
        self.billing.add_time_cost("cloudrun/self", elapsed_time, note="Whisper API wait time")

        full_text = res.text.strip()
        segments_data = []

        # ---------------------------------------------------------
        # ✨ データの整形
        # ---------------------------------------------------------
        if hasattr(res, 'segments') and res.segments:
            for i, seg in enumerate(res.segments):
                seg_text = seg.get('text', '') if isinstance(seg, dict) else getattr(seg, 'text', '')
                start = seg.get('start', 0.0) if isinstance(seg, dict) else getattr(seg, 'start', 0.0)
                end = seg.get('end', 0.0) if isinstance(seg, dict) else getattr(seg, 'end', 0.0)
                logprob = seg.get('avg_logprob', 0) if isinstance(seg, dict) else getattr(seg, 'avg_logprob', 0)

                # Confidenceが低すぎる(0.1以下)場合はハルシネーションの可能性が高いので弾く
                confidence = max(0.0, min(1.0, math.exp(logprob)))
                if confidence < 0.1:
                    continue

                sid = f"s{chunk_index:03d}{i+1:03d}"

                # ※ ここでの時間は「チャンク内の相対時間（0.0s〜34.0s）」。
                # 絶対時間への変換は assemble_transcript.py で行う！
                segments_data.append({
                    "sid": sid,
                    "text": seg_text.strip(),
                    "confidence": round(confidence, 4),
                    "start": round(start, 3),
                    "end": round(end, 3),
                    "chunk_index": chunk_index
                })

        # 音声が短すぎてセグメントが分かれなかった場合の安全策
        if not segments_data and full_text:
            segments_data.append({
                "sid": f"s{chunk_index:03d}001",
                "text": full_text,
                "confidence": 0.99,
                "start": 0.0,
                "end": round(actual_duration, 3),
                "chunk_index": chunk_index
            })

        # 💡 何もテキストが拾えなかった場合（無音やノイズのみのチャンク）
        if not segments_data:
            self.logger.log(f"   [Logic] 🔇 No speech detected by Whisper in chunk {chunk_index}.")

        return {
            "text": full_text,
            "segments": segments_data,
            "audio_duration": actual_duration
        }