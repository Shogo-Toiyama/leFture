"""
画面のコース(context.course_id)と、講義ページの Fun Fact(context.screen = fun_fact)を付けたときに、
実際のターンがどう変わるかを、本番の関数(作業ツリーの chat_service / chat_navigator)で通しに再生する。
振り分け役(_run_router) → 探索役(navigate、要るときだけ) → 材料の選別 → 回答役。

ケース:
- brother_midterm_course: 弟の「Midterm2（10/1~10/30）の範囲をまとめて」(本番は科目なしで全コースをまとめた)を、
  Formal logic のコース画面から送ったことにする。科目を聞き返さず Formal logic だけをまとめるか。
- funfact_on_lecture_page: 「このファンファクト意味わからない。どういう意味？」(本番は講義IDだけで、
  「どのファンファクトか見えていない」と答えた)を、講義ページの Fun Fact を screen に付けて送ったことにする。

本番と違うところ: 授業・チャットの検索(find)は空を返す(検索のRPCは auth.uid() で絞るため)。
回答役のプロンプトキャッシュは使わない。時刻は元のメッセージの時刻に固定する。

  .venv/bin/python contents_generation/test_codes/course_context_eval/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/course_context_eval/replay.py
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

from app.services import chat_navigator as nav  # noqa: E402
from app.services import chat_service as cs  # noqa: E402
from app.services.chat_attachments import estimate_tokens  # noqa: E402
from app.services.chat_lecture_source import DbLectureSource  # noqa: E402
from app.services.chat_map import load_chat_map, load_student_map  # noqa: E402
from app.services.chat_materials import select_materials_async  # noqa: E402
from app.services.chat_reasoning import REASONING_CONFIG  # noqa: E402
from app.services.chat_screen import ScreenRef, load_screen_page  # noqa: E402
from app.services.chat_summary import fetch_active_blocks  # noqa: E402
from app.services.chat_thread_source import DbChatThreadSource  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM  # noqa: E402

TZ_NAME = "America/Los_Angeles"
TZ = ZoneInfo(TZ_NAME)

CASES = [
    {"id": "brother_midterm_course", "thread": "a2f5c09f-bc98-4088-988f-75f96e93605e", "index": 0,
     "course_title": "Formal logic"},
    {"id": "funfact_on_lecture_page", "thread": "cf71c2ff-2dc6-4382-9392-1caa6d6fd1f6", "index": 0,
     "screen": {"kind": "fun_fact", "id": "a07d059e-0f8f-46e6-b996-9202e60d136b"}},
]


class FrozenDatetime(datetime):
    frozen: datetime = None

    @classmethod
    def now(cls, tz=None):
        return cls.frozen.astimezone(tz) if tz else cls.frozen


async def run_case(c, llm, billing, case: dict, dry: bool) -> dict:
    rows = c.table("chat_messages").select("id, role, content, status, created_at, context, router, usage") \
        .eq("thread_id", case["thread"]).order("created_at").execute().data
    target = rows[case["index"]]
    t_at = target["created_at"]
    when = datetime.fromisoformat(t_at.replace("Z", "+00:00")).astimezone(TZ)
    user_id = c.table("chat_threads").select("user_id").eq("id", case["thread"]).execute().data[0]["user_id"]
    l1 = [b for b in fetch_active_blocks(c, case["thread"], level=1) if (b.get("end_message_created_at") or "") < t_at]
    l2 = [b for b in fetch_active_blocks(c, case["thread"], level=2) if (b.get("end_message_created_at") or "") < t_at]
    folded_until = l1[-1]["end_message_created_at"] if l1 else ""
    history_rows = [r for r in rows[:case["index"]] if r["created_at"] > folded_until]
    history = cs.build_history_messages(history_rows, cs.RAW_MAX_TURNS, cs.HISTORY_MAX_CHARS_PER_MESSAGE)
    memory = cs.ConversationMemory.from_blocks(l1, l2)
    blocked = cs._load_blocked_source_types(user_id)
    student_map = load_student_map(c, user_id, TZ)

    # 画面の文脈(本番の prepare_chat_turn と同じ検証の関数でラベルを作る)
    lecture_id = (target.get("context") or {}).get("lecture_id")
    lecture_label = cs._lecture_label(c, lecture_id, user_id) if lecture_id else None
    course_id = course_label = None
    if case.get("course_title"):
        course_id = next(x.id for x in student_map.courses if x.title.lower() == case["course_title"].lower())
        course_label = cs._course_label(c, course_id, user_id)
    screen_page = None
    if case.get("screen"):
        screen_page = load_screen_page(c, user_id, ScreenRef(**case["screen"]), lecture_id, None, blocked)

    turn = cs.PreparedTurn(
        user_id=user_id, thread_id=case["thread"], is_new_thread=case["index"] == 0, thread_has_title=case["index"] > 0,
        user_message_id=target["id"], assistant_message_id="replay", content=target["content"], selected_text=None,
        lecture_label=lecture_label, context_lecture_id=lecture_id, timezone_name=TZ_NAME,
        context_course_id=course_id, course_label=course_label,
        history_rows=history_rows, summary_blocks=l1, summary_level2=l2,
    )
    turn.screen_page = screen_page
    prod = rows[case["index"] + 1]
    info = {"case": case["id"], "message": target["content"], "time": when.isoformat(), "lecture_label": lecture_label,
            "course_label": course_label, "screen_page": screen_page.title if screen_page else None,
            "production_router": {k: (prod.get("router") or {}).get(k) for k in ("needs_retrieval", "needs_reasoning")},
            "screen_context_router": cs.format_screen_context(lecture_label, None, screen_page, full_page=False, course_label=course_label)}
    print(f"\n## {case['id']}\n  {json.dumps({k: v for k, v in info.items() if k != 'message'}, ensure_ascii=False)}")
    if dry:
        return info

    FrozenDatetime.frozen = when
    cs.datetime = FrozenDatetime
    try:
        # 1. 振り分け役(本番の関数)
        n0 = len(billing.records)
        t0 = time.perf_counter()
        decision = await cs._run_router(llm, turn, memory, history, cs.router_courses_text(student_map), "(none)")
        t_router = time.perf_counter() - t0
        # 2. 探索役(要るときだけ)
        navigation = None
        materials = []
        searches: list[str] = []
        t_nav = 0.0
        if decision.needs_retrieval:
            chat_source = DbChatThreadSource(c, user_id)
            recent = await chat_source.recent_threads_with_trail(case["thread"], 20)
            nav_input = nav.NavigatorInput(
                message=turn.message_for_prompt, selected_text=None, screen_lecture_id=lecture_id,
                screen_course_id=course_id, recent_conversation=history, today=when.date(), student_map=student_map,
                current_time_str=when.strftime("%Y-%m-%d (%a) %H:%M"), chat_map=load_chat_map(l1, recent, l2),
                current_thread_id=case["thread"], blocked_source_types=blocked,
                screen_page_title=screen_page.title if screen_page else None,
                screen_page_excerpt=screen_page.excerpt() if screen_page else None, user_goal=decision.user_goal,
            )

            async def search(reqs):
                searches.extend(r.label() for r in reqs)
                return [[] for _ in reqs]

            async def web_search(q):
                searches.append(f"web: {q}")
                return []

            tools = nav.NavigatorTools(search=search, source=DbLectureSource(c, user_id, blocked),
                                       chat_source=chat_source, web_search=web_search)
            t1 = time.perf_counter()
            navigation = await nav.navigate(llm, nav_input, tools)
            t_nav = time.perf_counter() - t1
            materials = await select_materials_async([m for m in navigation.materials if m.source_type not in blocked], billing=billing)
        # 3. 回答役(推論が要るターンは本番と同じく一段でeffortを上げる)
        reasoning = navigation.laps[-1].reasoning if navigation and navigation.laps else ""
        messages = cs._build_answer_messages(turn, decision, memory, history, cs._load_student_profile(c, user_id),
                                             materials, retrieval_reasoning=reasoning)
        messages, _ = cs.fit_answer_input(messages)
        effort = REASONING_CONFIG.single_effort if decision.needs_reasoning and REASONING_CONFIG.mode == "single" else cs.ANSWER_REASONING_EFFORT
        opts = cs.answer_options(cs.ANSWER_MODEL, effort, cs._answer_max_tokens(navigation, materials))
        state = StreamState()
        t2 = time.perf_counter()
        first = None
        async for _ in llm.generate_stream(cs.ANSWER_MODEL, messages, state, opts):
            if first is None:
                first = time.perf_counter() - t2
        t_ans = time.perf_counter() - t2
    finally:
        cs.datetime = datetime
    cost = sum(r.cost_usd for r in billing.records[n0:])
    result = {
        **info,
        "router": decision.to_json(), "router_seconds": round(t_router, 2),
        "navigator": None if navigation is None else {
            "stop_reason": navigation.stop_reason, "seconds": round(t_nav, 2), "stubbed_searches": searches,
            "laps": [{"lap": lp.lap, "status": lp.status, "done": lp.done, "reasoning": lp.reasoning} for lp in navigation.laps]},
        "materials": [{"kind": m.kind, "label": m.label, "tokens": estimate_tokens(m.content or "")} for m in materials],
        "answer": {"text": state.output_text, "effort": effort, "first_token_s": round(first or 0, 2), "seconds": round(t_ans, 2),
                   "input_tokens": state.input_tokens, "output_tokens": state.output_tokens},
        "production_answer": prod["content"], "cost_usd": round(cost, 6),
    }
    print(f"  router {t_router:.2f}s: retrieval={decision.needs_retrieval} reasoning={decision.needs_reasoning} goal={(decision.user_goal or '')[:140]}")
    if navigation:
        print(f"  navigator {t_nav:.1f}s [{navigation.stop_reason}] " + " | ".join(f"L{lp.lap} {lp.status}: {', '.join(lp.done) or '-'}" for lp in navigation.laps))
        if searches:
            print(f"  ⚠️ stubbed searches: {searches}")
    print(f"  materials: " + (", ".join(f"{m['kind']}({m['tokens']:,})" for m in result["materials"]) or "-"))
    print(f"  answer effort={effort} first token {first or 0:.2f}s total {t_ans:.2f}s in {state.input_tokens:,} out {state.output_tokens:,}  ${cost:.4f}")
    print("  answer head: " + state.output_text[:300].replace("\n", " ⏎ "))
    return result


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    billing = BillingEngine(task_type="course_context_replay")
    llm = UnifiedLLM(billing)
    results = [await run_case(c, llm, billing, case, args.dry_run) for case in CASES]
    if args.dry_run:
        return
    print(f"\nTOTAL COST ${billing.total_usd():.4f}")
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    (HERE / "results").mkdir(exist_ok=True)
    out = HERE / "results" / f"{ts}_replay.json"
    out.write_text(json.dumps({"total_cost_usd": billing.total_usd(), "results": results}, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    md = ["# Course / Fun Fact context replay", ""]
    for r in results:
        md += [f"## {r['case']}", "", f"**Message:** {r['message']}", "", f"**Screen (router):** {r['screen_context_router']}", "",
               "### New answer", "", r["answer"]["text"], "", "### Production answer (at the time)", "", r["production_answer"], "", "---", ""]
    (HERE / "results" / f"{ts}_replay_answers.md").write_text("\n".join(md), encoding="utf-8")
    print("saved", out)


if __name__ == "__main__":
    asyncio.run(main())
