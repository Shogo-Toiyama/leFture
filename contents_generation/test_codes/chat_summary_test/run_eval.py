"""
スレッド要約(docs/chatbot_context_and_retrieval_roadmap.md ステップ2)の評価ハーネス。

本番のコード(app/services/chat_summary.py の summarize_turns と、
app/services/chat_service.py の _build_answer_messages)をそのまま使う。
DBとCloud Tasksの部分だけを、conversations/*.json の台本で置き換えている。

会話を設計2-3のたたみ方(未要約が15往復になったら古い10往復を畳む)で
シミュレートし、各probeで「生の全履歴」と「要約+直近の原文」の2条件の回答を
本番の回答役(ANSWER_MODEL)で作って比べる。事実が含まれているかはLLM審判で判定する。

実行: python run_eval.py
"""

import asyncio
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services.chat_service import (  # noqa: E402
    ANSWER_MODEL,
    ConversationMemory,
    PreparedTurn,
    RouterDecision,
    _build_answer_messages,
    build_history_messages,
)
from app.services.chat_summary import (  # noqa: E402
    EMPTY_HEADER,
    FOLD_SIZE_TURNS,
    FOLD_TRIGGER_TURNS,
    Turn,
    summarize_turns,
)
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM  # noqa: E402

TEST_DIR = Path(__file__).resolve().parent
CONV_DIR = TEST_DIR / "conversations"
RESULTS_DIR = TEST_DIR / "results"

JUDGE_MODEL = "gemini/gemini-2.5-flash-lite"

JUDGE_SCHEMA = {
    "type": "object",
    "properties": {
        "include_results": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "fact": {"type": "string"},
                    "present": {"type": "boolean"},
                    "note": {"type": "string"},
                },
                "required": ["fact", "present", "note"],
            },
        },
        "violation_results": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "fact": {"type": "string"},
                    "violated": {"type": "boolean"},
                    "note": {"type": "string"},
                },
                "required": ["fact", "violated", "note"],
            },
        },
        "overall_pass": {"type": "boolean"},
    },
    "required": ["include_results", "violation_results", "overall_pass"],
}


def _turn_from_round(r: dict, language: str) -> Turn:
    return Turn(
        number=r["round"],
        user_message_id=f"u{r['round']}",
        assistant_message_id=f"a{r['round']}",
        user_content=r["user"],
        assistant_content=r["assistant"],
        assistant_created_at="",
        reply_language=language,
    )


def _rows_from_rounds(rounds: list[dict]) -> list[dict]:
    rows = []
    for r in rounds:
        rows.append({"id": f"u{r['round']}", "role": "user", "content": r["user"], "status": "complete"})
        rows.append({"id": f"a{r['round']}", "role": "assistant", "content": r["assistant"], "status": "complete"})
    return rows


async def fold_conversation(llm: UnifiedLLM, conv: dict) -> dict:
    """本番のrun_fold()と同じ条件で畳み、各probeの時点での(blocks, 原文の範囲)を記録する。"""
    rounds = conv["rounds"]
    language = conv["language"]
    blocks: list[dict] = []
    folded_up_to = 0
    probe_rounds = {p["history_through_round"] for p in conv["probes"]}
    snapshots: dict[int, dict] = {}

    for r in rounds:
        round_num = r["round"]
        if round_num - folded_up_to >= FOLD_TRIGGER_TURNS:
            batch = [_turn_from_round(x, language) for x in rounds if folded_up_to < x["round"] <= folded_up_to + FOLD_SIZE_TURNS]
            prior_titles = [sec["title"] for b in blocks for sec in b["sections"]]
            next_handle = 1 + max((sec["handle"] for b in blocks for sec in b["sections"]), default=0)
            header = blocks[-1]["header"] if blocks else dict(EMPTY_HEADER)
            print(f"  [{conv['id']}] folding rounds {batch[0].number}-{batch[-1].number} (block #{len(blocks) + 1})...")
            sections, new_header = await summarize_turns(llm, prior_titles, header, batch, language, next_handle)
            blocks.append({
                "block_index": len(blocks) + 1,
                "turn_start": batch[0].number,
                "turn_end": batch[-1].number,
                "sections": sections,
                "header": new_header,
            })
            folded_up_to = batch[-1].number

        if round_num in probe_rounds:
            snapshots[round_num] = {
                "blocks": [dict(b) for b in blocks],
                "raw_rounds": [x for x in rounds if folded_up_to < x["round"] <= round_num],
            }
    return snapshots


def _answer_messages(conv: dict, question: str, memory: ConversationMemory, history_rounds: list[dict]) -> list[Message]:
    turn = PreparedTurn(
        user_id="eval", thread_id="eval", is_new_thread=False, thread_has_title=True,
        user_message_id="eval-u", assistant_message_id="eval-a", content=question,
        selected_text=None, lecture_label=None, context_lecture_id=None,
    )
    decision = RouterDecision(
        intent="learning", needs_retrieval=False, search_queries=[], complexity="simple",
        reply_language=conv["language"], thread_title=None,
    )
    history = build_history_messages(_rows_from_rounds(history_rounds), len(history_rounds), 2000)
    return _build_answer_messages(turn, decision, memory, history, "(The student has not shared any profile information yet.)", [])


