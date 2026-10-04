"""
二段構え(確かめ役 → 書き手)の比較。run_eval.py の続き(2026-10-03)。

確かめ役(GPT-6 Luna 推論low)が会話と最新の質問から「正しい答え・生徒の発言の正誤・前の返答の誤り・
会話の数え方」をメモにし、書き手(Gemini Flash-Lite)がそれを根拠にいつもの口調で返事を書く。
口調はGemini、正確さはLuna、を狙う。本番のコードは変えず、書き手のプロンプトへの追記はここだけで行う。

同じケース・同じ回の確かめ役のメモを、3つの書き手(3.5 / 3.1 / 2.5 Flash-Lite)で共通に使う
(書き手の違いだけを比べるため)。採点は run_eval.py と同じく構成名を伏せた blind_*.md で行う。

実行例:
  python run_two_stage.py --smoke                 # 1ケース1回だけ(メモと3つの返事を表示)
  python run_two_stage.py                         # 9ケース × 3回(確かめ役27回 + 書き手81回)
  python run_two_stage.py --run results/run_2s_XXXX.json --grades results/grades_2s_XXXX.json \\
      --base-run results/run_20261003_195702.json  # 採点を入れ、1段構えの結果と並べたレポート
"""

import argparse
import asyncio
import json
import time
from datetime import datetime
from pathlib import Path

import run_eval
from run_eval import (
    CASES_PATH,
    RESULTS_DIR,
    _cost_usd,
    build_messages,
    merge_grades,
    summarize,
    write_blind,
    write_report,
)
from app.services.chat_service import (
    ANSWER_MAX_OUTPUT_TOKENS,
    ANSWER_THINKING_TOKENS,
    HISTORY_MAX_CHARS_PER_MESSAGE,
    RAW_MAX_TURNS,
    build_history_messages,
)
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, StreamState, UnifiedLLM

SOLVER_MODEL = "gpt-6-luna"
SOLVER_EFFORT = "low"

# 書き手。名前 → (モデル, 推論の深さ)。2.5 Flash-Liteは既定で推論なしなので指定しない
WRITERS = {
    "2s_fl35": ("gemini/gemini-3.5-flash-lite", "none"),
    "2s_fl31": ("gemini/gemini-3.1-flash-lite", "none"),
    "2s_fl25": ("gemini/gemini-2.5-flash-lite", None),
}
for name, (model, effort) in WRITERS.items():
    run_eval.ALL_CONFIGS[name] = (f"{SOLVER_MODEL}({SOLVER_EFFORT}) → {model}", str(effort))

SOLVER_PROMPT = """\
You are the checking step of a study-companion chatbot. You do NOT talk to the student. Read the conversation and the student's latest message, work out the substance carefully, and write notes that a separate writer will turn into the reply.

Work everything out yourself from the original material in the conversation (problem statements, code, numbers the student gave), not from the assistant's earlier replies, which may contain mistakes.

Write concise notes in English (the writer replies in the student's language), under these headings, skipping any that do not apply:
- ANSWER: what the reply needs to say. Where a calculation, trace, or derivation is involved, give the exact values the student asked about and the short working that leads to them (for a step-by-step trace, list every step up to the point asked, with its values).
- STUDENT: each claim or value in the student's latest message (and any earlier work of theirs they are asking about), one by one: right or wrong, the correct value if wrong, and why. Say plainly which parts are right.
- EARLIER MISTAKES: any statement in the assistant's earlier replies that was wrong and matters now, with the correction. If the student had it right before, say so.
- CONVENTIONS: numbering, names, units, and reference points already used in the conversation that the reply must keep.
- UNSURE: anything you are not certain about.
No greetings, no encouragement, no formatting beyond these headings. Keep it under 300 words."""

