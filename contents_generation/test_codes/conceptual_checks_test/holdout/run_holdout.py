#!/usr/bin/env python3
"""
過学習の確認: 調整に使っていない確認の質問(cases/holdout_cases.json)で、
  base = コミット済みのプロンプト(HEAD)
  work = 作業ツリーのプロンプト(今の変更)
を同じ条件で生成して比べる。

- 推論の強さは、本番の振り分けの結果(needs_reasoning)どおり。推論ターンはmedium、それ以外はlow。
  (--effort low で全部lowに固定もできる。本番に合わせるのが基本)
- 人が読む用のファイルは、案をA/Bに伏せてシャッフルする(どちらがどちらかは *_key.json)。
- 数える指標は目安。訂正の構えが「訂正」か「おまけ」かは、読んで判断する。

使い方:
  python run_holdout.py --dry-run          # プロンプトの組み立てだけ確認(APIは呼ばない)
  python run_holdout.py --runs 2           # 全10ケース x 2案 x 2回
  python run_holdout.py --cases H1,H7 --runs 3
"""

import argparse
import asyncio
import json
import random
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services import chat_service as cs
from app.services.chat_screen import ScreenPage
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM

PROMPT_FILES = ("chat_answer_prompt.txt", "chat_answer_turn_prompt.txt")
PROMPT_DIR = "lefture_backend/app/services/prompts"
_orig_load = cs._load_prompt


def head_prompts() -> dict[str, str]:
    return {
        name: subprocess.run(
            ["git", "show", f"HEAD:{PROMPT_DIR}/{name}"], cwd=REPO_ROOT, capture_output=True, text=True, check=True
        ).stdout
        for name in PROMPT_FILES
    }


def use(variant: str, head: dict[str, str]) -> None:
    cs._load_prompt = (lambda name: head.get(name) or _orig_load(name)) if variant == "base" else _orig_load


def build_messages(case: dict):
    sp = case.get("screen_page")
    screen_page = (
        ScreenPage(
            kind=sp["kind"], lecture_id=sp.get("lecture_id"), topic_number=sp.get("topic_number"),
            title=sp.get("title") or "", text=sp.get("text") or "",
            selection_marked=sp.get("selection_marked", False), truncated=sp.get("truncated", False),
        )
        if sp else None
    )
    turn = cs.PreparedTurn(
        user_id=case["user_id"], thread_id=case["thread_id"], is_new_thread=False, thread_has_title=True,
        user_message_id="eval-user", assistant_message_id="eval-asst", content=case["question"],
        selected_text=None, lecture_label=case.get("lecture_label"), context_lecture_id=None, screen_page=screen_page,
    )
    router = case.get("router") or {}
    decision = cs.RouterDecision(
        intent="learning", needs_retrieval=False, reply_language=router.get("reply_language", "ja"),
        thread_title=None, needs_reasoning=bool(router.get("needs_reasoning")),
    )
    history = cs.build_history_messages(case["history_rows"], cs.RAW_MAX_TURNS, cs.HISTORY_MAX_CHARS_PER_MESSAGE)
    messages = cs._build_answer_messages(
        turn=turn, decision=decision, memory=cs.ConversationMemory(), history=history,
        profile=case.get("profile") or "", materials=[],
        student_memos=case.get("student_memos") or [], open_questions=case.get("open_questions") or [],
    )
    messages, _ = cs.fit_answer_input(messages)
    return messages, bool(router.get("needs_reasoning"))


# ---- 目安の指標(読む前の目安。最後は人が読む) ----
HABIT = re.compile(r"ほぼ|ただ|ひとつだけ|一つだけ|直させ|整理させ|補足|言い方を|整えさせ|おおむね|だいたい|正確には|厳密")
CORRECTION = re.compile(r"直させ|整理させ|訂正|言い直|正確に(は|する)|ズレ|修正")
CONTRAST = re.compile(r"というより|ではなく|じゃなくて|ではありません|わけではありません")
TEMPLATE = re.compile(r"という意味なら|のことなら|ならまさに|なら、まさに|その通り")


def metrics(text: str) -> dict:
    head = text[:130]
    return {
        "chars": len(text),
        "habit_head": bool(HABIT.search(head)),
        "correction_word_head": bool(CORRECTION.search(text[:200])),
        "contrast_first400": len(CONTRAST.findall(text[:400])),
        "template_phrase": len(TEMPLATE.findall(text)),
    }


