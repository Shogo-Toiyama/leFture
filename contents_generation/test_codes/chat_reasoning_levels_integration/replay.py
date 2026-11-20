"""Check four-level routing and progress without writes to Supabase."""

import argparse
import asyncio
import importlib.util
import json
import os
from pathlib import Path
import sys
import textwrap
from types import SimpleNamespace as NS
from unittest.mock import patch

import httpx

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")
sys.path.insert(0, str(ROOT / "lefture_backend"))

from app.services import chat_service as production
from app.services.helpers import llm_unified as llm_api

LEVELS = ("none", "low", "medium", "high")


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def load_candidate(directory):
    if directory is None:
        return production
    backend = load_module("candidate_chat_service", directory / "chat_service.py")
    progress = load_module("candidate_chat_progress", directory / "chat_reasoning_progress.py")
    backend.ReasoningProgress = progress.ReasoningProgress
    candidate_llm = load_module("candidate_llm_unified", directory / "llm_unified.py")
    backend.UnifiedLLM = candidate_llm.UnifiedLLM
    backend._load_prompt = lambda name: ((directory / name).read_text(encoding="utf-8")
                                         if name == "chat_router_prompt.txt" else production._load_prompt(name))
    return backend


def answer_loop(backend):
    # Exercise the same stream loop as a chat turn without billing or mutating its rows.
    source = Path(backend.__file__).read_text()
    start = source.index("        answer_model = ANSWER_MODEL")
    end = source.index('        timer.mark("answer_done")', start)
    namespace = vars(backend).copy()
    body = textwrap.dedent(source[start:end])
    exec("async def answer(llm, messages, decision, timer, stop, progress, emit):\n"
         "    navigation, materials = None, []\n" + textwrap.indent(body, "    ") +
         "    return state\n", namespace)
    return namespace["answer"]


def response(text, *, in_tokens=10, out_tokens=5):
    return NS(choices=[NS(message=NS(content=text), finish_reason="stop")],
              usage=NS(prompt_tokens=in_tokens, completion_tokens=out_tokens))


async def run_answer(backend, llm, decision, messages):
    timer = backend.TurnTimer()
    stop = NS(stopped=False, event=asyncio.Event(), raise_if_stopped=lambda: None)
    events = []

    async def emit(kind, payload):
        events.append((kind, payload))

    state = await answer_loop(backend)(
        llm, messages, decision, timer, stop, NS(answer_parts=[]), emit,
    )
    await asyncio.sleep(0)
    elapsed = {key.removeprefix("answer_") + "_ms": timer.marks[key] - timer.marks["answer_started"]
               for key in ("answer_first_thought", "answer_first_progress_label", "answer_first_token")
               if key in timer.marks}
    return events, state, elapsed


def verify_attachment_gate(backend):
    source = Path(backend.__file__).read_text()
    start = source.index("        retrieval_forced = False")
    end = source.index("        # --- 3. 分岐: 探索 ---", start)
    code = compile(textwrap.dedent(source[start:end]), backend.__file__, "exec")
    for level in LEVELS:
        for mentioned, new, full, already_retrieving in (
            (False, True, False, False), (True, False, False, False),
            (False, True, True, False), (False, True, False, True),
            (False, False, False, False),
        ):
            visibility = NS(is_mentioned=lambda _: mentioned, is_full=lambda _: full)
            decision = backend.RouterDecision("learning", already_retrieving, "en", None, reasoning_level=level)
            turn = NS(attachments=[NS(id="fixture")], new_attachment_rows=[{"id": "fixture"}] if new else [])
            env = dict(attachment_visibility=visibility, decision=decision, turn=turn)
            exec(code, env)
            deep = level in ("medium", "high")
            assert env["must_check_attachments"] == (deep and (mentioned or new) and not full)
            assert decision.needs_retrieval == (already_retrieving or (not full and (mentioned or (deep and new))))
            assert env["retrieval_forced"] == (decision.needs_retrieval and not already_retrieving)


