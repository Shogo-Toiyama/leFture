"""
回答役のモデル・推論の深さの比較(「ネットワークの宿題」スレッドで起きた失敗の再現)。

本番のコード(chat_service.build_history_messages / _build_answer_messages と、
llm_unified.UnifiedLLM.generate_stream)をそのまま使い、モデルと推論の深さだけを差し替える。
どのケースも検索なし(出典なし)。cases/cases.json は build_cases.py で作る。

流れ: ケース × 構成 × 回数 だけ回答を作る → results/run_*.json と、構成名を伏せて順番を混ぜた
results/blind_*.md(採点する人が読む用)を書き出す → 採点(Claude Codeが直接読んで付ける。2026-10-03に
ユーザーと決定。LLMの採点役は使わない)を results/grades_*.json に書く → --grades でレポートを作る。

費用は本番の料金表(PRICE_MATRIX)の単価で計算する。無いモデルだけlitellmのモデル表で補う。キャッシュ割引は無視。

実行例:
  python run_eval.py --dry-run                      # 組み立てだけ(LLMは呼ばない)
  python run_eval.py --smoke                        # 各構成に短い質問を1回ずつ(接続確認)
  python run_eval.py                                # 全部(9ケース × 7構成 × 3回)
  python run_eval.py --configs fl35_none,f38_low --cases table_check --runs 1
  python run_eval.py --grades results/grades_XXXX.json --run results/run_XXXX.json   # 採点を入れてレポート
"""

import argparse
import asyncio
import html
import json
import random
import statistics
import sys
import time
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

import litellm  # noqa: E402

from app.services.chat_service import (  # noqa: E402
    ANSWER_MAX_OUTPUT_TOKENS,
    HISTORY_MAX_CHARS_PER_MESSAGE,
    RAW_MAX_TURNS,
    ConversationMemory,
    PreparedTurn,
    RouterDecision,
    _build_answer_messages,
    build_history_messages,
)
from app.services.helpers.llm_unified import (  # noqa: E402
    BillingEngine,
    PRICE_MATRIX,
    LLMOptions,
    Message,
    StreamState,
    UnifiedLLM,
)

TEST_DIR = Path(__file__).resolve().parent
CASES_PATH = TEST_DIR / "cases" / "cases.json"
RESULTS_DIR = TEST_DIR / "results"

# 構成名 → (モデル, 推論の深さ)。fl35_noneが今の本番。
CONFIGS = {
    "fl35_none": ("gemini/gemini-3.5-flash-lite", "none"),
    "fl35_low": ("gemini/gemini-3.5-flash-lite", "low"),
    "fl35_medium": ("gemini/gemini-3.5-flash-lite", "medium"),
    "f25_low": ("gemini/gemini-2.5-flash", "low"),
    # 3.8 Flashは推論なし(minimal)を受け付けない(2026-10-03に400で確認)
    "f38_low": ("gemini/gemini-3.8-flash", "low"),
    "f38_medium": ("gemini/gemini-3.8-flash", "medium"),
    "luna_low": ("gpt-6-luna", "low"),
}
# 上限の目安(採用は考えない)。費用が大きいので、上の全部でうまくいかなかったときだけ、
# ユーザーに相談してから --configs sol_low で回す(2026-10-03の方針)
ON_REQUEST_CONFIGS = {
    "sol_low": ("gpt-6-sol", "low"),
}
# 口調の指示を足した構成(2026-10-03、Lunaの淡々とした口調をGeminiに近づけられるかの確認)。
# 足す節は回答役のsystemの「### CITATIONS」の直前に入れる(実験用。採用するなら本番のプロンプトに組み込む)
VOICE_SECTION = """\
### VOICE
Sound like a warm, upbeat friend who is genuinely on the student's side: casual and friendly, glad to help, encouraging when they are stuck, and gentle when they seem frustrated, tired, or unsure (acknowledge how they feel in a few words before getting into the content). Use exclamation marks and light, natural expressions of feeling where they fit. Warmth never changes the substance: every fact, number, and verdict stays exactly as accurate as GETTING IT RIGHT requires, and you never praise something that is wrong.

"""
VOICE_CONFIGS = {
    "luna_low_warm": ("gpt-6-luna", "low"),
}
ALL_CONFIGS = {**CONFIGS, **ON_REQUEST_CONFIGS, **VOICE_CONFIGS}
# 推論で使う分の余裕。途中で切れると比較にならないので本番(1024)より大きく取る。
# 切れたかどうかはfinish_reasonで記録する
THINKING_ALLOWANCE = 8192
CONCURRENCY = 6

