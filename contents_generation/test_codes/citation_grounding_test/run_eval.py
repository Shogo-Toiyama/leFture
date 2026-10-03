"""
出典の根拠箇所: 方式A(埋め込みで探す) と 方式B(回答役に抜粋を書かせる) を比べる。

流れ(1ケース = 1つの本番の返答。cases/cases.json は build_cases.py で作る):
  1. 方式B: 本番と同じ材料・会話で回答役(3.5 Flash-Lite)に回答を作り直させる。プロンプトには
     「本文の後に <!--citations: [...]--> で番号1か所ごとの抜粋を出す」指示を足す(B_RULE)。
     抜粋は grounding.locate_quote で原文から探す(完全一致 → 正規化一致 → 部分一致から広げる)。
  2. 方式A: Bが作った回答(タグを除いた本文)の [n] 1か所ごとに、その文と一番近い出典の文を
     gemini-embedding-2 で探す。3通り:
       A1 = 一番近い1文 / A2 = 隣の文も近ければ2文 / A3 = 埋め込み+文字の重なり(言語が同じときに効く)
     同じ比べ方を、保存済みの(本番の)回答にもかける(--judge-orig で採点も)。
  3. 採点: gemini-2.5-flash が、返答1件ごとにまとめて、各候補の箇所が「その文を支えているか」を
     supports / partly / no で判定。どの方式の候補かは伏せ、順番も混ぜる。出典の中にそもそも
     根拠があるか(source_has_support)も聞き、回答役が根拠の無い所に番号を付けたケースを区別する。
  4. results/run_*.json(全部入り)と results/report_*.html(目で見る用)を書き出す。

費用を抑えるオプション:
  --limit N        先頭からNケースだけ
  --no-b           方式Bを動かさない(作り直さない。Aを本番の回答にだけかける)
  --no-judge       採点しない
  --from-run PATH  前回の run_*.json の作り直し・候補をそのまま使い、採点とレポートだけやり直す

実行例: python run_eval.py --limit 1 --no-b --no-judge   # 試運転(埋め込み代だけ)
"""

import argparse
import asyncio
import html
import json
import math
import random
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

TEST_DIR = Path(__file__).resolve().parent
REPO_ROOT = TEST_DIR.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))
sys.path.insert(0, str(TEST_DIR))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.core.supabase import get_supabase_client  # noqa: E402
from app.services import chat_service as cs  # noqa: E402
from app.services.chat_materials import Material, normalize_citations, numbered  # noqa: E402
from app.services.helpers.llm_unified import (  # noqa: E402
    BillingEngine, LLMOptions, Message, StreamState, UnifiedLLM,
)
from app.services.knowledge_index import KNOWLEDGE_EMBEDDING_MODEL, _embed  # noqa: E402

from build_cases import OWN_USER_ID  # noqa: E402
from grounding import cited_claims, locate_quote, normalize, sentence_window, split_sentences  # noqa: E402

CASES_PATH = TEST_DIR / "cases" / "cases.json"
RESULTS_DIR = TEST_DIR / "results"
JUDGE_MODEL = "gemini/gemini-2.5-flash"
EMBED_BATCH = 50
# A2: 一番近い文との差がこれ以内なら、隣の文も含める
A2_ADJ_MARGIN = 0.03
# A3: 文字の重なり(2文字組のJaccard)の重み
A3_LEXICAL_WEIGHT = 0.3
# Bの抜粋の分、回答の出力上限を足す
B_EXTRA_TOKENS = 1500

B_RULE = """- Evidence block: if you cited anything, end the reply with this hidden block on its own line, after everything else:
<!--citations: [{"ref": "1", "quote": "..."}, {"ref": "W1", "quote": "..."}]-->
One entry for every citation mark, in the order the marks appear in your reply (a number used three times gets three entries). "quote" is the 1–3 consecutive sentences of that source that directly support the sentence carrying the mark, copied character for character in the source's own language — never translated, shortened, or reworded. Write nothing after the block.
"""
_TAG_RE = re.compile(r"<!--\s*citations:\s*(.*?)\s*(?:-->|$)", re.S)

# =========================================================
# 材料・回答役のメッセージ
# =========================================================


def case_materials(case: dict) -> list[Material]:
    return [Material(key=m["key"], kind=m["kind"], label=m["label"], content=m["content"],
                     source_type=m["source_type"], url=m.get("url")) for m in case["materials"]]


