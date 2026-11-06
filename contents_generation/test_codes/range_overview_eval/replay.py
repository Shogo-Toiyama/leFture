"""
ステップ2: 失敗した実際のターンを、新しい探索役(patched/)で探索 → 材料の選別 → 回答まで通しで再生する。

本番の関数をそのまま使う: navigate(パッチ版) / select_materials_async / _build_answer_messages /
fit_answer_input / answer_options / UnifiedLLM.generate_stream(回答役 Haiku 5.5, effort low)。

本番と違うところ(結果にも書く):
- 授業・チャットの検索(find)は空を返す。検索のRPCはログイン中のユーザー(auth.uid())で絞るため、
  管理者キーでは本番と同じ結果が取れない。探索役が検索を頼んだら記録する。Web検索も空。
- 確かめ役(needs_reasoning=trueのときのchat_reasoning.check_work)は呼ばない。
- 回答役のプロンプトキャッシュは使わない(コストはキャッシュなしの値)。
- 他のチャットの一覧(chat map)は、今の一覧を使う(そのターン以後のスレッドも入りうる)。
- 時刻は元のメッセージの時刻(America/Los_Angeles)に固定する。

  .venv/bin/python contents_generation/test_codes/range_overview_eval/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/range_overview_eval/replay.py
"""

import argparse
import asyncio
import json
import os
import re
import time
from datetime import datetime
from zoneinfo import ZoneInfo

from load_patched import HERE, install

nav, cs = install()

from supabase import create_client  # noqa: E402

from app.services.chat_attachments import estimate_tokens  # noqa: E402
from app.services.chat_lecture_source import DbLectureSource  # noqa: E402
from app.services.chat_map import load_chat_map, load_student_map  # noqa: E402
from app.services.chat_materials import select_materials_async  # noqa: E402
from app.services.chat_summary import fetch_active_blocks  # noqa: E402
from app.services.chat_thread_source import DbChatThreadSource  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM  # noqa: E402

TZ_NAME = "America/Los_Angeles"
TZ = ZoneInfo(TZ_NAME)
ROUTER_RESULT_1029 = sorted((HERE.parent / "router_language_eval" / "results").glob("*_router_retrieval_*.json"))

CASES = [
    {"id": "brother_midterm_no_course", "thread": "a2f5c09f-bc98-4088-988f-75f96e93605e", "index": 0},
    {"id": "brother_midterm_formal_logic", "thread": "a2f5c09f-bc98-4088-988f-75f96e93605e", "index": 4},
    # 本番(2.5 Flash Lite)はneeds_retrieval=falseにしたターン。振り分けの判断は、3.1 Flash Liteでの確認
    # (router_language_eval/check_router_retrieval.py)の1回目の出力を使う
    {"id": "pl_oct29_scope", "thread": "886879bc-3721-4c68-9ffd-df42021d77fa", "index": 44, "router_from_3_1": True},
]


class FrozenDatetime(datetime):
    frozen: datetime = None

    @classmethod
    def now(cls, tz=None):
        return cls.frozen.astimezone(tz) if tz else cls.frozen


def load_case(c, case: dict) -> dict:
    rows = c.table("chat_messages").select("id, role, content, status, created_at, context, router, usage") \
        .eq("thread_id", case["thread"]).order("created_at").execute().data
    target = rows[case["index"]]
    assert target["role"] == "user", (case["id"], target["role"])
    t_at = target["created_at"]
    l1 = [b for b in fetch_active_blocks(c, case["thread"], level=1) if (b.get("end_message_created_at") or "") < t_at]
    l2 = [b for b in fetch_active_blocks(c, case["thread"], level=2) if (b.get("end_message_created_at") or "") < t_at]
    folded_until = l1[-1]["end_message_created_at"] if l1 else ""
    history_rows = [r for r in rows[:case["index"]] if r["created_at"] > folded_until]
    prod = rows[case["index"] + 1]
    if case.get("router_from_3_1"):
        router = json.loads(ROUTER_RESULT_1029[-1].read_text(encoding="utf-8"))["rows"][0]["output_json"]
    else:
        router = prod["router"]
    user_id = c.table("chat_threads").select("user_id").eq("id", case["thread"]).execute().data[0]["user_id"]
    return {"rows": rows, "target": target, "l1": l1, "l2": l2, "history_rows": history_rows, "router": router,
            "user_id": user_id, "production": prod,
            "when": datetime.fromisoformat(t_at.replace("Z", "+00:00")).astimezone(TZ)}


