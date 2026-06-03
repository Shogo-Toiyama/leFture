import os, time, sys, json
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv

current_dir = Path(__file__).resolve().parent
sys.path.append(str(current_dir.parent))

# NEW: unified interface
from contents_generation.scripts.llm.llm_unified import UnifiedLLM, LLMOptions, CostCollector

from contents_generation.scripts.lecture_audio_to_text import lecture_audio_to_text
from contents_generation.scripts.role_classification import role_classification
from contents_generation.scripts.lecture_segmentation import lecture_segmentation
from contents_generation.scripts.generate_topic_details_from_segments import generate_topic_details
from contents_generation.scripts.generate_fun_facts import generate_fun_facts

AUDIO_EXTS = {".mp3", ".m4a", ".wav", ".flac", ".aac", ".ogg", ".wma", ".aiff"}


def make_lecture_dir():
    ROOT = Path(__file__).resolve().parent
    LECTURES_DIR = ROOT / "lectures"
    LECTURES_DIR.mkdir(exist_ok=True)

    local_with_tz = datetime.now().astimezone().strftime("%Y-%m-%d-%H-%M-%S%z")
    LECTURE_DIR = LECTURES_DIR / local_with_tz
    LECTURE_DIR.mkdir()

    return LECTURE_DIR


def list_audio_files(dirpath: Path):
    files = []
    for p in dirpath.iterdir():
        if p.is_file() and p.suffix.lower() in AUDIO_EXTS:
            try:
                stat = p.stat()
                files.append((p, stat.st_size, stat.st_mtime))
            except FileNotFoundError:
                pass
    return files


def human_size(n):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}PB"


def stable_files(dirpath: Path, settle_seconds=3.0, pattern="*"):
    """Check files matching a pattern inside a directory for stability."""
    def get_matching_files():
        files = []
        for p in dirpath.glob(pattern):
            if p.is_file() and p.name != ".DS_Store":
                try:
                    stat = p.stat()
                    files.append((p, stat.st_size, stat.st_mtime))
                except FileNotFoundError:
                    pass
        return files

    snapshot1 = {p: (size, mtime) for p, size, mtime in get_matching_files()}
    time.sleep(settle_seconds)
    snapshot2 = {p: (size, mtime) for p, size, mtime in get_matching_files()}

    stable = []
    for p, meta1 in snapshot1.items():
        meta2 = snapshot2.get(p)
        if meta2 and meta1 == meta2:
            stable.append((p, meta2[0], meta2[1]))
    return stable


def parse_time_to_ms(t_str: str) -> int:
    """Convert timestamp format (e.g. '2:24' or '1:03:08') to milliseconds."""
    parts = list(map(int, t_str.strip().split(":")))
    if len(parts) == 2:
        minutes, seconds = parts
        return (minutes * 60 + seconds) * 1000
    elif len(parts) == 3:
        hours, minutes, seconds = parts
        return (hours * 3600 + minutes * 60 + seconds) * 1000
    raise ValueError(f"Unknown timestamp format: {t_str}")


def parse_raw_transcript(txt_path: Path) -> list[dict]:
    """
    Parse a raw transcript text file where lines alternate between sentence text and timestamp.
    Example:
    So today I want to talk about distributed file systems.
    2:24
    Which of course are a subset of distributed systems in general.
    2:35
    """
    lines = [line.strip() for line in txt_path.read_text(encoding="utf-8").splitlines()]
    
    parsed = []
    idx = 1
    
    # We iterate looking for a text line followed by a timestamp line
    i = 0
    prev_ms = 0
    
    while i < len(lines):
        text = lines[i]
        if not text:
            i += 1
            continue
            
        # The next non-empty line should be a timestamp (e.g., '2:24' or '2:24\n')
        timestamp_str = None
        j = i + 1
        while j < len(lines) and not lines[j]:
            j += 1
            
        if j < len(lines):
            # Check if it looks like a timestamp (contains colon, e.g., '2:24')
            if ":" in lines[j]:
                timestamp_str = lines[j]
                i = j + 1
            else:
                # If there's no timestamp, we just treat it as a sentence with no timestamp
                i += 1
        else:
            i += 1
            
        current_ms = None
        if timestamp_str:
            try:
                current_ms = parse_time_to_ms(timestamp_str)
            except ValueError:
                pass
                
        # Generate item
        parsed.append({
            "sid": f"s{idx:06d}",
            "text": text,
            "start": prev_ms,
            "end": current_ms if current_ms is not None else prev_ms + 2000, # fallback to +2s if no end ts
            "confidence": 1.0,
        })
        
        if current_ms is not None:
            prev_ms = current_ms
            
        idx += 1
        
    return parsed


