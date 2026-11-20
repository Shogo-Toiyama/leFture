"""Replay the production answer loop with stubbed provider events and label responses."""

import argparse
import asyncio
import json
import os
import subprocess
from pathlib import Path
import sys
import tempfile
import textwrap
import time
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASELINE = "a0bdf7f705f0718ce24160fea770f1a6334117f1"
SERVICE = "lefture_backend/app/services/"
sys.path.insert(0, str(ROOT / "lefture_backend"))

from app.services import chat_service as chat
from app.services.helpers import llm_unified


def saved_source(relative_path):
    return subprocess.check_output(["git", "show", f"{BASELINE}:{SERVICE}{relative_path}"], cwd=ROOT, text=True)


def patched_source(baseline):
    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / "chat_service.py"
        source.write_text(baseline)
        return subprocess.check_output(
            ["patch", "-s", "-o", "-", str(source), str(HERE / "candidate.patch")], text=True,
        )


def answer_loop(source):
    # Run the answer block directly to exercise its SSE events without persisting a turn.
    start = source.index("        answer_model, answer_effort = ANSWER_MODEL")
    end = source.index('        timer.mark("answer_done")', start)
    namespace = vars(chat).copy()
    exec(saved_source("chat_reasoning_progress.py"), namespace)
    prompt = saved_source("prompts/chat_reasoning_progress_prompt.txt")
    namespace["_load_prompt"] = lambda name: prompt if name == "chat_reasoning_progress_prompt.txt" else chat._load_prompt(name)
    body = textwrap.dedent(source[start:end])
    exec("async def run(llm, messages, decision, timer, stop, progress, emit):\n"
         "    navigation, materials = None, []\n" + textwrap.indent(body, "    "), namespace)
    return namespace["run"]


def saved_cases():
    from dotenv import load_dotenv
    from supabase import create_client

    load_dotenv(ROOT / "lefture_backend/.env")
    allowed = json.loads((ROOT / "tools/experiment_privacy/allowlist.json").read_text())
    developer = next(user["user_id"] for user in allowed["users"] if user["label"] == "developer")
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    fields = ("chat_threads!inner(),route:router->needs_reasoning,language:router->>reply_language,"
              "model:usage->>answer_model,thought:usage->reasoning->>thought,timing:usage->timings->ms")
    rows = (client.table("chat_messages").select(fields).eq("chat_threads.user_id", developer)
            .eq("role", "assistant").eq("status", "complete").eq("router->>needs_reasoning", "false")
            .not_.is_("usage->reasoning->>thought", "null").order("created_at", desc=True)
            .limit(2).execute().data)
    assert len(rows) == 2 and all(row["thought"] and row["language"] for row in rows)
    return rows


async def replay(run, row, *, slow=False, trailing_thought=False):
    events = []
    calls = []
    cancelled = asyncio.Event()
    stop_event = asyncio.Event()
    timer = chat.TurnTimer()

    class ReplayLLM(chat.UnifiedLLM):
        async def generate(self, model, messages, options):
            assert model == chat.ANSWER_MODEL
            assert "${reply_language}" not in messages[0].content
            assert row["language"] in messages[0].content
            assert messages[1].content.strip() and options.reasoning_effort == "none"
            assert options.max_tokens == 256
            assert self._build_kwargs(model, messages, options)["thinking"] == {"type": "disabled"}
            calls.append(time.perf_counter())
            if slow:
                try:
                    await asyncio.Future()
                finally:
                    cancelled.set()
            return SimpleNamespace(output_text="確認しています")

    stop = SimpleNamespace(stopped=False, event=stop_event, raise_if_stopped=lambda: None)

    def packet(*, thought=None, text=None):
        return SimpleNamespace(usage=None, choices=[
            SimpleNamespace(finish_reason=None, delta=SimpleNamespace(reasoning_content=thought, content=text)),
        ])

    async def completion(**kwargs):
        assert kwargs["model"] == row["model"] and kwargs["stream"]
        expected_effort = chat.REASONING_CONFIG.single_effort if row["route"] else chat.ANSWER_REASONING_EFFORT
        assert kwargs["reasoning_effort"] == expected_effort

        async def stream():
            for offset in range(0, len(row["thought"]), 40):
                yield packet(thought=row["thought"][offset:offset + 40])
                await asyncio.sleep(0.001)
            yield packet(text="Fixture answer.")
            if trailing_thought:
                yield packet(thought="Do not replace visible answer with progress.\n")

        return stream()

    async def emit(event, data):
        events.append((event, data, time.perf_counter()))

    billing = chat.BillingEngine(task_type="PROGRESS_REPLAY")
    with patch.object(llm_unified.litellm, "acompletion", completion):
        await asyncio.wait_for(run(
            ReplayLLM(billing), [chat.Message(role="user", content="Fixture question.")],
            SimpleNamespace(needs_reasoning=row["route"], reply_language=row["language"]),
            timer, stop, SimpleNamespace(answer_parts=[]), emit,
        ), 1)
    await asyncio.sleep(0)
    sequence = [data.get("stage", event) + (" label" if "progress_label" in data else "")
                for event, data, _ in events]
    assert events[-1][1] == {"text": "Fixture answer."}
    if slow:
        assert calls and cancelled.is_set()
    return {"sequence": sequence, "calls": len(calls),
            "mock_ttft_ms": timer.marks["answer_first_token"] - timer.marks["answer_started"]}


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--supabase", action="store_true")
    args = parser.parse_args()
    original = args.baseline.read_text() if args.baseline else saved_source("chat_service.py")
    candidate = answer_loop(args.candidate.read_text() if args.candidate else patched_source(original))
    baseline = answer_loop(original)

    fixture = {"model": chat.ANSWER_MODEL, "language": "Japanese", "route": False,
               "thought": "I am checking the scope of the selected variable.\n"}
    cases = saved_cases() if args.supabase else [fixture]
    for index, row in enumerate(cases, 1):
        before = await replay(baseline, row)
        assert before["sequence"] == ["writing", "delta"] and before["calls"] == 0
        print(json.dumps({"case": index, "variant": "before", **before}))
        after = await replay(candidate, row)
        assert after["sequence"][:3] == ["writing", "reasoning", "reasoning label"]
        assert after["sequence"][-1] == "delta" and after["calls"] >= 1
        timing = row.get("timing")
        print(json.dumps({"case": index, "variant": "after", **after,
                          "historical_ttft_ms": timing["answer_first_token"] - timing["answer_started"]
                          if timing else None}))

    no_thought = await replay(candidate, {**fixture, "thought": ""}, trailing_thought=True)
    assert no_thought["sequence"] == ["writing", "delta"] and no_thought["calls"] == 0
    explicit = await replay(candidate, {**fixture, "route": True})
    assert explicit["sequence"] == ["reasoning", "reasoning label", "delta"]
    slow = await replay(candidate, fixture, slow=True)
    assert slow["sequence"] == ["writing", "reasoning", "delta"]
    print(json.dumps({"no_thought": no_thought, "explicit_reasoning": explicit, "slow_summary": slow}))


if __name__ == "__main__":
    asyncio.run(main())
