"""
出典の根拠箇所: 「出典を区切って番号を振り、回答役に番号で指させる」方式の実験。

回答役に渡す出典の本文に ‹3.5› のような区切りの番号を入れ、本文では [3] ではなく
[3.5] / [3.5-7](連続する範囲) で引用させる。指された区切りがそのまま根拠の箇所になる
(後から原文を探さない)。区切り方を2通り比べる:
  sentence: 全部の出典を文で区切る
  natural : 出典の種類ごとの自然な単位(Deep Note・復習カード等はMarkdownのブロック/キーワード1項目、
            300字を超えるブロックだけ文に。トランスクリプト・要約・Webは文)

同じ回答の上で方式A2(埋め込みで一番近い文+近ければ隣の文。run_eval.py)も動かして並べる。
採点は run_eval.py と同じ(gemini-2.5-flash、方式は伏せる)。

測るもの:
  書式  : 引用の印のうち区切りの番号で書けた割合 / 番号だけの[3](書式違反) / 存在しない区切り
  正しさ: 指した区切りが「その文を支えているか」(supports / partly / no)
  根拠  : 出典の中にそもそも根拠がある主張の割合(前回の作り直しでは約8割)
  量    : 回答の長さ・出力トークン・入力トークン

実行: python run_unit_eval.py --limit 5 [--variant sentence natural] [--resume]
"""

import argparse
import asyncio
import json
import random
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

TEST_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TEST_DIR))

import run_eval as base  # noqa: E402  (backendへのパス・.envの読み込みもここで済む)
from app.core.supabase import get_supabase_client  # noqa: E402
from app.services import chat_service as cs  # noqa: E402
from app.services.chat_materials import Material, numbered  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, StreamState, UnifiedLLM  # noqa: E402
from app.services.knowledge_index import KNOWLEDGE_EMBEDDING_MODEL  # noqa: E402
from build_cases import OWN_USER_ID  # noqa: E402
from grounding import cited_claims, normalize, split_sentences  # noqa: E402

PROMPTS_DIR = base.REPO_ROOT / "lefture_backend/app/services/prompts"
RESULTS_DIR = TEST_DIR / "results"
BLOCK_MAX_CHARS = 300
MIN_UNIT_CHARS = 12

# =========================================================
# 区切り
# =========================================================


@dataclass
class Unit:
    start: int
    end: int


# 段落(空行) / 見出し・箇条書き・「Keywords:」「Deep Note:」で始まる行 / キーワードの項目の境目「; 名前: 」
_BLOCK_SEP_RE = re.compile(r"\n\s*\n|\n(?=\s*(?:#|[-*+] |\d+\. |>|Keywords:|Deep Note:))|; (?=[^;\n]{1,60}: )")


def _trim(text: str, a: int, b: int) -> tuple[int, int]:
    while a < b and text[a] in " \t\n;":
        a += 1
    while b > a and text[b - 1] in " \t\n":
        b -= 1
    return a, b


def sentence_units(text: str) -> list[Unit]:
    return [Unit(s.start, s.end) for s in split_sentences(text)]


# わざと一番雑に割る(略語・小数点・ファクトリアル等への対策を一切しない。「。！？!?.\n」の
# 単発でも切る)。範囲指定([2.5-7])で回答役がちゃんと繋ぎ直せるかを試すための対照群。
_NAIVE_RE = re.compile(r"[。！？!?.]|\n+")


def naive_units(text: str) -> list[Unit]:
    units, pos = [], 0
    for m in _NAIVE_RE.finditer(text):
        a, b = _trim(text, pos, m.end())
        if b > a:
            units.append(Unit(a, b))
        pos = m.end()
    a, b = _trim(text, pos, len(text))
    if b > a:
        units.append(Unit(a, b))
    return units


