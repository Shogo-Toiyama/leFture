import io
import math
import time
import os
import base64
import requests
from pydub import AudioSegment
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine

class TranscriptionService:
    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.logger = logger
        self.billing = billing
        self.account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID")
        self.api_key = os.getenv("CLOUDFLARE_API_KEY")
        self.model = "@cf/openai/whisper-large-v3-turbo"
        
        if not self.account_id or not self.api_key:
            self.logger.log("⚠️ CLOUDFLARE_ACCOUNT_ID or CLOUDFLARE_API_KEY is not set in environment variables.")

    def run_in_memory(self, audio_bytes: bytes, chunk_index: int, prompt_keywords: str = "") -> dict:
        """
        [究極のシンプルパイプライン]
        Flutterから送られてきた34秒（オーバーラップ込み）のRAWデータをBase64エンコードし、
        Cloudflare Workers AIのWhisper-large-v3-turboモデルに送信する。
        """
        self.logger.log(f"   [Logic] Loading audio into memory for chunk {chunk_index}")
        
        # バイナリから音声を展開（長さを取得するためだけに読み込む）
        audio = AudioSegment.from_file(io.BytesIO(audio_bytes), format="wav")
        actual_duration = len(audio) / 1000.0
        
        if not self.account_id or not self.api_key:
            self.logger.log("   [Logic] ❌ Cloudflare credentials missing. Skipping transcription.")
            return {
                "text": "",
                "segments": [],
                "audio_duration": actual_duration
            }

        # ---------------------------------------------------------
        # ✨ Cloudflare Workers AI への送信（Base64形式）
        # ---------------------------------------------------------
        self.logger.log(f"   [Logic] Calling Cloudflare Worker AI API directly...")
        start_time = time.perf_counter()
        
        try:
            # Base64エンコード
            audio_b64 = base64.b64encode(audio_bytes).decode("utf-8")
            url = f"https://api.cloudflare.com/client/v4/accounts/{self.account_id}/ai/run/{self.model}"
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            payload = {
                "audio": audio_b64,
                "language": "en",
            }
            if prompt_keywords:
                payload["initial_prompt"] = prompt_keywords

            response = requests.post(url, headers=headers, json=payload, timeout=60)
            if response.status_code != 200:
                raise Exception(f"HTTP {response.status_code}: {response.text}")
                
            res_json = response.json()
            if not res_json.get("success"):
                errors = res_json.get("errors", [])
                err_msg = errors[0].get("message") if errors else "Unknown error"
                raise Exception(f"Cloudflare AI Error: {err_msg}")
                
            result = res_json.get("result") or {}
            
        except Exception as e:
            self.logger.log(f"   [Logic] ❌ Cloudflare API Error: {e}")
            # APIエラー時は空データを返す
            return {
                "text": "",
                "segments": [],
                "audio_duration": actual_duration
            }
            
        elapsed_time = time.perf_counter() - start_time
        self.billing.add_time_cost("cloudflare/whisper-large-v3-turbo", actual_duration, note="Audio transcription")
        self.billing.add_time_cost("cloudrun/self", elapsed_time, note="Whisper API wait time")

        full_text = result.get("text", "").strip()
        segments_data = []

        # ---------------------------------------------------------
        # ✨ データの整形
        # ---------------------------------------------------------
        raw_segments = result.get("segments") or []
        for i, seg in enumerate(raw_segments):
            seg_text = seg.get('text', '')
            start = seg.get('start', 0.0)
            end = seg.get('end', 0.0)
            logprob = seg.get('avg_logprob', 0.0)

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