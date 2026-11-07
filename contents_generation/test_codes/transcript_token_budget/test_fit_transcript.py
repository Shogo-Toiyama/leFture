"""
文字起こしの範囲を「60文を超えたら却下 + 3,000字で切る」から「1,000トークン(estimate_tokens)まで文の区切りで入れる」に
変えた(chat_navigator.fit_transcript)ことの確認。API呼び出しなし・$0。

1. 作った文での単体の確認(英語・日本語・1文だけで上限超え・前後の文・抜けたsid)
2. 本番の文字起こし: 検索のチャンク(knowledge_chunks の transcript_topic、sid_start〜sid_end)をそのまま開いたとき、
   丸ごと入るか、何トークンになるか(英語・日本語別)。旧ルールで開けなかった(61文以上)チャンクも数える
3. 本番で transcript_range_too_long で捨てられた要求を、今の地図で引き直して新しいルールで開く

  .venv/bin/python contents_generation/test_codes/transcript_token_budget/test_fit_transcript.py [--lectures 40]
"""

import argparse
import asyncio
import json
import os
import random
import statistics as st
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "lefture_backend"))
from dotenv import load_dotenv  # noqa: E402

load_dotenv(ROOT / "lefture_backend" / ".env")
from supabase import create_client  # noqa: E402

from app.services import chat_navigator as nav  # noqa: E402
from app.services.chat_attachments import estimate_tokens  # noqa: E402
from app.services.chat_lecture_source import DbLectureSource  # noqa: E402
from app.services.chat_map import load_student_map  # noqa: E402

OLD_MAX_SENTENCES = 60
OLD_CHARS = 3000


def unit_tests() -> list[str]:
    out = ["## 1. Unit cases"]
    budget = nav.TRANSCRIPT_MAX_TOKENS
    en = [{"sid": i, "text": f"Sentence number {i} explains one small idea about closures."} for i in range(1, 301)]
    ja = [{"sid": i, "text": f"これは{i}番目の文で、クロージャの考え方を一つ説明しています。"} for i in range(1, 301)]

    def check(name, cond, detail=""):
        out.append(f"- {'PASS' if cond else 'FAIL'} {name} {detail}")
        assert cond, name

    body, end = nav.fit_transcript(en, 10, 20)
    check("short English range fits whole, with context", end == 20 and body.startswith("Sentence number 9 ") and "number 21 " in body,
          f"(tokens {estimate_tokens(body)})")
    body, end = nav.fit_transcript(en, 1, 300)
    check("long English range is clamped at whole sentences", end < 300 and estimate_tokens(body) <= budget
          and body.endswith("closures.") and body.startswith("Sentence number 1 "), f"(shown s1-{end}, tokens {estimate_tokens(body)})")
    body, end = nav.fit_transcript(ja, 1, 300)
    check("long Japanese range is clamped under the same token budget", end < 300 and estimate_tokens(body) <= budget,
          f"(shown s1-{end}, {len(body)} chars, tokens {estimate_tokens(body)})")
    huge = [{"sid": 5, "text": "あ" * 5000}, {"sid": 6, "text": "short."}]
    body, end = nav.fit_transcript(huge, 5, 6)
    check("one sentence over the budget is cut, not dropped", end == 5 and 0 < estimate_tokens(body) <= budget,
          f"(tokens {estimate_tokens(body)})")
    gap = [s for s in en if s["sid"] not in (12, 13)]
    body, end = nav.fit_transcript(gap, 10, 15)
    check("missing sids are skipped", end == 15 and "number 12 " not in body)
    check("range with no sentences returns None", nav.fit_transcript(en, 500, 510) is None)
    tight = [{"sid": 1, "text": "x" * 3995}, {"sid": 2, "text": "y" * 8}, {"sid": 3, "text": "z" * 40}]
    body, end = nav.fit_transcript(tight, 2, 2)
    check("context sentences only added when they fit", end == 2 and "x" not in body and estimate_tokens(body) <= budget,
          f"(body {body[:20]!r}...)")
    return out


