"""
振り分け役の「推論が要るか」を true/false から 4段階(none / low / medium / high)にする実験。その1: 振り分け役の判定だけ。

背景(2026-11-06): needs_reasoning=true だと回答役(Haiku 5.5)は effort high で答える(chat_reasoning.REASONING_CONFIG)。
本番では true のとき出力の中央値2,195トークン・最初の文字まで9.9秒、false のとき1,139トークン・4.3秒。
テスト範囲の表を貼って「一つずつ確認したい」と言っただけのターン(404a9a0e)も true になり、出力6,092トークン・22秒だった。
4段階にすれば、「少し考えればいい」ものを medium / low で止められるかを見る。

やること: 本番のルータープロンプトの「ALSO, WHETHER TO THINK IT THROUGH」の節を4段階の定義に差し替え(prompts/ に保存)、
スキーマの needs_reasoning を reasoning_level(enum)に替えて、本番のモデル(gemini-3.1-flash-lite, 推論なし)で
本番の発言17件を判定させる。入力は router_reasoning_eval/run_eval.build_input で本番と同じ形に組む。
各ケースには許容できる段階の集合を付ける(境界のものは2段階)。baseline は本番に保存された needs_reasoning。

本番と違うところ(build_input と同じ): 添付資料の「選択中」は今の状態。コース一覧は名前だけ(学期なし)。
is_first_message は常に false(thread_title にしか効かない)。

  .venv/bin/python contents_generation/test_codes/router_reasoning_levels/run_eval.py --dry-run
  .venv/bin/python contents_generation/test_codes/router_reasoning_levels/run_eval.py
"""

import argparse
import asyncio
import copy
import json
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "router_reasoning_eval"))
import run_eval as base  # noqa: E402  (lefture_backend への path と .env の読み込みもここで済む)
from run_eval import cs, create_client, os  # noqa: E402

from app.services.chat_attachments import estimate_tokens  # noqa: E402
from app.services.helpers.helpers import _load_prompt  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM  # noqa: E402

LEVELS = ["none", "low", "medium", "high"]

# (スレッド, 生徒のメッセージのidの先頭, 許容する段階, メモ)
# 許容範囲は2026-11-06にユーザーの基準で付け直し: high は本当に厄介な証明などだけ。ラムダの答え合わせ・コードの追跡・
# 簡単な計算は medium(選択肢があるからといって high にしない)。
CASES = [
    ("6a3080e4", "7acf61c0", {"none"}, "今何時かわかる？"),
    ("3f8d3695", "5062109b", {"none", "low"}, "jaa (打ちかけ)"),
    ("4b0ff0b6", "9b7b7b42", {"none", "low"}, "14点でどうしよう、カーブある？(気持ち+事実)"),
    ("886879bc", "26472a8f", {"low"}, "ここでのBindingってどう言う意味？"),
    ("886879bc", "708113a6", {"low"}, "Implicit Conversion = Coercion であってる？"),
    ("886879bc", "b24572ba", {"low"}, "日本語で説明して。"),
    ("3f8d3695", "bd374d15", {"low"}, "次の概念に進みたい"),
    ("4b0ff0b6", "53148fb5", {"low"}, "授業の初めの成績の話をまとめて"),
    ("3f8d3695", "404a9a0e", {"low", "medium"}, "テスト範囲の表を貼って一つずつ確認したい(今回のターン)"),
    ("886879bc", "bbaf0d94", {"low", "medium"}, "強い型検査だと柔軟な操作ができないってこと？"),
    ("3f8d3695", "f4ffa520", {"medium"}, "自由変数・シャドーイングの問題を出して"),
    ("3f8d3695", "c9c02605", {"medium"}, "foldlとfoldrで違う結果になる例は？"),
    ("3f8d3695", "2a1d7184", {"medium"}, "foldl (flip (:)) と foldr (:) の違いは r/l 以外にある？"),
    ("886879bc", "ee537eba", {"medium"}, "僕の宿題の答えはこうだった(英文の解答)"),
    ("759f28e0", "1567062d", {"medium"}, "4464ってほんと？なんでこんな数字に(キャストの値)"),
    ("3f8d3695", "c7a89472", {"medium"}, "問1〜問3の答え(ラムダの評価)を採点"),
    ("4b0ff0b6", "c431a100", {"medium"}, "80%取るにはあと2回で何点？(最低点除外)"),
    # 2026-11-06 追加: high の候補(本番に本物の証明問題は無かった)。古いスレッドで needs_reasoning の記録なし
    ("931543fd", "fc388cec", {"high"}, "クロックリカバリ: 8%遅い送信で10ビットのサンプリング時刻とlagを計算"),
    ("399aab7f", "f24d94bd", {"medium"}, "株の売買の最大利益をO(N)で解くには"),
    ("aca016f4", "4ea6a277", {"low", "medium"}, "OCamlのwhileループの出力と純粋性、JaneStreet(一問目から)"),
]

