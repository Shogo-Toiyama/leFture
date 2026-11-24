"""
Gemini 4 Hydrogen 差し替え実験 (Review Cards / Deep Notes / Fun Fact / チャット回答役)

目的: 今 Haiku 5.5 を使っている4機能を gemini/gemini-4-hydrogen に差し替えたとき、
      コスト・速度・出力の質(形式・口調)がどうなるかを、全体予算 $0.50 以内で確認する。

本番との差分(それ以外は本番の Service クラス・プロンプト・入力データをそのまま使う):
  1. model:            anthropic/claude-haiku-5-5 -> gemini/gemini-4-hydrogen
  2. reasoning_effort: low のまま(Hydrogen は low が最小。litellm がどう変換するかは dryrun で確認)
  3. max_tokens:       実験用に絞る(CAPS)。本番は 32000。最悪ケースのコストを抑えるため
  4. cache_control:    メッセージから外す(Hydrogen は明示キャッシュ非対応。暗黙キャッシュのみ)
  + PRICE_MATRIX に Hydrogen の単価をこのプロセス内でだけ追加する(本番ファイルは変更しない)

安全策:
  - R2 の pipeline_cache は読み書きとも無効(base._disable_r2_cache)。Supabase/R2 への書き込みは無し。
  - 予算ガード: 呼び出しの直前に count_tokens(無料)で入力トークンを数え、
    「入力 + max_tokens 分の出力」を最悪ケースとして累計に足したとき BUDGET_CAP を超えるなら呼ばない。
  - 累計は results/ledger.json に残り、ラウンドをまたいで効く。

使い方:
  .venv/bin/python contents_generation/test_codes/gemini4_hydrogen_swap/swap_experiment.py prepare
  .venv/bin/python contents_generation/test_codes/gemini4_hydrogen_swap/swap_experiment.py dryrun
  .venv/bin/python contents_generation/test_codes/gemini4_hydrogen_swap/swap_experiment.py run --round 1 --confirm
"""

import argparse
import asyncio
import dataclasses
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent / "haiku_migration_tone"))
sys.path.insert(0, str(HERE.parent / "reply_ending_eval"))
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

import run_experiment as base  # noqa: E402  (haiku_migration_tone の仕組みを流用)
import replay as chat_replay  # noqa: E402  (reply_ending_eval: 本番の回答役メッセージ組み立て)
from app.services import chat_service as cs  # noqa: E402
from app.services.helpers import llm_unified as LU  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState  # noqa: E402

MODEL = "gemini/gemini-4-hydrogen"
API_MODEL = "gemini-4-hydrogen"
EFFORT = "low"
PRICE = {"input": 1.50, "output": 7.50, "cache_read": 0.075}  # 公式 2026-11-23 確認(標準・有料枠)
LU.PRICE_MATRIX["tokens"][MODEL] = dict(PRICE)

BUDGET_CAP = 0.45      # 全体予算 $0.50 のうち、ここを超える呼び出しは拒否する(残り $0.05 は丸め・誤差用)
CAPS = {"review_cards": 6000, "deep_notes": 8000, "fun_facts": 4000, "chat": 6144}  # chat: 本番は effort low でも 18432
# 期待出力トークン(思考込み)。Haiku での前回実測(RC 約2.5k)・本番記録(チャット)を仮置きしたもの。
# Hydrogen の実際の値ではない(未知)。最悪ケースは CAPS で別に計算する。
ASSUMED_OUT = {"review_cards": 2500, "deep_notes": 4000, "fun_facts": 1500, "chat": 1136}

LECTURES = {
    "review_cards": ("a028aad6-07ba-4e3f-ac39-7494e9d7f062", "2"),
    "deep_notes": ("666b2c9d-a997-451b-9318-98f98c9d29fa", "4"),
    "fun_facts": ("ed333ded-2e09-464a-8224-11b7517fb709", "ff"),
}
CHAT_CASE = {"id": "N_221bde86", "msg": "221bde86", "expect": "normal turn"}

INPUTS_DIR = HERE / "inputs"
RESULTS_DIR = HERE / "results"
LEDGER = RESULTS_DIR / "ledger.json"
base.INPUTS_DIR = INPUTS_DIR


