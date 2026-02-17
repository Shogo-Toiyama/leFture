import time, sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial

import os
from dotenv import load_dotenv
from google import genai
from google.genai import types

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROMPTS_DIR = PROJECT_ROOT / "prompts"

# ルートディレクトリのモジュールをインポート
sys.path.append(str(PROJECT_ROOT))
from cost_tracker import CostCollector, calculate_and_track

def _generate_one_fun_fact(
    client, gen_model, config_text,
    instr_fun_facts_generation: str,
    detail_file: Path, fun_fact_dir: Path,
    collector: CostCollector
):
    start_time_one_fun_fact = time.time()
    topic_name = detail_file.stem.replace(" - details", "")

    with open(detail_file, "r", encoding="utf-8") as f:
        topic_details_markdown = f.read()

    print(f"Waiting for response from Gemini API for {detail_file.name}...")
    contents = [
        instr_fun_facts_generation,
        topic_details_markdown,
        "Using the text provided above, follow the instructions and return the result in markdown text."
    ]
    response_fun_facts = client.models.generate_content(
        model = gen_model,
        contents = contents,
        config = config_text,
    )

    # --- コスト集計 ---
    calculate_and_track(collector, f"Fun Fact ({topic_name})", gen_model, response_fun_facts)
    # ----------------

    print("saving response...")

    with open(fun_fact_dir / f"{topic_name} - fun_fact.txt", "w", encoding="utf-8") as f:
        f.write(response_fun_facts.text)
    
    end_time_one_fun_fact = time.time()
    elapsed_time_one_fun_fact = end_time_one_fun_fact - start_time_one_fun_fact
    print(f"  --> ⏰Generated fun fact for '{topic_name}': {elapsed_time_one_fun_fact:.2f} seconds.")

def generate_fun_facts(client, gen_model, config_text, lecture_dir: Path, collector: CostCollector):
    # topicsごとのfun factを生成
    print("\n### Fun Fact Generation ###")

    start_time_fun_facts = time.time()

    FUN_FACT_DIR = Path(lecture_dir / "fun_facts")
    FUN_FACT_DIR.mkdir(exist_ok=True, parents=True)

    with open(PROMPTS_DIR / "fun_fact_generation.txt", "r", encoding="utf-8") as f:
        instr_fun_facts_generation = f.read()

    detail_files = sorted(Path(lecture_dir / "details/edited").glob("* - details.txt"))
    
    max_workers = 5
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        submit_one = partial(
            _generate_one_fun_fact,
            client, gen_model, config_text,
            instr_fun_facts_generation, fun_fact_dir = FUN_FACT_DIR,
            collector=collector
        )
        futures = {ex.submit(submit_one, detail): detail for detail in detail_files}

        for fut in as_completed(futures):
            f = futures[fut]
            try:
                fut.result()
            except Exception as e:
                print(f"❌ Generating fun facts failed for {f}: {e}")

    end_time_fun_facts = time.time()
    elapsed_time_fun_facts = end_time_fun_facts - start_time_fun_facts
    print(f"⏰Generated all fun facts: {elapsed_time_fun_facts:.2f} seconds.")

    print("\n✅All tasks of FUN FACT GENERATION completed.")