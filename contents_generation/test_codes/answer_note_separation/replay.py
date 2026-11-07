"""
回答役が「裏の検索メモ」(<retrieval_reasoning>・<user_goal>)にだけ出てくる話に返事をしてしまう問題の、プロンプト修正の評価。

背景(2026-11-06, スレッド3f8d3695 の 13100d37): 生徒はネットワークの話を一度もしていないのに、
「ネットワークの講義はA1に出てこないので、今回は外して大丈夫です」と書いた。探索役は C5(ネットワーク)の目次も開いていて、
最後の考え(retrieval_reasoning)にも C5 を外したことが書いてあった。
修正(prompts/ のコピー):
  - chat_answer_prompt.txt に「WHAT THE STUDENT ASKED VS. OUR BEHIND-THE-SCENES NOTES」の節を追加
  - HOW THE LATEST MESSAGE IS STRUCTURED に <user_goal>・<retrieval_reasoning> を「裏のメモ」として追記
  - chat_answer_turn_prompt.txt の </retrieval_reasoning> の直後に一行

再生は internal_label_eval/replay.py の build_case / run_once をそのまま使う(本番の関数で参照資料・回答役の入力を組み直す)。
Baseline = Supabase にある本番の回答。新プロンプトだけで回答役を再生する。

  .venv/bin/python contents_generation/test_codes/answer_note_separation/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/answer_note_separation/replay.py
"""

import argparse
import asyncio
import importlib.util
import json
import re
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("label_replay", HERE.parent / "internal_label_eval" / "replay.py")
lr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lr)
base = lr.base

SECTION = "### WHAT THE STUDENT ASKED VS. OUR BEHIND-THE-SCENES NOTES"
TURN_LINE = "is the search helper's own working notes"

CASES = [
    # 「ネットワークの講義はA1に出てこないので、今回は外して大丈夫です」
    {"id": "network_aside", "msg": "13100d37"},
    # 回帰確認: 参照資料ありで、ラベル以外は普通に答えていたケース
    {"id": "C4L11_T_table", "msg": "52eadf89"},
]

# 生徒が言っていない「外した資料」への言及を探す(このケース用)
ASIDE_PATTERN = r"ネットワーク|network|外して|外しています|関係ない|対象外"


class BothPrompts(set):
    """internal_label_eval の build_case は回答役の system プロンプトだけを差し替えるので、turn プロンプトも一緒に差し替える"""

    def add(self, name):
        super().add(name)
        if name == "chat_answer_prompt.txt":
            super().add("chat_answer_turn_prompt.txt")


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--cases", default="")
    ap.add_argument("--tag", default="v1")
    args = ap.parse_args()
    lr.HERE = HERE  # build_case が base.HERE = HERE として、ここの prompts/ を読む
    base.VARIANT_PROMPTS = BothPrompts()
    # 本番の回答役の履歴(build_answer_history)と同じ資料の印にする
    base.render_mentions = lr.base_mentions.answer_mentions

    wanted = [x for x in args.cases.split(",") if x]
    c = lr.create_client(lr.os.environ["SUPABASE_URL"], lr.os.environ["SUPABASE_SECRET_KEY"])
    billing = lr.BillingEngine(task_type="answer_note_separation")
    llm = lr.UnifiedLLM(billing)
    results = []
    for case in [k for k in CASES if not wanted or k["id"] in wanted]:
        b = await lr.build_case(c, case)
        sys_v, sys_p = b["messages_variant"][0].content, b["messages_prod_prompt"][0].content
        turn_v, turn_p = b["messages_variant"][-1].content, b["messages_prod_prompt"][-1].content
        assert SECTION in sys_v and SECTION not in sys_p, "variant system prompt not applied"
        has_reasoning = "<retrieval_reasoning>" in turn_v
        if has_reasoning:
            assert TURN_LINE in turn_v and TURN_LINE not in turn_p, "variant turn prompt not applied"
        reasoning = turn_v.split("<retrieval_reasoning>")[1].split("</retrieval_reasoning>")[0].strip() if has_reasoning else ""
        print(f"\n## {case['id']}  user: {b['u_row']['content'][:70]!r}")
        print(f"  {json.dumps(b['info'], ensure_ascii=False, default=str)}")
        print(f"  materials: {[m.label for m in b['materials']]}")
        print(f"  retrieval_reasoning ({len(reasoning)} chars): {reasoning[:300]!r}")
        print(f"  est tokens variant={base.est(b['messages_variant']):,} production prompt={base.est(b['messages_prod_prompt']):,}")
        print(f"  production reply asides: {re.findall(ASIDE_PATTERN, b['a_row']['content'], re.I)}")
        if args.dry_run:
            continue
        r = await lr.run_once(llm, billing, b, case)
        r["asides_new"] = re.findall(ASIDE_PATTERN, r["new_answer"], re.I)
        r["asides_production"] = re.findall(ASIDE_PATTERN, r["production_answer"], re.I)
        print(f"  asides  production: {r['asides_production']}  new: {r['asides_new']}")
        results.append(r)
    if args.dry_run:
        print("\nDRY RUN OK (no API calls)")
        return
    print(f"\nTOTAL COST ${billing.total_usd():.4f}")
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    (HERE / "results" / f"{ts}_{args.tag}.json").write_text(
        json.dumps({"total_cost_usd": billing.total_usd(), "results": results}, ensure_ascii=False, indent=2, default=str),
        encoding="utf-8")
    md = ["# Behind-the-scenes notes replay (baseline = production)", ""]
    for r in results:
        md += [f"## {r['case']} ({r['message_id']})", "", f"**Student:** {r['user_message']}", "",
               f"**Asides (production → new):** {r['asides_production']} → {r['asides_new']}  ",
               f"**Labels (new):** {json.dumps(r['labels_new'], ensure_ascii=False)}  ",
               f"**Cost:** ${r['cost_usd']:.4f}, TTFT {r['ttft_s']}s, total {r['total_s']}s", "",
               "### New prompt", "", r["new_answer"], "", "### Production (baseline)", "", r["production_answer"], "", "---", ""]
    (HERE / "results" / f"{ts}_{args.tag}_answers.md").write_text("\n".join(md), encoding="utf-8")


if __name__ == "__main__":
    asyncio.run(main())