# ---------------------------------------------------------------------------
# 予算台帳 / 入力トークンの数え方(count_tokens は無料)
# ---------------------------------------------------------------------------
def ledger_total() -> float:
    if not LEDGER.exists():
        return 0.0
    return round(sum(e["cost_usd"] for e in json.loads(LEDGER.read_text())), 6)


def ledger_add(label: str, cost: float) -> None:
    rows = json.loads(LEDGER.read_text()) if LEDGER.exists() else []
    rows.append({"at": datetime.now().isoformat(timespec="seconds"), "label": label, "cost_usd": round(cost, 6)})
    RESULTS_DIR.mkdir(exist_ok=True)
    LEDGER.write_text(json.dumps(rows, indent=1))


_client = None


def genai_client():
    global _client
    if _client is None:
        from google import genai
        _client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    return _client


def _msg_text(m) -> str:
    return m.content if isinstance(m.content, str) else json.dumps(m.content, ensure_ascii=False)


def count_input_tokens(messages) -> int:
    text = "\n\n".join(f"[{m.role}]\n{_msg_text(m)}" for m in messages)
    return genai_client().models.count_tokens(model=API_MODEL, contents=text).total_tokens


def worst_case_usd(in_tokens: int, max_out: int) -> float:
    return in_tokens * PRICE["input"] / 1e6 + max_out * PRICE["output"] / 1e6


class BudgetExceeded(RuntimeError):
    pass


def strip_cache_control(messages):
    return [dataclasses.replace(m, cache_control=None) if getattr(m, "cache_control", None) else m for m in messages]


def install_guard(label_prefix: str) -> None:
    """UnifiedLLM.generate / generate_stream に、cache_control 除去と予算ガードと台帳記録を差し込む。"""
    orig_gen, orig_stream = LU.UnifiedLLM.generate, LU.UnifiedLLM.generate_stream

    def preflight(messages, options):
        in_tokens = count_input_tokens(messages)
        worst = worst_case_usd(in_tokens, options.max_tokens or 0)
        if ledger_total() + worst > BUDGET_CAP:
            raise BudgetExceeded(f"ledger ${ledger_total():.4f} + worst ${worst:.4f} > cap ${BUDGET_CAP}")
        return in_tokens, worst

    async def gen(self, model, messages, options=None):
        messages = strip_cache_control(messages)
        in_tokens, worst = preflight(messages, options)
        before = self.billing.total_usd()
        try:
            return await orig_gen(self, model, messages, options)
        finally:
            ledger_add(f"{label_prefix}:generate in~{in_tokens} worst${worst:.4f}", self.billing.total_usd() - before)

    async def stream(self, model, messages, state, options=None, *a, **kw):
        messages = strip_cache_control(messages)
        in_tokens, worst = preflight(messages, options)
        before = self.billing.total_usd()
        try:
            async for x in orig_stream(self, model, messages, state, options, *a, **kw):
                yield x
        finally:
            ledger_add(f"{label_prefix}:stream in~{in_tokens} worst${worst:.4f}", self.billing.total_usd() - before)

    LU.UnifiedLLM.generate = gen  # type: ignore[assignment]
    LU.UnifiedLLM.generate_stream = stream  # type: ignore[assignment]


# ---------------------------------------------------------------------------
# 各ケースの組み立て
# ---------------------------------------------------------------------------
def configure_base(task: str) -> None:
    base.MODEL = MODEL
    base.REASONING_EFFORT = EFFORT
    base.MAX_TOKENS = CAPS[task]


async def run_batch_task(task: str, dry: bool) -> Dict[str, Any]:
    lid, topic = LECTURES[task]
    inp = json.loads((INPUTS_DIR / f"{lid}.json").read_text(encoding="utf-8"))
    configure_base(task)
    base._disable_r2_cache()
    base._install_prompt_loader("v0")  # v0 = 本番プロンプトそのもの
    only = {topic}
    res = await base.run_one(task, inp, dry, {}, only)
    res["checks"] = base.check(res)
    return res


