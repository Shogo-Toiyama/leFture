"""Compare router-only decisions with production prompt rendering and billing."""

import argparse
import asyncio
from dataclasses import dataclass
from datetime import datetime
import json
import math
import os
from pathlib import Path
import random
from statistics import median
import sys
from time import perf_counter
from types import SimpleNamespace
from unittest.mock import patch
from zoneinfo import ZoneInfo

os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "lefture_backend"))

from dotenv import load_dotenv
from jsonschema import validate
from supabase import create_client

load_dotenv(ROOT / "lefture_backend" / ".env")

from app.services import chat_service as cs
from app.services.helpers.llm_unified import BillingEngine, Message, UnifiedLLM

TZ = ZoneInfo("America/Los_Angeles")
NOW = datetime(2026, 11, 18, 1, 3, tzinfo=TZ)
PRODUCTION = cs.ROUTER_MODEL
VARIANTS = {
    "current_31": (PRODUCTION, False),
    "revised_31": (PRODUCTION, True),
    "revised_35": ("gemini/gemini-3.5-flash-lite", True),
    "priority_31": (PRODUCTION, "priority"),
}
COURSES = "- Introduction to Statistics (Fall 2026)\n- Operating Systems (Fall 2026)"
HEADLINE = "今週のニュースです。市営フェリーが港の規制当局の命令を受けて、夜間運航を一時停止しました。⟦W2.4⟧"
DETAIL = HEADLINE + "引用記事によると、当局が発表した直接の理由は夜間誘導灯の故障です。⟦W2.5⟧"
EN_NEWS = "In the news this week, the city transport board delayed the new night bus route. ⟦W1.2⟧"
JP_HISTORY = (("user", "今週の気になるニュースを教えて！"), ("assistant", HEADLINE))
JP_DETAILS = (("user", "その運航停止はなぜ？"), ("assistant", DETAIL))
EN_HISTORY = (("user", "Any interesting local news this week?"), ("assistant", EN_NEWS))


@dataclass(frozen=True)
class Case:
    name: str
    group: str
    expected: bool
    text: str
    history: tuple[tuple[str, str], ...] = ()
    language: str = "ja"
    courses: str = COURSES
    lecture: str | None = None
    attachments: str = "(none)"
    recorded: dict | None = None
    selected_text: str | None = None


def synthetic_cases():
    return [
        Case("reactive_why_ja", "missing_detail", True, "えー困る！なんで？港のルール厳しすぎる", JP_HISTORY),
        Case("reactive_why_en", "missing_detail", True, "Ugh, why? This is so frustrating.", EN_HISTORY, "en"),
        Case("whose_decision", "missing_detail", True, "最初に運航停止を提案したのは誰？", JP_HISTORY),
        Case("reason_for_regulation", "missing_detail", True, "That seems harsh. What triggered the board's decision?", EN_HISTORY, "en"),
        Case("reaction_ja", "reaction", False, "えー困る！やりすぎな気がする", JP_HISTORY),
        Case("reaction_en", "reaction", False, "Ugh, that's frustrating. Thanks for telling me.", EN_HISTORY, "en"),
        Case("rhetorical_why", "reaction", False, "なんでこうなるかな〜。愚痴りたかっただけ。", JP_HISTORY),
        Case("already_supported", "supported", False, "結局、何の故障が原因だったんだっけ？", JP_DETAILS),
        Case("paraphrase_quote", "supported", False, "さっき引用してた記事の理由を一文で言い換えて。", JP_DETAILS),
        Case("confirmation_of_fact", "supported", False, "つまり止めたのは夜間運航だけってこと？", JP_HISTORY),
        Case("recheck_ja", "explicit_recheck", True, "別の情報源でもう一回確認してほしい", JP_DETAILS),
        Case("recheck_en", "explicit_recheck", True, "Can you look that up again and check a primary source?", EN_HISTORY, "en"),
        Case("no_search", "controls", False, "理由は気になるけど、検索しないで見出しから分かることだけ教えて。", JP_HISTORY),
        Case("general_why", "controls", False, "なんで水は凍ると体積が増えるの？"),
        Case("lecture_lookup", "controls", True, "先週の統計の講義で先生が説明した分布を調べて。"),
        Case("general_explanation", "controls", False, "この比喩を高校生向けに説明し直して。",
             (("user", "コンピューターのメモリについて教えて"), ("assistant", "メモリは作業中の書類を置く机のようなものです。"))),
    ]