async def build_inputs(c, case: dict, data: dict, searches: list):
    uid, target = data["user_id"], data["target"]
    lecture_id = (target.get("context") or {}).get("lecture_id")
    lecture_label = cs._lecture_label(c, lecture_id, uid) if lecture_id else None
    blocked = cs._load_blocked_source_types(uid)
    student_map = load_student_map(c, uid, TZ)
    chat_source = DbChatThreadSource(c, uid)
    recent = await chat_source.recent_threads_with_trail(case["thread"], 20)
    chat_map = load_chat_map(data["l1"], recent, data["l2"])
    history = cs.build_history_messages(data["history_rows"], cs.RAW_MAX_TURNS, cs.HISTORY_MAX_CHARS_PER_MESSAGE)
    when = data["when"]
    router = data["router"]
    nav_input = nav.NavigatorInput(
        message=target["content"], selected_text=None, screen_lecture_id=lecture_id,
        recent_conversation=history, today=when.date(), student_map=student_map,
        current_time_str=when.strftime("%Y-%m-%d (%a) %H:%M"), chat_map=chat_map,
        current_thread_id=case["thread"], previous_turn_refs=cs._previous_turn_refs(data["history_rows"]),
        blocked_source_types=blocked, user_goal=router.get("user_goal"),
    )

    async def search(reqs):
        for r in reqs:
            searches.append(r.label())
        return [[] for _ in reqs]

    async def web_search(query):
        searches.append(f"web: {query}")
        return []

    tools = nav.NavigatorTools(search=search, source=DbLectureSource(c, uid, blocked), chat_source=chat_source,
                               web_search=web_search, link_fetch=None)
    turn = cs.PreparedTurn(
        user_id=uid, thread_id=case["thread"], is_new_thread=False, thread_has_title=True,
        user_message_id=target["id"], assistant_message_id="replay", content=target["content"],
        selected_text=None, lecture_label=lecture_label, context_lecture_id=lecture_id, timezone_name=TZ_NAME,
        history_rows=data["history_rows"], summary_blocks=data["l1"], summary_level2=data["l2"],
    )
    decision = cs.RouterDecision(
        intent=router.get("intent", "learning"), needs_retrieval=True, reply_language=router.get("reply_language", "ja"),
        thread_title=None, user_goal=router.get("user_goal"), needs_reasoning=bool(router.get("needs_reasoning")),
    )
    memory = cs.ConversationMemory.from_blocks(data["l1"], data["l2"])
    return nav_input, tools, turn, decision, memory, history, blocked, lecture_label


_CODE_RE = re.compile(r"(?<![A-Za-z0-9])(?:C\d+(?:/L\d+(?:-\d+)?)?(?:/T\d+)?|L\d+(?:\s*[-〜~]\s*L?\d+)?|T\d+(?:\s*[-〜~]\s*T?\d+)?)(?![A-Za-z0-9])")


def internal_codes(text: str) -> list[str]:
    """回答に出た内部の呼び名(C4、C4/L11、L11、T1 など)。引用の印 ⟦…⟧ の中は数えない。"""
    return _CODE_RE.findall(re.sub(r"⟦[^⟧]*⟧", "", text or ""))


