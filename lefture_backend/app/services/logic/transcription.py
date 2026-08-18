import io
import math
import time
import os
import base64
import asyncio
import subprocess
import requests
from pathlib import Path
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential_jitter
from pydub import AudioSegment
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine


class _RetryableCloudflareError(Exception):
    """429/5xx等、リトライすれば成功する見込みがあるCloudflare APIエラー。"""
    pass


async def _get_audio_duration_seconds(path: Path) -> float:
    """
    ffprobeでコンテナのヘッダのみを読み、音声の長さを取得する。
    AudioSegment.from_file()のようにPCMへフルデコードしないため、
    3時間超のマスター音声でもメモリ使用量はほぼゼロで済む。
    """
    proc = await asyncio.to_thread(
        subprocess.run,
        [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture_output=True, text=True, check=True,
    )
    return float(proc.stdout.strip())


@retry(
    retry=retry_if_exception_type((_RetryableCloudflareError, requests.exceptions.RequestException)),
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(initial=1, max=8),
    reraise=True,
)
async def _call_cloudflare_whisper(url: str, headers: dict, payload: dict) -> dict:
    """
    Cloudflare Whisper APIを呼び出す。429/5xx/接続エラーは指数バックオフ＋ジッターで
    リトライし、400等のクライアントエラーはリトライしても無駄なのでそのまま送出する。
    """
    response = await asyncio.to_thread(requests.post, url, headers=headers, json=payload, timeout=60)

    if response.status_code == 429 or response.status_code >= 500:
        raise _RetryableCloudflareError(f"HTTP {response.status_code}: {response.text}")
    if response.status_code != 200:
        raise Exception(f"HTTP {response.status_code}: {response.text}")

    res_json = response.json()
    if not res_json.get("success"):
        errors = res_json.get("errors", [])
        err_msg = errors[0].get("message") if errors else "Unknown error"
        raise Exception(f"Cloudflare AI Error: {err_msg}")

    return res_json.get("result") or {}


class TranscriptionService:
    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.logger = logger
        self.billing = billing
        self.account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID")
        self.api_key = os.getenv("CLOUDFLARE_API_KEY")
        self.model = "@cf/openai/whisper-large-v3-turbo"
        
        if not self.account_id or not self.api_key:
            self.logger.log("⚠️ CLOUDFLARE_ACCOUNT_ID or CLOUDFLARE_API_KEY is not set in environment variables.")

    async def run_in_memory(self, audio_bytes: bytes, chunk_index: int, prompt_keywords: str = "") -> dict:
        """
        [究極のシンプルパイプライン]
        Flutterから送られてきた34秒（オーバーラップ込み）のM4A(AAC)データをBase64エンコードし、
        Cloudflare Workers AIのWhisper-large-v3-turboモデルに送信する。

        言語は常にCloudflare側の自動判定に任せる(languageパラメータを渡さない)。
        以前はlectures.recording_languageをヒントとして渡していたが、Cloudflareの
        Whisperには「ヒントが実際の音声と違う場合にフォールバックする」機構が無く
        (Modal側のModalTranscriptionServiceとは異なる)、強制した言語が間違って
        いると文字起こしそのものが破綻する。実測でも(language未指定のまま)
        confidence 1.0で正しく自動判定できることを確認済みなので、常に自動判定に
        統一する方が安全。実際に検出された言語はレスポンスの
        transcription_info.languageから取得し、呼び出し側がDBへ保存する。
        """
        self.logger.log(f"   [Logic] Loading audio into memory for chunk {chunk_index}")

        # バイナリから音声を展開（長さを取得するためだけに読み込む）
        # ffmpegを呼ぶブロッキング処理なのでスレッドに逃がす
        audio = await asyncio.to_thread(AudioSegment.from_file, io.BytesIO(audio_bytes), format="m4a")
        actual_duration = len(audio) / 1000.0
        
        if not self.account_id or not self.api_key:
            self.logger.log("   [Logic] ❌ Cloudflare API credentials missing. Skipping transcription.")
            return {
                "text": "",
                "segments": [],
                "audio_duration": actual_duration,
                "detected_language": None,
            }

        # ---------------------------------------------------------
        # ✨ Cloudflare Workers AI への送信（Base64形式）
        # ---------------------------------------------------------
        self.logger.log(f"   [Logic] Calling Cloudflare Worker AI API directly...")
        start_time = time.perf_counter()
        
        # Base64エンコード
        audio_b64 = base64.b64encode(audio_bytes).decode("utf-8")
        url = f"https://api.cloudflare.com/client/v4/accounts/{self.account_id}/ai/run/{self.model}"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "audio": audio_b64,
        }
        if prompt_keywords:
            payload["initial_prompt"] = prompt_keywords

        # ⚠️ 例外はキャッチせず伝播させることで、エラー時はちゃんとエラーステータスになってリトライされるようにする
        result = await _call_cloudflare_whisper(url, headers, payload)
            
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
            "audio_duration": actual_duration,
            # 無音などでtranscription_info自体が返らない場合に備えてNoneフォールバック。
            "detected_language": (result.get("transcription_info") or {}).get("language"),
        }


