import math
import modal
from fastapi import UploadFile, File

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
)
class WhisperAPI:
    
    @modal.enter(snap=True)
    def load_model(self):
        from faster_whisper import WhisperModel
        
        print("🔥 コンテナ起動: GPUメモリにモデルをロード中...")
        # compute_type="float16" で精度を保ちながらメモリ消費と速度を最適化！
        self.model = WhisperModel("deepdml/faster-whisper-large-v3-turbo-ct2", device="cuda", compute_type="float16")
        print("✅ ロード完了！いつでも推論できます。")

    @modal.fastapi_endpoint(method="POST")
    async def transcribe(self, file: UploadFile = File(...)):
        import time
        import io
        
        start_time = time.time()
        print(f"🎙️ リクエスト受信: {file.filename} のトランスクライブを開始します...")
        
        # FastAPI経由で送られてきた音声ファイルをバイトデータとして読み込む
        audio_bytes = await file.read()
        audio_data = io.BytesIO(audio_bytes)
        
        # 推論実行（英語特化、幻覚防止オプション付き）
        segments, info = self.model.transcribe(
            audio_data, 
            beam_size=5, 
            language="en", 
            condition_on_previous_text=False,
            vad_filter=True,
        )
        
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

        total_time = time.time() - start_time
        print(f"🚀 推論完了: {file.filename} (処理時間: {total_time:.2f}秒)")
        
        return {
            "processing_time_seconds": round(total_time, 2),
            "filename": file.filename,
            "language": info.language,
            "language_probability": round(info.language_probability, 4),
            "segments": formatted_segments
        }