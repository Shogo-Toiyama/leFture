"""Compare status prompts using only written-for-testing excerpts."""

import argparse
import asyncio
from datetime import datetime
import json
import os
from pathlib import Path
import sys
import time
from types import SimpleNamespace
from unittest.mock import patch
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")
sys.path.insert(0, str(ROOT / "lefture_backend"))

from app.services.helpers import llm_unified as llm

MODEL = "anthropic/claude-haiku-5-5"
CASES = {
    "practice_planning": "I'm planning practice questions for tree traversal, picking an example before adding a cheerful closing.",
    "thin_task_context": "The student wants a definition of lexical scope in Japanese. Need to explain it and keep the answer short.",
    "equation_only": "0.4 × 75 + 0.6x = 84. Then 0.6x = 54. x = 90.",
    "finding_only": "The local binding can't be accessed outside the function, which is why Python raises a NameError.",
    "presentation_only": "Use a friendly opening, avoid too many headings, and include an encouraging ending.",
    "generic_planning": "Think about how to approach it. Need to check the above first.",
}


async def evaluate(*, live, grounded):
    baseline = (HERE / "prompts/baseline_status.txt").read_text()
    old_ending = "Return NONE if it contains no suitable activity."
    assert baseline.strip().endswith(old_ending)
    name = "allow_grounded_activity" if grounded else "allow_broad_activity"
    candidate = baseline.strip().removesuffix(old_ending) + (HERE / "prompts" / f"{name}.txt").read_text()
    variants = [("grounded_activity", candidate)] if grounded else [("current", baseline), ("broad_activity", candidate)]
    summaries = []
    for case, excerpt in CASES.items():
        for variant, template in variants:
            prompt = template.replace("${reply_language}", "ja")
            messages = [llm.Message(role="system", content=prompt), llm.Message(role="user", content=excerpt)]
            options = llm.LLMOptions(temperature=1.0, max_tokens=256, reasoning_effort="none")
            billing = llm.BillingEngine()
            runner = llm.UnifiedLLM(billing)

            async def mock_completion(**kwargs):
                assert kwargs["thinking"] == {"type": "disabled"} and kwargs["max_tokens"] == 256
                assert kwargs["messages"][-1]["content"] == excerpt
                assert kwargs["messages"][0]["content"] == prompt and "${reply_language}" not in prompt
                return SimpleNamespace(
                    choices=[SimpleNamespace(message=SimpleNamespace(content="確認中"), finish_reason="stop")],
                    usage=SimpleNamespace(prompt_tokens=1, completion_tokens=1),
                )

            for repetition in range(1, 3 if live else 2):
                started = time.perf_counter()
                if live:
                    answer = await runner.generate(MODEL, messages, options)
                else:
                    with patch.object(llm.litellm, "acompletion", mock_completion):
                        answer = await runner.generate(MODEL, messages, options)
                records = [r for r in billing.records if r.dimension == "tokens"]
                token_cost = records[-1].cost_usd
                text = " ".join(answer.output_text.split())
                row = {"case": case, "variant": variant, "repetition": repetition,
                       "result": text, "none": text.upper() == "NONE",
                       "elapsed_ms": round((time.perf_counter() - started) * 1000),
                       "input_tokens": answer.input_tokens if live else 0,
                       "output_tokens": answer.output_tokens if live else 0,
                       "provider_cost_usd": token_cost if live else 0}
                summaries.append(row)
                print(json.dumps(row, ensure_ascii=False), flush=True)
    stamp = datetime.now(ZoneInfo("America/Los_Angeles")).strftime("%Y-%m-%dT%H%M%S%z")
    result = HERE / "results" / f"{stamp}-{'live' if live else 'dry'}.json"
    result.write_text(json.dumps(summaries, indent=2, ensure_ascii=False) + "\n")
    print(result)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--grounded", action="store_true")
    args = parser.parse_args()
    if args.live:
        from dotenv import load_dotenv
        load_dotenv(ROOT / "lefture_backend/.env")
    asyncio.run(evaluate(live=args.live, grounded=args.grounded))
