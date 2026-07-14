import io
import math
import time
import os
import asyncio
from pydub import AudioSegment
from groq import AsyncGroq, APIStatusError, APIConnectionError, RateLimitError
from tenacity import retry, retry_if_exception, stop_after_attempt, wait_exponential_jitter
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine


def _is_retryable_groq_error(exc: BaseException) -> bool:
    if isinstance(exc, (APIConnectionError, RateLimitError)):
        return True
    if isinstance(exc, APIStatusError):
        return exc.status_code >= 500
    return False


@retry(
    retry=retry_if_exception(_is_retryable_groq_error),
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(initial=1, max=8),
    reraise=True,
)
async def _call_groq_whisper(client: AsyncGroq, model: str, file_payload: tuple, prompt_keywords: str):
    """
    Groq Whisper APIを呼び出す。429や5xxなどの一時的エラーはリトライする。
    """
    return await client.audio.transcriptions.create(
        file=file_payload,
        model=model,
        response_format="verbose_json",
        language="en",
        prompt=prompt_keywords or None
    )


class TranscriptionService:
    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.logger = logger
        self.billing = billing
        self.api_key = os.getenv("GROQ_API_KEY")
        self.model = "whisper-large-v3-turbo"
        self.client = AsyncGroq(api_key=self.api_key) if self.api_key else None
        
        if not self.api_key:
            self.logger.log("⚠️ GROQ_API_KEY is not set in environment variables.")

    async def run_in_memory(self, audio_bytes: bytes, chunk_index: int, prompt_keywords: str = "") -> dict:
        """
        [究極のシンプルパイプライン]
        Flutterから送られてきた34秒（オーバーラップ込み）のM4A(AAC)データを直接Groq APIへ送信し、
        Whisper-large-v3-turboモデルで文字起こしを行う。
        """
        self.logger.log(f"   [Logic] Loading audio into memory for chunk {chunk_index}")

        # バイナリから音声を展開（長さを取得するためだけに読み込む）
        # ffmpegを呼ぶブロッキング処理なのでスレッドに逃がす
        audio = await asyncio.to_thread(AudioSegment.from_file, io.BytesIO(audio_bytes), format="m4a")
        actual_duration = len(audio) / 1000.0
        
        if not self.client:
            self.logger.log("   [Logic] ❌ Groq API credentials missing. Skipping transcription.")
            return {
                "text": "",
                "segments": [],
                "audio_duration": actual_duration
            }

        # ---------------------------------------------------------
        # ✨ Groq API への送信
        # ---------------------------------------------------------
        self.logger.log(f"   [Logic] Calling Groq Whisper API...")
        start_time = time.perf_counter()
        
        # Groq API は (ファイル名, バイナリ) のタプルでファイルデータを受け取る
        file_payload = (f"chunk_{chunk_index}.m4a", audio_bytes)
        result = await _call_groq_whisper(self.client, self.model, file_payload, prompt_keywords)
            
        elapsed_time = time.perf_counter() - start_time
        self.billing.add_time_cost("groq/whisper-large-v3-turbo", actual_duration, note="Audio transcription")
        self.billing.add_time_cost("cloudrun/self", elapsed_time, note="Whisper API wait time")

        full_text = getattr(result, "text", "").strip()
        segments_data = []

        # ---------------------------------------------------------
        # ✨ データの整形
        # ---------------------------------------------------------
        raw_segments = getattr(result, "segments", []) or []
        for i, seg in enumerate(raw_segments):
            seg_text = seg.get('text', '') if isinstance(seg, dict) else getattr(seg, 'text', '')
            start = seg.get('start', 0.0) if isinstance(seg, dict) else getattr(seg, 'start', 0.0)
            end = seg.get('end', 0.0) if isinstance(seg, dict) else getattr(seg, 'end', 0.0)
            logprob = seg.get('avg_logprob', 0.0) if isinstance(seg, dict) else getattr(seg, 'avg_logprob', 0.0)

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