class ModalTranscriptionService:
    """ローカル Modal 上の Faster Whisper を使用するトランスクリプション（プレレコ用）"""

    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.logger = logger
        self.billing = billing
        self.modal_api_url = os.getenv("MODAL_WHISPER_URL")

        if not self.modal_api_url:
            self.logger.log("⚠️ MODAL_WHISPER_URL is not set in environment variables.")

    async def transcribe_file(self, audio_path: Path, chunk_index: int, prompt_keywords: str = "", language: str | None = None) -> dict:
        """
        ローカル Modal 上の Faster Whisper にマスターオーディオを送信する。
        Cloudflare 形式のレスポンスに統一して返す。

        マスター音声は3時間超に及ぶこともあるため、音声全体を`bytes`として
        メモリに載せない。長さの取得はffprobe（ヘッダのみ読む）で行い、
        Modalへのアップロードもディスク上のファイルをストリーミングで送信する。
        """
        self.logger.log(f"   [Logic] Reading audio duration via ffprobe (no full decode)")
        actual_duration = await _get_audio_duration_seconds(audio_path)

        if not self.modal_api_url:
            self.logger.log("   [Logic] ❌ MODAL_WHISPER_URL not configured.")
            raise ValueError("MODAL_WHISPER_URL environment variable is not set!")

        self.logger.log(f"   [Logic] Calling Modal Faster Whisper API (streaming upload)...")
        start_time = time.perf_counter()

        try:
            # Modal API にマルチパート形式でファイルを送信
            # language未指定ならdataフィールド自体を送らず、Modal側のデフォルト(自動言語判定)に任せる
            form_data = {"language": language} if language else None

            def _post() -> requests.Response:
                # ファイルオブジェクトを渡すことでrequestsがディスクからチャンク単位で
                # ストリーミング送信する（audio_bytesを丸ごとメモリに載せない）
                with open(audio_path, "rb") as f:
                    return requests.post(
                        self.modal_api_url,
                        files={"file": (audio_path.name, f, "audio/mpeg")},
                        data=form_data,
                        timeout=1800,  # 3時間超のマスター音声の推論待ちに耐えられるよう延長
                    )

            response = await asyncio.to_thread(_post)

            if response.status_code != 200:
                raise Exception(f"Modal API HTTP {response.status_code}: {response.text}")

            result = response.json()
            elapsed_time = time.perf_counter() - start_time

            # 💰 Modal 使用時のコスト計上 (Modalの純粋なGPU時間 ＋ スケールダウン待機時間2秒)
            gpu_time = result.get('processing_time_seconds', 0.0) + 2.0
            self.billing.add_time_cost("modal/t4", gpu_time, note="Whisper GPU processing (incl. scaledown)")
            self.billing.add_time_cost("cloudrun/self", elapsed_time, note="Modal API wait time")

            # ---------------------------------------------------------
            # ✨ Modal (Faster Whisper) のレスポンスを Cloudflare 形式に統一
            # ---------------------------------------------------------
            # Modal は既に Cloudflare 形式で segments を返す
            # ただし、confidence の値をそのまま使用し、chunk_index を追加する
            raw_segments = result.get("segments") or []
            segments_data = []

            for seg in raw_segments:
                seg_text = seg.get('text', '')
                start = seg.get('start', 0.0)
                end = seg.get('end', 0.0)
                confidence = seg.get('confidence', 0.99)

                # Cloudflare と同じく、confidence が低すぎるセグメントは除外
                if confidence < 0.1:
                    continue

                # Modal が返す sid をそのまま使用、chunk_index を追加
                sid = seg.get('sid', '')
                segments_data.append({
                    "sid": sid,
                    "text": seg_text.strip(),
                    "confidence": round(confidence, 4),
                    "start": round(start, 3),
                    "end": round(end, 3),
                    "chunk_index": chunk_index
                })

            # segments から全体のテキストを組み立てる
            full_text = " ".join([seg.get('text', '') for seg in segments_data]).strip()

            # 音声が短すぎてセグメントが分かれなかった場合の安全策
            if not segments_data:
                self.logger.log(f"   [Logic] 🔇 No speech detected by Modal Whisper.")

            return {
                "text": full_text,
                "segments": segments_data,
                "audio_duration": actual_duration,
                # Modal側は既にhint_languageの検証→不一致なら自動判定、まで
                # やった上でこの値を返している(modal/whisper_deploy_api.py参照)。
                "detected_language": result.get("language"),
            }

        except (Exception, asyncio.CancelledError) as e:
            # asyncio.CancelledErrorはPython 3.8+でBaseExceptionを継承しているため、
            # 明示的に拾わないとログ・ステータス更新が素通りされて詰まる原因になる。
            self.logger.log(f"   [Logic] ❌ Modal API error: {e}")
            raise