async def dry_run(backend):
    schema = backend.ROUTER_SCHEMA
    assert schema["properties"]["reasoning_level"]["enum"] == list(LEVELS)
    assert "reasoning_level" in schema["required"] and "needs_reasoning" not in schema["properties"]
    prompt = backend._load_prompt("chat_router_prompt.txt")
    v3 = (HERE.parent / "router_reasoning_levels/prompts/router_levels_v3.txt").read_text()
    start, end = "### ALSO, HOW MUCH", "### LAST"
    assert prompt.split(start)[1].split(end)[0] == v3.split(start)[1].split(end)[0]
    for raw, expected, fallback in [
        ({"intent": "learning", "needs_reasoning": True}, "high", False),
        ({"intent": "learning", "needs_reasoning": False}, "low", False),
        ({"intent": "personal", "reasoning_level": "unknown"}, "low", True),
        ({"intent": "learning", "reasoning_level": []}, "low", True),
        ({"intent": "learning"}, "low", True),
        (None, "low", True),
        ({"intent": "blocked", "reasoning_level": "high"}, "none", False),
        ({"intent": "crisis", "reasoning_level": "high"}, "none", False),
    ]:
        decision = backend.normalize_router_output(raw, "Example question", False)
        assert (decision.reasoning_level, decision.fallback) == (expected, fallback)
    verify_attachment_gate(backend)

    attachment_text = "A1 — Example handout (FULL TEXT visible)"
    turn = NS(is_new_thread=False, thread_has_title=True, timezone_name="America/Los_Angeles",
              lecture_label=None, selected_text=None, screen_page=None, reply_quote=None,
              message_for_prompt="Explain the rule.", language_hint=lambda: "Explain the rule.",
              timer=backend.TurnTimer())
    metrics = []
    for level, behavior in [(value, "label") for value in LEVELS] + [
        ("low", "skip"), ("medium", "slow"), ("high", "late"),
    ]:
        label_started, cancelled = asyncio.Event(), asyncio.Event()
        label_calls = 0

        async def completion(**kwargs):
            nonlocal label_calls
            if kwargs["model"] == backend.ROUTER_MODEL:
                assert kwargs["response_format"]["json_schema"]["schema"] == schema
                assert kwargs["messages"][0]["content"] == prompt
                assert attachment_text in kwargs["messages"][1]["content"]
                return response(json.dumps({"intent": "learning", "reasoning_level": level,
                                            "needs_retrieval": False, "reply_language": "ja"}))

            if not kwargs.get("stream"):
                label_calls += 1
                assert kwargs["thinking"] == {"type": "disabled"} and kwargs["max_tokens"] == 256
                assert "Japanese" in kwargs["messages"][0]["content"] and "${reply_language}" not in kwargs["messages"][0]["content"]
                assert kwargs["messages"][1]["content"] == "<excerpt>\nChecking the selected rule.\n</excerpt>"
                label_started.set()
                if behavior == "slow":
                    try:
                        await asyncio.Future()
                    finally:
                        cancelled.set()
                return response("規則の適用条件を確認中")

            assert kwargs["thinking"] == ({"type": "disabled"} if level == "none"
                                          else {"type": "adaptive", "display": "summarized"})
            if level != "none":
                assert kwargs["reasoning_effort"] == level

            def chunk(thought=None, text=None):
                return NS(choices=[NS(delta=NS(reasoning_content=thought, content=text))], usage=None)

            async def stream():
                if behavior not in ("skip", "late"):
                    yield chunk(thought="Checking the selected ")
                    yield chunk(thought="rule.")
                    if level != "none":
                        await asyncio.wait_for(label_started.wait(), 1)
                yield chunk(text="Fixture answer.")
                if behavior == "late":
                    yield chunk(thought="Checking the selected rule.\n")

            return stream()

        billing = llm_api.BillingEngine()
        llm = backend.UnifiedLLM(billing)
        with patch.object(llm_api.litellm, "acompletion", completion):
            decision = await backend._run_router(llm, turn, backend.ConversationMemory(), [],
                                                 attachments_text=attachment_text)
            assert decision.to_json()["reasoning_level"] == level
            assert decision.needs_reasoning == (level in ("medium", "high"))
            events, _, elapsed = await run_answer(backend, llm, decision, [backend.Message(role="user", content="Fixture.")])
        labels = [event[1]["progress_label"] for event in events if "progress_label" in event[1]]
        assert events[0] == ("status", {"stage": "writing" if level == "none" else "reasoning"})
        assert events[-1] == ("delta", {"text": "Fixture answer."})
        assert labels == (["規則の適用条件を確認中"] if level != "none" and behavior == "label" else [])
        assert label_calls == int(level != "none" and behavior in ("label", "slow"))
        assert cancelled.is_set() == (behavior == "slow")
        assert ("first_progress_label_ms" in elapsed) == bool(labels)
        assert ("first_thought_ms" in elapsed) == (level != "none" and behavior in ("label", "slow"))
        metrics.append({"level": level, "behavior": behavior, "labels": len(labels), **elapsed})
    print(json.dumps({"mode": "dry", "attachment_cases": 20, "stream_cases": metrics,
                      "provider_tokens": 0, "provider_cost_usd": 0}))


