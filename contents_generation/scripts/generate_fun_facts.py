import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial

from dotenv import load_dotenv

from contents_generation.scripts.llm.llm_unified import UnifiedLLM, LLMOptions, Message, CostCollector

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROMPTS_DIR = PROJECT_ROOT / "prompts"


def token_report_from_result(res, collector: CostCollector):
    u = res.usage
    collector.add("Fun Fact Generation", res.estimated_cost_usd)
    return (
        "TOKEN USAGE REPORT\n"
        f"  ⬆️:{u.input_tokens}, 🧠: {u.reasoning_tokens}, ⬇️: {u.output_tokens}\n"
        f"  TOTAL: {u.total_tokens}\n"
        f"  Estimated cost: ${res.estimated_cost_usd:.6f}"
    )


def _generate_one_fun_fact(
    llm: UnifiedLLM,
    model_alias: str,
    options: LLMOptions,
    instr_fun_facts_generation: str,
    detail_file: Path,
    collector: CostCollector,
    fun_fact_dir: Path,
):
    start_time_one_fun_fact = time.time()
    topic_name = detail_file.stem.replace(" - details", "")

    topic_details_markdown = detail_file.read_text(encoding="utf-8")

    print(f"Waiting for response from {llm.provider} API for {detail_file.name}...")

    messages = [
        Message(role="system", content=instr_fun_facts_generation),
        Message(role="user", content=topic_details_markdown),
        Message(
            role="user",
            content="Using the text provided above, follow the instructions and return the result in markdown text.",
        ),
    ]

    res = llm.generate(model=model_alias, messages=messages, options=options)

    print("saving response...")
    (fun_fact_dir / f"{topic_name} - fun_fact.txt").write_text(res.output_text, encoding="utf-8")

    elapsed_time_one_fun_fact = time.time() - start_time_one_fun_fact
    print(token_report_from_result(res, collector))
    if res.warnings:
        print("  [WARN]", "; ".join(res.warnings))
    print(f"  --> ⏰Generated fun fact for '{topic_name}': {elapsed_time_one_fun_fact:.2f} seconds.")


def generate_fun_facts(llm: UnifiedLLM, model_alias: str, lecture_dir: Path, collector: CostCollector, options: LLMOptions | None = None):
    # topicsごとのfun factを生成
    print("\n### Fun Fact Generation ###")
    start_time_fun_facts = time.time()

    FUN_FACT_DIR = Path(lecture_dir / "fun_facts")
    FUN_FACT_DIR.mkdir(exist_ok=True, parents=True)

    instr_fun_facts_generation = (PROMPTS_DIR / "fun_fact_generation.txt").read_text(encoding="utf-8")

    detail_files = sorted(Path(lecture_dir / "details").glob("* - details.txt"))
    if not detail_files:
        print(f"[WARN] No detail files found under: {Path(lecture_dir / 'details').resolve()}")
        return

    options = options or LLMOptions(output_type="text", temperature=0.2, google_search=False, reasoning_effort="low")

    max_workers = 3
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        submit_one = partial(
            _generate_one_fun_fact,
            llm,
            model_alias,
            options,
            instr_fun_facts_generation,
            collector=collector,
            fun_fact_dir=FUN_FACT_DIR,
        )
        futures = {ex.submit(submit_one, detail): detail for detail in detail_files}

        for fut in as_completed(futures):
            f = futures[fut]
            try:
                fut.result()
            except Exception as e:
                print(f"❌ Generating fun facts failed for {f}: {e}")

    elapsed_time_fun_facts = time.time() - start_time_fun_facts
    print(f"⏰Generated all fun facts: {elapsed_time_fun_facts:.2f} seconds.")
    print("\n✅All tasks of FUN FACT GENERATION completed.")


# ------ for test -------
def main():
    load_dotenv()

    # Switch here:
    llm = UnifiedLLM(provider="gemini")
    model_alias = "2_5_flash"
    # llm = UnifiedLLM(provider="openai")
    # model_alias = "5_mini"

    ROOT = Path(__file__).resolve().parent
    LECTURE_DIR = ROOT / "../lectures/2026-01-06-02-44-09-0800"

    options = LLMOptions(
        output_type="text",
        temperature=0.2,
        google_search=False,  # Search is disabled for now
        reasoning_effort="low"
    )

    generate_fun_facts(llm, model_alias, LECTURE_DIR, options=options)


if __name__ == "__main__":
    main()
