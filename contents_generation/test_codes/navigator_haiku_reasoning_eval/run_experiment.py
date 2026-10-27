"""
探索役 (Navigator) のモデル思考レベル比較実験:
Claude 3.5 Haiku (anthropic/claude-haiku-5-5) における
reasoning_effort="none" vs reasoning_effort="low" の比較評価。

キャッシュ最適化版プロンプト順序（<map>・会話履歴先頭、<current_time>・動的情報末尾）で
代表的な5ケースを実行し、精度（Pass/Fail）・思考トークン・レイテンシ・コストを計測する。
"""

import argparse
import asyncio
from datetime import datetime
import json
from pathlib import Path
import sys
import time
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services import chat_navigator as nav
from app.services.chat_map import StudentMap
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM

NAV_TEST_DIR = REPO_ROOT / "contents_generation" / "test_codes" / "navigator_test"
sys.path.insert(0, str(NAV_TEST_DIR))
from run_eval import build_student_map, build_nav_input, build_state, available_alternatives, _request_to_op
from run_eval_legacy import cumulative_steps, score

CASES_FILE = NAV_TEST_DIR / "cases" / "cases.json"
ALL_CASES = json.loads(CASES_FILE.read_text(encoding="utf-8"))

TARGET_CASE_IDS = [
    "outline_heap_insert",           # Case 1: 概念検索・階層探索
    "outline_known_lecture",          # Case 2: 講義番号直接指定
    "outline_on_screen",              # Case 3: 画面文脈からの解決
    "outline_selected_text_enough",   # Case 4: 選択テキストで十分→終了(nothing_needed)
    "outline_cross_course",           # Case 5: 複数コースの横断
]

