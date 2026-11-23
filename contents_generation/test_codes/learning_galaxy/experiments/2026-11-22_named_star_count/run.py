"""
Learning Galaxy 実験: 開発者本人のチャットから「名前のある星」が何個生まれ、
それぞれに名前のない星(根拠)がいくつ付くかを数える。設計は ../../03_design.md の案2。

  1. Supabase から開発者のチャット(全スレッド)とプロフィール(future_goals / interests)を読む
  2. 1スレッドずつ、本番の自己像の観察役と同じモデル(gpt-6-luna, reasoning low)で名前のある星と根拠を抽出
  3. 根拠の引用が本人の発言に一字一句あるかをコードで確かめ、ないものは捨てる
  4. 根拠を数える: 自分の言葉 / 心が動いた / 経験 / 未来とのつながり / 過去の自分とのつながり
     (grounding=inferred の根拠は数えない)

使い方:
  .venv/bin/python <this>/run.py --dry-run     # APIを呼ばずに入力・プロンプト・スキーマを確認
  .venv/bin/python <this>/run.py               # 本番実行
"""

import argparse
import asyncio
import json
import math
import re
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[4]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services.helpers.llm_unified import BillingEngine, Message, UnifiedLLM  # noqa: E402
from app.services.knowledge_index import KNOWLEDGE_EMBEDDING_MODEL, _embed  # noqa: E402
from app.services.profile_extraction import (  # noqa: E402
    ASSISTANT_SNIPPET_CHARS, OBSERVER_MODEL, OBSERVER_REASONING, _json_options, cosine, output_language_name,
)

USER_ID = "5be0566d-9b7a-499f-b7d2-f1c736fd5082"  # tools/experiment_privacy/allowlist.json の developer
LANGUAGE = "ja"
MODEL = OBSERVER_MODEL
REASONING = OBSERVER_REASONING
MAX_OUTPUT_TOKENS = 16000
CONCURRENCY = 6

KINDS = ["thought", "desire", "idea", "curiosity", "insight", "experience", "feeling", "value"]
COUNTED_GROUNDING = {"explicit", "near_explicit"}
# 閾値は未調整。複数の値で数えて、結果を見て決める
FUTURE_THRESHOLDS = [0.70, 0.75, 0.80]
REVISIT_THRESHOLDS = [0.75, 0.80, 0.85]

INPUTS = HERE / "inputs"
RESULTS = HERE / "results"

SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["named_stars"],
    "properties": {
        "named_stars": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["title", "description", "kind", "evidence"],
                "properties": {
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                    "kind": {"type": "string", "enum": KINDS},
                    "evidence": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["round", "quote", "initiative", "reaction", "grounding", "is_experience"],
                            "properties": {
                                "round": {"type": "integer"},
                                "quote": {"type": "string"},
                                "initiative": {"type": "string", "enum": ["user", "ai"]},
                                "reaction": {"type": "string", "enum": ["strong", "moderate", "mild", "neutral"]},
                                "grounding": {"type": "string", "enum": ["explicit", "near_explicit", "inferred"]},
                                "is_experience": {"type": "boolean"},
                            },
                        },
                    },
                },
            },
        }
    },
}


# ---------------------------------------------------------------- data

