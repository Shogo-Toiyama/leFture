import os
import sys
import re
import time
import shutil
import argparse
import subprocess
from pathlib import Path
from dataclasses import dataclass
from typing import Union
import requests
from dotenv import load_dotenv

# ディレクトリパスの設定
CURRENT_DIR = Path(__file__).resolve().parent
ENV_PATH = CURRENT_DIR / ".env"
TEMP_DIR = CURRENT_DIR / "temp"
DEFAULT_INPUT_FILE = CURRENT_DIR / "input_text.txt"
DEFAULT_OUTPUT_FILE = CURRENT_DIR / "output_audio.mp3"

# .envの読み込み（カレントディレクトリの.envを明示的に読み込む）
load_dotenv(dotenv_path=ENV_PATH)

FISH_AUDIO_API_KEY = os.getenv("FISH_AUDIO_API_KEY")
FISH_AUDIO_MODEL = os.getenv("FISH_AUDIO_MODEL", "s2.1-pro")
FISH_AUDIO_REFERENCE_ID = os.getenv("FISH_AUDIO_REFERENCE_ID", "").strip()

API_URL = "https://api.fish.audio/v1/tts"


@dataclass
class SpeechSegment:
    """音声合成するテキストセグメント"""
    index: int
    text: str
    audio_file: Path


@dataclass
class PauseSegment:
    """明示的に指定されたポーズ（無音）セグメント"""
    duration: float


# シーケンスを構成する要素
Segment = Union[SpeechSegment, PauseSegment]


def parse_input_text(file_path: Path, audio_format: str = "mp3") -> tuple[list[Segment], list[SpeechSegment]]:
    """
    テキストファイルを読み込み、'---' で区切られたセクションを解析する。
    '<10>' のような表記は PauseSegment(duration=10.0) として扱う。
    """
    if not file_path.exists():
        raise FileNotFoundError(f"テキストファイルが見つかりません: {file_path}")
    
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    
    if not content:
        raise ValueError(f"テキストファイルが空です: {file_path}")
    
    raw_blocks = re.split(r'\n\s*---\s*\n', content)
    
    timeline: list[Segment] = []
    speech_segments: list[SpeechSegment] = []
    speech_count = 0
    pause_pattern = re.compile(r"^<(\d+(?:\.\d+)?)>$")

    for block in raw_blocks:
        trimmed = block.strip()
        if not trimmed:
            continue
        
        # <10> や <30> のようなポーズ指定かをチェック
        match = pause_pattern.match(trimmed)
        if match:
            duration = float(match.group(1))
            timeline.append(PauseSegment(duration=duration))
        else:
            speech_count += 1
            audio_file = TEMP_DIR / f"chunk_{speech_count:03d}.{audio_format}"
            segment = SpeechSegment(index=speech_count, text=trimmed, audio_file=audio_file)
            timeline.append(segment)
            speech_segments.append(segment)

    return timeline, speech_segments


def synthesize_speech(
    text: str,
    api_key: str,
    output_path: Path,
    model: str = "s2.1-pro",
    reference_id: str | None = None,
    audio_format: str = "mp3"
) -> Path:
    """
    Fish Audio APIを呼び出して単一テキストを音声に変換し、ファイルに保存する。
    """
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    
    payload = {
        "text": text,
        "format": audio_format,
    }
    
    if reference_id:
        payload["reference_id"] = reference_id
        
    if model:
        headers["model"] = model
        payload["model"] = model

    start_time = time.time()
    response = requests.post(API_URL, json=payload, headers=headers, stream=True)
    elapsed_time = time.time() - start_time

    if response.status_code == 200:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
        
        file_size_kb = output_path.stat().st_size / 1024
        print(f"      ✓ 生成完了 ({elapsed_time:.2f}秒, {file_size_kb:.1f} KB)")
        return output_path
    else:
        error_msg = f"APIエラー (ステータスコード: {response.status_code})\nレスポンス: {response.text}"
        print(f"\n❌ {error_msg}", file=sys.stderr)
        if response.status_code == 401:
            print("💡 ヒント: APIキーが無効です。.env ファイルを確認してください。", file=sys.stderr)
        elif response.status_code == 402:
            print("💡 ヒント: クレジット/残高が不足している可能性があります。", file=sys.stderr)
        raise RuntimeError(error_msg)