# 書き手のsystemに足す節(実験用。採用するなら本番のプロンプトに組み込む)
WRITER_SECTION = """\
### CHECKED WORK (only when the latest message has <checked_work>)
A separate checking step has already worked this message out carefully; the <checked_work> at the end of the latest message holds its notes: the correct working and values, which of the student's statements are right or wrong, mistakes in your own earlier replies, and the conventions in use. Treat it as the ground truth: base every fact, number, and verdict in your reply on it, even where your earlier replies in this conversation said otherwise (then correct them openly). When the notes and your earlier replies disagree, the notes are right. Never mention that a checking step, notes, or <checked_work> exist, and never quote the tag. Write in your usual voice and follow everything else in these instructions.

"""


def solver_messages(data: dict, case: dict) -> list[Message]:
    history = build_history_messages(case["history_rows"], RAW_MAX_TURNS, HISTORY_MAX_CHARS_PER_MESSAGE)
    return [Message(role="system", content=SOLVER_PROMPT), *history,
            Message(role="user", content=f"<latest_student_message>\n{case['question']}\n</latest_student_message>")]


def writer_messages(data: dict, case: dict, notes: str) -> list[Message]:
    messages = build_messages(data, case)
    system = messages[0].content.replace("### CITATIONS", WRITER_SECTION + "### CITATIONS", 1)
    last = messages[-1].content
    return [Message(role="system", content=system), *messages[1:-1],
            Message(role="user", content=f"{last}\n\n<checked_work>\n{notes}\n</checked_work>")]


async def solve(llm: UnifiedLLM, sem: asyncio.Semaphore, data: dict, case: dict) -> dict:
    options = LLMOptions(max_completion_tokens=8192, reasoning_effort=SOLVER_EFFORT, temperature=1.0)
    async with sem:
        start = time.perf_counter()
        res = await llm.generate(SOLVER_MODEL, solver_messages(data, case), options)
        elapsed = time.perf_counter() - start
    return {"notes": res.output_text, "solver_s": elapsed, "solver_input_tokens": res.input_tokens,
            "solver_output_tokens": res.output_tokens,
            "solver_cost_usd": _cost_usd(SOLVER_MODEL, res.input_tokens, res.output_tokens)}


async def write(llm: UnifiedLLM, sem: asyncio.Semaphore, data: dict, case: dict, notes: str, writer: str) -> dict:
    model, effort = WRITERS[writer]
    # 本番の回答役と同じ上限
    options = LLMOptions(max_tokens=ANSWER_MAX_OUTPUT_TOKENS + ANSWER_THINKING_TOKENS, reasoning_effort=effort)
    async with sem:
        state = StreamState()
        start = time.perf_counter()
        first_token, error = None, None
        try:
            async for _delta in llm.generate_stream(model, writer_messages(data, case, notes), state, options):
                if first_token is None:
                    first_token = time.perf_counter() - start
        except Exception as e:
            error = str(e)[:500]
        total = time.perf_counter() - start
    return {"text": state.output_text, "error": error, "finish_reason": state.finish_reason,
            "writer_first_token_s": first_token, "writer_total_s": total,
            "input_tokens": state.input_tokens, "output_tokens": state.output_tokens,
            "writer_cost_usd": _cost_usd(model, state.input_tokens, state.output_tokens),
            "citation_marks": state.output_text.count("⟦") + state.output_text.count("[[")}


async def run_case(llm, sem, data, case, run, writers) -> list[dict]:
    solved = await solve(llm, sem, data, case)
    outs = await asyncio.gather(*[write(llm, sem, data, case, solved["notes"], w) for w in writers])
    results = []
    for w, out in zip(writers, outs):
        r = {"case": case["id"], "run": run, "config": w, "model": WRITERS[w][0], "effort": WRITERS[w][1],
             **solved, **out}
        # 1段構えと比べられる形にそろえる(最初の1文字 = 確かめ役の時間 + 書き手の最初の1文字)
        r["first_token_s"] = (solved["solver_s"] + out["writer_first_token_s"]) if out["writer_first_token_s"] else None
        r["total_s"] = solved["solver_s"] + out["writer_total_s"]
        r["cost_usd"] = solved["solver_cost_usd"] + out["writer_cost_usd"]
        results.append(r)
    print(f"{case['id']} #{run}: solver {solved['solver_s']:.1f}s, "
          + ", ".join(f"{r['config']} {r['total_s']:.1f}s" for r in results))
    return results


