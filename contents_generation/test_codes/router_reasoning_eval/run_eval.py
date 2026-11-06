"""
振り分け役の needs_reasoning の判定を、修正版プロンプト(prompts/router_v1.txt)と本番のモデル
(gemini-3.1-flash-lite, 推論なし)で確かめる。baselineは流さず、本番に保存された判定と並べる。

ケースは「不変データ構造」スレッドの実際のターン。入力は本番と同じ形で組み立てる:
そのターンより前に畳まれた要約・要約より後ろの履歴・画面(講義・選択テキスト・見ているページ)・
添付資料の一覧(render_for_router)・コース一覧・元の時刻。
本番と違うところ: 添付資料の「選択中」は今の状態を使う。コース一覧は名前だけ(学期なし)。

  .venv/bin/python contents_generation/test_codes/router_reasoning_eval/run_eval.py --dry-run
  .venv/bin/python contents_generation/test_codes/router_reasoning_eval/run_eval.py
"""

import argparse
import asyncio
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from supabase import create_client  # noqa: E402

from app.services import chat_service as cs  # noqa: E402
from app.services.chat_attachments import Attachment, mention_ids, plan_visibility, render_for_router  # noqa: E402
from app.services.chat_screen import ScreenRef, ScreenSelection, load_screen_page  # noqa: E402
from app.services.chat_summary import fetch_active_blocks  # noqa: E402
from app.services.helpers.helpers import _load_prompt, _render_conditional_sections  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM  # noqa: E402

THREAD = "886879bc-3721-4c68-9ffd-df42021d77fa"
TZ = ZoneInfo("America/Los_Angeles")
PROMPT_V1 = HERE / "prompts" / "router_v1.txt"

# (生徒のメッセージの書き出し, 期待するneeds_reasoning)。2026-11-06にユーザーと線引きを決めた:
# 意味・用語・一言の理解の確認・説明・まとめ・翻訳はfalse、宿題の解答・コード・問題を解く・計算への押し返しはtrue
CASES = [
    ("これってどう言う意味だっけ？", False),
    ("Implicit Conversion = Coercionっていう認識で合ってる？！", False),
    ("Type promotionは？", False),
    ("日本語で説明して。", False),
    ("分かりやすい！あ、そうだ、Shadowingの例も同じように挙げて説明して欲しい。", False),
    ("これはどんな言語でも絶対？それともこの場合は特別？", False),
    ("これどう言うコード？", True),
    ("え、僕の宿題の答えはこうだったんだけど。", True),
    ("TYPING5に進みたいんだけど、これ、1つ目の問題はStatically Typedだと思うんだけど", True),
    ("でもさ、実行前に起こるからと言って必ず静的型付けになるのかな？", True),
]