def _cost_usd(model: str, input_tokens: int, output_tokens: int) -> float:
    rates = PRICE_MATRIX["tokens"].get(model)
    if rates is not None:
        return (input_tokens * rates["input"] + output_tokens * rates["output"]) / 1_000_000
    rates = litellm.model_cost.get(model) or litellm.model_cost.get(model.split("/", 1)[-1]) or {}
    return input_tokens * (rates.get("input_cost_per_token") or 0) + output_tokens * (rates.get("output_cost_per_token") or 0)


def build_messages(data: dict, case: dict) -> list[Message]:
    turn = PreparedTurn(
        user_id="eval", thread_id="eval", is_new_thread=False, thread_has_title=True,
        user_message_id="eval-u", assistant_message_id="eval-a", content=case["question"],
        selected_text=None, lecture_label=None, context_lecture_id=None,
    )
    decision = RouterDecision(intent="learning", needs_retrieval=False, reply_language="ja", thread_title=None)
    history = build_history_messages(case["history_rows"], RAW_MAX_TURNS, HISTORY_MAX_CHARS_PER_MESSAGE)
    return _build_answer_messages(
        turn, decision, ConversationMemory(), history, data["profile"], [],
        student_memos=data["student_memos"], open_questions=data["open_questions"],
    )


async def run_one(llm: UnifiedLLM, sem: asyncio.Semaphore, messages: list[Message], config: str) -> dict:
    model, effort = ALL_CONFIGS[config]
    if config in VOICE_CONFIGS:
        system = messages[0].content.replace("### CITATIONS", VOICE_SECTION + "### CITATIONS", 1)
        messages = [Message(role="system", content=system), *messages[1:]]
    limit = ANSWER_MAX_OUTPUT_TOKENS + THINKING_ALLOWANCE
    # OpenAIの推論モデルはmax_tokensを受け付けず、max_completion_tokensで指定する。
    # temperatureも既定値(1)以外は受け付けない(本番の探索役と同じ)
    options = (LLMOptions(max_completion_tokens=limit, reasoning_effort=effort, temperature=1.0)
               if model.startswith("gpt-")
               else LLMOptions(max_tokens=limit, reasoning_effort=effort))
    async with sem:
        state = StreamState()
        start = time.perf_counter()
        first_token = None
        error = None
        try:
            async for _delta in llm.generate_stream(model, messages, state, options):
                if first_token is None:
                    first_token = time.perf_counter() - start
        except Exception as e:
            error = str(e)[:500]
        total = time.perf_counter() - start
    text = state.output_text
    return {
        "config": config, "model": model, "effort": effort, "text": text, "error": error,
        "finish_reason": state.finish_reason,
        "first_token_s": first_token, "total_s": total,
        "input_tokens": state.input_tokens, "output_tokens": state.output_tokens,
        "cost_usd": _cost_usd(model, state.input_tokens, state.output_tokens),
        # どのケースも出典なしなので、引用の記号が出たら全部違反(履歴の崩れた引用を真似たもの)
        "citation_marks": text.count("⟦") + text.count("[["),
    }


async def generate_all(data: dict, case_ids: list[str], configs: list[str], runs: int) -> list[dict]:
    llm = UnifiedLLM(BillingEngine())
    sem = asyncio.Semaphore(CONCURRENCY)
    jobs, keys = [], []
    for case in data["cases"]:
        if case["id"] not in case_ids:
            continue
        messages = build_messages(data, case)
        for config in configs:
            for run in range(runs):
                jobs.append(run_one(llm, sem, messages, config))
                keys.append((case["id"], run))
    results = []
    for i, coro in enumerate(asyncio.as_completed([_keyed(k, j) for k, j in zip(keys, jobs)]), 1):
        (case_id, run), res = await coro
        res.update({"case": case_id, "run": run})
        results.append(res)
        status = "ERR" if res["error"] else f"{res['total_s']:.1f}s {res['output_tokens']}tok"
        print(f"[{i}/{len(jobs)}] {case_id} {res['config']} #{run} {status}")
    return results


async def _keyed(key, coro):
    return key, await coro


def write_blind(data: dict, results: list[dict], md_path: Path, key_path: Path) -> None:
    """構成名を伏せ、ケースごとに順番を混ぜた回答一覧(採点する人が読む用)と、ラベル→回答の対応表。"""
    lines, key = [], {}
    for case in data["cases"]:
        answers = [r for r in results if r["case"] == case["id"]]
        if not answers:
            continue
        random.Random(case["id"]).shuffle(answers)
        lines += [f"# {case['id']}", "", "## expect", *[f"{i + 1}. {x}" for i, x in enumerate(case["expect"])],
                  "", "## must_not", *[f"{i + 1}. {x}" for i, x in enumerate(case["must_not"])], ""]
        for i, r in enumerate(answers, 1):
            label = f"{case['id']}/R{i:02d}"
            key[label] = {"case": r["case"], "config": r["config"], "run": r["run"]}
            lines += [f"### {label}", "", r["text"] or f"(ERROR: {r['error']})", ""]
    md_path.write_text("\n".join(lines))
    key_path.write_text(json.dumps(key, ensure_ascii=False, indent=2))


