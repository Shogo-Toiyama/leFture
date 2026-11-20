"""Test generic progress labels and the last-resort NONE on synthetic excerpts."""

import argparse
import asyncio
from datetime import datetime
from html import escape
import json
import os
from pathlib import Path
import re
import sys
from types import SimpleNamespace
from unittest.mock import patch
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")
sys.path.insert(0, str(ROOT / "lefture_backend"))

from app.services.chat_map import language_name
from app.services.helpers import llm_unified as llm

CASES = {
    "unresolved_reference": ("Think about how to approach it. Need to check the above first.", True),
    "response_style": ("Use a friendly opening, avoid too many headings, and include an encouraging ending.", True),
    "equation": ("0.4 × 75 + 0.6x = 84. Then 0.6x = 54. x = 90.", True),
    "concrete_topic": ("I'm creating a Python exercise about lexical scope, and considering an encouraging closing.", True),
    "unintelligible": ("zxqvt ... ## ?! zplbk", False),
    "punctuation_only": (" ... ? ", False),
}


async def evaluate(*, live, use_production):
    prompt_file = (ROOT / "lefture_backend/app/services/prompts/chat_reasoning_progress_prompt.txt"
                   if use_production else HERE / "prompts/fallback_status.txt")
    prompt = prompt_file.read_text().replace("${reply_language}", language_name("ja"))
    options = llm.LLMOptions(temperature=1.0, max_tokens=256, reasoning_effort="none")
    rows = []
    for case, (excerpt, expected_label) in CASES.items():
        content = f"<excerpt>\n{escape(excerpt, quote=False)}\n</excerpt>"
        messages = [llm.Message(role="system", content=prompt), llm.Message(role="user", content=content)]

        async def mock_completion(**kwargs):
            assert kwargs["thinking"] == {"type": "disabled"} and kwargs["max_tokens"] == 256
            assert kwargs["messages"][0]["content"] == prompt and "${reply_language}" not in prompt
            assert kwargs["messages"][1]["content"] == content
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(content="内容を確認しています" if expected_label else "NONE"),
                                         finish_reason="stop")],
                usage=SimpleNamespace(prompt_tokens=3, completion_tokens=2),
            )

        for _ in range(2 if live else 1):
            billing = llm.BillingEngine()
            runner = llm.UnifiedLLM(billing)
            if live:
                result = await runner.generate("anthropic/claude-haiku-5-5", messages, options)
            else:
                with patch.object(llm.litellm, "acompletion", mock_completion):
                    result = await runner.generate("anthropic/claude-haiku-5-5", messages, options)
            label = result.output_text.strip()
            valid = (len(label) <= 60 and len(label.splitlines()) == 1 and bool(re.search(r"[ぁ-ゖァ-ヺ]", label))
                     and not label.endswith((".", "。", "!", "！", "?", "？"))) if expected_label else label == "NONE"
            if case == "unresolved_reference":
                valid = valid and "確認" in label and "内容" in label
            row = {
                "case": case, "label": label, "expected_label": expected_label, "valid": valid,
                "elapsed_ms": round(result.elapsed_seconds * 1000),
                "input_tokens": result.input_tokens if live else 0,
                "output_tokens": result.output_tokens if live else 0,
                "provider_cost_usd": sum(record.cost_usd for record in billing.records
                                         if live and record.dimension == "tokens"),
            }
            rows.append(row)
            print(json.dumps(row, ensure_ascii=False), flush=True)
    stamp = datetime.now(ZoneInfo("America/Los_Angeles")).strftime("%Y-%m-%dT%H%M%S%z")
    target = HERE / "results" / f"{stamp}-{'live' if live else 'dry'}.json"
    target.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
    print(target)
    assert all(row["valid"] for row in rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--production", action="store_true", help="Read the deployed prompt source instead of the candidate")
    args = parser.parse_args()
    if args.live:
        from dotenv import load_dotenv
        load_dotenv(ROOT / "lefture_backend/.env")
    asyncio.run(evaluate(live=args.live, use_production=args.production))