def build_input(c, rows: list[dict], idx: int, user_id: str, courses_text: str, blocked, thread: str = THREAD) -> tuple[str, dict]:
    target = rows[idx]
    t_at = target["created_at"]

    def before(blocks):
        return [b for b in blocks if (b.get("end_message_created_at") or "") < t_at]
    l1 = before(fetch_active_blocks(c, thread, level=1))
    l2 = before(fetch_active_blocks(c, thread, level=2))
    memory = cs.ConversationMemory.from_blocks(l1, l2)
    folded_until = l1[-1]["end_message_created_at"] if l1 else ""
    history_rows = [r for r in rows[:idx] if r["created_at"] > folded_until]
    history = cs.build_history_messages(history_rows, cs.RAW_MAX_TURNS, cs.HISTORY_MAX_CHARS_PER_MESSAGE)

    ctx = target.get("context") or {}
    lecture_id = ctx.get("lecture_id")
    lecture_label = cs._lecture_label(c, lecture_id, user_id) if lecture_id else None
    selected = ctx.get("selected_text")
    page = None
    if ctx.get("screen"):
        sel = ScreenSelection(text=selected, before=ctx.get("selection_before") or "", after=ctx.get("selection_after") or "") if selected else None
        page = load_screen_page(c, user_id, ScreenRef(**ctx["screen"]), lecture_id, sel, blocked)

    att_rows = c.table("chat_attachments").select(cs.ATTACHMENT_COLUMNS).eq("thread_id", thread) \
        .lte("created_at", t_at).order("created_at").execute().data
    attachments = [Attachment.from_row(r) for r in att_rows if r.get("status") == "ready"]
    new_ids = {r["id"] for r in att_rows if r.get("message_id") == target["id"]}
    vis = plan_visibility(attachments, mention_ids(target["content"]), new_ids)

    template = _render_conditional_sections(_load_prompt("chat_router_input_prompt.txt"), {"HAS_REFERENCED_SOURCES": False})
    when = datetime.fromisoformat(t_at.replace("Z", "+00:00")).astimezone(TZ)
    user_input = cs.fill_placeholders(template, {
        "EARLIER_CONVERSATION": memory.for_router(),
        "REFERENCED_SOURCES": "",
        "RECENT_CONVERSATION": cs.format_router_conversation(history),
        "SCREEN_CONTEXT": cs.format_screen_context(lecture_label, selected, page, full_page=False) or "(none)",
        "COURSES": courses_text,
        "ATTACHMENTS": render_for_router(attachments, vis) or "(none)",
        "IS_FIRST_MESSAGE": "false",
        "CURRENT_TIME": when.strftime("%Y-%m-%d (%a) %H:%M"),
        "NEW_MESSAGE": target["content"],
    })
    meta = {"history": len(history), "summary_blocks": len(l1), "lecture": lecture_label,
            "selected_text": (selected or "")[:60], "page": page.title if page else None,
            "attachments": len(attachments), "input_chars": len(user_input)}
    return user_input, meta


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    rows = c.table("chat_messages").select("id, role, content, status, created_at, context, router, usage") \
        .eq("thread_id", THREAD).order("created_at").execute().data
    user_id = c.table("chat_threads").select("user_id").eq("id", THREAD).execute().data[0]["user_id"]
    courses = c.table("courses").select("course_title").eq("user_id", user_id).is_("deleted_at", "null").execute().data
    courses_text = "\n".join(f"- {r['course_title']} (term not set)" for r in courses)
    blocked = cs._load_blocked_source_types(user_id)
    system = PROMPT_V1.read_text(encoding="utf-8")
    print(f"model={cs.ROUTER_MODEL} effort={cs.ROUTER_REASONING_EFFORT} system chars={len(system)}")

    built = []
    for prefix, expected in CASES:
        idx = next(i for i, r in enumerate(rows) if r["role"] == "user" and r["content"].startswith(prefix))
        prod = rows[idx + 1]
        user_input, meta = build_input(c, rows, idx, user_id, courses_text, blocked)
        prod_nr = (prod.get("router") or {}).get("needs_reasoning")
        prod_model = ((prod.get("usage") or {}).get("router_model") or "?").split("/")[-1]
        built.append((prefix, expected, user_input, meta, prod_nr, prod_model))
        print(f"  expected={str(expected)[0]} production={str(prod_nr)[0]} ({prod_model}) | {prefix[:40]} | {json.dumps(meta, ensure_ascii=False)}")
    if args.dry_run:
        return

    billing = BillingEngine(task_type="router_reasoning_eval")
    llm = UnifiedLLM(billing)
    options = LLMOptions(output_type="json", json_schema=cs.ROUTER_SCHEMA, temperature=0.0, reasoning_effort=cs.ROUTER_REASONING_EFFORT)
    results = []
    for prefix, expected, user_input, meta, prod_nr, prod_model in built:
        n = len(billing.records)
        t0 = time.perf_counter()
        r = await llm.generate(cs.ROUTER_MODEL, [Message(role="system", content=system), Message(role="user", content=user_input)], options)
        dt = round(time.perf_counter() - t0, 2)
        out = r.output_json or {}
        got = out.get("needs_reasoning")
        row = {"message": prefix, "expected": expected, "got": got, "pass": got is expected,
               "production": prod_nr, "production_model": prod_model, "latency_s": dt,
               "tokens": {"in": r.input_tokens, "out": r.output_tokens, "cache": r.cache_read_tokens},
               "cost_usd": round(sum(x.cost_usd for x in billing.records[n:]), 6),
               "intent": out.get("intent"), "needs_retrieval": out.get("needs_retrieval"),
               "reply_language": out.get("reply_language"), "user_goal": out.get("user_goal"),
               "output_json": out, "meta": meta, "input": user_input}
        results.append(row)
        print(f"{'OK' if row['pass'] else 'NG'} expected={str(expected)[0]} got={str(got)[0]} prod={str(prod_nr)[0]} "
              f"ret={str(out.get('needs_retrieval'))[0]} lang={out.get('reply_language')} {dt}s ${row['cost_usd']:.5f} | {prefix[:40]}")
    total = billing.total_usd()
    passed = sum(r["pass"] for r in results)
    print(f"\nPASS {passed}/{len(results)}  TOTAL ${total:.5f}")
    out_path = HERE / "results" / f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_router_reasoning_v1.json"
    out_path.write_text(json.dumps({"model": cs.ROUTER_MODEL, "prompt": "router_v1", "pass": passed, "total": len(results),
                                    "total_cost_usd": total, "system_prompt": system, "rows": results},
                                   ensure_ascii=False, indent=2), encoding="utf-8")
    print("saved", out_path)


if __name__ == "__main__":
    asyncio.run(main())
