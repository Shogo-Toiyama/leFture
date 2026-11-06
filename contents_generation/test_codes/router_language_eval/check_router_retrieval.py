"""
振り分け役(本番の今のプロンプト+モデル)が、日付で講義を指した質問で needs_retrieval=true を返すかの確認。

対象: スレッド「不変データ構造」(886879bc)の「明日テストなんだけど…10月29日の内容って入る？」。
2026-11-06に本番(2.5 Flash Lite)は needs_retrieval=false と判定し、探索役が動かなかった。

本番に近づけるため、そのターンの時点で畳まれていた要約ブロック(chat_summary_blocks)、
要約より後ろの履歴、画面の講義ラベル(_lecture_label)を使う。

使い方 (リポジトリ直下から):
  .venv/bin/python contents_generation/test_codes/router_language_eval/check_router_retrieval.py --dry-run
  .venv/bin/python contents_generation/test_codes/router_language_eval/check_router_retrieval.py --repeat 3
"""

import argparse
import asyncio
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from supabase import create_client  # noqa: E402

from app.services import chat_service as cs  # noqa: E402
from app.services.chat_summary import fetch_active_blocks  # noqa: E402
from app.services.helpers.helpers import _load_prompt, _render_conditional_sections  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM  # noqa: E402

THREAD_ID = "886879bc-3721-4c68-9ffd-df42021d77fa"
MESSAGE_PREFIX = "明日テストなんだけど"


def build_input(c) -> tuple[str, dict]:
    ms = c.table("chat_messages").select("id,role,content,context,created_at") \
        .eq("thread_id", THREAD_ID).order("created_at").execute().data
    idx = next(i for i, m in enumerate(ms) if m["role"] == "user" and m["content"].startswith(MESSAGE_PREFIX))
    target = ms[idx]
    t_at = target["created_at"]

    # そのターンより前に畳まれていた要約だけを使う
    def before(blocks):
        return [b for b in blocks if (b.get("end_message_created_at") or "") < t_at]
    l1 = before(fetch_active_blocks(c, THREAD_ID, level=1))
    l2 = before(fetch_active_blocks(c, THREAD_ID, level=2))
    memory = cs.ConversationMemory.from_blocks(l1, l2)
    folded_until = l1[-1]["end_message_created_at"] if l1 else ""
    history = [Message(role=m["role"], content=m["content"])
               for m in ms[:idx] if (m["created_at"] > folded_until)]

    thread = c.table("chat_threads").select("user_id").eq("id", THREAD_ID).execute().data[0]
    lecture_id = (target.get("context") or {}).get("lecture_id")
    lecture_label = cs._lecture_label(c, lecture_id, thread["user_id"]) if lecture_id else None
    courses = c.table("courses").select("course_title").eq("user_id", thread["user_id"]).execute().data
    courses_text = "\n".join(f"- {r['course_title']} (term not set)" for r in courses)

    template = _render_conditional_sections(_load_prompt("chat_router_input_prompt.txt"), {"HAS_REFERENCED_SOURCES": False})
    user_input = cs.fill_placeholders(template, {
        "EARLIER_CONVERSATION": memory.for_router(),
        "REFERENCED_SOURCES": "",
        "RECENT_CONVERSATION": cs.format_router_conversation(history),
        "SCREEN_CONTEXT": cs.format_screen_context(lecture_label, None, None, full_page=False) or "(none)",
        "COURSES": courses_text,
        "ATTACHMENTS": "(none)",
        "IS_FIRST_MESSAGE": "false",
        "CURRENT_TIME": "2026-11-06 (Fri) 01:01",
        "NEW_MESSAGE": target["content"],
    })
    meta = {"message_index": idx, "summary_blocks_l1": len(l1), "summary_blocks_l2": len(l2),
            "history_messages": len(history), "lecture_label": lecture_label,
            "user_input_chars": len(user_input)}
    return user_input, meta


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--repeat", type=int, default=3)
    args = ap.parse_args()

    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    user_input, meta = build_input(c)
    system = _load_prompt("chat_router_prompt.txt")
    print("model:", cs.ROUTER_MODEL, "effort:", cs.ROUTER_REASONING_EFFORT)
    print("meta:", json.dumps(meta, ensure_ascii=False))
    print("system chars:", len(system))
    if args.dry_run:
        print("\n--- user input (head) ---\n" + user_input[:1500])
        print("\n--- user input (tail) ---\n" + user_input[-1200:])
        return

    billing = BillingEngine(task_type="router_retrieval_check")
    llm = UnifiedLLM(billing)
    options = LLMOptions(output_type="json", json_schema=cs.ROUTER_SCHEMA, temperature=0.0,
                         reasoning_effort=cs.ROUTER_REASONING_EFFORT)
    rows = []
    for i in range(1, args.repeat + 1):
        n_rec = len(billing.records)
        t0 = time.perf_counter()
        r = await llm.generate(cs.ROUTER_MODEL, [Message(role="system", content=system),
                                                  Message(role="user", content=user_input)], options)
        dt = round(time.perf_counter() - t0, 2)
        out = r.output_json or {}
        row = {"run": i, "needs_retrieval": out.get("needs_retrieval"), "pass": out.get("needs_retrieval") is True,
               "latency_s": dt, "tokens": {"in": r.input_tokens, "out": r.output_tokens, "cache": r.cache_read_tokens},
               "cost_usd": round(sum(x.cost_usd for x in billing.records[n_rec:]), 6),
               "output_json": out, "output_text": r.output_text,
               "cost_breakdown": [{"resource": x.resource, "usage": x.usage, "cost_usd": x.cost_usd}
                                  for x in billing.records[n_rec:]]}
        rows.append(row)
        print(f"#{i} needs_retrieval={row['needs_retrieval']} {'OK' if row['pass'] else 'NG'} {dt}s ${row['cost_usd']:.5f} "
              f"intent={out.get('intent')} reasoning={out.get('needs_reasoning')} lang={out.get('reply_language')}")
        print("   retrieval_reason:", out.get("retrieval_reason"))
    total = billing.total_usd()
    print(f"\nPASS {sum(r['pass'] for r in rows)}/{len(rows)}  TOTAL COST ${total:.5f}")
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_path = HERE / "results" / f"{ts}_router_retrieval_{cs.ROUTER_MODEL.split('/')[-1]}.json"
    out_path.write_text(json.dumps({"model": cs.ROUTER_MODEL, "effort": cs.ROUTER_REASONING_EFFORT, "meta": meta,
                                    "rows": rows, "total_cost_usd": total,
                                    "inputs": {"system": system, "user": user_input}},
                                   ensure_ascii=False, indent=2), encoding="utf-8")
    print("saved", out_path)


if __name__ == "__main__":
    asyncio.run(main())