async def build_chat(dry: bool):
    from supabase import create_client
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    chat_replay.VARIANT_PROMPTS.clear()  # 本番のプロンプト
    b = await chat_replay.build_case(c, CHAT_CASE)
    return b


# ---------------------------------------------------------------------------
# dryrun: API 生成呼び出しは一切しない。count_tokens / models.get(無料)だけ
# ---------------------------------------------------------------------------
async def dryrun() -> None:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out: Dict[str, Any] = {"created_at": ts, "model": MODEL, "effort": EFFORT, "caps": CAPS,
                           "budget_cap_usd": BUDGET_CAP, "ledger_spent_usd": ledger_total(), "checks": {}, "cases": []}

    # 1) キー / model id の確認 (models.get は無料)
    info = genai_client().models.get(model=API_MODEL)
    out["checks"]["models_get"] = {"name": info.name, "input_token_limit": info.input_token_limit,
                                   "output_token_limit": info.output_token_limit,
                                   "thinking": getattr(info, "thinking", None)}
    print("models.get:", out["checks"]["models_get"])

    # 2) litellm が reasoning_effort=low / max_tokens をどう Gemini に渡すか (オフライン)
    import litellm
    try:
        opt = litellm.utils.get_optional_params(
            model=API_MODEL, custom_llm_provider="gemini", reasoning_effort=EFFORT, max_tokens=1000)
        out["checks"]["litellm_optional_params"] = opt
    except Exception as e:  # noqa: BLE001
        out["checks"]["litellm_optional_params"] = f"ERROR {type(e).__name__}: {e}"
    print("litellm optional params:", out["checks"]["litellm_optional_params"])

    # 3) 本番のコードでメッセージを組み立て(API 生成なし)、count_tokens で入力を正確に数える
    for task in ("review_cards", "deep_notes", "fun_facts"):
        res = await run_batch_task(task, dry=True)
        call = next((x for x in res["calls"] if x.get("messages")), None)
        if call is None or res["error"]:
            out["cases"].append({"task": task, "error": res["error"] or "no call recorded"})
            print(f"❌ {task}: {res['error'] or 'no call recorded'}")
            continue
        msgs = [LU.Message(role=m["role"], content=m["content"]) for m in call["messages"]]
        n_in = count_input_tokens(msgs)
        out["cases"].append({
            "task": task, "lecture": LECTURES[task][0][:8], "topic": LECTURES[task][1],
            "input_tokens_exact": n_in, "max_tokens": CAPS[task], "calls_planned": len(res["calls"]),
            "request_kwargs": call["request_kwargs"],
            "assumed_out_tokens": ASSUMED_OUT[task],
            "expected_usd": round(n_in * PRICE["input"] / 1e6 + ASSUMED_OUT[task] * PRICE["output"] / 1e6, 4),
            "worst_case_usd": round(worst_case_usd(n_in, CAPS[task]), 4),
        })

    b = await build_chat(True)
    msgs = b["messages_prod_prompt"]
    n_in = count_input_tokens(msgs)
    opts = dataclasses.replace(cs.answer_options(MODEL, b["effort"], cs._answer_max_tokens(None, [])), max_tokens=CAPS["chat"])
    out["cases"].append({
        "task": "chat", "message": CHAT_CASE["msg"], "input_tokens_exact": n_in,
        "est_tokens_by_prod_estimator": chat_replay.est(msgs), "prod_recorded_input_tokens": b["info"]["prod_input_tokens"],
        "max_tokens": opts.max_tokens, "effort": b["effort"], "needs_reasoning": b["info"]["needs_reasoning"],
        "assumed_out_tokens": ASSUMED_OUT["chat"],
        "expected_usd": round(n_in * PRICE["input"] / 1e6 + ASSUMED_OUT["chat"] * PRICE["output"] / 1e6, 4),
        "worst_case_usd": round(worst_case_usd(n_in, opts.max_tokens), 4),
    })

    ok = [c for c in out["cases"] if "worst_case_usd" in c]
    out["round1_expected_usd"] = round(sum(c["expected_usd"] for c in ok), 4)
    out["round1_worst_case_usd"] = round(sum(c["worst_case_usd"] for c in ok), 4)
    out["remaining_after_worst_round1_usd"] = round(0.50 - out["ledger_spent_usd"] - out["round1_worst_case_usd"], 4)

    d = RESULTS_DIR / f"{ts}_dryrun"
    d.mkdir(parents=True, exist_ok=True)
    (d / "summary.json").write_text(json.dumps(out, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(f"\n{'task':14}{'in_tok':>9}{'max_out':>9}{'expected$':>11}{'worst$':>9}")
    for c in out["cases"]:
        if "worst_case_usd" in c:
            print(f"{c['task']:14}{c['input_tokens_exact']:>9}{c['max_tokens']:>9}{c['expected_usd']:>11}{c['worst_case_usd']:>9}")
        else:
            print(f"{c['task']:14} ERROR {c['error']}")
    print(f"\nround 1 expected ${out['round1_expected_usd']}  worst-case ${out['round1_worst_case_usd']}  "
          f"(ledger spent ${out['ledger_spent_usd']}, cap ${BUDGET_CAP}, total budget $0.50)")
    print(f"saved: {d}")


# ---------------------------------------------------------------------------
# run: 第1ラウンド(各機能1回)。--confirm が無ければ実行しない
# ---------------------------------------------------------------------------
async def run_round(round_no: int, only: Optional[List[str]]) -> None:
    install_guard(f"round{round_no}")
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    d = RESULTS_DIR / f"{ts}_run_round{round_no}"
    d.mkdir(parents=True, exist_ok=True)
    tasks = only or ["review_cards", "deep_notes", "fun_facts", "chat"]
    results: List[Dict[str, Any]] = []
    for task in tasks:
        if task == "chat":
            b = await build_chat(False)
            billing = BillingEngine(task_type="gemini4_swap_chat")
            llm = LU.UnifiedLLM(billing)
            chat_replay.FrozenDatetime.frozen = b["when"]
            cs.datetime = chat_replay.FrozenDatetime
            state = StreamState()
            opts = dataclasses.replace(cs.answer_options(MODEL, b["effort"], cs._answer_max_tokens(None, [])), max_tokens=CAPS["chat"])
            t0, first, err = time.perf_counter(), None, None
            try:
                async for _ in llm.generate_stream(MODEL, b["messages_prod_prompt"], state, opts):
                    if first is None:
                        first = time.perf_counter() - t0
            except Exception as e:  # noqa: BLE001
                err = f"{type(e).__name__}: {e}"
            finally:
                cs.datetime = datetime
            results.append({
                "task": "chat", "error": err, "ttft_s": round(first or 0, 2),
                "total_s": round(time.perf_counter() - t0, 2), "input_tokens": state.input_tokens,
                "output_tokens": state.output_tokens, "cost_usd": round(billing.total_usd(), 6),
                "user_message": b["u_row"]["content"], "answer": state.output_text,
                "production_answer": b["a_row"]["content"],
                "production_tokens": {"in": b["info"]["prod_input_tokens"],
                                      "out": (b["a_row"].get("usage") or {}).get("answer_output_tokens")},
            })
        else:
            r = await run_batch_task(task, dry=False)
            results.append(r)
        r = results[-1]
        print(f"[{task}] error={r.get('error')} cost=${r.get('cost_usd', r.get('token_cost_usd'))} "
              f"ledger=${ledger_total():.4f}")
    (d / "raw.json").write_text(json.dumps(results, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(f"saved: {d}\nledger total: ${ledger_total():.4f} / cap ${BUDGET_CAP}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["prepare", "dryrun", "run"])
    ap.add_argument("--round", type=int, default=1)
    ap.add_argument("--only", nargs="*", choices=["review_cards", "deep_notes", "fun_facts", "chat"])
    ap.add_argument("--confirm", action="store_true", help="run: 実際に API を呼ぶ(課金される)")
    a = ap.parse_args()
    if a.mode == "prepare":
        base.prepare([lid for lid, _ in LECTURES.values()])
    elif a.mode == "dryrun":
        asyncio.run(dryrun())
    else:
        if not a.confirm:
            sys.exit("run には --confirm が必要です(課金されます)。まず dryrun の結果を確認してください。")
        asyncio.run(run_round(a.round, a.only))


if __name__ == "__main__":
    main()