def wait_for_transcript(transcript_path: Path, poll_interval=1.0, settle_seconds=2.0, timeout=None):
    print(f"\n📂 Raw transcript file: {transcript_path.resolve()}")
    print("⬆️  Please paste/save your transcript text into this file.")
    print("   (We'll wait here; press Ctrl+C to abort.)")
    start = time.time()

    while True:
        try:
            if transcript_path.exists() and transcript_path.stat().st_size > 0:
                # Settle check
                size1 = transcript_path.stat().st_size
                time.sleep(settle_seconds)
                size2 = transcript_path.stat().st_size
                if size1 == size2:
                    print("\n✅ Detected transcript input!")
                    while True:
                        ans = input("\nProceed with this transcript? [Y/n/r] "
                                    "(Y: continue, n: quit, r: refresh/wait again) ").strip().lower()
                        if ans in {"", "y", "yes"}:
                            return
                        if ans in {"n", "no", "q", "quit"}:
                            print("💡 Aborted by user.")
                            sys.exit(0)
                        if ans in {"r", "refresh"}:
                            break
            else:
                print(f"\r⏳ Waiting for transcript data in {transcript_path.name}... (empty or doesn't exist)", end="", flush=True)
                time.sleep(poll_interval)

            if timeout is not None and (time.time() - start) > timeout:
                print("\n⏱️  Timeout waiting for transcript.")
                sys.exit(1)

        except KeyboardInterrupt:
            print("\n🛑 Interrupted.")
            sys.exit(1)


def wait_for_uploads(audio_dir: Path, min_files=1, poll_interval=1.0, settle_seconds=3.0, timeout=None):
    print(f"\n📂 Upload destination: {audio_dir.resolve()}")
    print("⬆️  Please copy your audio file(s) into this folder.")
    print("   (We'll wait here; press Ctrl+C to abort.)")
    start = time.time()

    while True:
        try:
            stable = stable_files(audio_dir, settle_seconds=settle_seconds, pattern="*")
            # Filter stable files to only include audio extensions
            stable_audio = [item for item in stable if item[0].suffix.lower() in AUDIO_EXTS]
            if len(stable_audio) >= min_files:
                print(f"\n✅ Detected {len(stable_audio)} stable file(s):")
                for p, size, _ in stable_audio:
                    print(f" - {p.name}  [{human_size(size)}]")
                while True:
                    ans = input("\nProceed with these file(s)? [Y/n/r] "
                                "(Y: continue, n: quit, r: refresh list) ").strip().lower()
                    if ans in {"", "y", "yes"}:
                        return [p for p, _, _ in stable_audio]
                    if ans in {"n", "no", "q", "quit"}:
                        print("💡 Aborted by user.")
                        sys.exit(0)
                    if ans in {"r", "refresh"}:
                        break
            else:
                found = list_audio_files(audio_dir)
                names = ", ".join(p.name for p, _, _ in found) or "(none yet)"
                print(f"\r⏳ Waiting for uploads... found: {names}", end="", flush=True)
                time.sleep(poll_interval)

            if timeout is not None and (time.time() - start) > timeout:
                print("\n⏱️  Timeout waiting for uploads.")
                sys.exit(1)

        except KeyboardInterrupt:
            print("\n🛑 Interrupted.")
            sys.exit(1)