async def verify_haiku_wire_effort(backend):
    # Intercept the final Anthropic request, after LiteLLM's provider-specific rewrite.
    bodies = []
    output = [
        {"type": "message_start", "message": {"id": "fixture", "type": "message", "role": "assistant",
         "model": "claude-haiku-5-5", "content": [], "usage": {"input_tokens": 10, "output_tokens": 0}}},
        {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
        {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "OK"}},
        {"type": "content_block_stop", "index": 0},
        {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 1}},
        {"type": "message_stop"},
    ]
    stream = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n" for event in output)

    async def send(_client, request, **kwargs):
        assert (request.url.host, request.url.path) == ("api.anthropic.com", "/v1/messages")
        bodies.append(json.loads(request.content))
        return httpx.Response(200, request=request, text=stream, headers={"Content-Type": "text/event-stream"})

    llm = backend.UnifiedLLM(llm_api.BillingEngine())
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "fixture"}):
        with patch.object(httpx.AsyncClient, "send", send):
            for level in LEVELS:
                state = llm_api.StreamState()
                options = backend.answer_options(backend.ANSWER_MODEL, level, 2048)
                text = "".join([delta async for delta in llm.generate_stream(
                    backend.ANSWER_MODEL, [backend.Message(role="user", content="Fixture.")], state, options,
                )])
                assert text == "OK"
    assert len(bodies) == len(LEVELS)
    assert bodies[0]["thinking"] == {"type": "disabled"} and "output_config" not in bodies[0]
    for level, body in zip(LEVELS[1:], bodies[1:]):
        assert body["thinking"] == {"type": "adaptive", "display": "summarized"}
        assert body["output_config"] == {"effort": level}
    print(json.dumps({"anthropic_wire_efforts": list(LEVELS), "provider_tokens": 0, "provider_cost_usd": 0}))


def billing_metrics(billing):
    records = [r for r in billing.records if r.dimension == "tokens"]
    return {"input_tokens": sum(r.usage["input"] for r in records),
            "output_tokens": sum(r.usage["output"] for r in records),
            "provider_cost_usd": round(sum(r.cost_usd for r in records), 8)}


async def supabase_replay(backend):
    from dotenv import load_dotenv
    from supabase import create_client

    sys.path.insert(0, str(HERE.parent / "router_reasoning_eval"))
    from run_eval import build_input

    sys.path.insert(0, str(HERE.parent / "reply_ending_eval"))
    import replay as answer_replay

    load_dotenv(ROOT / "lefture_backend/.env")
    allowed = json.loads((ROOT / "tools/experiment_privacy/allowlist.json").read_text())
    developer = next(user["user_id"] for user in allowed["users"] if user["label"] == "developer")
    db = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    threads = db.table("chat_threads").select("id").eq("user_id", developer).execute().data
    courses_text = production.router_courses_text(production.load_student_map(db, developer))
    blocked = production._load_blocked_source_types(developer)
    # Three recorded, developer-owned cases from the v3 probe.
    fixtures = [("6a3080e4", "7acf61c0", "none"), ("886879bc", "26472a8f", "low"),
                ("931543fd", "fc388cec", "medium")]
    for i, (thread_prefix, message_prefix, expected) in enumerate(fixtures, 1):
        thread = next(t["id"] for t in threads if t["id"].startswith(thread_prefix))
        rows = (db.table("chat_messages").select("id, thread_id, role, content, status, created_at, context, router, usage")
                .eq("thread_id", thread).order("created_at").execute().data)
        idx = next(i for i, r in enumerate(rows) if r["role"] == "user" and r["id"].startswith(message_prefix))
        router_input, _ = build_input(db, rows, idx, developer, courses_text, blocked, thread=thread)
        saved = rows[idx + 1]
        assert saved["role"] == "assistant"
        previous = (saved.get("router") or {}).get("needs_reasoning")
        billing = llm_api.BillingEngine()
        llm = backend.UnifiedLLM(billing)
        assert all(value not in router_input for value in ("${NEW_MESSAGE}", "${RECENT_CONVERSATION}"))
        opts = llm_api.LLMOptions(output_type="json", json_schema=backend.ROUTER_SCHEMA,
                                  reasoning_effort=backend.ROUTER_REASONING_EFFORT, temperature=0)
        prompts = [backend.Message(role="system", content=backend._load_prompt("chat_router_prompt.txt")),
                   backend.Message(role="user", content=router_input)]
        async def mock_completion(**kwargs):
            assert kwargs["response_format"]["json_schema"]["schema"] == backend.ROUTER_SCHEMA
            return response(json.dumps({"intent": "learning", "reasoning_level": expected,
                                        "reply_language": "ja", "needs_retrieval": False}))

        with patch.object(llm_api.litellm, "acompletion", mock_completion):
            routed = await llm.generate(backend.ROUTER_MODEL, prompts, opts)
        decision = backend.normalize_router_output(routed.output_json, rows[idx]["content"], False)
        assert decision.reasoning_level == expected
        print(json.dumps({"case": i, "level": decision.reasoning_level, "historical_boolean": previous,
                          "provider_cost_usd": 0}), flush=True)

        if expected == "medium":
            answer_replay.VARIANT_PROMPTS.clear()
            with patch.object(answer_replay, "find_message", return_value=saved):
                case = await answer_replay.build_case(db, {"id": "saved calculation", "msg": "saved"})
            request = llm._build_kwargs(backend.ANSWER_MODEL, case["messages_prod_prompt"],
                                        backend.answer_options(backend.ANSWER_MODEL, "medium", 2048))
            assert request["thinking"] == {"type": "adaptive", "display": "summarized"}
            print(json.dumps({"case": i, "answer_request_dry_run": True,
                              "messages": len(case["messages_prod_prompt"])}))


