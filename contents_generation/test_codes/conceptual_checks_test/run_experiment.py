#!/usr/bin/env python3
"""
本番と同一環境（固定ケースデータ・Claude Haiku 5.5・推論設定・プロンプト組み立て）で
Case E, F, G の回答を生成し、旧回答・理想回答・新回答を比較する実験スクリプト。
"""

import argparse
import asyncio
import json
import os
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services.chat_screen import ScreenPage
from app.services.chat_service import (
    ANSWER_MAX_OUTPUT_TOKENS,
    HISTORY_MAX_CHARS_PER_MESSAGE,
    RAW_MAX_TURNS,
    ConversationMemory,
    PreparedTurn,
    RouterDecision,
    _build_answer_messages,
    build_history_messages,
    fit_answer_input,
)
from app.services.helpers.llm_unified import (
    BillingEngine,
    LLMOptions,
    Message,
    StreamState,
    UnifiedLLM,
)

MODEL_NAME = "anthropic/claude-haiku-5-5"


def build_messages_for_case(case: dict) -> tuple[list[Message], str]:
    """本番コードと完全に同じ手順でプロンプトメッセージを構築する。"""
    screen_page = None
    if case.get("screen_page"):
        sp = case["screen_page"]
        screen_page = ScreenPage(
            kind=sp["kind"],
            lecture_id=sp.get("lecture_id"),
            topic_number=sp.get("topic_number"),
            title=sp.get("title") or "",
            text=sp.get("text") or "",
            selection_marked=sp.get("selection_marked", False),
            truncated=sp.get("truncated", False),
        )

    turn = PreparedTurn(
        user_id=case["user_id"],
        thread_id=case["thread_id"],
        is_new_thread=False,
        thread_has_title=True,
        user_message_id="eval-user",
        assistant_message_id="eval-asst",
        content=case["question"],
        selected_text=None,
        lecture_label=case.get("lecture_label"),
        context_lecture_id=None,
        screen_page=screen_page,
    )

    router_data = case.get("router") or {}
    needs_reasoning = router_data.get("needs_reasoning", False)
    decision = RouterDecision(
        intent="learning",
        needs_retrieval=False,
        reply_language=router_data.get("reply_language", "ja"),
        thread_title=None,
        needs_reasoning=needs_reasoning,
    )

    history = build_history_messages(
        case["history_rows"], RAW_MAX_TURNS, HISTORY_MAX_CHARS_PER_MESSAGE
    )

    messages = _build_answer_messages(
        turn=turn,
        decision=decision,
        memory=ConversationMemory(),
        history=history,
        profile=case.get("profile") or "",
        materials=[],
        student_memos=case.get("student_memos") or [],
        open_questions=case.get("open_questions") or [],
    )
    messages, _ = fit_answer_input(messages)

    # 本番の回答役設定: ANSWER_REASONING_EFFORT = "low" に完全準拠
    effort = "low"
    return messages, effort


def calc_cost(input_tokens: int, output_tokens: int) -> dict:
    """Claude Haiku 5.5の公式料金（PRICE_MATRIX）でコスト計算"""
    input_cost = (input_tokens / 1_000_000) * 0.10
    output_cost = (output_tokens / 1_000_000) * 0.50
    total_cost_usd = input_cost + output_cost
    # 参考JPYレート（1ドル=約150円）
    total_cost_jpy = total_cost_usd * 150.0
    return {
        "input_cost_usd": input_cost,
        "output_cost_usd": output_cost,
        "total_cost_usd": total_cost_usd,
        "total_cost_jpy": total_cost_jpy,
    }