# キャッシュ最適化版の build_user_message
def build_user_message_cache_optimized(nav_input: nav.NavigatorInput, state: nav.NavState, lap: int) -> str:
    m = nav_input.student_map
    parts = []

    # 1. <map> (静的情報: コース一覧、チャット地図、資料一覧など)
    if lap == 1:
        map_text = "Courses:\n" + m.render_courses()
        if nav.CAPABILITIES["CAN_CHAT"] and nav_input.chat_map is not None and nav_input.chat_map.has_anything:
            map_text += "\n\n" + nav_input.chat_map.render()
        if nav.CAPABILITIES["CAN_ATTACHMENTS"] and nav_input.attachments:
            map_text += "\n\n" + nav.render_for_navigator(
                nav_input.attachments, nav_input.attachment_visibility or nav.Visibility(full=set()))
        if nav_input.link_handles():
            map_text += "\n\n" + nav.render_links_for_navigator(nav_input.links)
        parts.append(f"<map>\n{map_text}\n</map>")

    # 2. <recent_conversation> (累積型: 過去のやり取り全文)
    if nav_input.recent_conversation:
        conv = "\n".join(
            f"{'student' if msg.role == 'user' else 'assistant'}: {msg.content[:nav.RECENT_CONVERSATION_MAX_CHARS]}"
            for msg in nav_input.recent_conversation[-nav.RECENT_CONVERSATION_MAX_MESSAGES:]
        )
        parts.append(f"<recent_conversation>\n{conv}\n</recent_conversation>")
    else:
        parts.append("<recent_conversation>(This is the first message of a new conversation.)</recent_conversation>")

    # 3. <screen> (動的情報: 画面・トピック・選択テキスト)
    screen = []
    screen_handle = m.lecture_handle(nav_input.screen_lecture_id)
    if screen_handle:
        topic = nav_input.screen_topic_handle()
        screen.append(f"The student is viewing {m.describe(screen_handle)}"
                      + (f", on topic {topic}" if topic else ""))
    if nav_input.screen_page_title:
        screen.append(f"Open page: {nav_input.screen_page_title}. The answerer already sees its full text"
                      " (excerpt below; the selected part, if any, is in <selected>), so never fetch it again.")
        if nav_input.screen_page_excerpt:
            screen.append(nav_input.screen_page_excerpt)
    if nav_input.selected_text and "<selected>" not in (nav_input.screen_page_excerpt or ""):
        screen.append(f"Selected text: {nav_input.selected_text}")
    if screen:
        parts.append("<screen>\n" + "\n".join(screen) + "\n</screen>")

    # 4. 直前ターンで開いたもの & 目的
    if lap == 1:
        if state.previous_turn_text and nav.CAPABILITIES["CAN_OPEN"]:
            parts.append(f"<previous_turn_opened>\n{state.previous_turn_text}\n</previous_turn_opened>")
        if nav_input.user_goal:
            parts.append(f"<user_goal>\n{nav_input.user_goal}\n</user_goal>")
        if nav_input.referenced_sources:
            parts.append(f"<referenced_sources>\n{nav_input.referenced_sources}\n</referenced_sources>")

    # 5. 現在時刻 (todayは含んでいるので単一タグ)
    cur_time = nav_input.current_time_str or nav_input.today.isoformat()
    parts.append(f"<current_time>{cur_time}</current_time>")

    # 6. 最新の学生メッセージ
    parts.append(f"<student_message>\n{nav_input.message}\n</student_message>")

    mentioned = nav_input.mentioned_unseen_handles()
    if lap == 1 and mentioned:
        parts.append(f"<mention_note>The student points at {', '.join(mentioned)} in their message, and the answerer "
                     "does not see it in full. Fetch the parts of it that the message is about: attachment.search "
                     "within it with the term or line in question, or open its table of contents and then the "
                     "section. If the message only asks about it as a whole, its table of contents is enough."
                     "</mention_note>")
    if lap == 1 and nav_input.must_check_attachments and nav_input.attachment_scope_handles():
        parts.append("<check_note>This message needs careful checking, and the answerer does not see the attached "
                     "material in full. Unless the message clearly has nothing to do with the material, fetch the "
                     "parts it depends on: attachment.search with a distinctive line of what the student pasted or "
                     "the term in question, or open the section from the table of contents. Without them, the "
                     "checking step can only guess.</check_note>")

    done_laps = [lp for lp in state.laps if lp.done]
    if done_laps:
        progress = []
        for lp in done_laps:
            looking = f" (you were looking for: {lp.missing})" if lp.missing else ""
            progress.append(f"Lap {lp.lap}{looking}: " + "; ".join(lp.done))
        parts.append("<progress>\n" + "\n".join(progress) + "\n</progress>")
    if state.opened:
        parts.append("<opened>\n" + "\n\n".join(op.text for op in state.opened.values()) + "\n</opened>")
    if state.outcomes:
        parts.append("<search_results>\n" + "\n\n".join(o.render() for o in state.outcomes) + "\n</search_results>")

    nxt = [f"This is lap {lap} of {nav.MAX_LAPS}."]
    if lap == nav.MAX_LAPS:
        nxt.append("This is the last lap. After it, the answerer writes the reply with whatever you have fetched.")
    else:
        nxt.append(f"{nav.MAX_LAPS - lap} more lap(s) after this one. After lap {nav.MAX_LAPS}, "
                   "the answerer writes the reply with whatever you have fetched.")
    if nav.CAPABILITIES["CAN_OPEN"]:
        nxt.append("Already opened (content is in <opened>; cannot be opened again): "
                   + (", ".join(state.opened) or "nothing yet"))
    nxt.append("Searches already run (do not repeat them): "
               + ("; ".join(o.request.label() for o in state.outcomes) or "none yet"))
    left = state.searches_left()
    nxt.append(f"Class and chat searches left for this reply: {left} of {nav.MAX_SEARCHES_PER_TURN}"
               + (" (no more searching; if the results do not contain the answer, choose enough_now)" if left == 0 else ""))
    if nav.CAPABILITIES["CAN_WEB"]:
        left = state.web_searches_left()
        nxt.append(f"Web searches left for this reply: {left} of {nav.MAX_WEB_SEARCHES_PER_TURN}"
                   + (" (web.search is no longer available)" if left == 0 else ""))
    if nav_input.link_handles():
        left = state.link_opens_left()
        unopened = [h for h in nav_input.link_handles() if h not in state.opened]
        nxt.append(f"Links you can still open for this reply: {left} of {nav.MAX_LINK_OPENS_PER_TURN}"
                   + (f" (not opened yet: {', '.join(unopened)})" if left and unopened else ""))
    if nav.CAPABILITIES["CAN_OPEN"]:
        nxt.append("Seen but not opened yet (open one only if it likely holds what is still missing): "
                   + (", ".join(state.surfaced_not_opened()) or "nothing"))
    parts.append("<next_options>\n" + "\n".join(nxt) + "\n</next_options>")

    return "\n\n".join(parts)