def b_answer_prompt() -> str:
    """本番の回答役のプロンプトに、方式Bの指示をCITATIONSの最後の項目として足したもの。"""
    base = (REPO_ROOT / "lefture_backend/app/services/prompts/chat_answer_prompt.txt").read_text()
    anchor = "### HOW THE LATEST MESSAGE IS STRUCTURED"
    assert anchor in base
    return base.replace(anchor, B_RULE + "\n" + anchor, 1)


def build_messages(case: dict, materials: list[Material], profile: str) -> list[Message]:
    prompt = b_answer_prompt()
    orig = cs._load_prompt
    cs._load_prompt = lambda name: prompt if name == "chat_answer_prompt.txt" else orig(name)
    try:
        turn = SimpleNamespace(lecture_label=case["lecture_label"], selected_text=case["selected_text"],
                               content=case["question"], screen_page=None)
        history = cs.build_history_messages(case["history_rows"], cs.RAW_MAX_TURNS, cs.HISTORY_MAX_CHARS_PER_MESSAGE)
        return cs._build_answer_messages(turn, SimpleNamespace(reply_language=case["reply_language"]),
                                         cs.ConversationMemory(), history, profile, materials, case["goal"])
    finally:
        cs._load_prompt = orig


async def regenerate_b(llm: UnifiedLLM, case: dict, materials: list[Material], profile: str) -> dict:
    messages = build_messages(case, materials, profile)
    state = StreamState()
    opts = LLMOptions(max_tokens=cs._answer_max_tokens(None, materials) + B_EXTRA_TOKENS + cs.ANSWER_THINKING_TOKENS,
                      reasoning_effort=cs.ANSWER_REASONING_EFFORT)
    t0 = time.perf_counter()
    t_tag = None
    buf = ""
    async for delta in llm.generate_stream(cs.ANSWER_MODEL, messages, state, opts):
        buf += delta
        if t_tag is None and "<!--" in buf:
            t_tag = time.perf_counter() - t0
    t_end = time.perf_counter() - t0
    raw = state.output_text
    m = _TAG_RE.search(raw)
    visible = raw[:m.start()].rstrip() if m else raw
    entries, parse_error = [], None
    if m:
        try:
            parsed = json.loads(m.group(1))
            entries = [e for e in parsed if isinstance(e, dict) and "ref" in e and "quote" in e]
        except Exception as e:  # noqa: BLE001
            parse_error = str(e)[:200]
    visible = normalize_citations(visible, materials)
    tag_chars = len(raw) - len(raw[:m.start()]) if m else 0
    return {
        "raw": raw, "answer": visible, "entries": entries,
        "tag_found": bool(m), "tag_closed": bool(m and raw.rstrip().endswith("-->")), "parse_error": parse_error,
        "finish_reason": state.finish_reason, "output_tokens": state.output_tokens, "input_tokens": state.input_tokens,
        # 抜粋の分の出力トークン(文字数の比で按分した概算)と、本文を書き終えてから終わるまでの秒数
        "tag_tokens_est": round(state.output_tokens * tag_chars / max(1, len(raw))),
        "seconds_total": round(t_end, 2), "seconds_after_body": round(t_end - t_tag, 2) if t_tag else None,
    }


# =========================================================
# 方式A
# =========================================================


async def embed(texts: list[str], kind: str, cost: dict) -> list[list[float]]:
    fmt = (lambda t: f"task: search result | query: {t}") if kind == "query" else (lambda t: f"title: none | text: {t}")
    out = []
    for i in range(0, len(texts), EMBED_BATCH):
        # _embedは429だけ自前で再試行する。503(一時的に使えない)もここで数回待って再試行する
        for attempt in range(4):
            try:
                vecs, tokens = await _embed([fmt(t) for t in texts[i:i + EMBED_BATCH]])
                break
            except Exception as e:  # noqa: BLE001
                if attempt == 3:
                    raise
                print(f"  ⏳ embedding failed ({type(e).__name__}), retrying in {5 * (attempt + 1)}s")
                await asyncio.sleep(5 * (attempt + 1))
        cost["embed_tokens"] += tokens
        out += vecs
    return out


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    return dot / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)) or 1)


def bigram_jaccard(a: str, b: str) -> float:
    ga = {a[i:i + 2] for i in range(len(a) - 1)}
    gb = {b[i:i + 2] for i in range(len(b) - 1)}
    return len(ga & gb) / len(ga | gb) if ga and gb else 0.0