def range_coverage(materials, answer: str) -> list[dict]:
    """範囲の材料の各講義について、トピック名か講義名が回答に出てくるか(おおまかな目安)。"""
    out = []
    for m in materials:
        if m.kind != "lecture_range":
            continue
        for sec in re.split(r"\n(?=### )", m.content):
            head = re.match(r"### (.+?) — (.*)", sec)
            if not head:
                continue
            names = [head.group(2).split(" / ")[-1].strip()] + re.findall(r"^- ([^—\n]+) —", sec, re.M)
            names = [n.strip() for n in names if len(n.strip()) >= 4]
            hit = [n for n in names if n in answer]
            out.append({"lecture": head.group(2), "date": head.group(1), "mentioned": bool(hit), "matched": hit[:2]})
    return out


async def run_case(c, llm, billing, case: dict, dry: bool) -> dict:
    data = load_case(c, case)
    searches: list[str] = []
    nav_input, tools, turn, decision, memory, history, blocked, label = await build_inputs(c, case, data, searches)
    first_prompt = nav.build_user_message(nav_input, nav.NavState(), 1)
    info = {"case": case["id"], "message": data["target"]["content"], "message_time": data["when"].isoformat(),
            "screen_lecture": label, "history_messages": len(history), "summary_blocks": len(data["l1"]),
            "user_goal": decision.user_goal, "navigator_lap1_input_chars": len(first_prompt)}
    print(f"\n## {case['id']}\n  {json.dumps({k: v for k, v in info.items() if k != 'message'}, ensure_ascii=False)}")
    if dry:
        return info

    FrozenDatetime.frozen = data["when"]
    cs.datetime = FrozenDatetime  # 回答役のプロンプトの現在時刻を元のメッセージの時刻にする
    n_rec = len(billing.records)
    t0 = time.perf_counter()
    navigation = await nav.navigate(llm, nav_input, tools)
    t_nav = time.perf_counter() - t0
    nav_cost = sum(r.cost_usd for r in billing.records[n_rec:])
    raw_materials = [m for m in navigation.materials if m.source_type not in blocked]
    pre_tokens = sum(estimate_tokens(m.content or "") for m in raw_materials)
    n_rec2 = len(billing.records)
    materials = await select_materials_async(raw_materials, billing=billing)
    select_cost = sum(r.cost_usd for r in billing.records[n_rec2:])
    retrieval_reasoning = navigation.laps[-1].reasoning if navigation.laps else ""
    messages = cs._build_answer_messages(turn, decision, memory, history, cs._load_student_profile(c, turn.user_id),
                                         materials, retrieval_reasoning=retrieval_reasoning)
    messages, trimmed = cs.fit_answer_input(messages)
    max_out = cs._answer_max_tokens(navigation, materials)
    opts = cs.answer_options(cs.ANSWER_MODEL, cs.ANSWER_REASONING_EFFORT, max_out)
    state = StreamState()
    n_rec3 = len(billing.records)
    t1 = time.perf_counter()
    first = None
    async for _ in llm.generate_stream(cs.ANSWER_MODEL, messages, state, opts):
        if first is None:
            first = time.perf_counter() - t1
    t_ans = time.perf_counter() - t1
    cs.datetime = datetime
    answer_cost = sum(r.cost_usd for r in billing.records[n_rec3:])
    answer = state.output_text
    prod_usage = data["production"].get("usage") or {}
    result = {
        **info,
        "navigator": {
            "stop_reason": navigation.stop_reason, "seconds": round(t_nav, 2), "cost_usd": round(nav_cost, 6),
            "searches_requested_but_stubbed": searches,
            "laps": [{"lap": lp.lap, "status": lp.status, "requests": [r.label() if hasattr(r, "label") else str(r) for r in lp.requests],
                      "done": lp.done, "dropped": lp.dropped, "missing": lp.missing, "reasoning": lp.reasoning,
                      "timing": lp.timing, "llm_error": getattr(lp, "llm_error", None)} for lp in navigation.laps],
        },
        "materials_before_select_tokens": pre_tokens,
        "materials": [{"key": m.key, "kind": m.kind, "label": m.label, "tokens": estimate_tokens(m.content or ""),
                       "compressed": m.compressed} for m in materials],
        "materials_total_tokens": sum(estimate_tokens(m.content or "") for m in materials),
        "select_cost_usd": round(select_cost, 6),
        "answer": {"text": answer, "first_token_s": round(first or 0, 2), "seconds": round(t_ans, 2),
                   "input_tokens": state.input_tokens, "output_tokens": state.output_tokens,
                   "finish_reason": state.finish_reason, "max_output_tokens": max_out, "history_trimmed_turns": trimmed,
                   "cost_usd": round(answer_cost, 6)},
        "range_coverage": range_coverage(materials, answer),
        "internal_codes": internal_codes(answer),
        "material_contents": {m.key: m.content for m in materials},
        "production": {"answer": data["production"]["content"], "materials": prod_usage.get("materials"),
                       "router_model": prod_usage.get("router_model"),
                       "navigator_stop": (prod_usage.get("navigator") or {}).get("stop_reason")},
        "total_cost_usd": round(nav_cost + select_cost + answer_cost, 6),
    }
    lap_line = " | ".join(f"L{lp['lap']} {lp['status']}: {', '.join(lp['done']) or '-'}" for lp in result["navigator"]["laps"])
    print(f"  navigator {result['navigator']['seconds']}s ${nav_cost:.4f} [{navigation.stop_reason}] {lap_line}")
    if searches:
        print(f"  ⚠️ stubbed searches: {searches}")
    print(f"  materials {result['materials_total_tokens']:,} tokens: " + ", ".join(f"{m['kind']}({m['tokens']:,}{'*' if m['compressed'] else ''})" for m in result["materials"]))
    cov = result["range_coverage"]
    if cov:
        print(f"  range coverage: {sum(x['mentioned'] for x in cov)}/{len(cov)} lectures mentioned")
    print(f"  internal codes in the answer: {len(result['internal_codes'])} {result['internal_codes'][:8]}")
    print(f"  answer first token {result['answer']['first_token_s']}s, total {result['answer']['seconds']}s, "
          f"in {state.input_tokens:,} / out {state.output_tokens:,}, ${answer_cost:.4f}, finish={state.finish_reason}")
    return result