async def run_one(llm, sem, messages, effort, model):
    opts = cs.answer_options(model, effort, cs.ANSWER_MAX_OUTPUT_TOKENS)
    async with sem:
        state = StreamState()
        t0 = time.perf_counter()
        first = None
        err = None
        try:
            async for _d in llm.generate_stream(model, messages, state, opts):
                if first is None:
                    first = time.perf_counter() - t0
        except Exception as e:  # noqa: BLE001
            err = str(e)[:300]
    return {"text": state.output_text, "error": err, "first_token_s": first, "total_s": time.perf_counter() - t0,
            "input_tokens": state.input_tokens, "output_tokens": state.output_tokens}


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--cases", default="")
    ap.add_argument("--effort", choices=["prod", "low"], default="prod")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    cases = json.loads((Path(__file__).parent / "cases" / "holdout_cases.json").read_text(encoding="utf-8"))
    if args.cases:
        want = {c.strip().upper() for c in args.cases.split(",")}
        cases = [c for c in cases if c["case_id"] in want]
    head = head_prompts()
    model = cs.ANSWER_MODEL

    if args.dry_run:
        for c in cases:
            sizes = {}
            for v in ("base", "work"):
                use(v, head)
                msgs, reasoning = build_messages(c)
                sizes[v] = (len(msgs[0].content), len(msgs[-1].content))
            eff = "medium" if (reasoning and args.effort == "prod") else "low"
            print(f"{c['case_id']} [{c['kind']}] effort={eff} system base/work={sizes['base'][0]}/{sizes['work'][0]} "
                  f"turn base/work={sizes['base'][1]}/{sizes['work'][1]}")
        use("work", head)
        return

    llm = UnifiedLLM(BillingEngine(task_type="holdout"))
    sem = asyncio.Semaphore(3)
    jobs = []
    for c in cases:
        for v in ("base", "work"):
            use(v, head)
            msgs, reasoning = build_messages(c)
            effort = "medium" if (reasoning and args.effort == "prod") else "low"
            for r in range(args.runs):
                jobs.append((c["case_id"], v, r, effort, msgs))
    use("work", head)

    print(f"{len(jobs)} calls ({len(cases)} cases x 2 variants x {args.runs} runs), model={model}")
    results = await asyncio.gather(*[run_one(llm, sem, m, e, model) for (_c, _v, _r, e, m) in jobs])

    rows = []
    for (cid, v, r, effort, _m), res in zip(jobs, results):
        rows.append({"case_id": cid, "variant": v, "run": r, "effort": effort, **res, **metrics(res["text"])})

    out_dir = Path(__file__).parent / "results"
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    (out_dir / f"holdout_{ts}.json").write_text(
        json.dumps({"timestamp": ts, "model": model, "effort_mode": args.effort, "rows": rows}, ensure_ascii=False, indent=2),
        encoding="utf-8")

    # 指標のまとめ(種類 x 案)
    kinds = {c["case_id"]: c["kind"] for c in cases}
    print("\n== 指標(目安) ==")
    for kind in ("A", "B", "C"):
        for v in ("base", "work"):
            sel = [x for x in rows if kinds[x["case_id"]] == kind and x["variant"] == v and not x["error"]]
            if not sel:
                continue
            n = len(sel)
            print(f"[{kind}] {v:4s} n={n:2d} 冒頭に ほぼ/ただ系 {sum(x['habit_head'] for x in sel)}/{n}  "
                  f"『訂正』語 {sum(x['correction_word_head'] for x in sel)}/{n}  "
                  f"『というより/ではなく』 平均{sum(x['contrast_first400'] for x in sel)/n:.2f}  "
                  f"定型フレーズ 平均{sum(x['template_phrase'] for x in sel)/n:.2f}  長さ平均{sum(x['chars'] for x in sel)//n}")

    # 人が読む用: 案を伏せてA/Bにシャッフル
    rnd = random.Random(args.seed)
    key = {}
    lines = [f"# holdout review {ts}\n", "(A/Bは案を伏せています。対応は *_key.json)\n"]
    for c in cases:
        flip = rnd.random() < 0.5
        key[c["case_id"]] = {"A": "work" if flip else "base", "B": "base" if flip else "work"}
        lines += [f"\n## {c['case_id']} [{c['kind']}] {c['name']}", f"*{c.get('note','')}*\n",
                  f"**ユーザー**: {c['question'][:400]}\n", f"**前の本番の回答(参考)**: {c['actual_previous_answer'][:300]}...\n"]
        for label in ("A", "B"):
            v = key[c["case_id"]][label]
            for x in sorted((x for x in rows if x["case_id"] == c["case_id"] and x["variant"] == v), key=lambda x: x["run"]):
                lines += [f"\n### 案{label} (回{x['run']+1})\n", x["text"] or f"[error] {x['error']}", ""]
    (out_dir / f"holdout_{ts}_review.md").write_text("\n".join(lines), encoding="utf-8")
    (out_dir / f"holdout_{ts}_key.json").write_text(json.dumps(key, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nSaved: {out_dir}/holdout_{ts}.json , _review.md , _key.json")


if __name__ == "__main__":
    asyncio.run(main())