async def method_a(claims: list, materials: list[Material], cost: dict, cache: dict) -> dict:
    """claim(occurrence) → {"A1": span, "A2": span, "A3": span}。spanは(材料番号, 開始, 終了)。"""
    by_n = {str(n): m for n, m in numbered(materials)}
    need = [(c, by_n[c.ref]) for c in claims if c.ref in by_n and c.text]
    for _, m in need:
        if m.key not in cache:
            sents = split_sentences(m.content)
            vecs = await embed([s.text for s in sents], "doc", cost) if sents else []
            cache[m.key] = (sents, vecs)
    claim_texts = sorted({c.text for c, _ in need})
    claim_vecs = dict(zip(claim_texts, await embed(claim_texts, "query", cost))) if claim_texts else {}

    out = {}
    for c, m in need:
        sents, vecs = cache[m.key]
        if not sents:
            continue
        cv = claim_vecs[c.text]
        cos = [cosine(cv, v) for v in vecs]
        i1 = max(range(len(sents)), key=lambda i: cos[i])
        spans = {"A1": (c.ref, sents[i1].start, sents[i1].end)}
        # A2: 隣の文のうち近い方が、一番近い文とほぼ同じくらい近ければ足す
        adj = [j for j in (i1 - 1, i1 + 1) if 0 <= j < len(sents)]
        j = max(adj, key=lambda j: cos[j]) if adj else None
        if j is not None and cos[j] >= cos[i1] - A2_ADJ_MARGIN:
            a, b = sorted((i1, j))
            spans["A2"] = (c.ref, sents[a].start, sents[b].end)
        else:
            spans["A2"] = spans["A1"]
        nc = normalize(c.text)
        hyb = [cos[i] + A3_LEXICAL_WEIGHT * bigram_jaccard(nc, normalize(sents[i].text)) for i in range(len(sents))]
        i3 = max(range(len(sents)), key=lambda i: hyb[i])
        spans["A3"] = (c.ref, sents[i3].start, sents[i3].end)
        out[c.occurrence] = spans
    return out


def method_b(claims: list, entries: list[dict], materials: list[Material]) -> dict:
    """claim(occurrence) → {"B": span or None, "B_step": ..., "B_quote": ...}。抜粋は番号ごとの出現順で対応させる。"""
    by_n = {str(n): m for n, m in numbered(materials)}
    per_ref: dict[str, list[str]] = {}
    for e in entries:
        per_ref.setdefault(str(e["ref"]).strip("[]"), []).append(str(e["quote"]))
    out = {}
    for c in claims:
        quotes = per_ref.get(c.ref, [])
        quote = quotes[c.ref_occurrence] if c.ref_occurrence < len(quotes) else None
        m = by_n.get(c.ref)
        loc = locate_quote(m.content, quote) if (m and quote) else None
        out[c.occurrence] = {
            "B": (c.ref, loc.start, loc.end) if loc else None,
            "B_step": loc.step if loc else ("no_quote" if not quote else "not_found"),
            "B_ratio": round(loc.matched_ratio, 2) if loc else None,
            "B_quote": quote,
        }
    return out


# =========================================================
# 採点
# =========================================================

JUDGE_PROMPT = """You check whether highlighted passages of a source support a sentence from a chatbot's reply.

For each item you get: the reply sentence (the claim), the source number it cites, and one or more candidate passages taken from that source. The sources are given in full below the items.

For each item:
- "source_has_support": "yes" if anything in the cited source supports the claim, "no" if nothing does (the chatbot cited it wrongly), "unclear" otherwise.
- For each candidate id: "supports" if the passage on its own states what the claim says (or the part of it attributed to this source), "partly" if it is related and supports only some of it, "no" if it does not support it.
Judge meaning, not wording: the claim may be in another language or paraphrased.

Return JSON: {"items": [{"id": "...", "source_has_support": "...", "candidates": {"<candidate id>": "supports|partly|no"}}]}
"""


async def judge_case(llm: UnifiedLLM, items: list[dict], materials: list[Material]) -> dict:
    by_n = {str(n): m for n, m in numbered(materials)}
    refs = sorted({it["ref"] for it in items}, key=lambda r: (r.startswith("W"), int(r.lstrip("W"))))
    sources = "\n\n".join(f"[{r}] {by_n[r].label}\n{by_n[r].content}" for r in refs if r in by_n)
    body = "\n\n".join(
        f"Item {it['id']} (cites [{it['ref']}])\nClaim: {it['claim']}\n"
        + "\n".join(f"Candidate {cid}: {txt}" for cid, txt in it["candidates"].items())
        for it in items
    )
    res = await llm.generate(JUDGE_MODEL, [
        Message(role="system", content=JUDGE_PROMPT),
        Message(role="user", content=f"<items>\n{body}\n</items>\n\n<sources>\n{sources}\n</sources>"),
    ], LLMOptions(output_type="json", temperature=0.0, reasoning_effort="low"))
    return {it["id"]: it for it in (res.output_json or {}).get("items", [])}


