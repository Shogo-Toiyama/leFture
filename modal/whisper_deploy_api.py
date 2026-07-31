import asyncio
import math
import modal
from fastapi import UploadFile, File, Form

# ==========================================
# 1. Modalアプリと環境の定義
# ==========================================
app = modal.App("lefture-whisper-api")

image = (
    modal.Image.from_registry("nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04", add_python="3.11")
    .apt_install("ffmpeg")
    .pip_install("faster-whisper", "fastapi[standard]", "python-multipart")
    .run_commands(
      "python -c 'from faster_whisper import WhisperModel; WhisperModel(\"deepdml/faster-whisper-large-v3-turbo-ct2\")'"
  )
    # print()を即座にModalのログへ流すため、標準出力のバッファリングを無効化
    # (Cloud Run側のDockerfileと同じ理由。キャンセル等でコンテナが強制終了された際、
    # バッファに溜まったままのログが失われて原因調査ができなくなるのを防ぐ)
    .env({"PYTHONUNBUFFERED": "1"})
)

# ==========================================
# 2. クラスベースのAPI定義
# ==========================================
@app.cls(
    image=image,
    gpu="T4",
    scaledown_window=2,
    enable_memory_snapshot=True,
    experimental_options={"enable_gpu_snapshot": True},
    # デフォルト300秒だと3時間超のマスター音声で推論中に強制キャンセルされるため、
    # Cloud Run側のrequests.post timeout(1800秒)に合わせて延長。
    timeout=1800,
)
class WhisperAPI:
    
    @modal.enter(snap=True)
    def load_model(self):
        from faster_whisper import WhisperModel
        
        print("🔥 コンテナ起動: GPUメモリにモデルをロード中...")
        # compute_type="float16" で精度を保ちながらメモリ消費と速度を最適化！
        self.model = WhisperModel("deepdml/faster-whisper-large-v3-turbo-ct2", device="cuda", compute_type="float16")
        print("✅ ロード完了！いつでも推論できます。")

    def _get_duration_seconds(self, path: str) -> float:
        import subprocess

        proc = subprocess.run(
            [
                "ffprobe", "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                path,
            ],
            capture_output=True, text=True, check=True,
        )
        return float(proc.stdout.strip())

    def _extract_probe_clip(self, path: str, offset_seconds: float, clip_seconds: float = 30.0):
        """指定オフセットから約30秒だけをffmpegで直接切り出す(全体をデコードしない)。"""
        import subprocess
        import tempfile
        from faster_whisper.audio import decode_audio

        with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
            subprocess.run(
                [
                    "ffmpeg", "-y",
                    "-ss", str(max(0.0, offset_seconds)),
                    "-t", str(clip_seconds),
                    "-i", path,
                    "-ar", "16000", "-ac", "1", "-f", "wav",
                    tmp.name,
                ],
                capture_output=True, check=True,
            )
            return decode_audio(tmp.name)

    def _detect_language(
        self,
        path: str,
        duration: float,
        hint_language: str | None,
        confirm_threshold: float = 0.5,
    ) -> tuple[str, float]:
        """
        マスター音声全体からの言語判定。冒頭30秒だけを見る素朴なやり方は、
        講義の前に無関係な言語のイントロ(YouTube広告等)が入っていると
        引っ張られてしまうため、時系列に散らばった複数箇所をサンプリングする。

        録音言語の指定(hint_language)がある場合、まず全体の30%地点だけを見て、
        そこでの判定がhint_languageと一致し確信度も十分なら即確定する(実際に
        ユーザーの指定通りであるケースが大半なので、その場合は最小コストで済ませる)。
        一致しない/確信度不足の場合のみ、10/50/70/90%地点も追加でサンプリングし、
        5箇所の確信度を合算した上で最も合計スコアが高い言語を採用する。
        言語未指定(hint_language=None)の場合は、確認すべき対象が無いため
        最初から5箇所すべてをサンプリングする。
        """
        def probe_at(pct: float) -> tuple[str, float]:
            offset = duration * pct
            clip = self._extract_probe_clip(path, offset)
            lang, prob, _ = self.model.detect_language(audio=clip)
            return lang, prob

        # 言語ごとに (確信度の合計, サンプル数) を集計し、最終的には平均確信度を返す
        # (単純合計のままだと0〜1の確率という体裁が崩れるため)。
        score_sums: dict[str, float] = {}
        score_counts: dict[str, int] = {}

        def add_sample(lang: str, prob: float) -> None:
            score_sums[lang] = score_sums.get(lang, 0.0) + prob
            score_counts[lang] = score_counts.get(lang, 0) + 1

        if hint_language:
            lang_30, prob_30 = probe_at(0.30)
            print(f"   [LangDetect] 30%地点: {lang_30} ({prob_30:.3f})")
            if lang_30 == hint_language and prob_30 >= confirm_threshold:
                print(f"   [LangDetect] ✅ 指定言語({hint_language})と一致、確定")
                return lang_30, prob_30
            add_sample(lang_30, prob_30)
            remaining_pcts = [0.10, 0.50, 0.70, 0.90]
        else:
            remaining_pcts = [0.10, 0.30, 0.50, 0.70, 0.90]

        for pct in remaining_pcts:
            lang, prob = probe_at(pct)
            print(f"   [LangDetect] {int(pct * 100)}%地点: {lang} ({prob:.3f})")
            add_sample(lang, prob)

        final_lang = max(score_sums, key=score_sums.get)
        final_avg_prob = score_sums[final_lang] / score_counts[final_lang]
        print(
            f"   [LangDetect] 🏁 サンプル合計スコアで確定: {final_lang} "
            f"(avg_prob={final_avg_prob:.3f}, sums={score_sums}, counts={score_counts})"
        )
        return final_lang, final_avg_prob

    @modal.fastapi_endpoint(method="POST")
    async def transcribe(self, file: UploadFile = File(...), language: str | None = Form(None)):
        import time
        import tempfile

        start_time = time.time()
        print(f"🎙️ リクエスト受信: {file.filename} のトランスクライブを開始します...(language={language or 'auto'})")

        # FastAPI経由で送られてきた音声ファイルをバイトデータとして読み込み、
        # 一時ファイルに保存する(ffmpegでの部分切り出し・faster-whisperでの
        # デコード両方でシーク可能なファイルパスが必要なため)。
        audio_bytes = await file.read()
        try:
            with tempfile.NamedTemporaryFile(suffix=".m4a") as tmp_audio:
                tmp_audio.write(audio_bytes)
                tmp_audio.flush()

                duration = self._get_duration_seconds(tmp_audio.name)
                detected_language, detected_probability = self._detect_language(
                    tmp_audio.name, duration, hint_language=language or None,
                )

                # 推論実行（幻覚防止オプション付き）。言語は上で確定済みのものを明示的に渡す
                # (faster-whisper自身の内部判定は冒頭30秒しか見ないため使わない)。
                segments, info = self.model.transcribe(
                    tmp_audio.name,
                    beam_size=5,
                    language=detected_language,
                    condition_on_previous_text=False,
                    vad_filter=True,
                )

                # ★ segmentsはlazy generatorで、実際のデコードはここでの反復消費時に
                # 行われる。tempfileが閉じて削除される前(with文の中)で必ず使い切る。
                formatted_segments = []
                for i, segment in enumerate(segments, start=1):
                    confidence = math.exp(segment.avg_logprob)

                    formatted_segments.append({
                        "sid": f"s{i:06d}",
                        "text": segment.text.strip(),
                        "confidence": round(confidence, 4),
                        "start": round(segment.start, 2),
                        "end": round(segment.end, 2)
                    })
        except BaseException as e:
            # ★ modal-clientの「Received a cancellation signal」ログは理由を一切
            # 教えてくれないため、次に同じ現象が起きた時に原因を切り分けられるよう
            # ここで種類ごとに詳細を出す。CancelledErrorはPython 3.8+でBaseException
            # 継承なので、通常のexcept Exceptionでは素通りしてしまう点に注意。
            elapsed = time.time() - start_time
            error_type = type(e).__name__
            is_cancellation = isinstance(e, asyncio.CancelledError)
            looks_like_oom = any(
                kw in str(e).lower() for kw in ("out of memory", "oom", "cuda")
            )
            print(
                f"💥 [transcribe失敗] type={error_type} cancelled={is_cancellation} "
                f"oom疑い={looks_like_oom} 経過時間={elapsed:.1f}秒 "
                f"ファイル={file.filename} エラー内容={e}"
            )
            raise

        total_time = time.time() - start_time
        print(f"🚀 推論完了: {file.filename} (処理時間: {total_time:.2f}秒)")

        return {
            "processing_time_seconds": round(total_time, 2),
            "filename": file.filename,
            # info.language/info.language_probabilityは、languageを明示指定すると
            # 判定自体をスキップして確信度1.0の固定値になり無意味なため、代わりに
            # 事前判定(_detect_language)で実際に得たスコアをそのまま返す。
            "language": detected_language,
            "language_probability": round(detected_probability, 4),
            "segments": formatted_segments
        }