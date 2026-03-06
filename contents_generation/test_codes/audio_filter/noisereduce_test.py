import time
import numpy as np
import soundfile as sf
import noisereduce as nr
import pyloudnorm as pyln
from pedalboard import Pedalboard, HighpassFilter


def load_mono_audio(input_file: str):
    """音声ファイルを読み込み、必要ならモノラル化する"""
    data, sr = sf.read(input_file)

    if data.ndim > 1:
        data = data.mean(axis=1)

    return data.astype(np.float32), sr


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


def apply_highpass_filter(data: np.ndarray, sr: int, cutoff_hz: float = 120.0):
    """
    低域ノイズを軽く落とす
    """
    board = Pedalboard([
        HighpassFilter(cutoff_frequency_hz=cutoff_hz),
    ])
    filtered = board(data, sr)
    return np.asarray(filtered, dtype=np.float32)


def finish_output_level(
    data: np.ndarray,
    peak_target: float = 0.95,
):
    """
    最終出力のピークを軽く整える
    """
    peak = np.max(np.abs(data))
    if peak > 0:
        data = data / peak * peak_target
    return data.astype(np.float32)


def run_noisereduce(
    data: np.ndarray,
    sr: int,
    output_file: str = "audio_noisereduce.wav",
    enable_preprocess_1: bool = True,   # pyloudnorm による前段ブースト
    enable_preprocess_2: bool = True,   # highpass filter
    enable_postprocess: bool = True,    # 最終ピーク調整
):
    print("🚀 [noisereduce] Running...")
    t0 = time.perf_counter()

    work_data = data.copy()

    # ==========================================
    # 前処理1: 音量が小さすぎるときだけ自動ブースト
    # ==========================================
    if enable_preprocess_1:
        work_data, orig_lufs, gain_db = loudness_boost_if_needed(
            work_data,
            sr,
            target_lufs=-26.0,
            max_gain_db=15.0,
        )
        print(f"🔊 Original loudness: {orig_lufs:.2f} LUFS")
        print(f"🔧 Applied loudness gain: {gain_db:.2f} dB")
    else:
        print("⏭️ Preprocess 1 skipped (loudness boost disabled)")

    # ==========================================
    # 前処理2: 軽いハイパス
    # ==========================================
    if enable_preprocess_2:
        work_data = apply_highpass_filter(work_data, sr, cutoff_hz=120.0)
        print("🎛️ Preprocess 2 applied (highpass filter)")
    else:
        print("⏭️ Preprocess 2 skipped (highpass filter disabled)")

    # ==========================================
    # メイン処理: noisereduce
    # ※ここはあなたの最適化済み設定を壊さずそのまま
    # ==========================================
    reduced_noise = nr.reduce_noise(
        y=work_data,
        sr=sr,
        stationary=True,
        prop_decrease=0.8,
        time_constant_s=1.0,
        freq_mask_smooth_hz=300,
        time_mask_smooth_ms=60
    )
    # ==========================================
    # 後処理: 出力のピークを軽く整える
    # ==========================================
    if enable_postprocess:
        output = finish_output_level(work_data, peak_target=0.8)
        print("📈 Postprocess applied (peak normalization)")
    else:
        output = work_data.astype(np.float32)
        print("⏭️ Postprocess skipped (peak normalization disabled)")

    sf.write(output_file, output, sr)

    elapsed = time.perf_counter() - t0
    print(f"✅ Saved to {output_file}")
    print(f"⏱️ Time taken: {elapsed:.3f} seconds")
    print("-" * 40)

    return elapsed


def main():
    input_file = "audio.wav"
    print(f"🎙️ Loading {input_file} ...")

    data, sr = load_mono_audio(input_file)

    elapsed = run_noisereduce(
        data,
        sr,
        output_file="audio_noisereduce.wav",
        enable_preprocess_1=True,
        enable_preprocess_2=True,
        enable_postprocess=True,
    )

    print("🎉 Processing completed!")
    print(f"📊 noisereduce: {elapsed:.3f}s")


if __name__ == "__main__":
    main()