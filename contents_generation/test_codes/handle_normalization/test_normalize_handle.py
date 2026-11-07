"""
探索役の呼び名(handle)の正規化(chat_navigator.normalize_handle)のテスト。API呼び出しなし・費用$0。

背景: 2026-11-06 スレッド「HaskellのClosureとLambda」(3f8d3695) で、探索役が "C4/L6-L7" と書き、
正しい形 "C4/L6-7" と違うだけで handle_not_openable として捨てられ、その周(約0.69クレジット)が丸ごと無駄になった。
handle は自由な文字列(build_schema)なので、LLMが書きそうな揺れを正しい形に直す。

確かめること:
  1. LLMが書きそうな揺れ → 正しい形 になる
  2. 正しい形はそのまま(本番のチャットで実際に開いた・要求した呼び名を全部通して、変わらないこと)
  3. 本番で handle_not_openable になった操作が、直したあとどうなるか

使い方:
  .venv/bin/python contents_generation/test_codes/handle_normalization/test_normalize_handle.py
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services.chat_navigator import normalize_handle, parse_handle, parse_chat_handle  # noqa: E402

RESULTS = Path(__file__).resolve().parent / "results"

# (LLMが書きそうな形, 正しい形)
CASES = [
    # 今回の実例
    ("C4/L6-L7", "C4/L6-7"),
    # 範囲の書き方
    ("C4/L6-7", "C4/L6-7"),
    ("C4/L6–L7", "C4/L6-7"),        # en dash
    ("C4/L6—7", "C4/L6-7"),         # em dash
    ("C4/L6−7", "C4/L6-7"),         # minus sign
    ("C4/L6‐7", "C4/L6-7"),         # hyphen U+2010
    ("C4/L6〜L7", "C4/L6-7"),       # wave dash
    ("C4/L6～L7", "C4/L6-7"),       # fullwidth tilde
    ("C4/L6~7", "C4/L6-7"),
    ("C4/L6..7", "C4/L6-7"),
    ("C4/L6...L7", "C4/L6-7"),
    ("C4/L6…7", "C4/L6-7"),
    ("C4/L6 - L7", "C4/L6-7"),
    ("C4/L6 to L7", "C4/L6-7"),
    ("C4/L6 through 7", "C4/L6-7"),
    ("C4/L6からL7", "C4/L6-7"),
    ("C4/L7-L6", "C4/L6-7"),        # 逆順
    ("C4/L6-C4/L7", "C4/L6-7"),     # コースを2回
    ("C4/L06-L08", "C4/L6-8"),      # 前のゼロ
    ("C4/L6-L7/cards", "C4/L6-7/cards"),
    ("C4/L6-L7/Cards", "C4/L6-7/cards"),
    ("C4/L6-7/card", "C4/L6-7/cards"),
    ("C4/L6-7/review_cards", "C4/L6-7/cards"),
    ("C4/L6-7/review-cards", "C4/L6-7/cards"),
    # 全角・大文字小文字・空白・区切り
    ("Ｃ４／Ｌ６", "C4/L6"),
    ("c4/l6", "C4/L6"),
    ("c4/l6/t2", "C4/L6/T2"),
    ("C4 / L6 / T2", "C4/L6/T2"),
    ("C4\\L6", "C4/L6"),
    ("C4/L6/", "C4/L6"),
    ("/C4/L6", "C4/L6"),
    ("C04/L06/T02", "C4/L6/T2"),
    ("C4/L 6", "C4/L6"),
    ("Course4/Lecture6/Topic2", "C4/L6/T2"),
    ("C4/Lecture 6", "C4/L6"),
    # 引用符・括弧・後ろの説明・前の動詞
    ("`C4/L6`", "C4/L6"),
    ("\"C4/L6\"", "C4/L6"),
    ("「C4/L6」", "C4/L6"),
    ("[C4/L6]", "C4/L6"),
    ("⟦C4/L6⟧", "C4/L6"),
    ("**C4/L6**", "C4/L6"),
    ("C4/L6 (Oct 13 lecture)", "C4/L6"),
    ("C4/L6（10月13日）", "C4/L6"),
    ("C4/L6: Haskell higher-order functions", "C4/L6"),
    ("C4/L6 \"Haskell\"", "C4/L6"),
    ("C4/L6.", "C4/L6"),
    ("open C4/L6", "C4/L6"),
    ("open: C4/L6", "C4/L6"),
    ("handle=C4/L6", "C4/L6"),
    # コースの集約
    ("C4/Topics", "C4/topics"),
    ("C4/topic", "C4/topics"),
    ("C4/TOPICS", "C4/topics"),
    ("C4/keyword", "C4/keywords"),
    ("C4/announcement", "C4/announcements"),
    ("C4/L6/Cards", "C4/L6/cards"),
    ("C4/L6/announcement", "C4/L6/announcements"),
    # 文字起こしの文(小文字のs)
    ("C4/L6/s10-20", "C4/L6/s10-20"),
    ("C4/L6/S10-20", "C4/L6/s10-20"),
    ("C4/L6/s10-s20", "C4/L6/s10-20"),
    ("C4/L6/s10–s20", "C4/L6/s10-20"),
    ("C4/L6/s20-10", "C4/L6/s10-20"),
    ("C4/L6/s010-020", "C4/L6/s10-20"),
    ("C4/L6/s10-10", "C4/L6/s10"),
    ("C4/L6/s10 to s20", "C4/L6/s10-20"),
    # 資料・リンク・Web・会話の節・過去のチャット(大文字のS)
    ("a1", "A1"),
    ("A1/s2", "A1/S2"),
    ("Ａ１／Ｓ２", "A1/S2"),
    ("u1/s3", "U1/S3"),
    ("w2", "W2"),
    ("W02", "W2"),
    ("s3", "S3"),
    ("S3/t2", "S3/T2"),
    ("p1", "P1"),
    ("P1/s2", "P1/S2"),
    ("p1/h2", "P1/H2"),
    ("h1", "H1"),
    # 直せないもの(そのあとの検証で今までどおり捨てる)
    ("", ""),
    ("   ", ""),
    ("C4/L6-C5/L7", None),          # 別のコースの範囲: 直さない(開けないまま)
]


def kind_of(h: str) -> str:
    p = parse_handle(h)
    if p:
        return p.kind
    c = parse_chat_handle(h)
    if c:
        return f"chat:{c.kind}"
    if re.match(r"^(W\d+|A\d+(/S\d+)?|U\d+(/S\d+)?)$", h):
        return "web/attachment/link"
    return "UNPARSED"


def test_cases() -> list[str]:
    fails = []
    for written, expected in CASES:
        got = normalize_handle(written)
        if expected is None:
            if kind_of(got) != "UNPARSED":
                fails.append(f"{written!r}: expected unparsable, got {got!r} ({kind_of(got)})")
            continue
        if got != expected:
            fails.append(f"{written!r}: expected {expected!r}, got {got!r}")
        elif expected and kind_of(got) == "UNPARSED":
            fails.append(f"{written!r}: normalized to {got!r} but parse failed")
        # 2回通しても同じ
        if normalize_handle(got) != got:
            fails.append(f"{written!r}: not idempotent ({got!r} -> {normalize_handle(got)!r})")
    return fails


def production_handles() -> tuple[set[str], list[dict]]:
    """本番の探索役の記録から、要求した呼び名・開いた呼び名・捨てられた操作を集める。"""
    from supabase import create_client
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    rows, off = [], 0
    while True:
        d = (c.table("chat_messages").select("id,created_at,usage->navigator,usage->materials")
             .eq("role", "assistant").order("created_at", desc=True).range(off, off + 499).execute().data)
        rows += d
        if len(d) < 500:
            break
        off += 500
    handles: set[str] = set()
    dropped: list[dict] = []
    for r in rows:
        for mat in r.get("materials") or []:
            if isinstance(mat, dict) and mat.get("handle"):
                handles.add(mat["handle"].split()[0])
        nav = r.get("navigator") or {}
        for lap in nav.get("laps") or []:
            for req in lap.get("requests") or []:
                if req.get("handle"):
                    handles.add(req["handle"])
                if req.get("within"):
                    handles.add(req["within"])
            for done in lap.get("done") or []:
                if isinstance(done, str) and done.startswith("open "):
                    handles.add(done[5:].strip())
            for d in lap.get("dropped") or []:
                dropped.append({"message": r["id"], "created_at": r["created_at"], **d})
    return handles, dropped


def main() -> None:
    RESULTS.mkdir(exist_ok=True)
    out = []
    fails = test_cases()
    out.append(f"## 1. Variant cases: {len(CASES) - len(fails)}/{len(CASES)} passed")
    out += [f"- FAIL {f}" for f in fails]

    handles, dropped = production_handles()
    changed = sorted((h, normalize_handle(h)) for h in handles if normalize_handle(h) != h)
    out.append(f"\n## 2. Production handles unchanged by normalization: {len(handles) - len(changed)}/{len(handles)}")
    out += [f"- CHANGED {h!r} -> {n!r}" for h, n in changed]

    out.append(f"\n## 3. Production dropped ops ({len(dropped)})")
    for d in dropped:
        op = d.get("op") or {}
        h = op.get("handle")
        if h is None:
            out.append(f"- {d['created_at'][:10]} {d['reason']}: {json.dumps(op, ensure_ascii=False)} (no handle)")
            continue
        n = normalize_handle(h)
        out.append(f"- {d['created_at'][:10]} {d['reason']}: {h!r} -> {n!r} ({kind_of(n)})")

    text = "\n".join(out)
    print(text)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    (RESULTS / f"{stamp}_normalize_handle.md").write_text(text + "\n")
    sys.exit(1 if fails or changed else 0)


if __name__ == "__main__":
    main()
