"""
振り分け役(chat_router)の reply_language 判定の実験。

問題: 日本語で進んでいる会話なのに、英単語が多い/英語の貼り付けのメッセージで
reply_language が "en" になる(<new_message>だけで言語を判定しているため)。

比較:
  baseline = 本番の chat_router_prompt.txt (そのまま)
  v1       = 本番の reply_language の1行だけを prompts/reply_language_v1.txt に差し替えたもの
モデル: gemini/gemini-2.5-flash-lite (現行) と anthropic/claude-haiku-5-5 (reasoning none)

使い方 (リポジトリ直下から):
  .venv/bin/python contents_generation/test_codes/router_language_eval/run_eval.py --build-cases
  .venv/bin/python .../run_eval.py --dry-run
  .venv/bin/python .../run_eval.py --model gemini/gemini-2.5-flash-lite --prompts baseline v1
  .venv/bin/python .../run_eval.py --model anthropic/claude-haiku-5-5 --effort none --prompts baseline v1
"""

import argparse
import asyncio
import json
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services.chat_service import (  # noqa: E402
    ROUTER_SCHEMA,
    format_router_conversation,
)
from app.services.helpers.helpers import _load_prompt, _render_conditional_sections  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM  # noqa: E402
from app.services.chat_service import fill_placeholders  # noqa: E402

# 既定の5ケース: 正しい結果が出るかの確認だけなので最小限(baselineは測らない。不具合の再現は
# Supabaseに保存済みの本番ルーター出力で確認できている)
DEFAULT_CASES = ["real_coercion", "real_paste_fib", "syn_english_word_answer", "syn_explicit_en", "first_mixed"]

CASES_FILE = HERE / "cases" / "cases.json"
VARIANT_LINE_FILE = HERE / "prompts" / "reply_language_v1.txt"

# 実チャット(Supabase)から取る場合: (thread_id, 生徒メッセージの index, case_id, 期待言語)
REAL_CASES = [
    ("886879bc-3721-4c68-9ffd-df42021d77fa", 24, "real_coercion", "ja"),   # 報告された不具合そのもの
    ("886879bc-3721-4c68-9ffd-df42021d77fa", 26, "real_type_promotion", "ja"),  # 同上
    ("a71a5edf-aa43-4ed1-aa03-f8ea49a0cc95", 12, "real_paste_typing2", "ja"),  # 英語の課題文貼り付け
    ("f62ae04c-8bc3-476e-9f66-01dae7ee785d", 14, "real_paste_coded_len", "ja"),  # 英語の設問+日本語
    ("aca016f4-599e-47cf-9ed7-317873f906de", 8, "real_paste_fib", "ja"),  # 英語だけの貼り付け
]
# 日本語の実チャット履歴(759f28e0)の末尾に、合成のターンを足すケース
SYNTHETIC_BASE_THREAD = "759f28e0-7869-4bed-b6d6-1155fc56d1ac"
SYNTHETIC_CASES = [
    {"id": "syn_english_word_answer", "expected": "ja",
     "extra_history": [("assistant", "じゃあ「ダウンキャスト」は英語でなんて言うでしょう？")],
     "message": "downcast"},
    {"id": "syn_how_to_say", "expected": "ja",
     "extra_history": [],
     "message": "how do I say 暗黙の型変換 in English?"},
    {"id": "syn_explicit_en", "expected": "en",
     "extra_history": [],
     "message": "ここからは英語で答えてほしい。What is upcasting?"},
]
# 履歴なし(初回メッセージ)
FIRST_MESSAGE_CASES = [
    {"id": "first_mixed", "expected": "ja", "message": "Implicit Conversion = Coercionっていう認識で合ってる？！"},
    {"id": "first_en_control", "expected": "en", "message": "Can you explain what a monad is?"},
]