def merge_grades(results: list[dict], key: dict, grades: dict) -> None:
    """grades: {ラベル: {expect_met, must_not_violated, factual_errors, note}} を各回答の"judge"に入れる。"""
    index = {(r["case"], r["config"], r["run"]): r for r in results}
    for label, g in grades.items():
        k = key[label]
        index[(k["case"], k["config"], k["run"])]["judge"] = g


def _passed(r: dict) -> bool | None:
    j = r.get("judge")
    if not j:
        return None
    return all(j["expect_met"]) and not any(j["must_not_violated"]) and not j["factual_errors"]


def summarize(results: list[dict]) -> list[dict]:
    rows = []
    for config in ALL_CONFIGS:
        rs = [r for r in results if r["config"] == config]
        if not rs:
            continue
        judged = [r for r in rs if r.get("judge")]
        by_case: dict[str, list[bool]] = {}
        for r in judged:
            by_case.setdefault(r["case"], []).append(_passed(r))
        ok = [r for r in rs if not r["error"]]
        rows.append({
            "config": config,
            "n": len(rs),
            "errors": len(rs) - len(ok),
            "pass": sum(bool(_passed(r)) for r in judged),
            "judged": len(judged),
            "expect_rate": _ratio(sum(sum(r["judge"]["expect_met"]) for r in judged),
                                  sum(len(r["judge"]["expect_met"]) for r in judged)),
            "violations": sum(sum(r["judge"]["must_not_violated"]) for r in judged),
            "factual_errors": sum(len(r["judge"]["factual_errors"]) for r in judged),
            # 同じケースの回答の合否が全部そろっているケースの数(3回とも合格・3回とも不合格)
            "consistent_cases": sum(len(set(v)) == 1 for v in by_case.values()),
            "cases": len(by_case),
            "first_token_p50": _median([r["first_token_s"] for r in ok if r["first_token_s"] is not None]),
            "total_p50": _median([r["total_s"] for r in ok]),
            "output_tokens_avg": _mean([r["output_tokens"] for r in ok]),
            "cost_avg": _mean([r["cost_usd"] for r in ok]),
            "citation_marks": sum(r["citation_marks"] for r in ok),
            "truncated": sum(r["finish_reason"] == "length" for r in ok),
        })
    return rows


def _ratio(a, b):
    return a / b if b else None


def _median(xs):
    return statistics.median(xs) if xs else None


def _mean(xs):
    return statistics.mean(xs) if xs else None


def _fmt(x, spec=".2f", none="–"):
    return none if x is None else format(x, spec)