def natural_units(text: str, source_type: str) -> list[Unit]:
    if source_type in ("transcript_topic", "lecture_summary", "web", "chat_turn", "course") or not source_type:
        return sentence_units(text)
    spans, pos = [], 0
    for m in _BLOCK_SEP_RE.finditer(text):
        spans.append((pos, m.start()))
        pos = m.end()
    spans.append((pos, len(text)))
    units: list[Unit] = []
    carry = None
    for a, b in spans:
        a, b = _trim(text, a, b)
        if b <= a:
            continue
        if carry is not None:
            a = carry
            carry = None
        # 見出しだけの行のような短いブロックは、次のブロックにつなげる
        if len(normalize(text[a:b])) < MIN_UNIT_CHARS:
            carry = a
            continue
        if b - a > BLOCK_MAX_CHARS:
            units += [Unit(a + s.start, a + s.end) for s in split_sentences(text[a:b])]
        else:
            units.append(Unit(a, b))
    if carry is not None:
        if units:
            units[-1].end = max(units[-1].end, len(text.rstrip()))
        else:
            units.append(Unit(*_trim(text, carry, len(text))))
    return units


def mark_content(text: str, units: list[Unit], ref: str) -> str:
    """各区切りの先頭に ‹ref.k› を入れた本文。"""
    out, pos = [], 0
    for k, u in enumerate(units, 1):
        out.append(text[pos:u.start])
        out.append(f"‹{ref}.{k}› ")
        pos = u.start
    out.append(text[pos:])
    return "".join(out)


# =========================================================
# プロンプト(引用の書き方だけ差し替える)
# =========================================================

_OLD_PLACEMENT = "- Put the number right after the sentence it supports: [2], or [W1] for a web page. Several in one sentence are each in their own brackets, like [1][W2] — never [1, W2]."
_NEW_PLACEMENT = ("- Each source's text is split into numbered units marked ‹2.5› (source 2, unit 5). Cite the exact unit that supports "
                  "your sentence, right after it: [2.5], or [W1.3] for a web page. For a run of consecutive units use a range, "
                  "like [2.5-7]. Several in one sentence are each in their own brackets, like [2.5][W1.3] — never [2.5, W1.3]. "
                  "Never write a bare source number like [2], and never cite a unit that does not exist.")
_OLD_TURN = 'Write "…a new record.[W1]", not "…a new record.[W1][W3]".'
_NEW_TURN = 'Write "…a new record.[W1.2]", not "…a new record.[W1.2][W3.1]". Cite the unit, never a bare source number.'


def unit_prompts() -> dict[str, str]:
    answer = (PROMPTS_DIR / "chat_answer_prompt.txt").read_text()
    turn = (PROMPTS_DIR / "chat_answer_turn_prompt.txt").read_text()
    # 2026-10-03に本番のプロンプト自体が区切りの引用(⟦2.5⟧)になった。それ以降は本番のものをそのまま使う
    if "‹2.5›" in answer:
        return {}
    assert _OLD_PLACEMENT in answer and _OLD_TURN in turn
    return {
        "chat_answer_prompt.txt": answer.replace(_OLD_PLACEMENT, _NEW_PLACEMENT),
        "chat_answer_turn_prompt.txt": turn.replace(_OLD_TURN, _NEW_TURN),
    }


# =========================================================
# 回答の引用の読み取り
# =========================================================

_CODE_RE = re.compile(r"(```[\s\S]*?(?:```|$)|`[^`\n]*`)")
_BRACKET_RE = re.compile(r"(?<![A-Za-z0-9_])\[([^\[\]\n]{1,40})\](?!\()")
_ITEM_RE = re.compile(r"^\s*(W?\d{1,2})(?:\s*\.\s*(\d{1,3})(?:\s*[-–]\s*(?:W?\d{1,2}\.)?(\d{1,3}))?)?\s*$")


