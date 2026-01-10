import json, time, re
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial

from dotenv import load_dotenv

from contents_generation.scripts.llm.llm_unified import UnifiedLLM, LLMOptions, Message, CostCollector

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROMPTS_DIR = PROJECT_ROOT / "prompts"
_ILLEGAL_FS = re.compile(r'[\\/:*?"<>|\n\r\t]')


def token_report_from_result(res, collector: CostCollector):
    u = res.usage
    collector.add("Topic Detail Generation", res.estimated_cost_usd)
    return (
        "TOKEN USAGE REPORT\n"
        f"  ⬆️:{u.input_tokens}, 🧠: {u.reasoning_tokens}, ⬇️: {u.output_tokens}\n"
        f"  TOTAL: {u.total_tokens}\n"
        f"  Estimated cost: ${res.estimated_cost_usd:.6f}"
    )


def _strip_code_fence(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        lines = t.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        while lines and lines[-1].strip() == "```":
            lines.pop()
        t = "\n".join(lines).strip()
    return t


def _safe_filename(name: str, max_len: int = 120) -> str:
    name = _ILLEGAL_FS.sub("_", name).strip()
    return (name[:max_len]).rstrip(" .")


def _slice_by_sid(sentences, start_sid=None, end_sid=None):
    if isinstance(sentences, dict):
        seq = sorted(sentences.values(), key=lambda s: s.get("sid", ""))
    else:
        seq = list(sentences)
    if not seq:
        return []

    sid_to_idx = {}
    for i, s in enumerate(seq):
        sid = s.get("sid")
        if sid is not None and sid not in sid_to_idx:
            sid_to_idx[sid] = i

    if start_sid is None:
        i0 = 0
    else:
        if start_sid not in sid_to_idx:
            raise ValueError(f"start_sid not found: {start_sid}")
        i0 = sid_to_idx[start_sid]

    if end_sid is None:
        i1 = len(seq) - 1
    else:
        if end_sid not in sid_to_idx:
            raise ValueError(f"end_sid not found: {end_sid}")
        i1 = sid_to_idx[end_sid]

    if i0 > i1:
        i0, i1 = i1, i0

    # add context window
    i0 = max(0, i0 - 20)
    i1 = min(len(seq) - 1, i1 + 20)

    return seq[i0 : i1 + 1]


def _generate_one_topic_detail(
    llm: UnifiedLLM,
    model_alias: str,
    options_text: LLMOptions,
    instr_topic_details_generation: str,
    details_dir: Path,
    sentences,
    collector: CostCollector,
    segment: dict,
):
    start_time = time.time()
    idx = segment["idx"]
    title = segment.get("title", f"Topic {idx}")
    start_sid = segment.get("start_sid")
    end_sid = segment.get("end_sid")

    ALLOWED = ["sid", "text", "role"]
    projected_sentences = [{k: s.get(k) for k in ALLOWED} for s in sentences]
    partial_sentences = _slice_by_sid(projected_sentences, start_sid, end_sid)

    print(f"Waiting for response from {llm.provider} API for topic {idx}...")

    payload = {
        "task": "Topic Detail Generation",
        "instruction": instr_topic_details_generation,
        "data": {
            "topic": segment,
            "partial-transcript": partial_sentences,
        },
    }

    # Keep your structure, just switch to messages
    messages = [
        Message(
            role="system",
            content="You are a careful lecture note generator. Follow the instructions strictly and keep the professor's nuance.",
        ),
        Message(
            role="user",
            content=json.dumps(payload, ensure_ascii=False),
        ),
    ]

    res = llm.generate(model=model_alias, messages=messages, options=options_text)

    print("saving response...")
    details_path = details_dir / f"{idx} - {_safe_filename(title)} - details.txt"
    details_path.write_text(res.output_text.strip(), encoding="utf-8")

    elapsed = time.time() - start_time
    print(token_report_from_result(res, collector))
    if res.warnings:
        print("  [WARN]", "; ".join(res.warnings))
    print(f"  --> ⏰ Generated details for topic {idx} in {elapsed:.2f} seconds.")


def _check_one_faithfulness(
    llm: UnifiedLLM,
    model_alias: str,
    options_text: LLMOptions,
    instr_faithfulness_check: str,
    sentences: dict,
    edited_dir: Path,
    segment: dict,
    draft_path: Path,
):
    start = time.time()

    # name alignment check (fix nested quotes)
    if str(segment.get("idx")).zfill(2) != draft_path.stem.split(" - ")[0].zfill(2):
        raise ValueError(f"Name mismatch: {segment.get('idx')} vs {draft_path}")

    detail_text = draft_path.read_text(encoding="utf-8")

    print(f"Waiting for response from {llm.provider} API... [{draft_path.name}]")

    payload = {
        "task": "Faithfulness Check and Readability Enhancement",
        "instruction": instr_faithfulness_check,
        "data": {
            "detail-draft": detail_text,
            "topic-segment": segment,
            "full-transcript": sentences,
        },
    }

    messages = [
        Message(
            role="system",
            content="You are a strict factuality editor. Keep meaning and nuance, minimize edits, and do not add new facts.",
        ),
        Message(role="user", content=json.dumps(payload, ensure_ascii=False)),
    ]

    res = llm.generate(model=model_alias, messages=messages, options=options_text)

    out_path = edited_dir / draft_path.name
    out_path.write_text(res.output_text, encoding="utf-8")

    elapsed = time.time() - start
    print(token_report_from_result(res))
    if res.warnings:
        print("  [WARN]", "; ".join(res.warnings))
    print(f"  --> ⏰ Checked and edited details for {draft_path.name} in {elapsed:.2f} seconds.")
    return out_path


def generate_details_draft(llm: UnifiedLLM, model_alias: str, options_text: LLMOptions, lecture_dir: Path, collector: CostCollector):
    # トピックごとに詳細を生成
    print("\n### Topic Details Generation ###")
    start_time = time.time()

    max_workers = 3

    DETAILS_DIR = Path(lecture_dir / "details")
    DETAILS_DIR.mkdir(exist_ok=True, parents=True)

    instr_topic_details_generation = (PROMPTS_DIR / "topic_details_generation_from_segments.txt").read_text(
        encoding="utf-8"
    )

    topic_segments_json = json.loads((lecture_dir / "topic_segments.json").read_text(encoding="utf-8"))
    topic_segments = topic_segments_json.get("topics", [])

    sentences_final = json.loads((lecture_dir / "sentences_final.json").read_text(encoding="utf-8"))

    submit_one = partial(
        _generate_one_topic_detail,
        llm,
        model_alias,
        options_text,
        instr_topic_details_generation,
        DETAILS_DIR,
        sentences_final,
        collector,
    )

    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = {ex.submit(submit_one, topic): topic for topic in topic_segments}
        for fut in as_completed(futures):
            seg = futures[fut]
            idx = seg.get("idx")
            try:
                fut.result()
            except Exception as e:
                print(f"[{idx}] ❌ Unhandled error: {e}")

    elapsed = time.time() - start_time
    print(f"⏰Generated topic details: {elapsed:.2f} seconds.")


def faithfulness_check_and_readablity_enhancement(
    llm: UnifiedLLM, model_alias: str, options_text: LLMOptions, lecture_dir: Path
):
    # 生成された詳細の忠実性チェックと最小限の修正
    print("\n### Faithfulness Check and Minimal Edit###")
    start_time = time.time()
    max_workers = 5

    DETAIL_DRAFT_DIR = Path(lecture_dir / "details/drafts")
    DETAIL_EDITED_DIR = Path(lecture_dir / "details/edited")
    DETAIL_EDITED_DIR.mkdir(exist_ok=True, parents=True)

    instr_faithfulness_check = (PROMPTS_DIR / "faithfulness_check_and_minimal_edit.txt").read_text(encoding="utf-8")

    sentences_final = json.loads((lecture_dir / "sentences_final.json").read_text(encoding="utf-8"))
    topic_segments_json = json.loads((lecture_dir / "topic_segments.json").read_text(encoding="utf-8"))
    segments = [t for t in topic_segments_json.get("topics", [])]

    detail_files = sorted(DETAIL_DRAFT_DIR.glob("* - details.txt"))
    if not detail_files:
        raise RuntimeError("no text file in details/")

    if len(segments) != len(detail_files):
        raise RuntimeError(f"Count mismatch: {len(segments)} vs {len(detail_files)}")

    def _prefix(p: Path) -> str:
        return p.stem.split(" - ")[0]

    seg_by_idx = {str(seg["idx"]).zfill(2): seg for seg in segments}
    dt_by_prefix = {_prefix(p).zfill(2): p for p in detail_files}
    common_keys = sorted(set(seg_by_idx) & set(dt_by_prefix))
    print(f"Found {len(common_keys)}: {common_keys}")

    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        submit_one = partial(
            _check_one_faithfulness,
            llm,
            model_alias,
            options_text,
            instr_faithfulness_check,
            sentences_final,
            DETAIL_EDITED_DIR,
        )
        futures = {ex.submit(submit_one, seg_by_idx[k], dt_by_prefix[k]): k for k in common_keys}

        for fut in as_completed(futures):
            k = futures[fut]
            try:
                fut.result()
            except Exception as e:
                print(f"❌ Faithfulness failed for {k}: {e}")

    elapsed = time.time() - start_time
    print(f"⏰Checked and edited topic details: {elapsed:.2f} seconds.")


def generate_topic_details(llm: UnifiedLLM, model_alias: str, lecture_dir: Path, collector: CostCollector, options_text: LLMOptions | None = None):
    options_text = options_text or LLMOptions(output_type="text", temperature=0.2, google_search=False)

    generate_details_draft(llm, model_alias, options_text, lecture_dir, collector)

    # If you want to run this later:
    # faithfulness_check_and_readablity_enhancement(llm, model_alias, options_text, lecture_dir)

    print("\n✅All tasks of TOPIC DETAIL GENERATION completed.")


# ------ for test -------
def main():
    load_dotenv()

    # Switch provider/model here
    llm = UnifiedLLM(provider="gemini")
    model_alias = "2_5_flash"
    # llm = UnifiedLLM(provider="openai")
    # model_alias = "5_mini"  # recommended for topic details quality

    ROOT = Path(__file__).resolve().parent
    LECTURE_DIR = ROOT / "../lectures/2026-01-06-02-44-09-0800"

    options_text = LLMOptions(output_type="text", temperature=0.2, google_search=False, reasoning_effort="low")

    generate_topic_details(llm, model_alias, LECTURE_DIR, options_text=options_text)


if __name__ == "__main__":
    main()