def saved_case(title, reply_at):
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    threads = client.table("chat_threads").select("id").eq("title", title).is_("deleted_at", "null").execute().data
    assert threads
    replies = client.table("chat_messages").select("thread_id,router,usage") \
        .in_("thread_id", [thread["id"] for thread in threads]).eq("created_at", reply_at) \
        .eq("role", "assistant").is_("deleted_at", "null").execute().data
    assert len(replies) == 1
    reply = replies[0]
    rows = client.table("chat_messages").select("id,role,content,status,created_at,context") \
        .eq("thread_id", reply["thread_id"]).lt("created_at", reply_at).is_("deleted_at", "null") \
        .order("created_at", desc=True).limit(cs.RAW_FETCH_MESSAGES).execute().data
    rows.reverse()
    current = rows.pop()
    assert current["role"] == "user" and not (current.get("context") or {}).get("lecture_id")
    history = tuple((msg.role, msg.content) for msg in cs.build_history_messages(rows))
    assert history and "Waymo" in history[-1][1]
    recorded = {
        "intent": reply["router"]["intent"],
        "needs_retrieval": reply["router"]["needs_retrieval"],
        "router_tokens": reply["usage"]["timings"]["details"]["router"],
        "previous_reply_chars": len(history[-1][1]),
        "topic_offset_chars": history[-1][1].index("Waymo"),
        "router_history_char_limit": cs.ROUTER_HISTORY_MAX_CHARS_PER_MESSAGE,
    }
    # The authorization covers chat text, not the user's course list. Use the synthetic map labels.
    return Case("recorded_news_followup", "missing_detail", True, current["content"], history, recorded=recorded)


def candidate_prompt(original, revision):
    reason = "explaining why lecture retrieval is or is not needed"
    anchor = "false for everything else, including:"
    assert original.count(anchor) == 1 and original.count(reason) == 1
    updated = original.replace(reason, "explaining why additional retrieval is or is not needed")
    if revision == "priority":
        rule = (HERE / "retrieval_rule_v2.txt").read_text().strip()
        return updated.replace("### THEN, WHETHER TO FETCH", f"{rule}\n\n### THEN, WHETHER TO FETCH").replace(
            "asking you to explain or continue a topic the conversation is already about",
            "asking you to explain or continue a topic with the facts already supplied in the conversation")
    rule = (HERE / "retrieval_rule.txt").read_text().strip()
    return updated.replace(anchor, f"{rule}\n\n{anchor}")


class MockModel:
    def __init__(self, case, billing):
        self.case = case
        self.serializer = UnifiedLLM(billing)

    async def generate(self, model, messages, options):
        args = self.serializer._build_kwargs(model, messages, options)
        assert args["response_format"]["type"] == "json_schema"
        assert self.case.text in messages[-1].content
        output = {"intent": "personal", "needs_retrieval": self.case.expected, "needs_reasoning": False,
                  "reply_language": self.case.language, "thread_title": None,
                  "user_goal": "Classify the synthetic question.", "retrieval_reason": "Synthetic dry-run."}
        validate(output, options.json_schema)
        return SimpleNamespace(output_json=output, input_tokens=0, cache_read_tokens=0, output_tokens=0,
                               finish_reason="stop")


class FixedDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        return NOW.astimezone(tz) if tz else NOW