def parse_citations(answer: str, units_by_ref: dict[str, list[Unit]]) -> tuple[str, list[dict]]:
    """
    本文の引用を読み、(1) 区切りの番号を外して [3] だけにした本文(主張の取り出し用)と
    (2) 印1つずつの記録(出現順)を返す。[2.5, 3.1] のようなまとめ書きも1つずつに分ける。
    """
    marks: list[dict] = []
    # 本番の形 ⟦3.5⟧ も、実験時の形 [3.5] と同じに読む
    # (⟦ は語の直後にも付くので、添字 a[1] と見なされないよう前に空白を入れる)
    answer = answer.replace("⟦", " [").replace("⟧", "]")

    def repl(m: "re.Match[str]") -> str:
        items = [x for x in re.split(r"[,、，]", m.group(1))]
        parsed = [_ITEM_RE.match(x) for x in items]
        if not all(parsed):
            return m.group(0)  # 引用ではない角括弧
        # 区切りの番号もWも無い数字だけのまとまり([0, 1]のような区間)は、全部が実在する出典のときだけ引用とみなす
        # (本番の normalize_citations と同じ規則)
        if len(parsed) > 1 and not any(pm.group(2) or pm.group(1).startswith("W") for pm in parsed) \
                and not all(pm.group(1) in units_by_ref for pm in parsed):
            return m.group(0)
        out = ""
        for pm in parsed:
            ref, a, b = pm.group(1), pm.group(2), pm.group(3)
            units = units_by_ref.get(ref)
            rec = {"ref": ref, "raw": pm.group(0).strip(), "kind": "unit" if a else "bare"}
            if units is None:
                rec["kind"] = "unknown_source"
            elif a:
                a_i = int(a)
                b_i = int(b) if b else a_i
                if not (1 <= a_i <= len(units) and 1 <= b_i <= len(units)) or b_i < a_i:
                    rec["kind"] = "invalid_unit"
                else:
                    rec.update(a=a_i, b=b_i, is_range=b_i > a_i)
            marks.append(rec)
            out += f"[{ref}]"
        return out

    segments = _CODE_RE.split(answer)
    for i in range(0, len(segments), 2):
        segments[i] = _BRACKET_RE.sub(repl, segments[i])
    return "".join(segments), marks


# =========================================================
# 1ケース
# =========================================================


async def run_case(llm, case, variant: str, profile: str, cost: dict, emb_cache: dict) -> dict:
    materials = base.case_materials(case)
    units_by_ref: dict[str, list[Unit]] = {}
    marked: list[Material] = []
    for n, m in numbered(materials):
        units = {"sentence": sentence_units, "naive": naive_units}.get(variant, lambda t: natural_units(t, m.source_type))(m.content)
        units_by_ref[str(n)] = units
        marked.append(Material(key=m.key, kind=m.kind, label=m.label, content=mark_content(m.content, units, str(n)),
                               source_type=m.source_type, url=m.url))

    prompts = unit_prompts()
    orig = cs._load_prompt
    cs._load_prompt = lambda name: prompts.get(name) or orig(name)
    try:
        turn = SimpleNamespace(lecture_label=case["lecture_label"], selected_text=case["selected_text"],
                               content=case["question"], screen_page=None)
        history = cs.build_history_messages(case["history_rows"], cs.RAW_MAX_TURNS, cs.HISTORY_MAX_CHARS_PER_MESSAGE)
        messages = cs._build_answer_messages(turn, SimpleNamespace(reply_language=case["reply_language"]),
                                             cs.ConversationMemory(), history, profile, marked)
    finally:
        cs._load_prompt = orig

    state = StreamState()
    opts = LLMOptions(max_tokens=cs._answer_max_tokens(None, marked) + cs.ANSWER_THINKING_TOKENS,
                      reasoning_effort=cs.ANSWER_REASONING_EFFORT)
    t0 = time.perf_counter()
    async for _ in llm.generate_stream(cs.ANSWER_MODEL, messages, state, opts):
        pass
    seconds = time.perf_counter() - t0
    answer = state.output_text

    plain, marks = parse_citations(answer, units_by_ref)
    claims = cited_claims(plain)
    assert len(claims) == len(marks), (len(claims), len(marks))

    # 指された区切り → 原文の文字範囲。比較用に同じ主張でA2も
    spans: dict[int, dict] = {}
    for c, mk in zip(claims, marks):
        if "a" in mk:
            units = units_by_ref[mk["ref"]]
            spans[c.occurrence] = {"U": (mk["ref"], units[mk["a"] - 1].start, units[mk["b"] - 1].end)}
    a_spans = await base.method_a(claims, materials, cost, emb_cache)
    for occ, s in a_spans.items():
        spans.setdefault(occ, {})["A2"] = s["A2"]

    return {
        "message_id": case["message_id"], "variant": variant, "question": case["question"],
        "answer": answer, "plain": plain, "marks": marks,
        "claims": [vars(c) for c in claims],
        "spans": {str(k): v for k, v in spans.items()},
        "units_per_source": {r: len(u) for r, u in units_by_ref.items()},
        "input_tokens": state.input_tokens, "output_tokens": state.output_tokens,
        "answer_chars": len(answer), "orig_answer_chars": len(case["answer"]), "seconds": round(seconds, 2),
        "finish_reason": state.finish_reason,
    }


