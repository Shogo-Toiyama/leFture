import os, json, time
import assemblyai as aai
from dotenv import load_dotenv
from pathlib import Path

from contents_generation.scripts.llm.llm_unified import UnifiedLLM, LLMOptions, Message, CostCollector

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROMPTS_DIR = PROJECT_ROOT / "prompts"

def token_report_from_result(res, collector: CostCollector):
    u = res.usage
    collector.add("Lecture Audio to Text", res.estimated_cost_usd)
    return (
        "TOKEN USAGE REPORT\n"
        f"  ⬆️:{u.input_tokens}, 🧠: {u.reasoning_tokens}, ⬇️: {u.output_tokens}\n"
        f"  TOTAL: {u.total_tokens}\n"
        f"  Estimated cost: ${res.estimated_cost_usd:.6f}"
    )


def _strip_code_fence(text: str) -> str:
    if text.lstrip().startswith("```"):
        lines = [ln.rstrip("\n") for ln in text.splitlines()]
        # 先頭の```を落とす
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        # 末尾の```を落とす
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines)
    return text

def _has_valid_transcript_outputs(lecture_dir: Path) -> bool:
    """
    AssemblyAI の成果物が存在して、最低限パースできるなら True。
    """
    sent_path = lecture_dir / "transcript_sentences.json"
    if not sent_path.exists():
        return False

    try:
        data = json.loads(sent_path.read_text(encoding="utf-8"))
        if not isinstance(data, list) or len(data) == 0:
            return False
        # 最低限のキー確認（sid/text があればOK扱い）
        first = data[0]
        if not isinstance(first, dict):
            return False
        if "sid" not in first or "text" not in first:
            return False
        return True
    except Exception:
        return False