def build_cases() -> None:
    from supabase import create_client
    import os

    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])

    def thread_msgs(tid):
        return c.table("chat_messages").select("role,content,router,usage,created_at") \
            .eq("thread_id", tid).order("created_at").execute().data

    def thread_courses(tid):
        uid = c.table("chat_threads").select("user_id").eq("id", tid).execute().data[0]["user_id"]
        rows = c.table("courses").select("course_title").eq("user_id", uid).execute().data
        return "\n".join(f"- {r['course_title']} (term not set)" for r in rows) or "(unknown)"

    cases = []
    for tid, idx, cid, expected in REAL_CASES:
        ms = thread_msgs(tid)
        user_msg = ms[idx]
        assert user_msg["role"] == "user", (cid, user_msg["role"])
        prod_router = (ms[idx + 1].get("router") or {}) if idx + 1 < len(ms) else {}
        cases.append({
            "id": cid, "source": f"supabase thread {tid} msg#{idx}", "expected": expected,
            "history": [{"role": m["role"], "content": m["content"]} for m in ms[:idx]],
            "message": user_msg["content"], "courses": thread_courses(tid),
            "is_first_message": False,
            "production_router": {k: prod_router.get(k) for k in ("intent", "needs_retrieval", "needs_reasoning", "reply_language")},
        })

    base = thread_msgs(SYNTHETIC_BASE_THREAD)
    base_hist = [{"role": m["role"], "content": m["content"]} for m in base]
    # 末尾が生徒の発言なら落として、assistantで終わるようにする
    while base_hist and base_hist[-1]["role"] != "assistant":
        base_hist.pop()
    base_courses = thread_courses(SYNTHETIC_BASE_THREAD)
    for s in SYNTHETIC_CASES:
        cases.append({
            "id": s["id"], "source": f"synthetic on supabase thread {SYNTHETIC_BASE_THREAD}", "expected": s["expected"],
            "history": base_hist + [{"role": r, "content": t} for r, t in s["extra_history"]],
            "message": s["message"], "courses": base_courses, "is_first_message": False,
            "production_router": None,
        })
    for s in FIRST_MESSAGE_CASES:
        cases.append({
            "id": s["id"], "source": "synthetic (no history)", "expected": s["expected"],
            "history": [], "message": s["message"], "courses": base_courses, "is_first_message": True,
            "production_router": None,
        })
    CASES_FILE.write_text(json.dumps(cases, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"saved {len(cases)} cases -> {CASES_FILE}")
    for k in cases:
        print(f"  {k['id']:28s} history={len(k['history']):2d} msg_chars={len(k['message']):5d} expected={k['expected']}")


def load_system_prompt(variant: str) -> str:
    base = _load_prompt("chat_router_prompt.txt")
    if variant == "baseline":
        return base
    lines = base.split("\n")
    idx = [i for i, l in enumerate(lines) if l.startswith("- `reply_language`:")]
    assert len(idx) == 1, "reply_language line not found exactly once"
    lines[idx[0]] = VARIANT_LINE_FILE.read_text(encoding="utf-8").strip()
    return "\n".join(lines)


def build_user_input(case: dict) -> str:
    template = _render_conditional_sections(_load_prompt("chat_router_input_prompt.txt"), {
        "HAS_REFERENCED_SOURCES": False,
    })
    history = [Message(role=h["role"], content=h["content"]) for h in case["history"]]
    return fill_placeholders(template, {
        "EARLIER_CONVERSATION": "(none)",
        "REFERENCED_SOURCES": "",
        "RECENT_CONVERSATION": format_router_conversation(history),
        "SCREEN_CONTEXT": "(none)",
        "COURSES": case["courses"],
        "ATTACHMENTS": "(none)",
        "IS_FIRST_MESSAGE": "true" if case["is_first_message"] else "false",
        "CURRENT_TIME": "2026-11-06 (Fri) 12:00",
        "NEW_MESSAGE": case["message"],
    })


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build-cases", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--model", default="gemini/gemini-2.5-flash-lite")
    ap.add_argument("--effort", default=None, choices=[None, "none", "low", "medium", "high"])
    ap.add_argument("--prompts", nargs="+", default=["v1"])
    ap.add_argument("--repeat", type=int, default=1, help="各ケースを何回流すか")
    ap.add_argument("--cases", nargs="*", default=DEFAULT_CASES, help="case ids (default: 5 essential cases); 'all' for all 10")
    args = ap.parse_args()

    if args.build_cases:
        build_cases()
        return

    cases = json.loads(CASES_FILE.read_text(encoding="utf-8"))
    if args.cases != ["all"]:
        cases = [c for c in cases if c["id"] in args.cases]

    if args.dry_run:
        # 外部APIは呼ばない: 組み立てとスキーマ・文字数・概算コストだけ確認する
        print("schema required:", ROUTER_SCHEMA["required"])
        for v in args.prompts:
            sp = load_system_prompt(v)
            print(f"\n[{v}] system chars={len(sp)}")
            if v != "baseline":
                base = load_system_prompt("baseline")
                print(f"   delta vs baseline: {len(sp) - len(base):+d} chars")
        total_chars = 0
        for c in cases:
            ui = build_user_input(c)
            total_chars += len(ui)
            print(f"  {c['id']:28s} user_input_chars={len(ui):6d}  expected={c['expected']}")
        sys_chars0 = len(load_system_prompt("baseline"))
        worst = max(len(build_user_input(c)) + sys_chars0 for c in cases)
        print(f"max single-request size: ~{worst/3:,.0f} tokens (Haiku long-context threshold: 100,000)")
        n_calls = len(cases) * len(args.prompts)
        sys_chars = len(load_system_prompt("baseline"))
        est_tokens = (total_chars + sys_chars * len(cases)) * len(args.prompts) / 3.0  # 粗い概算(日英混在で3文字/トークン)
        print(f"\ncalls planned: {n_calls}; rough input tokens: {est_tokens:,.0f}")
        # 入力$0.10/M(flash-lite, haiku-5-5とも)、出力は1コール300トークン見込み
        print(f"rough cost (input $0.10/M, 300 out tokens @ $0.4-0.5/M): ~${est_tokens * 0.10 / 1e6 + n_calls * 300 * 0.5 / 1e6:.4f}")
        return

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    model_tag = args.model.split("/")[-1] + (f"_{args.effort}" if args.effort else "")
    billing = BillingEngine(task_type="router_language_eval")
    llm = UnifiedLLM(billing)
    rows = []
    inputs = {"system_prompts": {v: load_system_prompt(v) for v in args.prompts},
              "user_inputs": {c["id"]: build_user_input(c) for c in cases}}
    for v, run_idx in [(v, r) for r in range(1, args.repeat + 1) for v in args.prompts]:
        sp = load_system_prompt(v)
        for c in cases:
            messages = [Message(role="system", content=sp), Message(role="user", content=build_user_input(c))]
            options = LLMOptions(output_type="json", json_schema=ROUTER_SCHEMA, temperature=0.0,
                                 reasoning_effort=args.effort)
            before = billing.total_usd()
            n_rec = len(billing.records)
            r = None
            t0 = time.perf_counter()
            try:
                r = await llm.generate(args.model, messages, options)
                out = r.output_json or {}
                err = r.json_parse_error
                toks = {"in": r.input_tokens, "out": r.output_tokens, "cache": r.cache_read_tokens}
            except Exception as e:  # noqa: BLE001
                out, err, toks = {}, str(e), {}
            dt = round(time.perf_counter() - t0, 2)
            got = out.get("reply_language")
            ok = bool(got) and got.startswith(c["expected"])
            prod = c.get("production_router") or {}
            other_diff = {k: (prod.get(k), out.get(k)) for k in ("intent", "needs_retrieval", "needs_reasoning")
                          if prod and prod.get(k) != out.get(k)}
            row = {"run": run_idx, "prompt": v, "case": c["id"], "expected": c["expected"], "got": got, "pass": ok,
                   "latency_s": dt, "tokens": toks, "cost_usd": round(billing.total_usd() - before, 6),
                   "intent": out.get("intent"), "needs_retrieval": out.get("needs_retrieval"),
                   "needs_reasoning": out.get("needs_reasoning"), "thread_title": out.get("thread_title"),
                   "diff_vs_production_router": other_diff, "error": err,
                   "output_json": out, "output_text": getattr(r, "output_text", None),
                   "output_chars": len(getattr(r, "output_text", "") or ""),
                   "cost_breakdown": [{"resource": x.resource, "usage": x.usage, "cost_usd": x.cost_usd}
                                      for x in billing.records[n_rec:]]}
            rows.append(row)
            print(f"#{run_idx} {v:9s} {c['id']:28s} expected={c['expected']} got={got} {'OK ' if ok else 'NG '} {dt}s ${row['cost_usd']:.5f}"
                  + (f"  diff={other_diff}" if other_diff else "") + (f"  ERR={err}" if err else ""))

    summary = {}
    for v in args.prompts:
        rs = [r for r in rows if r["prompt"] == v]
        summary[v] = {"pass": sum(r["pass"] for r in rs), "total": len(rs),
                      "avg_latency_s": round(sum(r["latency_s"] for r in rs) / max(1, len(rs)), 2),
                      "max_latency_s": max((r["latency_s"] for r in rs), default=0),
                      "in_tokens": sum(r["tokens"].get("in", 0) for r in rs),
                      "out_tokens": sum(r["tokens"].get("out", 0) for r in rs),
                      "cost_usd": round(sum(r["cost_usd"] for r in rs), 6)}
    print("\nSUMMARY", json.dumps(summary, ensure_ascii=False))
    print(f"TOTAL COST ${billing.total_usd():.5f}")
    out_path = HERE / "results" / f"{ts}_{model_tag}.json"
    out_path.write_text(json.dumps({"model": args.model, "effort": args.effort, "summary": summary,
                                    "total_cost_usd": billing.total_usd(), "rows": rows, "inputs": inputs},
                                   ensure_ascii=False, indent=2), encoding="utf-8")
    print("saved", out_path)


if __name__ == "__main__":
    asyncio.run(main())