def main():
    load_dotenv()

    # =========================
    # Choose mode
    # =========================
    print("=== Orbit Lecture Companion: Note Generation ===")
    print("Select input mode:")
    print("  1. Audio file (Standard)")
    print("  2. Transcript text file (Skip transcription & sentence review)")
    
    while True:
        mode_choice = input("Enter selection [1/2, default: 1]: ").strip()
        if mode_choice in {"", "1"}:
            mode = "audio"
            break
        elif mode_choice == "2":
            mode = "transcript"
            break
        else:
            print("Invalid selection. Please choose 1 or 2.")

    # =========================
    # Choose provider & models
    # =========================
    
    provider = "gemini"
    # provider = "openai"
    # provider = "deepseek"

    if (provider == "gemini"):
        MODELS = {
            "sentence_review": "2_5_flash",
            "role_full": "2_5_flash",
            "role_lite": "2_5_flash_lite",
            "seg_full": "2_5_flash",
            "seg_lite": "2_5_flash_lite",
            "topic_details": "2_5_flash",
            "fun_facts": "2_5_flash",
        }
    elif (provider == "openai"):
        MODELS = {
            "sentence_review": "5_mini",
            "role_full": "5_mini",
            "role_lite": "5_nano",
            "seg_full": "5_mini",
            "seg_lite": "5_nano",
            "topic_details": "5_mini",
            "fun_facts": "5_mini",
        }
    elif (provider == "deepseek"):
        MODELS = {
            "sentence_review": "v4_flash",
            "role_full": "v4_flash",
            "role_lite": "v4_flash",
            "seg_full": "v4_flash",
            "seg_lite": "v4_flash",
            "topic_details": "v4_flash",
            "fun_facts": "v4_flash",
        }

    llm = UnifiedLLM(provider=provider)
    collector = CostCollector()

    # Common options (Search is off)
    json_opts = LLMOptions(output_type="json", temperature=0.2, google_search=False)
    text_opts = LLMOptions(output_type="text", temperature=0.2, google_search=False)

    LECTURE_DIR = make_lecture_dir()

    if mode == "audio":
        AUDIO_DIR = LECTURE_DIR / "audio"
        AUDIO_DIR.mkdir()
        audio_files = wait_for_uploads(AUDIO_DIR)
        audio_file_param = audio_files[0]
    else:
        # Create empty transcript txt file
        transcript_txt = LECTURE_DIR / "raw_transcript.txt"
        transcript_txt.touch()
        wait_for_transcript(transcript_txt)
        
        # Parse text into JSON
        print("\nParsing raw transcript text...")
        parsed_sentences = parse_raw_transcript(transcript_txt)
        
        # Write transcript_sentences.json and reviewed_sentences.json directly
        with open(LECTURE_DIR / "transcript_sentences.json", "w", encoding="utf-8") as f:
            json.dump(parsed_sentences, f, ensure_ascii=False, indent=2)
        with open(LECTURE_DIR / "reviewed_sentences.json", "w", encoding="utf-8") as f:
            json.dump(parsed_sentences, f, ensure_ascii=False, indent=2)
        print("✅ Saved parsed sentences directly.")
        audio_file_param = None

    start_time_total = time.time()

    # 1) AssemblyAI transcription / sentence review
    # If audio_file_param is None, this will be bypassed
    lecture_audio_to_text(audio_file_param, LECTURE_DIR, llm, MODELS["sentence_review"], collector)

    # 2) Role classification (lite for batches, full optional review)
    role_classification(
        llm,
        MODELS["role_full"],
        MODELS["role_lite"],
        LECTURE_DIR,
        collector,
        max_batch_size=350,
        ctx=10,
        concurrency=6,
    )

    # 3) Topic segmentation
    lecture_segmentation(
        llm,
        MODELS["seg_full"],
        MODELS["seg_lite"],
        LECTURE_DIR,
        collector,
    )

    # 4) Topic details generation (text)
    generate_topic_details(
        llm,
        MODELS["topic_details"],
        LECTURE_DIR,
        collector,
        options_text=text_opts,
    )

    # 5) Fun facts (text)
    generate_fun_facts(
        llm,
        MODELS["fun_facts"],
        LECTURE_DIR,
        collector,
        options=text_opts,
    )

    elapsed_time_total = time.time() - start_time_total
    total_minutes = int(elapsed_time_total // 60)
    total_seconds = int(elapsed_time_total % 60)
    print(f"\n⏰⏰⏰ Total elapsed time: {total_minutes} m {total_seconds} s.")
    print(collector.report())
    print("\n🎉 All tasks completed.")


if __name__ == "__main__":
    main()