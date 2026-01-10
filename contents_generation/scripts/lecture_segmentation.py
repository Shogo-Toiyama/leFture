import json, re, time
from pathlib import Path

from dotenv import load_dotenv

from contents_generation.scripts.llm.llm_unified import UnifiedLLM, LLMOptions, Message, CostCollector

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROMPTS_DIR = PROJECT_ROOT / "prompts"

SID_NUM = re.compile(r"s(\d+)")


def token_report_from_result(res, collector: CostCollector):
    u = res.usage
    collector.add("Lecture Segmentation", res.estimated_cost_usd)
    return (
        "TOKEN USAGE REPORT\n"
        f"  ⬆️:{u.input_tokens}, 🧠: {u.reasoning_tokens}, ⬇️: {u.output_tokens}\n"
        f"  TOTAL: {u.total_tokens}\n"
        f"  Estimated cost: ${res.estimated_cost_usd:.6f}"
    )


def sid_to_num(sid: str):
    m = SID_NUM.match(sid)
    if m:
        return int(m.group(1))
    return None


def topic_segmentation(llm: UnifiedLLM, model_alias: str, options_json: LLMOptions, lecture_dir: Path, collector: CostCollector):
    # トピックで分割
    print("\n### Topic Segmentation ###")
    start_time = time.time()

    instr_topic_segmentation = (PROMPTS_DIR / "topic_segmentation.txt").read_text(encoding="utf-8")
    sentences_final = json.loads((lecture_dir / "sentences_final.json").read_text(encoding="utf-8"))

    ALLOWED = ["sid", "text", "start", "role"]
    projected_sentences = [{k: s.get(k) for k in ALLOWED} for s in sentences_final]

    print(f"Waiting for response from {llm.provider} API...")

    payload = {
        "task": "Topic Segmentation",
        "instruction": instr_topic_segmentation,
        "data": {"sentences": projected_sentences},
    }

    messages = [
        Message(
            role="system",
            content="You are a careful lecture segmentation assistant. Return JSON only, matching the requested format.",
        ),
        Message(role="user", content=json.dumps(payload, ensure_ascii=False)),
    ]

    res = llm.generate(model=model_alias, messages=messages, options=options_json)

    print("saving response...")
    out_obj = json.loads(res.output_text.strip())
    (lecture_dir / "topic_segments.json").write_text(
        json.dumps(out_obj, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    elapsed = time.time() - start_time
    print(token_report_from_result(res, collector))
    if res.warnings:
        print("  [WARN]", "; ".join(res.warnings))
    print(f"⏰Extracted topic: {elapsed:.2f} seconds.")


def out_of_segment_classification(llm: UnifiedLLM, model_alias_lite: str, options_json: LLMOptions, lecture_dir: Path, colector: CostCollector):
    # セグメント外の文章分類
    print("\n### Out of Segments Classification ###")
    start_time = time.time()

    topic_segments = json.loads((lecture_dir / "topic_segments.json").read_text(encoding="utf-8"))
    sentences_final = json.loads((lecture_dir / "sentences_final.json").read_text(encoding="utf-8"))

    instr_oos_classification = (PROMPTS_DIR / "out_of_segment_classification.txt").read_text(encoding="utf-8")

    topics = topic_segments.get("topics", [])
    segment_sids = [(sid_to_num(t["start_sid"]), sid_to_num(t["end_sid"])) for t in topics]

    # NOTE: original code used last_sid = len(sentences_final); keep behavior for now
    last_sid = len(sentences_final)

    out_of_segment_sids = []
    current_sid = 1

    for start_sid, end_sid in segment_sids:
        if start_sid is None or end_sid is None:
            continue
        if current_sid == start_sid:
            current_sid = end_sid + 1
        elif current_sid < start_sid:
            out_of_segment_sids.append((current_sid, start_sid - 1))
            current_sid = end_sid + 1
        else:
            raise ValueError("Segments are overlapping or not sorted correctly.")

    if current_sid <= last_sid:
        out_of_segment_sids.append((current_sid, last_sid))

    payload = {
        "task": "Out of Segment Classification",
        "instruction": instr_oos_classification,
        "data": {
            "sentences": sentences_final,
            "out_of_segment_sids": out_of_segment_sids,
        },
    }

    messages = [
        Message(
            role="system",
            content="You are a careful classifier. Return JSON only, matching the requested format.",
        ),
        Message(role="user", content=json.dumps(payload, ensure_ascii=False)),
    ]

    print(f"Waiting for response from {llm.provider} API...")
    res = llm.generate(model=model_alias_lite, messages=messages, options=options_json)

    print("saving response...")
    out_obj = json.loads(res.output_text.strip())
    (lecture_dir / "out_of_segment_classification.json").write_text(
        json.dumps(out_obj, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    elapsed = time.time() - start_time
    print(token_report_from_result(res, colector))
    if res.warnings:
        print("  [WARN]", "; ".join(res.warnings))
    print(f"⏰Classified out of segments: {elapsed:.2f} seconds.")


def lecture_segmentation(
    llm: UnifiedLLM,
    model_alias_full: str,
    model_alias_lite: str,
    lecture_dir: Path,
    collector: CostCollector,
):
    options_json = LLMOptions(output_type="json", temperature=0.2, google_search=False, reasoning_effort="low")

    topic_segmentation(llm, model_alias_full, options_json, lecture_dir, collector)

    # If you want to run later:
    # out_of_segment_classification(llm, model_alias_lite, options_json, lecture_dir)

    print("\n✅All tasks of LECTURE SEGMENTATION completed.")


# ------ for test -------
def main():
    load_dotenv()

    # Switch provider/model here
    llm = UnifiedLLM(provider="gemini")
    full_model = "2_5_flash"
    lite_model = "2_5_flash_lite"

    # llm = UnifiedLLM(provider="openai")
    # full_model = "5_mini"
    # lite_model = "5_nano"

    ROOT = Path(__file__).resolve().parent
    LECTURE_DIR = ROOT / "../lectures/2026-01-06-02-44-09-0800"  # ⚠️ CHANGE FOLDER NAME!!! 🛑

    lecture_segmentation(llm, full_model, lite_model, LECTURE_DIR)


if __name__ == "__main__":
    main()