async def run_single_test(
    case: dict,
    model: str,
    effort: str,
    dry_run: bool = False
) -> dict:
    steps = cumulative_steps(case)
    if not steps:
        return {"error": "no steps"}
    step = steps[0]  # Lap 1
    alternatives = available_alternatives(step)
    nav_input = build_nav_input(case)
    state = await build_state(case, step, nav_input)
    
    sys_prompt = nav.build_system_prompt(nav_input.can_transcript)
    user_prompt = build_user_message_cache_optimized(nav_input, state, lap=1)
    
    if dry_run:
        schema = nav.build_schema(nav_input, state)
        return {
            "case_id": case["id"],
            "category": case["category"],
            "model": model,
            "effort": effort,
            "dry_run": True,
            "sys_prompt_chars": len(sys_prompt),
            "user_prompt_chars": len(user_prompt),
            "schema_properties": list(schema.get("properties", {}).keys()),
            "status": "dry_run_success"
        }

    billing = BillingEngine(task_type="navigator_eval")
    llm = UnifiedLLM(billing)

    original_fn = nav.build_user_message
    nav.build_user_message = build_user_message_cache_optimized
    nav.NAVIGATOR_MODEL = model
    nav.NAVIGATOR_REASONING_EFFORT = None if effort == "none" else effort

    t0 = time.perf_counter()
    try:
        out, err = await nav.decide_lap(llm, nav_input, state, lap=1)
    finally:
        nav.build_user_message = original_fn

    elapsed = round(time.perf_counter() - t0, 3)

    if out is None:
        return {
            "case_id": case["id"],
            "category": case["category"],
            "model": model,
            "effort": effort,
            "elapsed_sec": elapsed,
            "error": f"LLM error: {err}",
            "pass": False,
        }

    requests, dropped = nav.validate_operations(
        out.get("operations"), nav_input, state, out.get("need"), out.get("fetch_from")
    )
    scored_out = {"status": out["status"], "operations": [_request_to_op(r) for r in requests]}
    score_res = score(case, {**step, "alternatives": alternatives}, scored_out)

    cost_info = {}
    if billing.records:
        rec = billing.records[-1]
        cost_info = {
            "cost_usd": rec.cost_usd,
            "input_tokens": rec.usage.get("input", 0),
            "output_tokens": rec.usage.get("output", 0),
            "cache_read": rec.usage.get("cache_read", 0),
            "cache_write": rec.usage.get("cache_write", 0),
        }

    return {
        "case_id": case["id"],
        "category": case["category"],
        "model": model,
        "effort": effort,
        "elapsed_sec": elapsed,
        "pass": score_res.get("pass", False),
        "score_details": score_res,
        "reasoning": out.get("reasoning", ""),
        "status": out.get("status"),
        "operations": out.get("operations", []),
        "cost_info": cost_info,
    }


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="APIコールを行わずにプロンプトとスキーマを検証する")
    parser.add_argument("--model", default="anthropic/claude-haiku-5-5", help="評価対象モデル")
    parser.add_argument("--efforts", nargs="+", default=["none", "low"], help="比較するreasoning_effortリスト (例: none low)")
    args = parser.parse_args()

    selected_cases = [c for c in ALL_CASES if c["id"] in TARGET_CASE_IDS]
    print(f"=== 探索役思考レベル評価実験 (ケース数: {len(selected_cases)}) ===")
    print(f"Model: {args.model}")
    print(f"Efforts: {args.efforts}")
    print(f"Dry Run: {args.dry_run}\n")

    results_dir = Path(__file__).resolve().parent / "results"
    results_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    all_eval_results = {}

    for effort in args.efforts:
        print(f"\n--- Testing effort='{effort}' ---")
        effort_results = []
        for case in selected_cases:
            print(f"  Running case: {case['id']}...", end=" ", flush=True)
            res = await run_single_test(case, args.model, effort, dry_run=args.dry_run)
            effort_results.append(res)
            if args.dry_run:
                print(f"[DRY-RUN OK] sys={res['sys_prompt_chars']}c user={res['user_prompt_chars']}c")
            else:
                passed = "PASS" if res.get("pass") else "FAIL"
                cost = res.get("cost_info", {}).get("cost_usd", 0)
                elapsed = res.get("elapsed_sec", 0)
                print(f"[{passed}] {elapsed}s | ${cost:.5f}")

        all_eval_results[effort] = effort_results

    result_file = results_dir / f"eval_{timestamp}.json"
    result_file.write_text(json.dumps(all_eval_results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nSaved detailed results to: {result_file}")


if __name__ == "__main__":
    asyncio.run(main())