OLD_SECTION_START = "### ALSO, WHETHER TO THINK IT THROUGH\n"
OLD_SECTION_END = "### LAST\n"
NEW_SECTION = """### ALSO, HOW MUCH TO THINK IT THROUGH
`reasoning_level` — how much the answerer should think before writing. Thinking makes the reply slower and costs more, so pick the lowest level at which a quick answer would still be right and complete:
- `none`: nothing to explain or work out: chitchat, greetings, thanks and reactions with no new question, feelings and support with no question about a course, the current time or date, `blocked`, `crisis`.
- `low`: explaining from what the answerer knows or is given: a fact, a definition or word meaning, how two terms relate, confirming a one-line understanding of a concept ("so X is the same as Y, right?"), an explanation or example of a concept, moving on to the next concept, a summary or overview (of a lecture, a course, or a test's scope), a translation or re-explaining in another language. Most messages are `low`.
- `medium`: a question with a catch that needs a few careful steps, but no long working: whether a claim holds in general or only in this case, telling apart concepts that are easy to confuse, reading and explaining a short piece of code or a small example, making practice problems together with correct answers, checking a short answer or a one-line reason the student gives.
- `high`: careful step-by-step working, where a quick answer is likely to be wrong: calculations, derivations, proofs, math beyond a quick fact, unit conversions, or applying a formula to given numbers; tracing, predicting the output of, or debugging code, an algorithm, or a circuit beyond a few lines; checking the student's own substantial work (their code, their solutions to several problems, an essay, a report, an application); the student pushing back on an earlier calculation, code trace, or answer in a way that needs re-checking ("hm? wait", "isn't it the other way around?"); continuing a calculation or trace the conversation is in the middle of.
Material the student pastes to study from or to have explained (a syllabus, a test's scope, a worksheet, lecture notes) is not their own work: judge the level by what they ask about it.
When torn between two levels, choose the lower one.

"""