async def real_chunks(c, n_lectures: int) -> tuple[list[str], dict]:
    rows, off = [], 0
    while True:
        d = c.table("knowledge_chunks").select("user_id, lecture_id, metadata, content").eq("source_type", "transcript_topic") \
            .is_("deleted_at", "null").range(off, off + 999).execute().data
        rows += d
        if len(d) < 1000:
            break
        off += 1000
    by_lec = defaultdict(list)
    for r in rows:
        md = r["metadata"] if isinstance(r["metadata"], dict) else json.loads(r["metadata"])
        by_lec[(r["user_id"], r["lecture_id"])].append((md["sid_start"], md["sid_end"], r["content"]))
    ja_lecs = [k for k, v in by_lec.items() if sum(ord(ch) > 127 for ch in v[0][2]) > len(v[0][2]) * 0.3]
    en_lecs = [k for k in by_lec if k not in set(ja_lecs)]
    random.seed(7)
    picked = random.sample(en_lecs, min(len(en_lecs), n_lectures - n_lectures // 4)) + random.sample(ja_lecs, min(len(ja_lecs), n_lectures // 4))
    stats = {"en": defaultdict(list), "ja": defaultdict(list)}
    sources: dict[str, DbLectureSource] = {}
    for user_id, lec_id in picked:
        src = sources.setdefault(user_id, DbLectureSource(c, user_id))
        sentences = await src.transcript(lec_id)
        if not sentences:
            continue
        lang = "ja" if (user_id, lec_id) in set(ja_lecs) else "en"
        for a, b, _ in by_lec[(user_id, lec_id)]:
            fit = nav.fit_transcript(sentences, a, b)
            if fit is None:
                continue
            body, end = fit
            s = stats[lang]
            s["n_sentences"].append(b - a + 1)
            s["old_rejected"].append(b - a + 1 > OLD_MAX_SENTENCES)
            old_body = " ".join(x["text"] for x in sentences if a - 1 <= x["sid"] <= b + 1 and x["text"])
            s["old_cut_mid"].append(len(old_body) > OLD_CHARS)
            s["old_tokens"].append(estimate_tokens(old_body[:OLD_CHARS]))
            s["new_full"].append(end == b)
            s["new_tokens"].append(estimate_tokens(body))
            s["new_share"].append((end - a + 1) / (b - a + 1))
    out = ["", f"## 2. Real transcript chunks opened as search hits ({len(picked)} lectures sampled; seed 7)"]
    q = lambda v, p: sorted(v)[min(len(v) - 1, int(len(v) * p))]
    for lang, s in stats.items():
        if not s["n_sentences"]:
            continue
        n = len(s["n_sentences"])
        out += [f"### {lang}: {n} chunks",
                f"- sentences per chunk: median {st.median(s['n_sentences']):.0f}, p90 {q(s['n_sentences'], .9)}, max {max(s['n_sentences'])}",
                f"- old rule: rejected (>60 sentences) {sum(s['old_rejected'])} ({sum(s['old_rejected']) / n:.0%}); "
                f"cut mid-sentence at 3,000 chars {sum(s['old_cut_mid'])} ({sum(s['old_cut_mid']) / n:.0%}); "
                f"tokens median {st.median(s['old_tokens']):.0f}, max {max(s['old_tokens'])}",
                f"- new rule: whole chunk shown {sum(s['new_full'])} ({sum(s['new_full']) / n:.0%}); "
                f"tokens median {st.median(s['new_tokens']):.0f}, max {max(s['new_tokens'])}; "
                f"share of the chunk shown when clamped: median {st.median([x for x, f in zip(s['new_share'], s['new_full']) if not f] or [1]):.0%}"]
    return out, stats


async def production_drops(c) -> list[str]:
    rows, off = [], 0
    while True:
        d = c.table("chat_messages").select("id, thread_id, created_at, usage->navigator").eq("role", "assistant") \
            .range(off, off + 499).execute().data
        rows += d
        if len(d) < 500:
            break
        off += 500
    out = ["", "## 3. Production requests dropped as transcript_range_too_long, opened with the new rule",
           "(handles resolved against today's student map; if lectures were added or reordered since, a handle can point "
           "elsewhere, which the row shows)"]
    maps, sources, users = {}, {}, {}
    for r in rows:
        for lap in (r.get("navigator") or {}).get("laps") or []:
            for d in lap.get("dropped") or []:
                if d.get("reason") != "transcript_range_too_long":
                    continue
                handle = (d.get("op") or {}).get("handle", "")
                if r["thread_id"] not in users:
                    users[r["thread_id"]] = c.table("chat_threads").select("user_id").eq("id", r["thread_id"]).execute().data[0]["user_id"]
                uid = users[r["thread_id"]]
                m = maps.setdefault(uid, load_student_map(c, uid))
                src = sources.setdefault(uid, DbLectureSource(c, uid))
                parsed = nav.parse_handle(nav.normalize_handle(handle))
                lec = m.lecture(parsed.lecture) if parsed and parsed.lecture else None
                if not lec or parsed.kind != "transcript":
                    out.append(f"- {r['created_at'][:10]} {handle}: cannot resolve today ({parsed.kind if parsed else 'unparsed'})")
                    continue
                fit = nav.fit_transcript(await src.transcript(lec.id), parsed.sid_start, parsed.sid_end)
                if fit is None:
                    out.append(f"- {r['created_at'][:10]} {handle}: no sentences in range")
                    continue
                body, end = fit
                out.append(f"- {r['created_at'][:10]} {handle} ({parsed.sid_end - parsed.sid_start + 1} sentences): "
                           f"shows s{parsed.sid_start}-{end}, {estimate_tokens(body)} tokens"
                           + ("" if end == parsed.sid_end else f", rest s{end + 1}-{parsed.sid_end} offered"))
    return out


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lectures", type=int, default=40)
    args = ap.parse_args()
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    lines = [f"# fit_transcript check ({datetime.now():%Y-%m-%d %H:%M}), budget {nav.TRANSCRIPT_MAX_TOKENS:,} tokens, $0 (no API calls)", ""]
    lines += unit_tests()
    chunk_lines, stats = await real_chunks(c, args.lectures)
    lines += chunk_lines
    lines += await production_drops(c)
    text = "\n".join(lines)
    print(text)
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / f"{datetime.now():%Y%m%d_%H%M%S}_fit_transcript.md").write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    asyncio.run(main())
