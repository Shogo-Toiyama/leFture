"""
Silero VAD (v5 ONNX) テストスクリプト
音声ファイルを指定して、VAD確率の時系列変化を確認する
"""

import sys
import numpy as np
import onnxruntime as ort
from pydub import AudioSegment

# =========================================================
# 設定
# =========================================================
AUDIO_FILE = "./audio.wav"   # ← テストしたい音声ファイルを指定
VAD_MODEL  = "./silero_vad.onnx"

WINDOW_SIZE   = 512          # VADに渡す1チャンクのサンプル数（固定）
CONTEXT_SIZE  = 64           # v5の前文脈サイズ（固定）
SAMPLE_RATE   = 16000        # Silero VAD は 16kHz 固定

DISPLAY_INTERVAL_MS = 500    # グラフ表示の集計単位（ms）
SPEECH_THRESHOLD    = 0.5    # 発話とみなす確率のしきい値
SILENCE_THRESHOLD   = 0.15   # 発話終了とみなす確率のしきい値

# =========================================================
# メイン処理
# =========================================================
def run_vad_test(audio_file: str):
    print(f"\n🎙️  Loading: {audio_file}")

    # --- 音声読み込み & 16kHz モノラル変換 ---
    audio = AudioSegment.from_file(audio_file)
    audio_16k = audio.set_frame_rate(SAMPLE_RATE).set_channels(1).set_sample_width(2)
    samples = np.array(audio_16k.get_array_of_samples(), dtype=np.float32) / 32768.0
    duration_sec = len(samples) / SAMPLE_RATE

    print(f"📊 Duration  : {duration_sec:.2f} sec")
    print(f"📊 Samples   : {len(samples)}")
    print(f"📊 Interval  : {DISPLAY_INTERVAL_MS} ms ごとに集計")
    print()

    # --- ONNX モデルの自動ダウンロード ---
    import urllib.request
    from pathlib import Path

    if not Path(VAD_MODEL).exists():
        url = "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
        print(f"📥 モデルが見つかりません。ダウンロード中...")
        print(f"   URL: {url}")
        urllib.request.urlretrieve(url, VAD_MODEL)
        print(f"✅ 保存しました: {VAD_MODEL}\n")

    # --- ONNX セッション ---
    opt = ort.SessionOptions()
    opt.log_severity_level = 3
    session = ort.InferenceSession(VAD_MODEL, sess_options=opt)

    # --- VAD 推論ループ ---
    state   = np.zeros((2, 1, 128), dtype=np.float32)
    context = np.zeros(CONTEXT_SIZE, dtype=np.float32)
    probs   = []

    for i in range(0, len(samples), WINDOW_SIZE):
        chunk = samples[i:i + WINDOW_SIZE]
        if len(chunk) < WINDOW_SIZE:
            chunk = np.pad(chunk, (0, WINDOW_SIZE - len(chunk)))

        chunk_with_context = np.concatenate([context, chunk])

        inputs = {
            "input": chunk_with_context.reshape(1, WINDOW_SIZE + CONTEXT_SIZE),
            "sr"   : np.array(SAMPLE_RATE, dtype=np.int64),
            "state": state,
        }
        outs  = session.run(None, inputs)
        probs.append(float(outs[0][0][0]))
        state   = outs[1]
        context = chunk_with_context[-CONTEXT_SIZE:]

    # --- ASCII グラフ表示 ---
    windows_per_interval = max(1, int(SAMPLE_RATE * (DISPLAY_INTERVAL_MS / 1000) / WINDOW_SIZE))

    print("=" * 65)
    print(f"  VAD Probability  |  {DISPLAY_INTERVAL_MS}ms ごとの平均")
    print("=" * 65)
    print(f"  {'時刻':>7}  {'確率':>5}  グラフ (0.0 ─────────────── 1.0)")
    print("-" * 65)

    for i in range(0, len(probs), windows_per_interval):
        chunk_probs = probs[i:i + windows_per_interval]
        if not chunk_probs:
            continue
        avg = sum(chunk_probs) / len(chunk_probs)
        sec = (i * WINDOW_SIZE) / SAMPLE_RATE

        # バー描画
        bar_len   = int(avg * 40)
        bar_color = "🟩" if avg >= SPEECH_THRESHOLD else ("🟨" if avg >= SILENCE_THRESHOLD else "⬜")
        bar       = "█" * bar_len + "░" * (40 - bar_len)

        label = " 🗣️ " if avg >= SPEECH_THRESHOLD else ("    " if avg >= SILENCE_THRESHOLD else "    ")
        print(f"  {sec:6.2f}s  {avg:.3f}  |{bar}|{label}")

    print("=" * 65)

    # --- ヒステリシス判定（発話区間） ---
    start_idx = next((i for i, p in enumerate(probs) if p > SPEECH_THRESHOLD), -1)
    end_idx   = -1
    if start_idx != -1:
        for i in range(len(probs) - 1, -1, -1):
            if probs[i] > SILENCE_THRESHOLD:
                end_idx = i
                break

    print()
    if start_idx == -1 or start_idx >= end_idx:
        print("🔇 発話区間: 検出されませんでした")
    else:
        s_sec = start_idx * WINDOW_SIZE / SAMPLE_RATE
        e_sec = end_idx   * WINDOW_SIZE / SAMPLE_RATE
        print(f"🗣️  発話区間: {s_sec:.2f}s  →  {e_sec:.2f}s  (長さ: {e_sec - s_sec:.2f}s)")

    print()
    print(f"📈 確率の統計:")
    print(f"   平均  : {np.mean(probs):.4f}")
    print(f"   最大  : {np.max(probs):.4f}")
    print(f"   最小  : {np.min(probs):.4f}")
    speech_ratio = sum(1 for p in probs if p >= SPEECH_THRESHOLD) / len(probs) * 100
    print(f"   発話率: {speech_ratio:.1f}%  (閾値 {SPEECH_THRESHOLD} 以上のウィンドウの割合)")
    print()


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else AUDIO_FILE
    run_vad_test(target)