# -----------
# AssemblyAI 
# -----------
def speech_to_text(audio_file, lecture_dir: Path, collector:CostCollector):
    print("\n### Lecture Audio To Text ###")
    start_time_audio_to_text = time.time()

    load_dotenv()
    aai.settings.api_key = os.getenv("ASSEMBLYAI_API_KEY")

    aai_config = aai.TranscriptionConfig(
        speech_models=["universal-2"],
        punctuate=True,
        format_text=True,
        disfluencies=False,
    )

    print("Waiting for response from AssemblyAI API...")
    transcript = aai.Transcriber(config=aai_config).transcribe(str(audio_file))

    if transcript.status == "error":
        raise RuntimeError(f"Transcription failed: {transcript.error}")

    print("saving response...")
    with open(lecture_dir / "transcript_raw.json", "w", encoding="utf-8") as f:
        json.dump(transcript.json_response, f, ensure_ascii=False, indent=2)

    sentences = transcript.get_sentences()

    def sentence_to_dict(s, idx):
        return {
            "sid": f"s{idx:06d}",
            "text": getattr(s, "text", None),
            "start": getattr(s, "start", None),
            "end": getattr(s, "end", None),
            "confidence": getattr(s, "confidence", None),
        }

    data = [sentence_to_dict(s, idx) for idx, s in enumerate(sentences, start=1)]
    duration = transcript.audio_duration
    print(f"Cost (universal-2): ${duration/3600*0.15:.3f}")
    collector.add("AssemblyAI Transcription (universal-2)", duration/3600*0.15)
    with open(lecture_dir / "transcript_sentences.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    end_time_audio_to_text = time.time()
    elapsed_time_audio_to_text = end_time_audio_to_text - start_time_audio_to_text
    print(f"⏰Transcribed audio to text: {elapsed_time_audio_to_text:.2f} seconds.")


# -------------------------
# Sentence Review (UPDATED)
# -------------------------
def sentence_review(
    llm: UnifiedLLM, 
    model_alias: str, 
    lecture_dir: Path, 
    collector: CostCollector, 
    options_json: LLMOptions | None = None,
    force_review: bool = False
):

    REVIEWED_RAW_PATH = lecture_dir / "reviewed" / "reviewed_sentences_raw.json"
    TRANSCRIPT_SENTENCES_PATH = lecture_dir / "transcript_sentences.json"
    
    # 1. 共通で必要な「元の文章」をまず読み込む
    with open(TRANSCRIPT_SENTENCES_PATH, "r", encoding="utf-8") as f:
        sentences = json.load(f)

    # 2. スキップ判定
    is_skipped = not force_review and REVIEWED_RAW_PATH.exists()

    if is_skipped:
        print("\n### Sentence Review ###")
        print(f"✅ Found existing {REVIEWED_RAW_PATH.name}, loading from file...")
        # すでに実行済みなら、その結果をロードする
        with open(REVIEWED_RAW_PATH, "r", encoding="utf-8") as f:
            out_review_sentence = json.load(f)
    else:

        print("\n### Sentence Review ###")
        start_time_sentence_review = time.time()

        REVIEWED_DIR = lecture_dir / "reviewed"
        REVIEWED_DIR.mkdir(exist_ok=True)

        instr_sentence_review = (PROMPTS_DIR / "sentence_review.txt").read_text(encoding="utf-8")

        with open(lecture_dir / "transcript_sentences.json", "r", encoding="utf-8") as f:
            sentences = json.load(f)

        ALLOWED = ["sid", "text", "confidence"]
        projected_sentences = [{k: s.get(k) for k in ALLOWED} for s in sentences]
        low_confidence_sentences = [s for s in projected_sentences if (s.get("confidence") is not None and s.get("confidence", 1.0) < 0.7)]
        print("Low Confident Sentences: ", len(low_confidence_sentences))

        payload = {
            "task": "Sentence Review",
            "instruction": instr_sentence_review,
            "data": {
                "low_confidence_sentences": low_confidence_sentences
            }
        }

        messages = [
            Message(
                role="system",
                content="You are a careful transcript editor. Follow the instruction and return JSON only.",
            ),
            Message(role="user", content=json.dumps(payload, ensure_ascii=False)),
        ]

        options_json = options_json or LLMOptions(output_type="json", temperature=0.2, google_search=False, reasoning_effort="low")

        print(f"Waiting for response from {llm.provider} API...")
        res = llm.generate(model=model_alias, messages=messages, options=options_json)

        print("saving response...")
        raw_text = res.output_text
        clean_text = _strip_code_fence(raw_text).strip()

        try:
            out_review_sentence = json.loads(clean_text)
        except json.JSONDecodeError as e:
            # keep raw for debug
            (lecture_dir / "reviewed/reviewed_sentences_raw_text.txt").write_text(raw_text, encoding="utf-8")
            raise ValueError(f"Sentence Review JSON parse failed: {e}") from e

        with open(lecture_dir / "reviewed/reviewed_sentences_raw.json", "w", encoding="utf-8") as f:
            json.dump(out_review_sentence, f, ensure_ascii=False, indent=2)

    sentence_reviewed_list = out_review_sentence.get("results") or []

    mods = {}
    for r in sentence_reviewed_list:
        sid = r.get("sid")
        modified = r.get("modified")
        if sid and isinstance(modified, str) and modified.strip():
            mods[sid] = modified.strip()

    reviewed_sentences = []
    for s in sentences:
        sid = s.get("sid")
        if sid in mods:
            new_s = dict(s)
            new_s["text"] = mods[sid]
            reviewed_sentences.append(new_s)
        else:
            reviewed_sentences.append(s)

    with open(lecture_dir / "reviewed_sentences.json", "w", encoding="utf-8") as f:
        json.dump(reviewed_sentences, f, ensure_ascii=False, indent=2)

    if not is_skipped:
        elapsed_time_sentence_review = time.time() - start_time_sentence_review
        print(token_report_from_result(res, collector))
        if res.warnings:
            print("  [WARN]", "; ".join(res.warnings))
        print(f"⏰Sentence Review: {elapsed_time_sentence_review:.2f} seconds.")


def lecture_audio_to_text(
    audio_file,
    lecture_dir: Path,
    llm: UnifiedLLM,
    model_alias: str,
    collector: CostCollector,
    *,
    force_transcribe: bool = False,
):
    """
    - transcript_sentences.json が既にあれば speech_to_text をスキップ
    - force_transcribe=True のときは必ず AssemblyAI を再実行
    """
    if audio_file is None:
        print("\n### Lecture Audio To Text (Transcript Mode) ###")
        print("✅ Skipping AssemblyAI transcription and Sentence Review.")
        # Ensure reviewed_sentences.json exists
        src = lecture_dir / "transcript_sentences.json"
        dst = lecture_dir / "reviewed_sentences.json"
        if src.exists() and not dst.exists():
            import shutil
            shutil.copy(str(src), str(dst))
        return

    if force_transcribe or not _has_valid_transcript_outputs(lecture_dir):
        speech_to_text(audio_file, lecture_dir, collector)
    else:
        print("\n### Lecture Audio To Text ###")
        print("✅ Found existing transcript_sentences.json, skip AssemblyAI transcription.")

    sentence_review(llm, model_alias, lecture_dir, collector)


# ------ for test -------
def main():
    load_dotenv()

    # Switch provider/model here
    llm = UnifiedLLM(provider="gemini")
    model_alias = "2_5_flash"
    # llm = UnifiedLLM(provider="openai")
    # model_alias = "5_mini"

    ROOT = Path(__file__).resolve().parent
    LECTURE_DIR = ROOT / "../lectures/2025-10-31-12-04-37-0700"

    # audio_file should be an actual file path when running for real
    lecture_audio_to_text("", LECTURE_DIR, llm, model_alias)


if __name__ == "__main__":
    main()