def write_report(data: dict, results: list[dict], path: Path) -> None:
    summary = summarize(results)
    e = html.escape
    head = ("<tr><th>構成</th><th>合格</th><th>expect達成率</th><th>禁止違反</th><th>事実誤り</th><th>一貫したケース</th>"
            "<th>最初の1文字(中央値)</th><th>全体(中央値)</th><th>出力tok(平均)</th><th>1回の費用(平均)</th>"
            "<th>引用記号</th><th>途中切れ</th><th>エラー</th></tr>")
    body = "".join(
        f"<tr><td>{e(s['config'])}<br><small>{e(' / '.join(ALL_CONFIGS[s['config']]))}</small></td>"
        f"<td>{s['pass']}/{s['judged']}</td><td>{_fmt(s['expect_rate'], '.0%')}</td><td>{s['violations']}</td>"
        f"<td>{s['factual_errors']}</td><td>{s['consistent_cases']}/{s['cases']}</td>"
        f"<td>{_fmt(s['first_token_p50'])}s</td><td>{_fmt(s['total_p50'])}s</td>"
        f"<td>{_fmt(s['output_tokens_avg'], '.0f')}</td><td>${_fmt(s['cost_avg'], '.4f')}</td>"
        f"<td>{s['citation_marks']}</td><td>{s['truncated']}</td><td>{s['errors']}</td></tr>"
        for s in summary)
    sections = []
    for case in data["cases"]:
        rs = [r for r in results if r["case"] == case["id"]]
        if not rs:
            continue
        items = []
        for config in ALL_CONFIGS:
            for r in sorted([r for r in rs if r["config"] == config], key=lambda r: r["run"]):
                j = r.get("judge") or {}
                verdict = {True: "✅", False: "❌", None: "?"}[_passed(r)]
                detail = ""
                if j:
                    detail = (f"expect {''.join('○' if x else '×' for x in j['expect_met'])} / "
                              f"禁止 {''.join('×' if x else '○' for x in j['must_not_violated'])}"
                              f" — {e(j.get('note', ''))}")
                    if j["factual_errors"]:
                        detail += "<br>誤り: " + e(" / ".join(j["factual_errors"]))
                items.append(
                    f"<details><summary>{verdict} <b>{e(config)}</b> #{r['run']} "
                    f"({_fmt(r['total_s'], '.1f')}s, {r['output_tokens']}tok) {detail}</summary>"
                    f"<pre>{e(r['text'] or r['error'] or '')}</pre></details>")
        sections.append(
            f"<h2>{e(case['id'])}</h2><p>{e(case['about'])}</p>"
            f"<blockquote>{e(case['question'])}</blockquote>"
            f"<p><b>expect</b></p><ol>{''.join(f'<li>{e(x)}</li>' for x in case['expect'])}</ol>"
            f"<p><b>must_not</b></p><ol>{''.join(f'<li>{e(x)}</li>' for x in case['must_not'])}</ol>"
            + "".join(items))
    path.write_text(f"""<!doctype html><meta charset="utf-8"><title>回答役の比較</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1100px;margin:24px auto;padding:0 16px;line-height:1.5}}
table{{border-collapse:collapse;font-size:13px}}td,th{{border:1px solid #ccc;padding:4px 8px;text-align:right}}
td:first-child{{text-align:left}}pre{{white-space:pre-wrap;background:#f6f6f6;padding:8px;font-size:13px}}
summary{{cursor:pointer;margin:4px 0}}blockquote{{white-space:pre-wrap;border-left:3px solid #999;margin:0;padding-left:12px}}</style>
<h1>回答役の比較(ネットワークの宿題)</h1><table>{head}{body}</table>{''.join(sections)}""")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--configs", default=",".join(CONFIGS))
    ap.add_argument("--cases", default=None)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--run", default=None, help="既存のrun_*.json(--gradesと一緒に使う)")
    ap.add_argument("--grades", default=None, help="採点のJSON。指定するとレポートを書く")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--smoke", action="store_true")
    args = ap.parse_args()

    data = json.loads(CASES_PATH.read_text())
    configs = args.configs.split(",")
    case_ids = args.cases.split(",") if args.cases else [c["id"] for c in data["cases"]]

    if args.dry_run:
        for case in data["cases"]:
            if case["id"] in case_ids:
                msgs = build_messages(data, case)
                print(f"{case['id']}: {len(msgs)} messages, {sum(len(m.content) for m in msgs)} chars")
        return

    if args.smoke:
        async def smoke():
            llm, sem = UnifiedLLM(BillingEngine()), asyncio.Semaphore(CONCURRENCY)
            msgs = [Message(role="user", content="1+1は？一言で。")]
            for r in await asyncio.gather(*[run_one(llm, sem, msgs, c) for c in configs]):
                print(f"{r['config']}: {r['error'] or repr(r['text'][:40])} "
                      f"first={_fmt(r['first_token_s'])}s out={r['output_tokens']}tok")
        asyncio.run(smoke())
        return

    RESULTS_DIR.mkdir(exist_ok=True)
    if args.run:
        run_path = Path(args.run)
        results = json.loads(run_path.read_text())["results"]
    else:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        run_path = RESULTS_DIR / f"run_{stamp}.json"
        results = asyncio.run(generate_all(data, case_ids, configs, args.runs))
        run_path.write_text(json.dumps({"results": results}, ensure_ascii=False, indent=2))
        write_blind(data, results, run_path.with_name(f"blind_{stamp}.md"), run_path.with_name(f"blindkey_{stamp}.json"))
        print(f"→ {run_path}\n→ blind_{stamp}.md(採点用)")

    if args.grades:
        key = json.loads(run_path.with_name(run_path.name.replace("run_", "blindkey_")).read_text())
        merge_grades(results, key, json.loads(Path(args.grades).read_text()))
        run_path.write_text(json.dumps({"results": results}, ensure_ascii=False, indent=2))
    report_path = run_path.with_name(run_path.name.replace("run_", "report_").replace(".json", ".html"))
    write_report(data, results, report_path)
    for s in summarize(results):
        print(json.dumps(s, ensure_ascii=False))
    print(f"→ {report_path}")


if __name__ == "__main__":
    main()