# v2: v1 では high が0件(計算・採点も medium)。「迷ったら低い方」を、計算と問題の答えの確認は high と先に決めてからに限る。
# medium の「短い答えの確認」を、計算もコードの評価も要らない一言の理由に絞る
NEW_SECTION_V2 = NEW_SECTION.replace(
    "checking a short answer or a one-line reason the student gives.",
    "checking a one-line reason the student gives when no calculation or code evaluation is needed.",
).replace(
    "checking the student's own substantial work (their code, their solutions to several problems, an essay, a report, an application);",
    "checking the student's answers to problems that need working (evaluating expressions or code, math), or their own "
    "substantial work (code, an essay, a report, an application);",
).replace(
    "When torn between two levels, choose the lower one.",
    "Any reply that must compute numbers, or check the student's answers to such problems, is `high`. Otherwise, when torn "
    "between two levels, choose the lower one.",
)
# v3 (2026-11-06, ユーザーの基準): high は本当に厄介なものだけ。ラムダの答え合わせ・コードの追跡・簡単な計算は medium。
# v2 の「数値の計算は high」を外し、短い計算・数問の答え合わせ・短いコードの追跡・前の答えへの疑問を medium に移す
NEW_SECTION_V3 = NEW_SECTION.replace(
    "checking a short answer or a one-line reason the student gives.",
    "a short calculation or applying a formula to given numbers (a grade average, a unit conversion, a cast value), "
    "tracing or predicting the output of a short piece of code, checking the student's answers to a few short problems "
    "or a one-line reason they give, the student pushing back on an earlier answer in a way that needs re-checking "
    "(\"hm? wait\", \"isn't it the other way around?\").",
).replace(
    "- `high`: careful step-by-step working, where a quick answer is likely to be wrong: calculations, derivations, proofs, "
    "math beyond a quick fact, unit conversions, or applying a formula to given numbers; tracing, predicting the output of, "
    "or debugging code, an algorithm, or a circuit beyond a few lines; checking the student's own substantial work (their "
    "code, their solutions to several problems, an essay, a report, an application); the student pushing back on an earlier "
    "calculation, code trace, or answer in a way that needs re-checking (\"hm? wait\", \"isn't it the other way around?\"); "
    "continuing a calculation or trace the conversation is in the middle of.",
    "- `high`: rare. Long, careful working where even a careful quick answer is likely to be wrong: proofs and derivations; "
    "long multi-step calculations or simulations that carry values from step to step (stepping an algorithm, a protocol, or "
    "a circuit through many inputs); tracing or debugging long or tricky code; checking the student's own substantial work "
    "(a long proof, a program, an essay, a report, an application); continuing such working the conversation is in the "
    "middle of.",
).replace(
    "When torn between two levels, choose the lower one.",
    "When torn between two levels, choose the lower one: most calculations, code questions, and answer checks are `medium`.",
)
VARIANTS = {"levels_v1": NEW_SECTION, "levels_v2": NEW_SECTION_V2, "levels_v3": NEW_SECTION_V3}


def make_prompt(tag: str = "levels_v1") -> str:
    prod = _load_prompt("chat_router_prompt.txt")
    start = OLD_SECTION_START if OLD_SECTION_START in prod else "### ALSO, HOW MUCH TO THINK IT THROUGH\n"
    a = prod.index(start)
    b = prod.index(OLD_SECTION_END)
    assert a < b and prod.count(start) == 1
    section = VARIANTS[tag]
    assert tag == "levels_v1" or section != NEW_SECTION, "v2 replacements did not apply"
    if tag == "levels_v3":
        assert section.count("`medium`") == 2 and "- `high`: rare." in section and "a cast value" in section, "v3 replacements did not apply"
    return prod[:a] + section + prod[b:]