def fetch_inputs(refresh: bool) -> dict:
    path = INPUTS / "developer_chats.json"
    if path.exists() and not refresh:
        return json.loads(path.read_text())
    import os
    from supabase import create_client
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    threads = (c.table("chat_threads").select("id,title,created_at").eq("user_id", USER_ID)
               .order("created_at").execute().data)
    ids = [t["id"] for t in threads]
    msgs = []
    for i in range(0, len(ids), 30):
        msgs += (c.table("chat_messages").select("id,thread_id,role,content,status,created_at")
                 .in_("thread_id", ids[i:i + 30]).execute().data)
    profile = c.table("user_profiles").select("bio,interests,future_goals,future_goals_written_by,interests_written_by") \
        .eq("id", USER_ID).execute().data[0]
    data = {"fetched_at": datetime.now().isoformat(), "threads": threads, "messages": msgs, "profile": profile}
    INPUTS.mkdir(exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    return data


def build_rounds(thread_id: str, messages: list[dict]) -> list[dict]:
    ms = sorted((m for m in messages if m["thread_id"] == thread_id), key=lambda m: m["created_at"])
    rounds = []
    for m in ms:
        if m["role"] == "user":
            rounds.append({"number": len(rounds) + 1, "date": m["created_at"][:10], "user": m["content"] or "",
                           "assistant": "", "message_id": m["id"]})
        elif rounds and not rounds[-1]["assistant"]:
            rounds[-1]["assistant"] = m["content"] or ""
    return rounds


def snippet(text: str) -> str:
    text = text.strip()
    return text if len(text) <= ASSISTANT_SNIPPET_CHARS else text[:ASSISTANT_SNIPPET_CHARS] + "…"


def build_messages(rounds: list[dict]) -> list[Message]:
    system = (HERE / "star_finder_prompt.txt").read_text().replace(
        "${OUTPUT_LANGUAGE}", output_language_name(LANGUAGE))
    body = "\n\n".join(
        f"[round {r['number']} · {r['date']}] Student: {r['user']}\n"
        f"[round {r['number']} · {r['date']}] Assistant: {snippet(r['assistant'])}"
        for r in rounds)
    return [Message(role="system", content=system), Message(role="user", content=f"<thread>\n{body}\n</thread>")]


# ---------------------------------------------------------------- validation & counting

def norm(s: str) -> str:
    return re.sub(r"\s+", "", s or "")


def validate(raw: dict, rounds: list[dict]) -> tuple[list[dict], dict]:
    by_num = {r["number"]: r for r in rounds}
    stats = {"evidence_total": 0, "evidence_dropped_quote": 0, "stars_dropped_no_counted_evidence": 0}
    stars = []
    for s in (raw or {}).get("named_stars", []):
        kept = []
        for e in s.get("evidence", []):
            stats["evidence_total"] += 1
            r = by_num.get(e.get("round"))
            q = norm(e.get("quote"))
            if not r or not q or q not in norm(r["user"]):
                stats["evidence_dropped_quote"] += 1
                continue
            kept.append({**e, "date": r["date"], "message_id": r["message_id"]})
        if not any(e["grounding"] in COUNTED_GROUNDING for e in kept):
            stats["stars_dropped_no_counted_evidence"] += 1
            stars.append({**s, "evidence": kept, "dropped": True})
            continue
        stars.append({**s, "evidence": kept, "dropped": False})
    return stars, stats


def count_local(star: dict) -> dict:
    ev = [e for e in star["evidence"] if e["grounding"] in COUNTED_GROUNDING]
    rounds_user = {e["round"] for e in ev if e["initiative"] == "user"}
    rounds_strong = {e["round"] for e in ev if e["reaction"] == "strong"}
    rounds_moderate = {e["round"] for e in ev if e["reaction"] == "moderate"}
    rounds_exp = {e["round"] for e in ev if e["is_experience"]}
    return {"own_words": len(rounds_user), "emotion_strong": len(rounds_strong),
            "emotion_moderate": len(rounds_moderate), "experience": len(rounds_exp),
            "counted_evidence": len(ev), "inferred_evidence_not_counted":
                sum(1 for e in star["evidence"] if e["grounding"] == "inferred")}


def split_sentences(text: str) -> list[str]:
    return [s.strip() for s in re.split(r"[。\n]", text or "") if len(s.strip()) >= 6]


def doc(text: str) -> str:
    return f"title: none | text: {text}"


# ---------------------------------------------------------------- main

async def run_thread(llm: UnifiedLLM, sem: asyncio.Semaphore, t: dict, rounds: list[dict]) -> dict:
    async with sem:
        t0 = time.perf_counter()
        res = await llm.generate(MODEL, build_messages(rounds),
                                 _json_options(MODEL, SCHEMA, REASONING, MAX_OUTPUT_TOKENS))
        return {"thread_id": t["id"], "title": t["title"], "rounds": len(rounds),
                "elapsed_s": round(time.perf_counter() - t0, 2), "input_tokens": res.input_tokens,
                "output_tokens": res.output_tokens, "finish_reason": res.finish_reason,
                "json_error": res.json_parse_error, "raw": res.output_json}


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--refresh", action="store_true", help="Supabase から読み直す")
    ap.add_argument("--limit", type=int, default=0, help="先頭Nスレッドだけ")
    args = ap.parse_args()

    data = fetch_inputs(args.refresh)
    threads = [t for t in data["threads"]]
    work = []
    for t in threads:
        rounds = build_rounds(t["id"], data["messages"])
        if rounds:
            work.append((t, rounds))
    if args.limit:
        work = work[:args.limit]
    profile = data["profile"]
    anchors = ([{"field": "future_goals", "text": s} for s in split_sentences(profile.get("future_goals"))]
               + [{"field": "interests", "text": s} for s in split_sentences(profile.get("interests"))])

    total_chars = sum(len(m.content) for _, r in work for m in build_messages(r))
    print(f"threads={len(work)} rounds={sum(len(r) for _, r in work)} prompt_chars={total_chars} "
          f"anchors={len(anchors)} model={MODEL} reasoning={REASONING}")
    if args.dry_run:
        msgs = build_messages(work[0][1])
        print("--- system prompt head ---\n" + msgs[0].content[:300])
        print("--- user content head ---\n" + msgs[1].content[:600])
        opts = _json_options(MODEL, SCHEMA, REASONING, MAX_OUTPUT_TOKENS)
        print("options:", opts)
        # 検証ロジックの自己テスト(偽の出力)
        r = work[0][1]
        fake = {"named_stars": [{"title": "t", "description": "d", "kind": "thought", "evidence": [
            {"round": 1, "quote": r[0]["user"][:10], "initiative": "user", "reaction": "strong",
             "grounding": "explicit", "is_experience": False},
            {"round": 1, "quote": "存在しない引用xyz", "initiative": "user", "reaction": "strong",
             "grounding": "explicit", "is_experience": False}]}]}
        stars, st = validate(fake, r)
        print("validate self-test:", st, count_local(stars[0]))
        print("anchors:", [a["field"] + ":" + a["text"][:20] for a in anchors])
        print("rough input tokens (chars/1.5):", int(total_chars / 1.5))
        return

    billing = BillingEngine()
    llm = UnifiedLLM(billing)
    sem = asyncio.Semaphore(CONCURRENCY)
    t0 = time.perf_counter()
    outs = await asyncio.gather(*(run_thread(llm, sem, t, r) for t, r in work), return_exceptions=True)
    llm_wall = time.perf_counter() - t0

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    RESULTS.mkdir(exist_ok=True)

    stars_all, thread_rows, totals = [], [], {"evidence_total": 0, "evidence_dropped_quote": 0,
                                               "stars_dropped_no_counted_evidence": 0, "errors": 0}
    for (t, rounds), o in zip(work, outs):
        if isinstance(o, Exception):
            totals["errors"] += 1
            thread_rows.append({"thread_id": t["id"], "title": t["title"], "error": str(o)[:300]})
            continue
        stars, st = validate(o["raw"], rounds)
        for k in st:
            totals[k] += st[k]
        for s in stars:
            s.update({"thread_id": t["id"], "thread_title": t["title"],
                      "date": min((e["date"] for e in s["evidence"]), default=rounds[0]["date"])})
            stars_all.append(s)
        thread_rows.append({k: v for k, v in o.items() if k != "raw"} | {
            "named_stars": sum(1 for s in stars if not s["dropped"])})

    kept = [s for s in stars_all if not s["dropped"]]
    for s in kept:
        s["counts"] = count_local(s)

    # embeddings (stars + anchors)
    texts = [doc(f"{s['title']}。{s['description']}") for s in kept] + [doc(a["text"]) for a in anchors]
    vecs = []
    for i in range(0, len(texts), 50):
        v, tok = await _embed(texts[i:i + 50])
        billing.add_token_cost(KNOWLEDGE_EMBEDDING_MODEL, tok, 0)
        vecs += v
    star_vecs, anchor_vecs = vecs[:len(kept)], vecs[len(kept):]

    for i, s in enumerate(kept):
        sims = [cosine(star_vecs[i], av) for av in anchor_vecs]
        s["future_sims"] = [{"field": a["field"], "anchor": a["text"], "sim": round(x, 3)}
                            for a, x in sorted(zip(anchors, sims), key=lambda p: -p[1])]
        s["counts"]["future"] = {str(th): sum(1 for x in sims if x >= th) for th in FUTURE_THRESHOLDS}
        neigh = []
        for j, o in enumerate(kept):
            if j == i or o["date"] == s["date"]:
                continue
            neigh.append((cosine(star_vecs[i], star_vecs[j]), o))
        neigh.sort(key=lambda p: -p[0])
        s["revisit_neighbors"] = [{"sim": round(x, 3), "date": o["date"], "title": o["title"]} for x, o in neigh[:5]]
        s["counts"]["revisit_days"] = {str(th): len({o["date"] for x, o in neigh if x >= th})
                                       for th in REVISIT_THRESHOLDS}

    span_days = None
    dates = sorted({r["date"] for _, rs in work for r in rs})
    if dates:
        span_days = (datetime.fromisoformat(dates[-1]) - datetime.fromisoformat(dates[0])).days + 1

    meta = {"timestamp": ts, "model": MODEL, "reasoning": REASONING, "embedding_model": KNOWLEDGE_EMBEDDING_MODEL,
            "threads": len(work), "rounds": sum(len(r) for _, r in work), "chat_date_range": [dates[0], dates[-1]],
            "chat_span_days": span_days, "llm_wall_seconds": round(llm_wall, 1),
            "input_tokens": sum(r.get("input_tokens", 0) for r in thread_rows),
            "output_tokens": sum(r.get("output_tokens", 0) for r in thread_rows),
            "cost_usd": round(billing.total_usd(), 5), "totals": totals,
            "named_stars": len(kept), "future_thresholds": FUTURE_THRESHOLDS,
            "revisit_thresholds": REVISIT_THRESHOLDS, "anchors": anchors}
    out = {"meta": meta, "threads": thread_rows, "stars": kept,
           "dropped_stars": [s for s in stars_all if s["dropped"]]}
    path = RESULTS / f"{ts}_stars.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(json.dumps(meta, ensure_ascii=False, indent=1))
    print(billing.report())
    print("saved", path)


if __name__ == "__main__":
    asyncio.run(main())
