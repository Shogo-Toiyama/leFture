"""
修正版プロンプト(prompts/router_v1.txt)で、本当に推論が要るターンが needs_reasoning=true のままかを確かめる。
ケースは本番のチャット(「不変データ構造」以外のスレッド)から選んだ、計算・コードの追跡・デバッグ・
生徒の解答や計算のチェック・計算への押し返し。入力の組み立ては run_eval.build_input と同じ。

  .venv/bin/python contents_generation/test_codes/router_reasoning_eval/run_true_cases.py --dry-run
  .venv/bin/python contents_generation/test_codes/router_reasoning_eval/run_true_cases.py
"""

import argparse
import asyncio
import json
import os
import time
from datetime import datetime

from run_eval import HERE, PROMPT_V1, build_input, cs

from supabase import create_client  # noqa: E402

from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM  # noqa: E402

# (スレッド, 生徒のメッセージの書き出し, 種類)。どれも期待はtrue
CASES = [
    ("4b0ff0b6-0360-46c6-9626-60e71cfce2e0", "80%取ろうとしたらあと2回のテストで何点取らないといけない？", "calculation"),
    ("c0e86b71-6e87-4f70-9bae-1fd53de9f893", "foldl (*) 1 [1, 2, 3, 4]", "code trace"),
    ("68aff1ab-774b-4a40-a90e-89f2ce190193", "できた！次、Guardを使って書いてみたんだけど、何がエラーなのかな？", "debugging"),
    ("68aff1ab-774b-4a40-a90e-89f2ce190193", "これでどうだ？！", "checking the student's solution"),
    ("f62ae04c-8bc3-476e-9f66-01dae7ee785d", "結果101が余りになった。じゃあCRCは100110101であってる？", "checking the student's calculation"),
    ("f62ae04c-8bc3-476e-9f66-01dae7ee785d", "長い場合は全然多くならないんじゃないんかな？", "pushback on a calculation"),
]


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    system = PROMPT_V1.read_text(encoding="utf-8")
    print(f"model={cs.ROUTER_MODEL} effort={cs.ROUTER_REASONING_EFFORT}")
    built = []
    for thread, prefix, kind in CASES:
        rows = c.table("chat_messages").select("id, role, content, status, created_at, context, router, usage") \
            .eq("thread_id", thread).order("created_at").execute().data
        idx = next(i for i, r in enumerate(rows) if r["role"] == "user" and r["content"].startswith(prefix))
        user_id = c.table("chat_threads").select("user_id").eq("id", thread).execute().data[0]["user_id"]
        courses = c.table("courses").select("course_title").eq("user_id", user_id).is_("deleted_at", "null").execute().data
        courses_text = "\n".join(f"- {r['course_title']} (term not set)" for r in courses)
        user_input, meta = build_input(c, rows, idx, user_id, courses_text, cs._load_blocked_source_types(user_id), thread=thread)
        prod = rows[idx + 1]
        prod_nr = (prod.get("router") or {}).get("needs_reasoning")
        prod_model = ((prod.get("usage") or {}).get("router_model") or "?").split("/")[-1]
        built.append((thread, prefix, kind, user_input, meta, prod_nr, prod_model))
        print(f"  {kind:34s} prod={str(prod_nr)[0]} ({prod_model}) | {prefix[:36]} | {json.dumps(meta, ensure_ascii=False)[:230]}")
    if args.dry_run:
        return

    billing = BillingEngine(task_type="router_reasoning_true_cases")
    llm = UnifiedLLM(billing)
    options = LLMOptions(output_type="json", json_schema=cs.ROUTER_SCHEMA, temperature=0.0, reasoning_effort=cs.ROUTER_REASONING_EFFORT)
    results = []
    for thread, prefix, kind, user_input, meta, prod_nr, prod_model in built:
        n = len(billing.records)
        t0 = time.perf_counter()
        r = await llm.generate(cs.ROUTER_MODEL, [Message(role="system", content=system), Message(role="user", content=user_input)], options)
        dt = round(time.perf_counter() - t0, 2)
        out = r.output_json or {}
        got = out.get("needs_reasoning")
        row = {"thread": thread, "message": prefix, "kind": kind, "expected": True, "got": got, "pass": got is True,
               "production": prod_nr, "production_model": prod_model, "latency_s": dt,
               "tokens": {"in": r.input_tokens, "out": r.output_tokens, "cache": r.cache_read_tokens},
               "cost_usd": round(sum(x.cost_usd for x in billing.records[n:]), 6),
               "output_json": out, "meta": meta, "input": user_input}
        results.append(row)
        print(f"{'OK' if row['pass'] else 'NG'} got={str(got)[0]} prod={str(prod_nr)[0]} intent={out.get('intent')} "
              f"ret={str(out.get('needs_retrieval'))[0]} lang={out.get('reply_language')} {dt}s ${row['cost_usd']:.5f} | {kind}: {prefix[:36]}")
    total = billing.total_usd()
    passed = sum(r["pass"] for r in results)
    print(f"\nPASS {passed}/{len(results)}  TOTAL ${total:.5f}")
    out_path = HERE / "results" / f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_router_reasoning_v1_true_cases.json"
    out_path.write_text(json.dumps({"model": cs.ROUTER_MODEL, "prompt": "router_v1", "pass": passed, "total": len(results),
                                    "total_cost_usd": total, "rows": results}, ensure_ascii=False, indent=2), encoding="utf-8")
    print("saved", out_path)


if __name__ == "__main__":
    asyncio.run(main())