def write_markdown(results: list[dict], path):
    lines = ["# Range overview replay — answers", ""]
    for r in results:
        lines += [f"## {r['case']}", "", f"**Message ({r['message_time']}):** {r['message']}", "",
                  f"**Navigator:** {r['navigator']['stop_reason']} — " + " | ".join(
                      f"lap {lp['lap']} {lp['status']}: {', '.join(lp['done']) or '-'}" for lp in r["navigator"]["laps"]), "",
                  f"**Materials ({r['materials_total_tokens']:,} tokens):** " + ", ".join(f"{m['label']} ({m['tokens']:,})" for m in r["materials"]), "",
                  "### New answer", "", r["answer"]["text"], "",
                  "### Production answer (at the time)", "", r["production"]["answer"], "", "---", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--cases", nargs="*", default=[c["id"] for c in CASES])
    args = ap.parse_args()
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    billing = BillingEngine(task_type="range_overview_replay")
    llm = UnifiedLLM(billing)
    print(f"navigator={nav.NAVIGATOR_MODEL} ({nav.NAVIGATOR_REASONING_EFFORT}), answer={cs.ANSWER_MODEL} ({cs.ANSWER_REASONING_EFFORT}), "
          f"range budget={nav.RANGE_MATERIAL_BUDGET:,}")
    results = [await run_case(c, llm, billing, case, args.dry_run) for case in CASES if case["id"] in args.cases]
    if args.dry_run:
        return
    total = billing.total_usd()
    print(f"\nTOTAL COST ${total:.4f}")
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = HERE / "results" / f"{ts}_replay.json"
    out.write_text(json.dumps({"total_cost_usd": total, "results": results,
                               "billing": [{"resource": r.resource, "usage": r.usage, "cost_usd": r.cost_usd} for r in billing.records]},
                              ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    write_markdown(results, HERE / "results" / f"{ts}_replay_answers.md")
    print("saved", out)


if __name__ == "__main__":
    asyncio.run(main())