def judge_items(claims: list, spans: dict, materials: list[Material], rng: random.Random) -> tuple[list[dict], dict]:
    """同じ(主張, 番号)と同じ箇所はまとめて1回だけ採点する。返り値の2つ目は (occurrence, 方式) → (item id, 候補id)。"""
    by_n = {str(n): m for n, m in numbered(materials)}
    items: dict[tuple, dict] = {}
    lookup = {}
    for c in claims:
        key = (c.text, c.ref)
        if key not in items:
            items[key] = {"id": f"i{len(items) + 1}", "ref": c.ref, "claim": c.text, "candidates": {}, "_by_text": {}}
        it = items[key]
        for method, span in spans.get(c.occurrence, {}).items():
            if not span:
                continue
            ref, a, b = span
            txt = by_n[ref].content[a:b].strip()
            if txt not in it["_by_text"]:
                it["_by_text"][txt] = None
            lookup[(c.occurrence, method)] = (it["id"], txt)
    # 候補idは中身ごとにランダムな記号(方式を伏せる)
    out = []
    for it in items.values():
        texts = list(it["_by_text"])
        rng.shuffle(texts)
        ids = {t: "xyzuvw"[k] if k < 6 else f"c{k}" for k, t in enumerate(texts)}
        it["candidates"] = {ids[t]: t for t in texts}
        it["_ids"] = ids
        out.append(it)
    final = {}
    for (occ, method), (iid, txt) in lookup.items():
        it = next(x for x in out if x["id"] == iid)
        final[(occ, method)] = (iid, it["_ids"][txt])
    return [{k: v for k, v in it.items() if not k.startswith("_")} for it in out], final


# =========================================================
# 実行
# =========================================================


async def run_case(llm, case, profile, args, cost, emb_cache, rng) -> dict:
    materials = case_materials(case)
    out = {"message_id": case["message_id"], "question": case["question"], "sets": {}}

    targets = [("orig", case["answer"], None)]
    if not args.no_b:
        regen = await regenerate_b(llm, case, materials, profile)
        out["regen"] = regen
        targets.append(("regen", regen["answer"], regen))

    for name, answer, regen in targets:
        claims = cited_claims(answer)
        spans = {occ: dict(v) for occ, v in (await method_a(claims, materials, cost, emb_cache)).items()}
        if regen is not None:
            for occ, b in method_b(claims, regen["entries"], materials).items():
                spans.setdefault(occ, {})["B"] = b["B"]
                spans[occ]["_b"] = b
        out["sets"][name] = {
            "answer": answer,
            "claims": [vars(c) for c in claims],
            "spans": {str(k): {m: v for m, v in s.items()} for k, s in spans.items()},
        }
    return out


async def judge_run(llm, case, result, args, rng):
    materials = case_materials(case)
    for name, st in result["sets"].items():
        if name == "orig" and not args.judge_orig and "regen" in result["sets"]:
            continue
        claims = [SimpleNamespace(**c) for c in st["claims"]]
        spans = {int(k): {m: tuple(v) if v else None for m, v in s.items() if m != "_b"} for k, s in st["spans"].items()}
        items, lookup = judge_items(claims, spans, materials, rng)
        if not items:
            continue
        verdicts = await judge_case(llm, items, materials)
        st["judge"] = {
            "items": items,
            "verdicts": verdicts,
            "per_occurrence": {
                f"{occ}:{method}": {
                    "verdict": (verdicts.get(iid) or {}).get("candidates", {}).get(cid),
                    "source_has_support": (verdicts.get(iid) or {}).get("source_has_support"),
                }
                for (occ, method), (iid, cid) in lookup.items()
            },
        }