async def one(case, variant, dry):
    model, revised = VARIANTS[variant]
    history = [Message(role=role, content=text) for role, text in case.history]
    turn = cs.PreparedTurn(user_id="fixture", thread_id="fixture", is_new_thread=not history,
                           thread_has_title=bool(history), user_message_id="fixture", assistant_message_id="fixture",
                           content=case.text, selected_text=case.selected_text, lecture_label=case.lecture, context_lecture_id=None,
                           timezone_name=TZ.key)
    billing = BillingEngine(task_type="ROUTER_WEB_FOLLOWUP_EVAL")
    llm = MockModel(case, billing) if dry else UnifiedLLM(billing)
    load_prompt = cs._load_prompt

    def use_candidate(name):
        original = load_prompt(name)
        return candidate_prompt(original, revised) if revised and name == "chat_router_prompt.txt" else original

    start = perf_counter()
    with patch.object(cs, "ROUTER_MODEL", model), patch.object(cs, "_load_prompt", use_candidate), \
         patch.object(cs, "datetime", FixedDatetime):
        decision = await cs._run_router(llm, turn, cs.ConversationMemory(), history, case.courses, case.attachments)
    elapsed = (perf_counter() - start) * 1000
    tokens = [entry for entry in billing.records if entry.dimension == "tokens"]
    return {
        "case": case.name, "group": case.group, "variant": variant, "expected": case.expected,
        "actual": decision.needs_retrieval, "intent": decision.intent, "fallback": decision.fallback,
        "reply_language": decision.reply_language, "expected_language": case.language,
        "needs_reasoning": decision.needs_reasoning,
        "latency_ms": round(elapsed, 2),
        "provider_usd": round(sum(entry.cost_usd for entry in tokens), 8),
        "in_tokens": sum(int(entry.usage["input"]) for entry in tokens),
        "out_tokens": sum(int(entry.usage["output"]) for entry in tokens),
        "cache_read": sum(int(entry.usage.get("cache_read", 0)) for entry in tokens),
        "provider_calls_recorded": len(tokens),
    }


def summarize(rows):
    def per_variant(subset):
        valid = [row for row in subset if not row["fallback"]]
        latency = sorted(row["latency_ms"] for row in valid)
        return {
            "trials": len(subset), "correct": sum(row["expected"] == row["actual"] for row in valid),
            "missed_search": sum(row["expected"] and not row["actual"] for row in valid),
            "unnecessary_search": sum(not row["expected"] and row["actual"] for row in valid),
            "fallbacks": len(subset) - len(valid), "language_errors": sum(
                row["reply_language"] != row["expected_language"] for row in valid),
            "median_ms": round(median(latency), 2) if latency else None,
            "p95_ms": latency[math.ceil(0.95 * len(latency)) - 1] if latency else None,
            "input_tokens": sum(row["in_tokens"] for row in subset),
            "output_tokens": sum(row["out_tokens"] for row in subset),
            "provider_usd": round(sum(row["provider_usd"] for row in subset), 8),
        }
    return {variant: per_variant([row for row in rows if row["variant"] == variant])
            for variant in dict.fromkeys(row["variant"] for row in rows)}


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--recorded", nargs=2, metavar=("TITLE", "REPLY_AT"))
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--variants", nargs="+", choices=VARIANTS,
                        default=["current_31", "revised_31", "revised_35"])
    args = parser.parse_args()
    cases = [saved_case(*args.recorded)] if args.recorded else synthetic_cases()
    jobs = [(case, variant, repeat) for repeat in range(1, args.repeats + 1)
            for case in cases for variant in args.variants]
    random.Random(64).shuffle(jobs)
    stamp = datetime.now(TZ).strftime("%Y-%m-%dT%H%M%S%z")
    kind = "recorded" if args.recorded else "synthetic"
    variant_tag = f"-{args.variants[0]}" if len(args.variants) == 1 else ""
    output = HERE / "results" / f"{stamp}-{kind}{variant_tag}{'-dry-run' if args.dry_run else ''}.json"
    rows = []
    for case, variant, repeat in jobs:
        row = await one(case, variant, args.dry_run)
        rows.append({**row, "repeat": repeat})
        print(f"{variant} {case.name} {row['actual']} expected={case.expected}"
              f" {row['latency_ms']:.0f}ms fallback={row['fallback']}", flush=True)
        output.write_text(json.dumps({"mode": "dry" if args.dry_run else "live",
                                      "recorded_baseline": cases[0].recorded,
                                      "summary": summarize(rows), "trials": rows}, indent=2) + "\n")
    if args.dry_run:
        assert all(not row["fallback"] and row["actual"] == row["expected"] and not row["provider_usd"]
                   for row in rows)
    print(json.dumps(summarize(rows), indent=2))
    print(output.name, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
