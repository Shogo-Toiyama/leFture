import io
import os
import math
import time  # 💡 [追加] 高精度タイマー用
import urllib.request
from pathlib import Path

import numpy as np
import onnxruntime as ort
from groq import Groq
from pydub import AudioSegment, effects

from app.services.helpers.helpers import print_log
from app.core.supabase import get_supabase_client

# =========================================================
# 🛠️ ヘルパー: Silero VAD (ONNX)
# =========================================================
def get_silero_vad_session():
    model_path = "silero_vad.onnx"
    opt = ort.SessionOptions()
    opt.log_severity_level = 3
    return ort.InferenceSession(str(model_path), sess_options=opt)


class TranscriptionDebugService:
    def __init__(self, collector=None):
        self.client = Groq()
        self.model = "whisper-large-v3-turbo"
        self.collector = collector
        self.vad_session = get_silero_vad_session()

    def _upload_debug_audio(self, lecture_id: str, chunk_index: int, step_name: str, audio: AudioSegment):
        supabase = get_supabase_client()
        file_name = f"chunk_{chunk_index}_{step_name}.wav"
        storage_path = f"debug/{lecture_id}/{file_name}"
        
        io_buf = io.BytesIO()
        audio.export(io_buf, format="wav")
        io_buf.seek(0)
        
        supabase.storage.from_("lecture_assets").upload(
            path=storage_path,
            file=io_buf.read(),
            file_options={"upsert": "true", "contentType": "audio/wav"}
        )

    def _upload_debug_text(self, lecture_id: str, chunk_index: int, text_content: str):
        supabase = get_supabase_client()
        file_name = f"chunk_{chunk_index}_vad_log.txt"
        storage_path = f"debug/{lecture_id}/{file_name}"
        
        supabase.storage.from_("lecture_assets").upload(
            path=storage_path,
            file=text_content.encode("utf-8"),
            file_options={"upsert": "true", "contentType": "text/plain"}
        )

    # 💡 [追加] タイマー結果を整形するヘルパー
    def _generate_timing_report(self, timings: dict, total_start_time: float) -> str:
        s = "\n\n" + "="*50 + "\n"
        s += "⏱️ Execution Timings (High-Res CPU Time)\n"
        s += "="*50 + "\n"
        for step, duration in timings.items():
            s += f"{step:<25}: {duration*1000:8.2f} ms\n"
        s += "-"*50 + "\n"
        total_time = time.perf_counter() - total_start_time
        s += f"{'Total Function Time':<25}: {total_time*1000:8.2f} ms\n"
        return s

    def run_in_memory_debug(self, lecture_id: str, audio_bytes: bytes, chunk_index: int, prompt_keywords: str = "") -> dict:
        t_total_start = time.perf_counter()
        timings = {}
        
        print_log(f"   [Logic] Loading audio into memory for chunk {chunk_index}")
        
        # ⏱️ 1. メモリ展開の計測
        t0 = time.perf_counter()
        audio = AudioSegment.from_file(io.BytesIO(audio_bytes), format="wav")
        actual_duration = len(audio) / 1000.0
        timings["1_memory_load"] = time.perf_counter() - t0
        self._upload_debug_audio(lecture_id, chunk_index, "1_original", audio)
        
        # ⏱️ 2. 帯域通過フィルターの計測
        # print_log(f"   [Logic] Applying Bandpass Filter (100Hz - 4000Hz)...")
        # t0 = time.perf_counter()
        # audio = audio.high_pass_filter(100).low_pass_filter(4000)
        # timings["2_bandpass_filter"] = time.perf_counter() - t0
        # self._upload_debug_audio(lecture_id, chunk_index, "2_bandpass", audio)
        
        # ⏱️ 3. ノーマライズの計測
        # print_log(f"   [Logic] Applying Normalization...")
        # t0 = time.perf_counter()
        # audio = effects.normalize(audio)
        # timings["3_normalization"] = time.perf_counter() - t0
        # self._upload_debug_audio(lecture_id, chunk_index, "3_normalized", audio)

        # ⏱️ 4. Silero VAD (v5) の計測
        print_log(f"   [Logic] Running Silero VAD...")
        t0 = time.perf_counter()
        audio_16k = audio.set_frame_rate(16000).set_channels(1).set_sample_width(2)
        samples = np.array(audio_16k.get_array_of_samples(), dtype=np.float32) / 32768.0
        
        window_size = 512
        state = np.zeros((2, 1, 128), dtype=np.float32)
        probs = []
        
        for i in range(0, len(samples), window_size):
            chunk = samples[i:i+window_size]
            if len(chunk) < window_size:
                chunk = np.pad(chunk, (0, window_size - len(chunk)))
                
            inputs = {
                "input": chunk.reshape(1, window_size),
                "sr": np.array([16000], dtype=np.int64),
                "state": state
            }
            ort_outs = self.vad_session.run(None, inputs)
            probs.append(ort_outs[0][0][0])
            state = ort_outs[1]
            
        timings["4_vad_inference"] = time.perf_counter() - t0

        # ASCIIグラフ化
        windows_per_half_sec = int(16000 * 0.5 / window_size)
        ascii_log = f"VAD Probability Log for Chunk {chunk_index}\n"
        ascii_log += "="*50 + "\n"
        
        for i in range(0, len(probs), windows_per_half_sec):
            chunk_probs = probs[i:i+windows_per_half_sec]
            if not chunk_probs: continue
            avg_prob = sum(chunk_probs) / len(chunk_probs)
            sec = (i * window_size) / 16000.0
            bar_length = int(avg_prob * 50)
            bar = "#" * bar_length
            ascii_log += f"{sec:05.2f}s - {avg_prob:.3f} | {bar}\n"

        # ヒステリシス判定
        start_idx = -1
        end_idx = -1
        for i, p in enumerate(probs):
            if p > 0.5:
                start_idx = i
                break
                
        if start_idx != -1:
            for i in range(len(probs)-1, -1, -1):
                if probs[i] > 0.15:
                    end_idx = i
                    break

        if start_idx == -1 or start_idx >= end_idx:
            print_log(f"   [Logic] 🔇 No human speech detected in chunk {chunk_index}. Skipping Groq.")
            # 💡 [無音時] ログにタイマー結果を足してアップロードし、終了
            ascii_log += self._generate_timing_report(timings, t_total_start)
            self._upload_debug_text(lecture_id, chunk_index, ascii_log)
            return {"text": "", "segments": [], "audio_duration": actual_duration}

        # ⏱️ 5. クロップ＆バイト変換の計測
        t0 = time.perf_counter()
        start_ms = max(0, (start_idx * window_size / 16000.0) * 1000 - 500)
        end_ms = min(len(audio), (end_idx * window_size / 16000.0) * 1000 + 500)
        offset_seconds = start_ms / 1000.0
        cropped_audio = audio[start_ms:end_ms]
        
        cropped_io = io.BytesIO()
        cropped_audio.export(cropped_io, format="wav")
        cropped_bytes = cropped_io.getvalue()
        timings["5_crop_and_export"] = time.perf_counter() - t0
        
        self._upload_debug_audio(lecture_id, chunk_index, "4_final_cropped", cropped_audio)
        
        # ⏱️ 6. Groq APIの計測（ネットワーク時間込み）
        print_log(f"   [Logic] Calling Groq API...")
        t0 = time.perf_counter()
        res = self.client.audio.transcriptions.create(
            file=(f"chunk_{chunk_index}.wav", cropped_bytes),
            model=self.model,
            response_format="verbose_json",
            language="en",
            prompt=prompt_keywords
        )
        timings["6_groq_api_call"] = time.perf_counter() - t0

        # 💡 [完了時] ログにタイマー結果を足してアップロード
        ascii_log += self._generate_timing_report(timings, t_total_start)
        self._upload_debug_text(lecture_id, chunk_index, ascii_log)

        # (以下、データの整形 ＆ オフセット計算は変更なしのため省略せずにそのまま残してください！)
        full_text = res.text.strip()
        segments_data = []

        if hasattr(res, 'segments') and res.segments:
            for i, seg in enumerate(res.segments):
                seg_text = seg.get('text', '') if isinstance(seg, dict) else getattr(seg, 'text', '')
                start = seg.get('start', 0.0) if isinstance(seg, dict) else getattr(seg, 'start', 0.0)
                end = seg.get('end', 0.0) if isinstance(seg, dict) else getattr(seg, 'end', 0.0)
                logprob = seg.get('avg_logprob', 0) if isinstance(seg, dict) else getattr(seg, 'avg_logprob', 0)

                confidence = max(0.0, min(1.0, math.exp(logprob)))
                if confidence < 0.1:
                    continue

                segments_data.append({
                    "sid": f"s{chunk_index:03d}{i+1:03d}",
                    "text": seg_text.strip(),
                    "confidence": round(confidence, 4),
                    "start": round(start + offset_seconds, 3),
                    "end": round(end + offset_seconds, 3),
                    "chunk_index": chunk_index
                })

        if not segments_data and full_text:
            segments_data.append({
                "sid": f"s{chunk_index:03d}001",
                "text": full_text,
                "confidence": 0.99,
                "start": round(offset_seconds, 3),
                "end": round(offset_seconds + (len(cropped_audio)/1000.0), 3),
                "chunk_index": chunk_index
            })

        return {"text": full_text, "segments": segments_data, "audio_duration": actual_duration}