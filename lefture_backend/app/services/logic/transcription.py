import io
import os
import math
import urllib.request
from pathlib import Path

import numpy as np
import onnxruntime as ort
from groq import Groq
from pydub import AudioSegment, effects
from app.services.helpers.helpers import print_log

# =========================================================
# 🛠️ ヘルパー: Silero VAD (ONNX) の初期化
# =========================================================
def get_silero_vad_session():
    model_path = "silero_vad.onnx"
    opt = ort.SessionOptions()
    opt.log_severity_level = 3
    return ort.InferenceSession(str(model_path), sess_options=opt)


def get_wav_duration(file_path: Path) -> float:
    # (既存のコードのまま) ファイルから読み込む場合の保険用
    import contextlib, wave
    try:
        with contextlib.closing(wave.open(str(file_path), 'r')) as f:
            frames = f.getnframes()
            rate = f.getframerate()
            return frames / float(rate)
    except Exception as e:
        print_log(f"⚠️ Failed to get audio duration: {e}")
        return 0.0


class TranscriptionService:
    def __init__(self, collector=None):
        self.client = Groq()
        self.model = "whisper-large-v3-turbo"
        self.collector = collector
        
        # コンテナ起動時にVADモデルをメモリにロード（コールドスタート対策）
        self.vad_session = get_silero_vad_session()

    def run_in_memory(self, audio_bytes: bytes, chunk_index: int) -> dict:
        """
        [最強の音声処理パイプライン]
        1. 帯域通過フィルター (Bandpass)
        2. ノーマライズ (AGC)
        3. Silero VAD (AIベースの無音・ノイズ判定)
        4. クロップ＆オフセット補正して Groq へ
        """
        print_log(f"   [Logic] Loading audio into memory for chunk {chunk_index}")
        
        # 1. バイナリから音声を展開
        audio = AudioSegment.from_file(io.BytesIO(audio_bytes), format="wav")
        actual_duration = len(audio) / 1000.0
        
        # ---------------------------------------------------------
        # ✨ 前処理 1: 帯域通過フィルター (Bandpass Filter)
        # ---------------------------------------------------------
        # 200Hz以下(エアコンの重低音、マイクの振動) と 
        # 3000Hz以上(キーンというノイズ) をスッパリ切り落とす
        print_log(f"   [Logic] Applying Bandpass Filter (200Hz - 3000Hz)...")
        audio = audio.high_pass_filter(200).low_pass_filter(3000)
        
        # ---------------------------------------------------------
        # ✨ 前処理 2: ノーマライズ (音量均一化)
        # ---------------------------------------------------------
        print_log(f"   [Logic] Applying Normalization...")
        audio = effects.normalize(audio)

        # ---------------------------------------------------------
        # ✨ 前処理 3: Silero VAD による AI 声判定
        # ---------------------------------------------------------
        print_log(f"   [Logic] Running Silero VAD...")
        
        # VADの仕様に合わせて、16kHz, モノラル, Float32のNumpy配列に変換
        audio_16k = audio.set_frame_rate(16000).set_channels(1)
        samples = np.array(audio_16k.get_array_of_samples(), dtype=np.float32) / 32768.0
        
        window_size = 512 # 1回の判定サイズ (16000Hzで32ms)
        h = np.zeros((2, 1, 64), dtype=np.float32)
        c = np.zeros((2, 1, 64), dtype=np.float32)
        
        probs = []
        # 音声を32msごとに区切って「声の確率(0.0~1.0)」を計算
        for i in range(0, len(samples), window_size):
            chunk = samples[i:i+window_size]
            if len(chunk) < window_size:
                chunk = np.pad(chunk, (0, window_size - len(chunk)))
                
            inputs = {
                "input": chunk.reshape(1, window_size),
                "sr": np.array([16000], dtype=np.int64),
                "h": h,
                "c": c
            }
            ort_outs = self.vad_session.run(None, inputs)
            probs.append(ort_outs[0][0][0]) # 確率を保存
            h, c = ort_outs[1], ort_outs[2] # 次の文脈に引き継ぐ

        # [ヒステリシス・ロジック] 0.5を超えたら開始、最後に0.15を上回った場所を終了とする
        start_idx = -1
        end_idx = -1
        
        for i, p in enumerate(probs):
            if p > 0.5:
                start_idx = i
                break
                
        if start_idx != -1:
            for i in range(len(probs)-1, -1, -1):
                if probs[i] > 0.15: # 0.15までは声の余韻として許容する
                    end_idx = i
                    break

        # もし「人間の声」が一度も0.5を超えなかった場合（チョークやドアの音のみ）
        if start_idx == -1 or start_idx >= end_idx:
            print_log(f"   [Logic] 🔇 No human speech detected in chunk {chunk_index} (AI VAD). Skipping Groq.")
            return {
                "text": "",
                "segments": [],
                "audio_duration": actual_duration
            }

        # クロップ範囲の決定 (前後に0.5秒 = 500ms のパディングを持たせる)
        start_ms = max(0, (start_idx * window_size / 16000.0) * 1000 - 500)
        end_ms = min(len(audio), (end_idx * window_size / 16000.0) * 1000 + 500)
        
        offset_seconds = start_ms / 1000.0
        cropped_audio = audio[start_ms:end_ms]
        
        print_log(f"   [Logic] ✂️ Cropped audio: {start_ms:.0f}ms to {end_ms:.0f}ms (Offset: +{offset_seconds:.2f}s)")

        # ---------------------------------------------------------
        # Promptを加工
        # ---------------------------------------------------------

        # いまは一旦固定キーワード
        prompt_keywords = "UCLA, lecture, Computer Science, Architecture, Programming Languages, Git, Turring Machine"

        
        # ---------------------------------------------------------
        # ✨ Groq Whisper への送信
        # ---------------------------------------------------------
        cropped_io = io.BytesIO()
        cropped_audio.export(cropped_io, format="wav")
        cropped_bytes = cropped_io.getvalue()
        
        print_log(f"   [Logic] Calling Groq API...")
        res = self.client.audio.transcriptions.create(
            file=(f"chunk_{chunk_index}.wav", cropped_bytes),
            model=self.model,
            response_format="verbose_json",
            language="en",
            prompt=prompt_keywords
        )

        full_text = res.text.strip()
        segments_data = []

        # ---------------------------------------------------------
        # ✨ データの整形 ＆ オフセット計算
        # ---------------------------------------------------------
        if hasattr(res, 'segments') and res.segments:
            for i, seg in enumerate(res.segments):
                seg_text = seg.get('text', '') if isinstance(seg, dict) else getattr(seg, 'text', '')
                start = seg.get('start', 0.0) if isinstance(seg, dict) else getattr(seg, 'start', 0.0)
                end = seg.get('end', 0.0) if isinstance(seg, dict) else getattr(seg, 'end', 0.0)
                logprob = seg.get('avg_logprob', 0) if isinstance(seg, dict) else getattr(seg, 'avg_logprob', 0)

                # 💡 [作戦の反映] Confidenceが低すぎる(0.1以下)場合はハルシネーションの可能性が高い
                confidence = max(0.0, min(1.0, math.exp(logprob)))
                if confidence < 0.1:
                    continue

                real_start = start + offset_seconds
                real_end = end + offset_seconds
                sid = f"s{chunk_index:03d}{i+1:03d}"

                segments_data.append({
                    "sid": sid,
                    "text": seg_text.strip(),
                    "confidence": round(confidence, 4),
                    "start": round(real_start, 3),
                    "end": round(real_end, 3),
                    "chunk_index": chunk_index
                })

        # 音声が短すぎてセグメントが分かれなかった場合の安全策
        if not segments_data and full_text:
            segments_data.append({
                "sid": f"s{chunk_index:03d}001",
                "text": full_text,
                "confidence": 0.99,
                "start": round(offset_seconds, 3),
                "end": round(offset_seconds + (len(cropped_audio)/1000.0), 3),
                "chunk_index": chunk_index
            })

        return {
            "text": full_text,
            "segments": segments_data,
            "audio_duration": actual_duration
        }