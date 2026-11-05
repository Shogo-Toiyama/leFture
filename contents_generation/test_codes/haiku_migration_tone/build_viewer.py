"""
実験結果 (results/<run>/raw.json, 複数可) と、既存の Gemini 出力 (inputs/<lecture>.json の gemini_reference) を
並べて読むための単一 HTML ビューアを生成する。複数の run を渡すと、ビューア上で版を切り替えられる。

使い方:
  .venv/bin/python contents_generation/test_codes/haiku_migration_tone/build_viewer.py OUT.html results/<run_v0> results/<run_v1> ...
"""

import json
import sys
from pathlib import Path

EXP_DIR = Path(__file__).resolve().parent


def _haiku_from(raw, lid):
    runs = {r["task"]: r for r in raw["results"] if r["lecture_id"] == lid}
    rc = {str(t.get("topic_idx")): t.get("review_cards", []) for t in (runs["review_cards"]["output"] or [])} \
        if "review_cards" in runs else None
    dn = {str(d.get("topic_idx")): d.get("content", "") for d in (runs["deep_notes"]["output"] or [])} \
        if "deep_notes" in runs else None
    ff = runs["fun_facts"]["output"] if "fun_facts" in runs else None
    return {
        "outputs": {"review_cards": rc, "deep_notes": dn, "fun_facts": ff},
        "ran": sorted(runs),
        "checks": {task: r.get("checks", {}) for task, r in runs.items()},
        "errors": {task: r.get("error") for task, r in runs.items() if r.get("error")},
    }


def build(out_path: Path, run_dirs) -> Path:
    raws = [json.loads((d / "raw.json").read_text(encoding="utf-8")) for d in run_dirs]
    lecture_ids = raws[0]["meta"]["lectures"]
    versions = [{"name": r["meta"]["prompt_version"], "meta": r["meta"]} for r in raws]
    lectures = []
    for lid in lecture_ids:
        inp = json.loads((EXP_DIR / "inputs" / f"{lid}.json").read_text(encoding="utf-8"))
        lec = inp["lecture"]
        core_topics = [t for t in inp["core_extraction"].get("topics", []) if t.get("topic_type") == "ACADEMIC"]
        ref = inp["gemini_reference"]
        ref_rc = {}
        for row in ref["review_cards"]:
            ref_rc.setdefault(str(row["topic_number"]), []).append({
                "card_type": row["card_type"], "title": row["title"], "hero_emoji": row["hero_emoji"],
                "content_blocks": row["card_content"] or [],
            })
        lectures.append({
            "id": lid,
            "title": lec.get("title") or lec.get("title_generated") or lid[:8],
            "lang": f'{inp["language"]["transcript_language"]} → {inp["language"]["content_language"]}',
            "topics": [{"idx": str(t.get("idx")), "title": t.get("title")} for t in core_topics],
            "gemini": {
                "review_cards": ref_rc,
                "deep_notes": {str(r["topic_number"]): r["note_contents"] for r in ref["deep_notes"]},
                "fun_facts": ref["fun_facts"][0] if ref["fun_facts"] else None,
            },
            "haiku": {v["name"]: _haiku_from(raw, lid) for v, raw in zip(versions, raws)},
        })

    data = {"versions": versions, "lectures": lectures}
    template = (EXP_DIR / "viewer_template.html").read_text(encoding="utf-8")
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    html = template.replace("/*__DATA__*/null", payload)
    out_path.write_text(html, encoding="utf-8")
    print(f"viewer: {out_path} ({len(html)/1024:.0f} KB, versions={[v['name'] for v in versions]})")
    return out_path


if __name__ == "__main__":
    out = Path(sys.argv[1])
    dirs = [Path(a) if Path(a).is_absolute() else EXP_DIR / a for a in sys.argv[2:]]
    build(out, dirs)