async def judge(llm, case, r, rng):
    materials = base.case_materials(case)
    claims = [SimpleNamespace(**c) for c in r["claims"]]
    spans = {int(k): {m: tuple(v) for m, v in s.items()} for k, s in r["spans"].items()}
    items, lookup = base.judge_items(claims, spans, materials, rng)
    if not items:
        return
    verdicts = await base.judge_case(llm, items, materials)
    r["judge"] = {
        f"{occ}:{method}": {
            "verdict": (verdicts.get(iid) or {}).get("candidates", {}).get(cid),
            "source_has_support": (verdicts.get(iid) or {}).get("source_has_support"),
        }
        for (occ, method), (iid, cid) in lookup.items()
    }


def summarize(results: list[dict]) -> dict:
    out = {}
    for variant in sorted({r["variant"] for r in results}):
        rs = [r for r in results if r["variant"] == variant]
        marks = [mk for r in rs for mk in r["marks"]]
        kinds = {}
        for mk in marks:
            kinds[mk["kind"]] = kinds.get(mk["kind"], 0) + 1
        unit_marks = [mk for mk in marks if mk["kind"] == "unit"]
        verdict = {"U": {}, "A2": {}}
        support = {"yes": 0, "no": 0, "unclear": 0, None: 0}
        for r in rs:
            j = r.get("judge") or {}
            seen_occ = set()
            for key, v in j.items():
                occ, method = key.split(":")
                verdict[method][v["verdict"]] = verdict[method].get(v["verdict"], 0) + 1
                if occ not in seen_occ:
                    seen_occ.add(occ)
                    support[v["source_has_support"]] = support.get(v["source_has_support"], 0) + 1
        out[variant] = {
            "cases": len(rs),
            "marks": len(marks),
            "mark_kinds": kinds,
            "unit_rate": round(len(unit_marks) / max(1, len(marks)), 3),
            "range_rate": round(sum(mk.get("is_range", False) for mk in unit_marks) / max(1, len(unit_marks)), 3),
            "verdict_U": verdict["U"],
            "verdict_A2_same_answers": verdict["A2"],
            "source_has_support": {str(k): v for k, v in support.items() if v},
            "avg_answer_chars": round(sum(r["answer_chars"] for r in rs) / len(rs)),
            "avg_orig_answer_chars": round(sum(r["orig_answer_chars"] for r in rs) / len(rs)),
            "avg_input_tokens": round(sum(r["input_tokens"] for r in rs) / len(rs)),
            "avg_output_tokens": round(sum(r["output_tokens"] for r in rs) / len(rs)),
            "avg_units_per_turn": round(sum(sum(r["units_per_source"].values()) for r in rs) / len(rs)),
        }
    return out


