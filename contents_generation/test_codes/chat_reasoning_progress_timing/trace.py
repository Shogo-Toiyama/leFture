"""Measure the existing progress deadline using synthetic prompts only."""

import argparse
import asyncio
from contextlib import nullcontext
from datetime import datetime
import json
from pathlib import Path
import sys
import time
from types import SimpleNamespace
from unittest.mock import patch
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "chat_reasoning_levels_integration"))
import replay


async def trace(level, question, *, mock_summary_seconds=None):
    chat = replay.production
    billing = replay.llm_api.BillingEngine()
    llm = chat.UnifiedLLM(billing)
    timestamps = []
    prompt_stats = []
    base_progress = chat.ReasoningProgress
    base_timer = chat.TurnTimer

    def record(name):
        timestamps.append((name, time.perf_counter()))

    class TracedTimer(base_timer):
        def mark(self, name):
            super().mark(name)
            if name in ("answer_started", "answer_first_thought",
                        "answer_first_progress_label", "answer_first_token"):
                record(name)

    class TracedProgress(base_progress):
        def __init__(self, summarize, publish):
            async def timed_summary(excerpt):
                record("summary_started")
                prompt_stats.append({"excerpt_chars": len(excerpt)})
                try:
                    text = await summarize(excerpt)
                except asyncio.CancelledError:
                    record("summary_cancelled")
                    raise
                except Exception:
                    record("summary_failed")
                    raise
                record("summary_none" if text.strip().upper() == "NONE" else "summary_finished")
                return text
            super().__init__(timed_summary, publish)

        def feed(self, chunk):
            previous = self._task
            super().feed(chunk)
            if previous is None and self._task is not None:
                record("first_excerpt_ready")

    async def mock_provider(**kwargs):
        if not kwargs.get("stream"):
            await asyncio.sleep(mock_summary_seconds)
            return replay.response("加重平均の式を確認中")

        def chunk(*, thought=None, content=None):
            return SimpleNamespace(
                choices=[SimpleNamespace(delta=SimpleNamespace(reasoning_content=thought, content=content))],
                usage=None,
            )

        async def stream():
            await asyncio.sleep(0.01)
            yield chunk(thought="Checking the weighted average")
            await asyncio.sleep(0.01)
            yield chunk(thought=" formula.")
            await asyncio.sleep(0.02)
            yield chunk(content="Fixture answer.")
        return stream()

    turn = chat.PreparedTurn(
        user_id="fixture", thread_id="fixture", is_new_thread=False, thread_has_title=True,
        user_message_id="fixture", assistant_message_id="fixture", content=question,
        selected_text=None, lecture_label=None, context_lecture_id=None,
        timezone_name="America/Los_Angeles",
    )
    decision = chat.RouterDecision("learning", False, "ja", None, reasoning_level=level)
    memory = chat.ConversationMemory()
    messages = chat.fit_answer_input(chat._build_answer_messages(turn, decision, memory, [], "", []))[0]
    mock = patch.object(replay.llm_api.litellm, "acompletion", mock_provider) if mock_summary_seconds is not None else nullcontext()
    with mock, patch.object(chat, "ReasoningProgress", TracedProgress), patch.object(chat, "TurnTimer", TracedTimer):
        events, state, _ = await replay.run_answer(chat, llm, decision, messages)
    start = timestamps[0][1]
    assert timestamps[0][0] == "answer_started" and state.output_text
    result = {
        "level": level,
        "events_ms": [(name, round((when - start) * 1000)) for name, when in timestamps],
        "summary_excerpts": prompt_stats,
        "labels": sum("progress_label" in payload for _, payload in events),
    }
    if mock_summary_seconds is not None:
        result["provider_cost_usd"] = 0
    else:
        result.update(replay.billing_metrics(billing))
    return result


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    grade = "75点のテストが成績の40%、次のテストが60%です。最終成績を84点にするには、次が90点で合ってる？式の確認もお願いします。"
    results = []
    cases = [
        ("dry_completed", "medium", grade, 0),
        ("dry_cancelled", "medium", grade, 0.2),
    ]
    if args.live:
        from dotenv import load_dotenv
        load_dotenv(replay.ROOT / "lefture_backend/.env")
        cases.extend([
            ("weighted_grade_1", "medium", grade, None),
            ("weighted_grade_2", "medium", grade, None),
            ("variable_scope", "low", "プログラミングの変数のスコープって何？簡単な例で教えて。", None),
        ])
    for name, level, question, mock_seconds in cases:
        result = {"case": name, **await trace(level, question, mock_summary_seconds=mock_seconds)}
        results.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
        names = [event for event, _ in result["events_ms"]]
        if name == "dry_completed":
            assert names.index("summary_finished") < names.index("answer_first_token")
        if name == "dry_cancelled":
            assert "summary_finished" not in names and names.index("answer_first_token") < names.index("summary_cancelled")
    stamp = datetime.now(ZoneInfo("America/Los_Angeles")).strftime("%Y-%m-%dT%H%M%S%z")
    dest = HERE / "results" / f"{stamp}-{'live' if args.live else 'dry'}.json"
    dest.write_text(json.dumps(results, indent=2) + "\n")
    print(dest)


if __name__ == "__main__":
    asyncio.run(main())