async def judge(llm: UnifiedLLM, answer: str, must_include: list[str], must_not_include: list[str]) -> dict:
    system = (TEST_DIR / "judge_prompt.txt").read_text(encoding="utf-8")
    user_content = (
        f"<answer>\n{answer}\n</answer>\n\n"
        f"<must_include>\n{json.dumps(must_include, ensure_ascii=False)}\n</must_include>\n\n"
        f"<must_not_include>\n{json.dumps(must_not_include, ensure_ascii=False)}\n</must_not_include>"
    )
    messages = [Message(role="system", content=system), Message(role="user", content=user_content)]
    options = LLMOptions(output_type="json", json_schema=JUDGE_SCHEMA, temperature=0.0)
    result = await llm.generate(JUDGE_MODEL, messages, options)
    if not isinstance(result.output_json, dict):
        raise RuntimeError(f"judge returned non-JSON: {result.output_text[:300]}")
    return result.output_json


async def run_probe(llm: UnifiedLLM, conv: dict, probe: dict, snapshot: dict) -> dict:
    all_rounds = conv["rounds"]
    history_through = probe["history_through_round"]
    probe_round = next(r for r in all_rounds if r["round"] == probe["probe_round"])
    question = probe_round["user"]

    raw_history = [r for r in all_rounds if r["round"] <= history_through]
    memory = ConversationMemory.from_blocks(snapshot["blocks"])
    raw_messages = _answer_messages(conv, question, ConversationMemory(), raw_history)
    summarized_messages = _answer_messages(conv, question, memory, snapshot["raw_rounds"])

    options = LLMOptions(max_tokens=800, reasoning_effort="none")
    raw_result, summarized_result = await asyncio.gather(
        llm.generate(ANSWER_MODEL, raw_messages, options),
        llm.generate(ANSWER_MODEL, summarized_messages, options),
    )

    must_include = probe.get("key_facts_must_include", [])
    must_not_include = probe.get("key_facts_must_not_include", [])
    raw_judge, summarized_judge = await asyncio.gather(
        judge(llm, raw_result.output_text, must_include, must_not_include),
        judge(llm, summarized_result.output_text, must_include, must_not_include),
    )

    return {
        "probe_id": probe["id"],
        "history_through_round": history_through,
        "probe_question": question,
        "gold_reference_answer": probe_round["assistant"],
        "expected_tier": probe.get("expected_tier_at_probe_time"),
        "why_it_matters": probe.get("why_it_matters"),
        "context_stats": {
            "raw_condition_rounds": len(raw_history),
            "summarized_condition_raw_rounds": len(snapshot["raw_rounds"]),
            "summarized_condition_blocks": len(snapshot["blocks"]),
        },
        "raw_condition": {"answer": raw_result.output_text, "judge": raw_judge},
        "summarized_condition": {
            "answer": summarized_result.output_text,
            "summary_text": memory.summary,
            "header_text": memory.notes,
            "judge": summarized_judge,
        },
    }


async def run_conversation(llm: UnifiedLLM, conv_path: Path) -> dict:
    conv = json.loads(conv_path.read_text(encoding="utf-8"))
    print(f"[{conv['id']}] folding ({len(conv['rounds'])} rounds, {len(conv['probes'])} probes)...")
    snapshots = await fold_conversation(llm, conv)

    probe_results = []
    for probe in conv["probes"]:
        print(f"  [{conv['id']}] running probe {probe['id']!r}...")
        probe_results.append(await run_probe(llm, conv, probe, snapshots[probe["history_through_round"]]))

    final = snapshots[max(snapshots)] if snapshots else {"blocks": []}
    return {
        "id": conv["id"],
        "language": conv["language"],
        "scenario": conv["scenario"],
        "qualitative_checks": conv.get("qualitative_checks", []),
        "final_blocks": final["blocks"],
        "final_header": final["blocks"][-1]["header"] if final["blocks"] else EMPTY_HEADER,
        "probe_results": probe_results,
    }


async def main() -> None:
    RESULTS_DIR.mkdir(exist_ok=True)
    billing = BillingEngine(task_type="CHAT_SUMMARY_EVAL")
    llm = UnifiedLLM(billing)

    all_results = []
    for path in sorted(CONV_DIR.glob("*.json")):
        result = await run_conversation(llm, path)
        (RESULTS_DIR / f"{result['id']}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        all_results.append(result)

    (RESULTS_DIR / "_all_results.json").write_text(json.dumps(all_results, ensure_ascii=False, indent=2), encoding="utf-8")

    print("\n=== results ===")
    for r in all_results:
        for p in r["probe_results"]:
            print(f"  {r['id']}/{p['probe_id']}: raw={p['raw_condition']['judge']['overall_pass']} "
                  f"summarized={p['summarized_condition']['judge']['overall_pass']}")
    print(f"\ntotal cost: ${billing.total_usd():.6f}")


if __name__ == "__main__":
    asyncio.run(main())
