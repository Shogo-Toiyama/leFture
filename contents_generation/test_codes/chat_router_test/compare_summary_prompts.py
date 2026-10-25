# contents_generation/test_codes/compare_summary_prompts.py
import asyncio
import json
import os
import sys
import time
from pathlib import Path
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[3]
load_dotenv(REPO_ROOT / 'lefture_backend' / '.env')
sys.path.insert(0, str(REPO_ROOT / 'lefture_backend'))
sys.path.insert(0, str(REPO_ROOT))

from app.services.chat_summary import (
    Turn,
    validate_summary_output,
    extract_source_turns_to_fetch,
    EMPTY_HEADER,
    SUMMARY_MODEL,
    SUMMARY_SCHEMA,
    _load_prompt,
    _LANGUAGE_NAMES,
    HEADER_CATEGORIES,
)
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM
from contents_generation.test_codes.chat_router_test.summary_eval_experiment import make_test_case_3, make_test_case_1


def build_custom_messages(prompt_template: str, prior_titles: list[str], header: dict, turns: list[Turn], language: str):
    system = prompt_template.replace("${SUMMARY_LANGUAGE}", _LANGUAGE_NAMES.get(language, language))
    titles_text = "\n".join(f"- {t}" for t in prior_titles) if prior_titles else "(none yet)"

    header_lines = []
    for key in HEADER_CATEGORIES:
        items = header.get(key) or []
        if items:
            header_lines.append(f"[{key}]")
            header_lines.extend(f"- {it['text']} (source_turn={it.get('source_turn') or it.get('source_round')})" for it in items)
    header_text = "\n".join(header_lines) if header_lines else "(none yet)"

    turns_text = "\n\n".join(
        f"[turn {t.number}] Student: {t.user_content}\n[turn {t.number}] Assistant: {t.assistant_content}"
        for t in turns
    )
    user_content = (
        f"<previous_section_titles>\n{titles_text}\n</previous_section_titles>\n\n"
        f"<current_header>\n{header_text}\n</current_header>\n\n"
        f"<turns_to_fold>\n{turns_text}\n</turns_to_fold>"
    )
    return [Message(role="system", content=system), Message(role="user", content=user_content)]


async def run_with_prompt(prompt_text: str, turns: list[Turn], label: str):
    messages = build_custom_messages(prompt_text, [], EMPTY_HEADER, turns, language="ja")
    billing = BillingEngine(task_type="CHAT_SUMMARY")
    llm = UnifiedLLM(billing)
    options = LLMOptions(output_type="json", json_schema=SUMMARY_SCHEMA, temperature=1.0, max_completion_tokens=4000)
    
    t0 = time.time()
    result = await llm.generate(SUMMARY_MODEL, messages, options)
    elapsed = round(time.time() - t0, 2)
    
    sections, header = validate_summary_output(result.output_json, turns, next_handle=1)
    to_fetch = extract_source_turns_to_fetch(header)
    cost = billing.total_usd()
    
    print(f"\n[{label}] Elapsed: {elapsed}s | Cost: ${cost:.5f}")
    print("Header:")
    print(json.dumps(header, ensure_ascii=False, indent=2))
    print(f"source_turns_to_fetch: {to_fetch}")
    return {"elapsed": elapsed, "cost": cost, "header": header, "source_turns_to_fetch": to_fetch}


async def main():
    base_prompt = _load_prompt("chat_summary_prompt.txt")
    
    # Candidate prompt: allow detailed, precise items rather than forcing one short line
    candidate_prompt = base_prompt.replace(
        "- Each item is one short line. Avoid vague phrasing like \"discussed X\" — say what was actually decided or stated.",
        "- Items should be as detailed and specific as necessary to preserve exact requirements, parameters, criteria, or constraints (do not artificially compress them into a single vague line). Avoid conversational fluff and small talk, but never sacrifice concrete technical details or conditions for brevity. Avoid vague phrasing like \"discussed X\" — state the exact rules, values, and decisions."
    ).replace(
        "- `needs_source: false`: For standard facts, preferences, single questions, or when a concise description in `text` is sufficient.",
        "- `needs_source: false`: For standard facts, preferences, single questions, or when the full specifications/criteria can be cleanly described in `text`."
    )
    
    turns = make_test_case_3()
    print("=== Running Comparative Test on Test Case 3 (Current vs Candidate) ===")
    res_curr = await run_with_prompt(base_prompt, turns, "CURRENT PROMPT (One short line)")
    res_cand = await run_with_prompt(candidate_prompt, turns, "CANDIDATE PROMPT (Detailed as necessary)")


if __name__ == "__main__":
    asyncio.run(main())