def make_schema() -> dict:
    s = copy.deepcopy(cs.ROUTER_SCHEMA)
    s["properties"].pop("needs_reasoning", None)
    s["properties"]["reasoning_level"] = {"type": "string", "enum": LEVELS}
    s["required"] = [("reasoning_level" if k == "needs_reasoning" else k) for k in s["required"]]
    # プロンプトの節の並び(FETCH → THINK → LAST)に合わせて、needs_retrieval の後ろに置く
    props = s["properties"]
    order = ["intent", "user_goal", "retrieval_reason", "needs_retrieval", "reasoning_level", "reply_language", "thread_title"]
    s["properties"] = {k: props[k] for k in order}
    return s


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--tag", default="levels_v1")
    ap.add_argument("--cases", default="", help="message id prefixes, comma separated (default: all)")
    args = ap.parse_args()
    wanted = [x for x in args.cases.split(",") if x]
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    system = make_prompt(args.tag)
    schema = make_schema()
    (HERE / "prompts").mkdir(exist_ok=True)
    (HERE / "prompts" / f"router_{args.tag}.txt").write_text(system, encoding="utf-8")
    print(f"model={cs.ROUTER_MODEL} effort={cs.ROUTER_REASONING_EFFORT} system chars={len(system)} "
          f"(production {len(_load_prompt('chat_router_prompt.txt'))})")

    threads: dict[str, dict] = {}
    built = []
    for t_prefix, m_prefix, ok, note in [k for k in CASES if not wanted or k[1] in wanted]:
        if t_prefix not in threads:
            th = next(r for r in c.table("chat_threads").select("id, user_id").execute().data if r["id"].startswith(t_prefix))
            rows = c.table("chat_messages").select("id, role, content, status, created_at, context, router, usage") \
                .eq("thread_id", th["id"]).order("created_at").execute().data
            courses = c.table("courses").select("course_title").eq("user_id", th["user_id"]).is_("deleted_at", "null").execute().data
            threads[t_prefix] = {"id": th["id"], "user_id": th["user_id"], "rows": rows,
                                 "courses_text": "\n".join(f"- {r['course_title']} (term not set)" for r in courses),
                                 "blocked": cs._load_blocked_source_types(th["user_id"])}
        t = threads[t_prefix]
        idx = next(i for i, r in enumerate(t["rows"]) if r["role"] == "user" and r["id"].startswith(m_prefix))
        prod = t["rows"][idx + 1]
        user_input, meta = base.build_input(c, t["rows"], idx, t["user_id"], t["courses_text"], t["blocked"], thread=t["id"])
        prod_nr = (prod.get("router") or {}).get("needs_reasoning")
        prod_out = (prod.get("usage") or {}).get("answer_output_tokens")
        built.append((t_prefix, m_prefix, ok, note, user_input, meta, prod_nr, prod_out))
        print(f"  ok={sorted(ok, key=LEVELS.index)} prod_needs_reasoning={prod_nr} prod_out={prod_out} "
              f"in≈{estimate_tokens(system) + estimate_tokens(user_input):,} | {note}")
    if args.dry_run:
        print("\nDRY RUN OK (no API calls)")
        return

    billing = BillingEngine(task_type="router_reasoning_levels")
    llm = UnifiedLLM(billing)
    options = LLMOptions(output_type="json", json_schema=schema, temperature=0.0, reasoning_effort=cs.ROUTER_REASONING_EFFORT)
    results = []
    for t_prefix, m_prefix, ok, note, user_input, meta, prod_nr, prod_out in built:
        n = len(billing.records)
        t0 = time.perf_counter()
        r = await llm.generate(cs.ROUTER_MODEL, [Message(role="system", content=system), Message(role="user", content=user_input)], options)
        dt = round(time.perf_counter() - t0, 2)
        out = r.output_json or {}
        got = out.get("reasoning_level")
        row = {"thread": t_prefix, "message": m_prefix, "note": note, "acceptable": sorted(ok, key=LEVELS.index),
               "got": got, "pass": got in ok, "production_needs_reasoning": prod_nr, "production_answer_output_tokens": prod_out,
               "latency_s": dt, "tokens": {"in": r.input_tokens, "out": r.output_tokens},
               "cost_usd": round(sum(x.cost_usd for x in billing.records[n:]), 6),
               "intent": out.get("intent"), "needs_retrieval": out.get("needs_retrieval"),
               "reply_language": out.get("reply_language"), "user_goal": out.get("user_goal"), "meta": meta}
        results.append(row)
        print(f"{'OK' if row['pass'] else 'NG'} got={got:<6} ok={row['acceptable']} prod={prod_nr} "
              f"ret={out.get('needs_retrieval')} {dt}s ${row['cost_usd']:.5f} | {note}")
    total = billing.total_usd()
    passed = sum(r["pass"] for r in results)
    dist = {lv: sum(r["got"] == lv for r in results) for lv in LEVELS}
    print(f"\nPASS {passed}/{len(results)}  levels={dist}  TOTAL ${total:.5f}")
    out_path = HERE / "results" / f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{args.tag}.json"
    out_path.parent.mkdir(exist_ok=True)
    out_path.write_text(json.dumps({"model": cs.ROUTER_MODEL, "prompt": f"router_{args.tag}", "pass": passed,
                                    "total": len(results), "levels": dist, "cases": wanted or "all", "total_cost_usd": total, "rows": results},
                                   ensure_ascii=False, indent=2), encoding="utf-8")
    print("saved", out_path)


if __name__ == "__main__":
    asyncio.run(main())
