import modal
from fastapi import Response

# ==========================================
# 1. Modalアプリと環境の定義
# ==========================================
app = modal.App("lefture-kokoro-tts")

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("espeak-ng", "wget")
    .pip_install(
        "kokoro-onnx",
        "soundfile",
        "fastapi[standard]",
        "onnxruntime"
    )
    .run_commands(
        "mkdir -p /kokoro",
        # 💡 改善①：int8をやめ、CPUが一番得意な「標準モデル（fp32 / 330MB）」を使用！
        "wget -q -O /kokoro/kokoro-v1.0.onnx https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx",
        "wget -q -O /kokoro/voices-v1.0.bin https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin",
    )
)

# ==========================================
# 2. クラスベースのAPI定義
# ==========================================
@app.cls(
    image=image,
    cpu=4,                       
    memory=2048,                 
    scaledown_window=60,         
    enable_memory_snapshot=True, 
)
class KokoroTTSAPI:

    @modal.enter(snap=True)
    def load_model(self):
        import onnxruntime as rt
        from kokoro_onnx import Kokoro

        print("🔥 コンテナ起動: Kokoro ONNX モデルをロード中（スナップショット作成）...")

        # 💡 改善②：スレッド暴走を完全に阻止する！
        # ONNXに「Modalで割り当てた4コアだけを使え」と強制命令を下します。
        sess_options = rt.SessionOptions()
        sess_options.intra_op_num_threads = 4  # cpu=4 に一致させる
        sess_options.inter_op_num_threads = 4
        # CPU向けのグラフ最適化をフル稼働
        sess_options.graph_optimization_level = rt.GraphOptimizationLevel.ORT_ENABLE_ALL

        # セッションに設定を適応して生成
        session = rt.InferenceSession(
            "/kokoro/kokoro-v1.0.onnx",
            sess_options=sess_options,
            providers=["CPUExecutionProvider"]
        )

        self.kokoro = Kokoro.from_session(session, "/kokoro/voices-v1.0.bin")
        print("✅ ロード完了！真の最適化CPU構成で推論します。")

    @modal.fastapi_endpoint(method="POST")
    def synthesize(self, data: dict):
        import io
        import time
        import soundfile as sf

        start_time = time.time()
        text: str = data.get("text", "")
        voice: str = data.get("voice", "af_heart")
        speed: float = float(data.get("speed", 1.0))
        lang: str = data.get("lang", "en-us") 

        if not text.strip():
            return Response(content=b'{"error": "text is empty"}', status_code=400)

        print(f"🗣️ リクエスト受信: voice={voice}, speed={speed}, text={text[:50]}...")

        try:
            samples, sample_rate = self.kokoro.create(text, voice=voice, speed=speed, lang=lang)
        except Exception as e:
            return Response(content=f'{{"error": "{str(e)}"}}'.encode(), status_code=500)

        wav_buffer = io.BytesIO()
        sf.write(wav_buffer, samples, sample_rate, format="WAV")

        total_time = time.time() - start_time
        audio_duration = len(samples) / sample_rate
        rtf = total_time / audio_duration if audio_duration > 0 else 0

        print(f"🚀 推論完了: {audio_duration:.1f}秒の音声を {total_time:.2f}秒で生成 (RTF={rtf:.3f})")

        return Response(
            content=wav_buffer.getvalue(),
            media_type="audio/wav",
            headers={"X-Processing-Time": f"{total_time:.3f}"}
        )