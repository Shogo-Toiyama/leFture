"""
回答役プロンプトの整理(2026-11-07)の確認。重複の統合・最後のリマインダーの差し替えで、崩れていないか。
変更(prompts/):
  - system: テーマごとに1か所へ(トーン1回、READING WHAT THEY MEAN、WHEN SOMETHING IS MISSING OR UNCERTAIN、
    BEHIND THE SCENES にラベル・呼び方・裏の仕組み)。長さのルールに宿題の例外。最新メッセージの構造を全タグに更新。
  - turn: トーンの繰り返し・出典の重複行・user_goal と links の説明を外し、how_to_write_this_reply を
    本番で失敗してきたルール4つのリマインダーに。

Cases(各1回):
  labels_c4l11:  本番で C/L/T を10個漏らした返信(52eadf89)。参照資料は本番の探索の open を再実行して組み直す
  clock_medium:  宿題(931543fd / fc388cec)。effort medium。homework_help_policy v1(本番の今のプロンプト)と比べる
  feelings_14:   「14点でどうしよう、カーブある？」(4b0ff0b6 / 9b7b7b42)。トーン
effort は本番の記録どおり(clock だけ medium)。Baseline = 本番の返信。

  .venv/bin/python contents_generation/test_codes/answer_prompt_cleanup/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/answer_prompt_cleanup/replay.py
"""
import argparse, asyncio, importlib.util, json, re, time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("label_replay", HERE.parent / "internal_label_eval" / "replay.py")
lr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lr)
base = lr.base
cs = base.cs

MARK_SYS = "### BEHIND THE SCENES"
MARK_TURN = "On work they'll hand in, go all the way through with the why"
CASES = [
    {"id": "labels_c4l11", "msg": "52eadf89", "rebuild_materials": True},
    {"id": "clock_medium", "msg": "-", "thread": "931543fd", "user": "fc388cec", "effort": "medium"},
    {"id": "feelings_14", "msg": "-", "thread": "4b0ff0b6", "user": "9b7b7b42"},
]
CLOCK = ["0.5", "1.5", "2.58", "3.66", "4.74", "5.82", "6.9", "7.98", "9.06", "10.14"]
ENDING = r"(どう？|どうかな|わかった？|やってみ|考えてみ|次は.{0,20}(しよう|見て|いこう)|一緒に.{0,15}(しよう|いこう|みよう)[！!？?]?\s*$)"


class BothPrompts(set):
    def add(self, name):
        super().add(name)
        if name == "chat_answer_prompt.txt":
            super().add("chat_answer_turn_prompt.txt")


def find_after(c, case):
    th = next(r for r in c.table("chat_threads").select("id").execute().data if r["id"].startswith(case["thread"]))
    rows = c.table("chat_messages").select("id, thread_id, role, content, status, created_at, router, usage") \
        .eq("thread_id", th["id"]).order("created_at").execute().data
    i = next(i for i, r in enumerate(rows) if r["role"] == "user" and r["id"].startswith(case["user"]))
    return rows[i + 1]


async def build(c, case):
    base.VARIANT_PROMPTS = BothPrompts()
    if case.get("rebuild_materials"):
        lr.HERE = HERE
        return await lr.build_case(c, case)
    base.HERE = HERE
    base.VARIANT_PROMPTS.add("chat_answer_prompt.txt")
    orig = base.find_message
    base.find_message = lambda c_, prefix: find_after(c_, case)
    try:
        b = await base.build_case(c, case)
    finally:
        base.find_message = orig
    b["materials"] = []
    return b


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--cases", default="")
    ap.add_argument("--tag", default="v1")
    args = ap.parse_args()
    base.render_mentions = lr.base_mentions.answer_mentions  # 本番の回答役の履歴と同じ資料の印
    c = lr.create_client(lr.os.environ["SUPABASE_URL"], lr.os.environ["SUPABASE_SECRET_KEY"])
    billing = lr.BillingEngine(task_type="answer_prompt_cleanup")
    llm = lr.UnifiedLLM(billing)
    wanted = [x for x in args.cases.split(",") if x]
    results = []
    for case in [k for k in CASES if not wanted or k["id"] in wanted]:
        b = await build(c, case)
        v, p = b["messages_variant"], b["messages_prod_prompt"]
        assert MARK_SYS in v[0].content and MARK_SYS not in p[0].content, "variant system prompt not applied"
        assert MARK_TURN in v[-1].content and MARK_TURN not in p[-1].content, "variant turn prompt not applied"
        effort = case.get("effort") or b["effort"]
        print(f"\n## {case['id']}  user: {b['u_row']['content'][:60]!r}")
        print(f"  effort={effort} materials={[m.label for m in b.get('materials') or []]}")
        print(f"  est tokens variant={base.est(v):,} production prompt={base.est(p):,}")
        if args.dry_run:
            continue
        b["effort"] = effort
        r = await lr.run_once(llm, billing, b, case)
        text = r["new_answer"]
        r["effort"] = effort
        r["ending_tail_new"] = text.strip()[-160:]
        r["ending_flag_new"] = bool(re.search(ENDING, text.strip()[-120:]))
        r["opens_with_student_words"] = b["u_row"]["content"].strip()[:6] in text[:40]
        if case["id"] == "clock_medium":
            nums = {n.rstrip("0").rstrip(".") if "." in n else n for n in re.findall(r"\d+(?:\.\d+)?", text)}
            r["clock_samples_found"] = sum(s in nums for s in CLOCK)
            print(f"  clock samples {r['clock_samples_found']}/10")
        print(f"  ending flag={r['ending_flag_new']}  tail={r['ending_tail_new'][-80:]!r}")
        results.append(r)
    if args.dry_run:
        print("\nDRY RUN OK (no API calls)")
        return
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / f"{ts}_{args.tag}.json").write_text(
        json.dumps({"total_cost_usd": billing.total_usd(), "results": results}, ensure_ascii=False, indent=2, default=str),
        encoding="utf-8")
    md = [f"# Answer prompt cleanup {args.tag} (baseline = production)", ""]
    for r in results:
        md += [f"## {r['case']} ({r['message_id']}, effort {r['effort']})", "", f"**Student:** {r['user_message']}", "",
               f"**Labels new:** {json.dumps(r['labels_new'], ensure_ascii=False)}  production: {json.dumps(r['labels_production'], ensure_ascii=False)}  ",
               f"**Cost:** ${r['cost_usd']:.4f}, TTFT {r['ttft_s']}s, total {r['total_s']}s, in {r['input_tokens']:,}, out {r['output_tokens']:,}", "",
               "### New prompt", "", r["new_answer"], "", "### Production (baseline)", "", r["production_answer"], "", "---", ""]
    (HERE / "results" / f"{ts}_{args.tag}_answers.md").write_text("\n".join(md), encoding="utf-8")
    print(f"\nTOTAL ${billing.total_usd():.4f}")


if __name__ == "__main__":
    asyncio.run(main())