async def synthetic_replay(backend, *, live=False):
    """Exercise the deployed provider request format using only author-written examples."""
    from dotenv import load_dotenv

    if live:
        load_dotenv(ROOT / "lefture_backend/.env")
    examples = (
        ("none", "ありがとう、助かった！"),
        ("low", "プログラミングの変数のスコープって何？簡単な例で教えて。"),
        ("medium", "75点のテストが成績の40%、次のテストが60%です。最終成績を84点にするには、"
                   "次が90点で合ってる？式の確認もお願いします。"),
    )
    for expected, question in examples:
        turn = backend.PreparedTurn(
            user_id="fixture", thread_id="fixture", is_new_thread=False, thread_has_title=True,
            user_message_id="fixture", assistant_message_id="fixture", content=question,
            selected_text=None, lecture_label=None, context_lecture_id=None,
            timezone_name="America/Los_Angeles",
        )
        memory = backend.ConversationMemory()
        router_billing = llm_api.BillingEngine()
        if not live:
            decision = backend.RouterDecision("learning", False, "ja", None, reasoning_level=expected)
            messages = backend._build_answer_messages(turn, decision, memory, [], "", [])
            request = backend.UnifiedLLM(router_billing)._build_kwargs(
                backend.ANSWER_MODEL, messages, backend.answer_options(backend.ANSWER_MODEL, expected, 2048),
            )
            assert request["messages"] and request["thinking"]["type"] == (
                "disabled" if expected == "none" else "adaptive"
            )
            continue
        decision = await backend._run_router(
            backend.UnifiedLLM(router_billing), turn, memory, [],
            courses_text="(The student has no courses yet.)",
        )
        turn.timer.mark("router_done")
        assert not decision.fallback and decision.reasoning_level in LEVELS
        messages = backend._build_answer_messages(turn, decision, memory, [], "", [])
        messages = backend.fit_answer_input(messages)[0]
        answer_billing = llm_api.BillingEngine()
        events, state, elapsed = await run_answer(
            backend, backend.UnifiedLLM(answer_billing), decision, messages,
        )
        assert state.output_text
        print(json.dumps({
            "case": expected, "level": decision.reasoning_level,
            "router_ms": turn.timer.marks["router_done"], "router": billing_metrics(router_billing),
            "answer": billing_metrics(answer_billing), "answer_ms": round(state.elapsed_seconds * 1000),
            **elapsed, "labels": [data["progress_label"] for _, data in events if "progress_label" in data],
            "synthetic_reply": state.output_text,
        }, ensure_ascii=False), flush=True)


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--supabase", action="store_true", help="Provider mock with approved data, read-only")
    mode.add_argument("--synthetic-live", action="store_true")
    args = parser.parse_args()
    candidate = load_candidate(args.candidate)
    await dry_run(candidate)
    await verify_haiku_wire_effort(candidate)
    if args.supabase:
        await supabase_replay(candidate)
    else:
        await synthetic_replay(candidate)
        if args.synthetic_live:
            await synthetic_replay(candidate, live=True)


if __name__ == "__main__":
    asyncio.run(main())