async def run_one(
    llm: UnifiedLLM,
    sem: asyncio.Semaphore,
    messages: list[Message],
    effort: str,
    case_id: str,
    run_idx: int,
) -> dict:
    options = LLMOptions(
        max_tokens=ANSWER_MAX_OUTPUT_TOKENS + 4096,
        reasoning_effort=effort,
    )
    async with sem:
        state = StreamState()
        start = time.perf_counter()
        first_token = None
        error = None
        try:
            async for _delta in llm.generate_stream(MODEL_NAME, messages, state, options):
                if first_token is None:
                    first_token = time.perf_counter() - start
        except Exception as e:
            error = str(e)[:500]
        total = time.perf_counter() - start

    text = state.output_text
    cost_info = calc_cost(state.input_tokens, state.output_tokens)
    print(
        f"[{case_id} #{run_idx}] done in {total:.1f}s (first token: {first_token:.2f}s, "
        f"in: {state.input_tokens} tok, out: {state.output_tokens} tok, "
        f"cost: ${cost_info['total_cost_usd']:.5f} / ¥{cost_info['total_cost_jpy']:.3f})"
    )
    return {
        "case_id": case_id,
        "run": run_idx,
        "effort": effort,
        "text": text,
        "error": error,
        "time_s": total,
        "first_token_s": first_token,
        "input_tokens": state.input_tokens,
        "output_tokens": state.output_tokens,
        "cost": cost_info,
    }



async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=1, help="Number of runs per case (default: 1)")
    parser.add_argument("--cases", type=str, default="E,F,G", help="Comma-separated case IDs to run")
    parser.add_argument("--dry-run", action="store_true", help="Print prompt only, do not call API")
    args = parser.parse_args()

    cases_file = Path(__file__).parent / "cases" / "cases.json"
    with open(cases_file, encoding="utf-8") as f:
        all_cases = json.load(f)

    selected_ids = [c.strip().upper() for c in args.cases.split(",")]
    cases_to_run = [c for c in all_cases if c["case_id"] in selected_ids]

    if not cases_to_run:
        print(f"No cases matched {args.cases}")
        return

    if args.dry_run:
        print("=== DRY RUN: PROMPT VERIFICATION ===")
        for c in cases_to_run:
            msgs, effort = build_messages_for_case(c)
            print(f"\n================ Case {c['case_id']} ({c['name']}) [effort={effort}] ================")
            print(f"--- SYSTEM PROMPT (First 300 chars) ---\n{msgs[0].content[:300]}...")
            print(f"--- SYSTEM PROMPT (GETTING IT RIGHT section) ---")
            for line in msgs[0].content.split("\n"):
                if "check their own attempt" in line or "GETTING IT RIGHT" in line:
                    print("  ", line)
            print(f"--- USER PROMPT (Turn message - last 800 chars) ---\n{msgs[-1].content[-800:]}")
        return

    llm = UnifiedLLM(BillingEngine())
    sem = asyncio.Semaphore(3)

    print(f"Starting experiment on {len(cases_to_run)} cases × {args.runs} runs using {MODEL_NAME}...")
    tasks = []
    for c in cases_to_run:
        msgs, effort = build_messages_for_case(c)
        for r in range(args.runs):
            tasks.append(run_one(llm, sem, msgs, effort, c["case_id"], r))

    raw_results = await asyncio.gather(*tasks)

    # ケースごとにまとめる
    grouped: dict[str, list[dict]] = {}
    for r in raw_results:
        grouped.setdefault(r["case_id"], []).append(r)

    # 結果JSONの保存
    out_dir = Path(__file__).parent / "results"
    out_dir.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_json = out_dir / f"run_{timestamp}.json"

    final_output = {
        "timestamp": timestamp,
        "model": MODEL_NAME,
        "cases": [],
    }

    for c in cases_to_run:
        cid = c["case_id"]
        final_output["cases"].append(
            {
                "case_id": cid,
                "name": c["name"],
                "question": c["question"],
                "actual_previous_answer": c["actual_previous_answer"],
                "ideal_answer": c["ideal_answer"],
                "new_runs": grouped.get(cid, []),
            }
        )

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(final_output, f, indent=2, ensure_ascii=False)

    print(f"\nSaved raw results to: {out_json}")


if __name__ == "__main__":
    asyncio.run(main())