def concatenate_timeline_with_ffmpeg(timeline: list[Segment], output_path: Path, default_pause_sec: float = 1.0) -> bool:
    """
    ffmpeg の filter_complex (concat filter) を使用して、
    すべてのチャンクと無音を完全に同一形式（44.1kHz, Mono, 192kbps）に揃えて結合する。
    """
    ffmpeg_path = shutil.which("ffmpeg")
    if not ffmpeg_path:
        raise RuntimeError("ffmpeg がシステムに見つかりませんでした。Homebrew等で ffmpeg をインストールしてください。")

    print(f"\n🔗 ffmpeg を使用してマスター音声を構築・エンコード中...")
    
    ffmpeg_args = [ffmpeg_path, "-y"]
    filter_inputs = []
    input_idx = 0
    last_item_was_speech = False

    for item in timeline:
        if isinstance(item, SpeechSegment):
            # 前のアイテムが音声セグメントだった場合はデフォルトポーズを挟む
            if last_item_was_speech and default_pause_sec > 0:
                ffmpeg_args.extend(["-f", "lavfi", "-t", str(default_pause_sec), "-i", "anullsrc=r=44100:cl=mono"])
                filter_inputs.append(f"[{input_idx}:a]")
                input_idx += 1
            
            ffmpeg_args.extend(["-i", str(item.audio_file.resolve())])
            filter_inputs.append(f"[{input_idx}:a]")
            input_idx += 1
            last_item_was_speech = True

        elif isinstance(item, PauseSegment):
            if item.duration > 0:
                print(f"   ⏱️ 指定ポーズ挿入: {item.duration} 秒")
                ffmpeg_args.extend(["-f", "lavfi", "-t", str(item.duration), "-i", "anullsrc=r=44100:cl=mono"])
                filter_inputs.append(f"[{input_idx}:a]")
                input_idx += 1
            last_item_was_speech = False

    if not filter_inputs:
        print("結合対象の音声がありません。", file=sys.stderr)
        return False

    # concat フィルタの構築
    filter_complex_str = f"{''.join(filter_inputs)}concat=n={len(filter_inputs)}:v=0:a=1[outa]"
    ffmpeg_args.extend([
        "-filter_complex", filter_complex_str,
        "-map", "[outa]",
        "-c:a", "libmp3lame",
        "-b:a", "192k",
        str(output_path.resolve())
    ])

    result = subprocess.run(
        ffmpeg_args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    if result.returncode != 0:
        print(f"❌ ffmpeg エラー:\n{result.stderr}", file=sys.stderr)
        return False

    return True


def main():
    parser = argparse.ArgumentParser(description="Fish Audio TTS テスト & ポーズ付きチャンク結合スクリプト")
    parser.add_argument(
        "--input", "-i",
        type=str,
        default=str(DEFAULT_INPUT_FILE),
        help=f"入力テキストファイルのパス (デフォルト: {DEFAULT_INPUT_FILE.name})"
    )
    parser.add_argument(
        "--output", "-o",
        type=str,
        default=str(DEFAULT_OUTPUT_FILE),
        help=f"出力マスター音声ファイルのパス (デフォルト: {DEFAULT_OUTPUT_FILE.name})"
    )
    parser.add_argument(
        "--model", "-m",
        type=str,
        default=FISH_AUDIO_MODEL,
        help=f"使用するモデル (デフォルト: {FISH_AUDIO_MODEL})"
    )
    parser.add_argument(
        "--reference-id", "-r",
        type=str,
        default=FISH_AUDIO_REFERENCE_ID if FISH_AUDIO_REFERENCE_ID else None,
        help="参照音声ID (voice clone reference ID)"
    )
    parser.add_argument(
        "--format", "-f",
        type=str,
        default="mp3",
        choices=["mp3", "wav", "opus"],
        help="出力フォーマット (デフォルト: mp3)"
    )
    parser.add_argument(
        "--default-pause", "-p",
        type=float,
        default=1.0,
        help="通常のチャンク間のデフォルト無音間隔（秒） (デフォルト: 1.0秒)"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="既存の temp 音声ファイルがあっても再生成する (デフォルトはスキップしてクレジット節約)"
    )
    parser.add_argument(
        "--clean-temp",
        action="store_true",
        help="結合完了後に temp ディレクトリ内の一時ファイルを削除する"
    )

    args = parser.parse_args()

    # APIキーの検証
    api_key = FISH_AUDIO_API_KEY
    if not api_key or api_key == "your_api_key_here":
        print("❌ エラー: FISH_AUDIO_API_KEY が設定されていません。", file=sys.stderr)
        print(f"👉 {ENV_PATH} を開いて、取得したAPIキーを設定してください。\n", file=sys.stderr)
        sys.exit(1)

    input_file = Path(args.input)
    output_file = Path(args.output)

    try:
        # テキストの読み込みと解析
        timeline, speech_segments = parse_input_text(input_file, audio_format=args.format)
        total_speech = len(speech_segments)
        
        print(f"📄 入力ファイルを読み込みました: {input_file.name}")
        print(f"   - 音声生成セクション: {total_speech} 箇所")
        
        # ポーズ指定の確認
        custom_pauses = [item for item in timeline if isinstance(item, PauseSegment)]
        if custom_pauses:
            pause_durations = ", ".join([f"{p.duration}秒" for p in custom_pauses])
            print(f"   - 指定ポーズ: {len(custom_pauses)} 箇所 ({pause_durations})")

        # temp ディレクトリの準備
        TEMP_DIR.mkdir(parents=True, exist_ok=True)

        overall_start_time = time.time()

        # 音声合成の実行
        for seg in speech_segments:
            # 既存ファイルのキャッシュ確認
            if not args.force and seg.audio_file.exists() and seg.audio_file.stat().st_size > 1024:
                file_size_kb = seg.audio_file.stat().st_size / 1024
                print(f"\n⚡ [{seg.index}/{total_speech}] 既存の音声を再利用 (スキップ): {seg.audio_file.name} ({file_size_kb:.1f} KB)")
                continue

            print(f"\n🚀 [{seg.index}/{total_speech}] チャンクを生成中... ({len(seg.text)} 文字)")
            preview = seg.text.replace('\n', ' ')
            print(f"   プレビュー: \"{preview[:80]}{'...' if len(preview) > 80 else ''}\"")

            synthesize_speech(
                text=seg.text,
                api_key=api_key,
                output_path=seg.audio_file,
                model=args.model,
                reference_id=args.reference_id,
                audio_format=args.format
            )

        # タイムラインに従って音声を結合
        concatenate_timeline_with_ffmpeg(timeline, output_file, default_pause_sec=args.default_pause)

        overall_elapsed = time.time() - overall_start_time
        master_size_kb = output_file.stat().st_size / 1024

        print(f"\n🎉 すべての処理が完了しました！")
        print(f"   - 一時ファイル保存先: {TEMP_DIR}/")
        print(f"   - マスター音声ファイル: {output_file}")
        print(f"   - 合計サイズ: {master_size_kb / 1024:.2f} MB")
        print(f"   - 合計所要時間: {overall_elapsed:.2f} 秒")

        if args.clean_temp:
            shutil.rmtree(TEMP_DIR)
            print(f"   - 一時ファイルを削除しました。")

    except Exception as e:
        print(f"\n実行中にエラーが発生しました: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