def summarize(results: list[dict]) -> dict:
    summary = {}
    for name in ("regen", "orig"):
        rows = [(r, r["sets"][name]) for r in results if name in r["sets"] and "judge" in r["sets"][name]]
        if not rows:
            continue
        per = {}
        for _, st in rows:
            for key, v in st["judge"]["per_occurrence"].items():
                _, method = key.split(":")
                d = per.setdefault(method, {"supports": 0, "partly": 0, "no": 0, "none": 0, "n": 0, "n_supported_src": 0, "supports_supported_src": 0})
                d["n"] += 1
                d[v["verdict"] or "none"] = d.get(v["verdict"] or "none", 0) + 1
                if v["source_has_support"] == "yes":
                    d["n_supported_src"] += 1
                    d["supports_supported_src"] += v["verdict"] == "supports"
        summary[name] = per
    b = [r["regen"] for r in results if "regen" in r]
    if b:
        steps = {}
        for r in results:
            for s in (r["sets"].get("regen") or {}).get("spans", {}).values():
                if "_b" in s:
                    steps[s["_b"]["B_step"]] = steps.get(s["_b"]["B_step"], 0) + 1
        summary["b_format"] = {
            "cases": len(b),
            "tag_found": sum(x["tag_found"] for x in b),
            "tag_closed": sum(x["tag_closed"] for x in b),
            "parse_errors": sum(bool(x["parse_error"]) for x in b),
            "locate_steps": steps,
            "avg_tag_tokens": round(sum(x["tag_tokens_est"] for x in b) / len(b)),
            "avg_seconds_after_body": round(sum(x["seconds_after_body"] or 0 for x in b) / len(b), 2),
        }
    return summary


def print_summary(summary: dict, cost_usd: float):
    for name in ("regen", "orig"):
        if name not in summary:
            continue
        print(f"\n[{name}] 方式ごとの判定(主張1か所ずつ)")
        for method, d in sorted(summary[name].items()):
            n = d["n"] or 1
            print(f"  {method:3s} n={d['n']:3d} supports={d['supports'] / n:5.0%} partly={d['partly'] / n:5.0%} "
                  f"no={d['no'] / n:5.0%}  | 出典に根拠がある主張だけ: supports={d['supports_supported_src'] / max(1, d['n_supported_src']):5.0%} (n={d['n_supported_src']})")
    if "b_format" in summary:
        print(f"\n[B 形式] {summary['b_format']}")
    print(f"\ncost ${cost_usd:.4f}")