def write_report(results, cases, path: Path):
    import html as h
    parts = ["<h1>Unit citation test</h1>"]
    for r in results:
        case = cases[r["message_id"]]
        by_n = {str(n): m for n, m in numbered(base.case_materials(case))}
        parts.append(f"<h2>[{r['variant']}] {h.escape(r['question'][:120])}</h2>"
                     f"<details><summary>answer</summary><pre>{h.escape(r['answer'])}</pre></details>")
        for c, mk in zip(r["claims"], r["marks"]):
            s = r["spans"].get(str(c["occurrence"]), {})
            rows = []
            for method in ("U", "A2"):
                v = (r.get("judge") or {}).get(f"{c['occurrence']}:{method}", {})
                if method in s:
                    ref, a, b = s[method]
                    txt = h.escape(by_n[ref].content[a:b])
                else:
                    txt = f"<em>({mk['kind']}: {h.escape(mk['raw'])})</em>" if method == "U" else ""
                rows.append(f"<tr><td>{method}</td><td class='v {v.get('verdict') or ''}'>{v.get('verdict') or ''}</td><td><mark>{txt}</mark></td></tr>")
            sup = next(((r.get("judge") or {}).get(f"{c['occurrence']}:{k}", {}).get("source_has_support")
                        for k in ("U", "A2") if f"{c['occurrence']}:{k}" in (r.get("judge") or {})), "")
            parts.append(f"<div class=claim><b>{h.escape(mk['raw'])}</b> {h.escape(c['text'])} <small>source_has_support={sup}</small><table>{''.join(rows)}</table></div>")
    css = ("body{font-family:system-ui,sans-serif;max-width:980px;margin:24px auto;padding:0 16px;line-height:1.6}"
           "mark{background:#ffe48a}td{vertical-align:top;padding:4px 8px;border-top:1px solid #eee}"
           ".claim{margin:14px 0;padding:8px;border:1px solid #ddd;border-radius:8px}.v.supports{color:#178a3c}"
           ".v.partly{color:#b07a00}.v.no{color:#c0392b}pre{white-space:pre-wrap;background:#f6f6f6;padding:8px}")
    path.write_text(f"<!doctype html><meta charset=utf-8><title>Unit citations</title><style>{css}</style>{''.join(parts)}")


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--offset", type=int, default=0, help="使えるケースのうち、この番号から(0始まり)")
    ap.add_argument("--variant", nargs="*", default=["sentence", "natural"])
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    all_cases = json.loads(base.CASES_PATH.read_text())
    cases = [c for c in all_cases if c["rebuild"]["all_cited_ok"]][args.offset:args.offset + args.limit]
    by_id = {c["message_id"]: c for c in all_cases}
    billing = BillingEngine(task_type="citation_unit_test")
    llm = UnifiedLLM(billing)
    cost = {"embed_tokens": 0}
    emb_cache: dict = {}
    rng = random.Random(args.seed)
    profile = cs._load_student_profile(get_supabase_client(), OWN_USER_ID)

    RESULTS_DIR.mkdir(exist_ok=True)
    partial_path = RESULTS_DIR / "unit_partial.json"
    done = {}
    if args.resume and partial_path.exists():
        done = {(r["message_id"], r["variant"]): r for r in json.loads(partial_path.read_text())}
    results = []
    for variant in args.variant:
        for c in cases:
            key = (c["message_id"], variant)
            if key in done:
                results.append(done[key])
                continue
            r = await run_case(llm, c, variant, profile, cost, emb_cache)
            kinds = {}
            for mk in r["marks"]:
                kinds[mk["kind"]] = kinds.get(mk["kind"], 0) + 1
            print(f"[{variant}] {c['message_id'][:8]} marks={len(r['marks'])} {kinds} units={sum(r['units_per_source'].values())} "
                  f"chars={r['answer_chars']} (orig {r['orig_answer_chars']})")
            results.append(r)
            partial_path.write_text(json.dumps(list({**done, **{(x['message_id'], x['variant']): x for x in results}}.values()),
                                               ensure_ascii=False, default=list))

    await asyncio.gather(*(judge(llm, by_id[r["message_id"]], r, rng) for r in results if "judge" not in r))
    billing.add_token_cost(KNOWLEDGE_EMBEDDING_MODEL, cost["embed_tokens"], 0)

    summary = summarize(results)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    (RESULTS_DIR / f"unit_run_{stamp}.json").write_text(
        json.dumps({"summary": summary, "results": results}, ensure_ascii=False, indent=1, default=list))
    write_report(results, by_id, RESULTS_DIR / f"unit_report_{stamp}.html")
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    print(f"cost ${billing.total_usd():.4f}\n→ results/unit_report_{stamp}.html")


if __name__ == "__main__":
    asyncio.run(main())
