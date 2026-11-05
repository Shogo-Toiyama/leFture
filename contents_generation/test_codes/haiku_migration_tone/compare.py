"""
複数の実行結果 (results/*_run_<ver>) と既存 Gemini 出力を、同じ指標で並べる。
良し悪しの判定はしない(数値の記録のみ)。

使い方: .venv/bin/python contents_generation/test_codes/haiku_migration_tone/compare.py v0 v1
"""
import collections
import glob
import json
import re
import sys
from pathlib import Path

EXP = Path(__file__).resolve().parent
JP = re.compile(r"[぀-ヿ一-鿿]")
STOCK = ("Curious? Dig into these too", "Make sure to cover these", "Self-Study List", "Take Action & Practice")


def rc_texts(cards):
    out = []
    for c in cards:
        out.append(c.get("title") or "")
        for b in c.get("content_blocks") or []:
            out += [b.get("text") or "", b.get("explanation") or ""] + list(b.get("items") or [])
    return out


def kw_variants(kw):
    parts = [kw] + re.findall(r"[（(]([^）)]+)[）)]", kw) + [re.sub(r"\s*[（(][^）)]*[）)]", "", kw)]
    return {p.strip().lower() for p in parts if p.strip()}


def selfstudy(cards):
    heads, items = [], []
    for c in cards:
        if c.get("card_type") != "next_action":
            continue
        bl = c.get("content_blocks") or []
        for i, b in enumerate(bl):
            if b.get("type") == "list" and i > 0 and bl[i - 1].get("type") == "paragraph":
                heads.append(bl[i - 1].get("text") or "")
                items += b.get("items") or []
    return heads, items


def md_stats(md):
    c = collections.Counter()
    for line in md.splitlines():
        s = line.strip()
        if not s:
            continue
        if re.match(r"^[-*+]\s", s):
            c["bullet"] += 1
        elif re.match(r"^\d+[.)]\s", s):
            c["numbered"] += 1
        elif s.startswith("## "):
            c["h2"] += 1
        elif s.startswith("#") or s.startswith("<!--") or s.startswith("```") or s.startswith(">"):
            pass
        else:
            c["para"] += 1
    c["examples"] = len(re.findall(r"例えば|たとえば|具体例|for example|e\.g\.", md, re.I))
    return c


def collect(source_name, rc_by_topic, dn_list, ff, inputs, store):
    S = store.setdefault(source_name, collections.Counter())
    for lid, topics in rc_by_topic.items():
        inp = inputs[lid]
        ctopics = {t["idx"]: t for t in inp["core_extraction"]["topics"]}
        bilingual_ja = inp["language"]["content_language"] == "Japanese"
        for tidx, cards in topics.items():
            S["rc_topics"] += 1
            S["rc_cards"] += len(cards)
            S["rc_bad_sequence"] += [c.get("card_type") for c in cards] != ["hook", "core_why", "gotcha", "next_action"]
            text = "\n".join(rc_texts(cards))
            S["rc_chars"] += len(text)
            S["rc_excl"] += text.count("！") + text.count("!")
            S["rc_q"] += text.count("？") + text.count("?")
            if bilingual_ja:
                body = re.sub(r"\s|⟦[^⟧]*⟧", "", text)
                if len(JP.findall(body)) / max(1, len(body)) < 0.4:
                    S["rc_topics_mostly_english"] += 1
                S["rc_ja_titles_total"] += len(cards)
                S["rc_ja_titles_english"] += sum(1 for c in cards if not JP.search(c.get("title") or ""))
            kws = [k["keyword"] for k in ctopics.get(tidx, {}).get("keywords", []) if isinstance(k, dict)]
            low = text.lower()
            S["kw_total"] += len(kws)
            S["kw_used"] += sum(1 for k in kws if any(v in low for v in kw_variants(k)))
            heads, items = selfstudy(cards)
            S["ss_lists"] += len(heads)
            S["ss_stock_heading"] += sum(1 for h in heads if any(p in h for p in STOCK))
            S["ss_items"] += len(items)
            S["ss_items_cited"] += sum(1 for i in items if "⟦" in i)
    for md in dn_list:
        S["dn_notes"] += 1
        S["dn_chars"] += len(md)
        S.update({f"dn_{k}": v for k, v in md_stats(md).items()})
        S["dn_q"] += md.count("？") + md.count("?")
        S["dn_excl"] += md.count("！") + md.count("!")
    for f in ff:
        if f:
            t = f"{f.get('title', '')}\n{f.get('hook', '')}\n{f.get('body', '')}"
            S["ff_count"] += 1
            S["ff_chars"] += len(t)
            S["ff_excl"] += t.count("！") + t.count("!")


def main(versions):
    store = {}
    inputs = {}
    gemini_done = False
    for ver in versions:
        run_dir = sorted(glob.glob(str(EXP / f"results/*_run_{ver}")))[-1]
        raw = json.loads(Path(run_dir, "raw.json").read_text())
        for lid in raw["meta"]["lectures"]:
            inputs.setdefault(lid, json.loads((EXP / "inputs" / f"{lid}.json").read_text()))
        rc, dn, ff = {}, [], []
        for r in raw["results"]:
            if r["task"] == "review_cards" and r["output"]:
                rc[r["lecture_id"]] = {t["topic_idx"]: t.get("review_cards", []) for t in r["output"]}
            if r["task"] == "deep_notes" and r["output"]:
                dn += [d.get("content") or "" for d in r["output"]]
            if r["task"] == "fun_facts":
                ff.append(r["output"])
        collect(f"Haiku {ver}", rc, dn, ff, inputs, store)
        S = store[f"Haiku {ver}"]
        S["cost_milli_usd"] = round(raw["meta"]["token_cost_usd_total"] * 1000)
        S["errors"] = sum(1 for r in raw["results"] if r["error"])
        S["truncated"] = sum(1 for r in raw["results"] for c in r["calls"] if c.get("finish_reason") == "length")
        S["json_errors"] = sum(1 for r in raw["results"] for c in r["calls"] if c.get("json_parse_error"))
        if not gemini_done:
            grc, gdn, gff = {}, [], []
            for lid in raw["meta"]["lectures"]:
                ref = inputs[lid]["gemini_reference"]
                g = {}
                for row in ref["review_cards"]:
                    g.setdefault(row["topic_number"], []).append({
                        "card_type": row["card_type"], "title": row["title"], "content_blocks": row["card_content"] or []})
                grc[lid] = g
                gdn += [x["note_contents"] or "" for x in ref["deep_notes"]]
                gff.append(ref["fun_facts"][0] if ref["fun_facts"] else None)
            collect("Gemini (existing)", grc, gdn, gff, inputs, store)
            gemini_done = True
    keys = sorted({k for s in store.values() for k in s})
    names = list(store)
    print("metric".ljust(28) + "".join(n.ljust(20) for n in names))
    for k in keys:
        print(k.ljust(28) + "".join(str(store[n].get(k, "")).ljust(20) for n in names))
    out = EXP / "results" / f"compare_{'_'.join(versions)}.json"
    out.write_text(json.dumps({n: dict(s) for n, s in store.items()}, ensure_ascii=False, indent=1))
    print("saved", out)


if __name__ == "__main__":
    main(sys.argv[1:] or ["v0"])
