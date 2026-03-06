import time
import os
import tempfile

import numpy as np
import numpy as np
import pyloudnorm as pyln
import soundfile as sf
import noisereduce as nr
from pyrnnoise import RNNoise
from scipy.signal import resample_poly
from df.enhance import enhance, init_df, load_audio, save_audio
from pedalboard import Pedalboard, Compressor, HighpassFilter, Gain


def load_mono_audio(input_file: str):
    """音声ファイルを読み込み、必要ならモノラル化する"""
    data, sr = sf.read(input_file)

    if data.ndim > 1:
        data = data.mean(axis=1)

    return data.astype(np.float32), sr


def normalize_audio(data: np.ndarray):
    """最大振幅で正規化する（無音ならそのまま）"""
    max_amp = np.max(np.abs(data))
    if max_amp > 0.0:
        return data / max_amp * 0.95
    return data

def loudness_boost_if_needed(
    data: np.ndarray,
    sr: int,
    target_lufs: float = -26.0,
    max_gain_db: float = 15.0,
):
    """
    音量が小さすぎるときだけ、目標LUFSまで上限付きで持ち上げる
    """
    meter = pyln.Meter(sr)
    loudness = meter.integrated_loudness(data)

    gain_db = target_lufs - loudness
    gain_db = min(gain_db, max_gain_db)

    if gain_db <= 0:
        return data, loudness, 0.0

    boosted = data * (10 ** (gain_db / 20.0))

    # クリップ防止
    peak = np.max(np.abs(boosted))
    if peak > 0.99:
        boosted = boosted / peak * 0.99

    return boosted.astype(np.float32), loudness, gain_db


def run_noisereduce(data: np.ndarray, sr: int, output_file: str = "audio_noisereduce.wav"):
    print("🚀 [noisereduce] Running...")
    t0 = time.perf_counter()

    normalized = normalize_audio(data)
    reduced_noise = nr.reduce_noise(
        y=data,
        sr=sr,
        stationary=False,
        prop_decrease=0.65,
        time_constant_s=1.0,
        freq_mask_smooth_hz=300,
        time_mask_smooth_ms=60
    )

    sf.write(output_file, reduced_noise, sr)

    elapsed = time.perf_counter() - t0
    print(f"✅ Saved to {output_file}")
    print(f"⏱️ Time taken: {elapsed:.3f} seconds")
    print("-" * 40)

    return elapsed


def run_deepfilternet(data: np.ndarray, sr: int, output_file: str = "audio_deepfilter.wav", atten_lim_db: int = 6):
    print("🚀 [DeepFilterNet] Running...")
    t0 = time.perf_counter()

    normalized = normalize_audio(data)

    model, df_state, _ = init_df()

    # DeepFilterNet に読ませるため一時wavを書き出す
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        temp_input = tmp.name

    try:
        sf.write(temp_input, normalized, sr)

        audio_df, _ = load_audio(temp_input, sr=df_state.sr())
        enhanced_df = enhance(model, df_state, audio_df, atten_lim_db=atten_lim_db)

        save_audio(output_file, enhanced_df, df_state.sr())

    finally:
        if os.path.exists(temp_input):
            os.remove(temp_input)

    elapsed = time.perf_counter() - t0
    print(f"✅ Saved to {output_file}")
    print(f"⏱️ Time taken: {elapsed:.3f} seconds")
    print(f"🎛️ atten_lim_db = {atten_lim_db}")
    print("-" * 40)

    return elapsed


def run_pedalboard(data: np.ndarray, sr: int, output_file: str = "audio_pedalboard.wav"):
    print("🚀 [pedalboard] Running...")
    t0 = time.perf_counter()

    board = Pedalboard([
        HighpassFilter(cutoff_frequency_hz=120),
        Compressor(threshold_db=-24, ratio=2.0, attack_ms=10, release_ms=150),
        Gain(gain_db=6),
    ])

    effected_data = board(data, sr)
    sf.write(output_file, effected_data, sr)

    elapsed = time.perf_counter() - t0
    print(f"✅ Saved to {output_file}")
    print(f"⏱️ Time taken: {elapsed:.3f} seconds")
    print("-" * 40)

    return elapsed


def run_pyrnnoise(
    data: np.ndarray,
    sr: int,
    output_file: str = "audio_pyrnnoise.wav",
    wet: float = 0.7,   # 0.0 = 元音声そのまま, 1.0 = RNNoise全振り
):
    print("🚀 [pyrnnoise] Running...")
    t0 = time.perf_counter()

    data_rn = data.copy().astype(np.float32)

    # RNNoise は 48kHz 前提
    target_sr = 48000
    if sr != target_sr:
        data_48k = resample_poly(data_rn, target_sr, sr).astype(np.float32)
        sr_rn = target_sr
    else:
        data_48k = data_rn
        sr_rn = sr

    # 念のため振幅をクリップ
    data_48k = np.clip(data_48k, -1.0, 1.0)

    # 元音声を保持しておく（あとで混ぜ戻す）
    original_48k = data_48k.copy()

    # RNNoise 入力は int16
    data_int16 = (data_48k * 32767.0).astype(np.int16)
    audio_chunk = data_int16[np.newaxis, :]

    denoiser = RNNoise(sample_rate=sr_rn)

    out_frames = []
    speech_probs = []

    for speech_prob, denoised_frame in denoiser.denoise_chunk(audio_chunk):
        speech_probs.append(speech_prob)
        out_frames.append(denoised_frame)

    if not out_frames:
        raise RuntimeError("RNNoise produced no frames")

    denoised = np.concatenate(out_frames, axis=1)[0].astype(np.float32) / 32768.0

    # 長さを揃える
    min_len = min(len(original_48k), len(denoised))
    original_48k = original_48k[:min_len]
    denoised = denoised[:min_len]

    # ===== 緩め設定のキモ: wet/dry mix =====
    mixed = wet * denoised + (1.0 - wet) * original_48k

    # 念のため最終クリップ
    mixed = np.clip(mixed, -1.0, 1.0)

    sf.write(output_file, mixed, sr_rn)

    elapsed = time.perf_counter() - t0
    mean_speech_prob = float(np.mean(speech_probs)) if speech_probs else 0.0

    print(f"✅ Saved to {output_file}")
    print(f"⏱️ Time taken: {elapsed:.3f} seconds")
    print(f"🎚️ wet = {wet:.2f}")
    print(f"🗣️ Mean speech probability: {mean_speech_prob:.4f}")
    print("-" * 40)

    return elapsed


def main():
    input_file = "audio.wav"
    print(f"🎙️ Loading {input_file} ...")

    data, sr = load_mono_audio(input_file)

    results = {}

    results["noisereduce"] = run_noisereduce(data, sr)
    # results["DeepFilterNet"] = run_deepfilternet(data, sr, atten_lim_db=6)
    # results["pedalboard"] = run_pedalboard(data, sr)
    # results["pyrnnoise"] = run_pyrnnoise(data, sr, wet=0.6)

    print("🎉 Selected tests completed!")
    print("📊 Results:")
    for name, sec in results.items():
        print(f"  - {name}: {sec:.3f}s")


if __name__ == "__main__":
    main()