def write_notes(data: dict, results: list[dict], path: Path) -> None:
    """確かめ役のメモの一覧(ケース・回ごと。どの書き手にも同じものを渡している)。"""
    lines = ["# 確かめ役(GPT-6 Luna low)のメモ", ""]
    for case in data["cases"]:
        for run in sorted({r["run"] for r in results if r["case"] == case["id"]}):
            r = next(r for r in results if r["case"] == case["id"] and r["run"] == run)
            lines += [f"## {case['id']} #{run} ({r['solver_s']:.1f}s)", "", r["notes"], ""]
    path.write_text("\n".join(lines))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--writers", default=",".join(WRITERS))
    ap.add_argument("--cases", default=None)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--smoke", action="store_true")
    ap.add_argument("--run", default=None)
    ap.add_argument("--grades", default=None)
    ap.add_argument("--base-run", default=None, help="1段構えのrun_*.json(採点済み)。並べたレポートを作る")
    args = ap.parse_args()

    data = json.loads(CASES_PATH.read_text())
    writers = args.writers.split(",")
    case_ids = args.cases.split(",") if args.cases else [c["id"] for c in data["cases"]]
    cases = [c for c in data["cases"] if c["id"] in case_ids]

    if args.smoke:
        async def smoke():
            llm, sem = UnifiedLLM(BillingEngine()), asyncio.Semaphore(run_eval.CONCURRENCY)
            for r in await run_case(llm, sem, data, cases[0], 0, writers):
                print(f"\n===== {r['config']} =====\n{r['error'] or r['text'][:600]}")
            print(f"\n===== notes =====\n{r['notes']}")
        asyncio.run(smoke())
        return

    RESULTS_DIR.mkdir(exist_ok=True)
    if args.run:
        run_path = Path(args.run)
        results = json.loads(run_path.read_text())["results"]
    else:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        run_path = RESULTS_DIR / f"run_2s_{stamp}.json"

        async def go():
            llm, sem = UnifiedLLM(BillingEngine()), asyncio.Semaphore(run_eval.CONCURRENCY)
            groups = await asyncio.gather(*[run_case(llm, sem, data, c, run, writers)
                                            for c in cases for run in range(args.runs)])
            return [r for g in groups for r in g]
        results = asyncio.run(go())
        run_path.write_text(json.dumps({"results": results}, ensure_ascii=False, indent=2))
        write_blind(data, results, run_path.with_name(f"blind_2s_{stamp}.md"), run_path.with_name(f"blindkey_2s_{stamp}.json"))
        write_notes(data, results, run_path.with_name(f"notes_2s_{stamp}.md"))
        print(f"→ {run_path}\n→ blind_2s_{stamp}.md(採点用) / notes_2s_{stamp}.md(確かめ役のメモ)")

    if args.grades:
        key = json.loads(run_path.with_name(run_path.name.replace("run_", "blindkey_")).read_text())
        merge_grades(results, key, json.loads(Path(args.grades).read_text()))
        run_path.write_text(json.dumps({"results": results}, ensure_ascii=False, indent=2))
    combined = results
    if args.base_run:
        combined = json.loads(Path(args.base_run).read_text())["results"] + results
    report_path = run_path.with_name(run_path.name.replace("run_", "report_").replace(".json", ".html"))
    write_report(data, combined, report_path)
    for s in summarize(combined):
        print(json.dumps(s, ensure_ascii=False))
    print(f"→ {report_path}")


if __name__ == "__main__":
    main()
