import os, time, sys
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


def stable_files(dirpath: Path, settle_seconds=3.0):
    snapshot1 = {p: (size, mtime) for p, size, mtime in list_audio_files(dirpath)}
    time.sleep(settle_seconds)
    snapshot2 = {p: (size, mtime) for p, size, mtime in list_audio_files(dirpath)}

    stable = []
    for p, meta1 in snapshot1.items():
        meta2 = snapshot2.get(p)
        if meta2 and meta1 == meta2:
            stable.append((p, meta2[0], meta2[1]))
    return stable


def wait_for_uploads(audio_dir: Path, min_files=1, poll_interval=1.0, settle_seconds=3.0, timeout=None):
    print(f"\n📂 Upload destination: {audio_dir.resolve()}")
    print("⬆️  Please copy your audio file(s) into this folder.")
    print("   (We'll wait here; press Ctrl+C to abort.)")
    start = time.time()

    while True:
        try:
            stable = stable_files(audio_dir, settle_seconds=settle_seconds)
            if len(stable) >= min_files:
                print(f"\n✅ Detected {len(stable)} stable file(s):")
                for p, size, _ in stable:
                    print(f" - {p.name}  [{human_size(size)}]")
                while True:
                    ans = input("\nProceed with these file(s)? [Y/n/r] "
                                "(Y: continue, n: quit, r: refresh list) ").strip().lower()
                    if ans in {"", "y", "yes"}:
                        return [p for p, _, _ in stable]
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
    # Choose provider & models
    # =========================
    
    provider = "gemini"
    # provider = "openai"

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

    llm = UnifiedLLM(provider=provider)
    colector = CostCollector()

    # Common options (Search is off)
    json_opts = LLMOptions(output_type="json", temperature=0.2, google_search=False)
    text_opts = LLMOptions(output_type="text", temperature=0.2, google_search=False)

    LECTURE_DIR = make_lecture_dir()
    AUDIO_DIR = LECTURE_DIR / "audio"
    AUDIO_DIR.mkdir()

    audio_files = wait_for_uploads(AUDIO_DIR)

    start_time_total = time.time()

    # 1) AssemblyAI transcription stays inside lecture_audio_to_text, sentence review uses llm
    lecture_audio_to_text(audio_files[0], LECTURE_DIR, llm, MODELS["sentence_review"], colector)

    # 2) Role classification (lite for batches, full optional review)
    role_classification(
        llm,
        MODELS["role_full"],
        MODELS["role_lite"],
        LECTURE_DIR,
        colector,
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
        colector,
    )

    # 4) Topic details generation (text)
    generate_topic_details(
        llm,
        MODELS["topic_details"],
        LECTURE_DIR,
        colector,
        options_text=text_opts,
    )

    # 5) Fun facts (text)
    generate_fun_facts(
        llm,
        MODELS["fun_facts"],
        LECTURE_DIR,
        colector,
        options=text_opts,
    )

    elapsed_time_total = time.time() - start_time_total
    total_minutes = int(elapsed_time_total // 60)
    total_seconds = int(elapsed_time_total % 60)
    print(f"\n⏰⏰⏰ Total elapsed time: {total_minutes} m {total_seconds} s.")
    print(colector.report())
    print("\n🎉 All tasks completed.")


if __name__ == "__main__":
    main()