def write_report(results: list[dict], cases: dict, summary: dict, path: Path):
    def esc(s):
        return html.escape(s or "")

    def span_html(m: Material, span, sents_cache):
        if not span:
            return "<em class=muted>(not found)</em>"
        _, a, b = span
        if m.key not in sents_cache:
            sents_cache[m.key] = split_sentences(m.content)
        wa, wb = sentence_window(sents_cache[m.key], a, b, 1)
        return (("… " if wa > 0 else "") + esc(m.content[wa:a]) + "<mark>" + esc(m.content[a:b]) + "</mark>"
                + esc(m.content[b:wb]) + (" …" if wb < len(m.content) else ""))

    parts = [f"<h1>Citation grounding test</h1><pre>{esc(json.dumps(summary, ensure_ascii=False, indent=1))}</pre>"]
    for r in results:
        case = cases[r["message_id"]]
        materials = case_materials(case)
        by_n = {str(n): m for n, m in numbered(materials)}
        sc = {}
        parts.append(f"<h2>{esc(case['question'][:120])}</h2>")
        for name, st in r["sets"].items():
            judged = (st.get("judge") or {}).get("per_occurrence", {})
            parts.append(f"<h3>{name}</h3><details><summary>answer</summary><pre>{esc(st['answer'])}</pre></details>")
            for c in st["claims"]:
                s = st["spans"].get(str(c["occurrence"]), {})
                m = by_n.get(c["ref"])
                rows = []
                for method in ("A1", "A2", "A3", "B"):
                    if method not in s:
                        continue
                    v = judged.get(f"{c['occurrence']}:{method}", {})
                    extra = ""
                    if method == "B" and "_b" in s:
                        extra = f" <small>[{s['_b']['B_step']}]</small>"
                        if s["_b"]["B_step"] == "not_found" and s["_b"]["B_quote"]:
                            extra += f"<div class=quote>LLM quote: {esc(s['_b']['B_quote'])}</div>"
                    rows.append(f"<tr><td>{method}{extra}</td><td class='v {v.get('verdict') or ''}'>{v.get('verdict') or ''}</td>"
                                f"<td>{span_html(m, tuple(s[method]) if s[method] else None, sc) if m else ''}</td></tr>")
                support = next((judged.get(f"{c['occurrence']}:{k}", {}).get("source_has_support") for k in ("A1", "B") if f"{c['occurrence']}:{k}" in judged), "")
                parts.append(f"<div class=claim><b>[{c['ref']}]</b> {esc(c['text'])} <small>source_has_support={support}</small>"
                             f"<table>{''.join(rows)}</table></div>")
    css = ("body{font-family:system-ui,sans-serif;max-width:980px;margin:24px auto;padding:0 16px;line-height:1.6}"
           "mark{background:#ffe48a}td{vertical-align:top;padding:4px 8px;border-top:1px solid #eee}"
           ".claim{margin:14px 0;padding:8px;border:1px solid #ddd;border-radius:8px}.v.supports{color:#178a3c}"
           ".v.partly{color:#b07a00}.v.no{color:#c0392b}.muted{color:#888}.quote{color:#666;font-size:.9em}"
           "pre{white-space:pre-wrap;background:#f6f6f6;padding:8px}")
    path.write_text(f"<!doctype html><meta charset=utf-8><title>Citation grounding</title><style>{css}</style>{''.join(parts)}")


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int)
    ap.add_argument("--only", nargs="*", help="message_idの先頭")
    ap.add_argument("--no-b", action="store_true")
    ap.add_argument("--no-judge", action="store_true")
    ap.add_argument("--judge-orig", action="store_true")
    ap.add_argument("--from-run", type=Path)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--resume", action="store_true", help="results/partial.jsonの済んだケースを作り直さない")
    args = ap.parse_args()

    all_cases = json.loads(CASES_PATH.read_text())
    cases = [c for c in all_cases if c["rebuild"]["all_cited_ok"]]
    print(f"{len(cases)}/{len(all_cases)} cases usable (materials rebuilt exactly)")
    if args.only:
        cases = [c for c in cases if any(c["message_id"].startswith(o) for o in args.only)]
    if args.limit:
        cases = cases[:args.limit]
    by_id = {c["message_id"]: c for c in all_cases}

    billing = BillingEngine(task_type="citation_grounding_test")
    llm = UnifiedLLM(billing)
    cost = {"embed_tokens": 0}
    rng = random.Random(args.seed)

    if args.from_run:
        results = json.loads(args.from_run.read_text())["results"]
        results = [r for r in results if r["message_id"] in {c["message_id"] for c in cases}]
    else:
        profile = cs._load_student_profile(get_supabase_client(), OWN_USER_ID)
        emb_cache: dict = {}
        # 1件ごとに途中結果を保存し、落ちたら次回(--resume)は済んだケースを作り直さない
        partial_path = RESULTS_DIR / "partial.json"
        done = {}
        if args.resume and partial_path.exists():
            done = {r["message_id"]: r for r in json.loads(partial_path.read_text())}
            print(f"resuming: {len(done)} cases already done")
        results = []
        for c in cases:
            if c["message_id"] in done:
                results.append(done[c["message_id"]])
                continue
            r = await run_case(llm, c, profile, args, cost, emb_cache, rng)
            results.append(r)
            RESULTS_DIR.mkdir(exist_ok=True)
            partial_path.write_text(json.dumps(list({**done, **{x["message_id"]: x for x in results}}.values()),
                                               ensure_ascii=False, default=list))
            g = r.get("regen")
            print(f"{c['message_id'][:8]} claims(orig)={len(r['sets']['orig']['claims'])}"
                  + (f" claims(regen)={len(r['sets']['regen']['claims'])} tag={g['tag_found']} parse_err={bool(g['parse_error'])}"
                     f" entries={len(g['entries'])} +{g['seconds_after_body']}s" if g else ""))

    if not args.no_judge:
        await asyncio.gather(*(judge_run(llm, by_id[r["message_id"]], r, args, rng) for r in results))

    billing.add_token_cost(KNOWLEDGE_EMBEDDING_MODEL, cost["embed_tokens"], 0)
    summary = summarize(results)
    RESULTS_DIR.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_path = RESULTS_DIR / f"run_{stamp}.json"
    run_path.write_text(json.dumps({"args": {k: str(v) for k, v in vars(args).items()}, "summary": summary,
                                    "results": results}, ensure_ascii=False, indent=1, default=list))
    report = RESULTS_DIR / f"report_{stamp}.html"
    write_report(results, by_id, summary, report)
    print_summary(summary, billing.total_usd())
    print(f"→ {run_path.relative_to(TEST_DIR)}\n→ {report.relative_to(TEST_DIR)}")


if __name__ == "__main__":
    asyncio.run(main())
