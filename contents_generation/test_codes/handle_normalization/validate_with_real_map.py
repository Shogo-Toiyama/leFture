"""
本番の探索入力(同じユーザーの「不変データ構造」スレッドの最終ターンを navigator_schema_cache/replay.py の
build_turn で再現)に対して、validate_operations が表記の揺れた handle を通すか確かめる。API呼び出しなし・$0。
  .venv/bin/python contents_generation/test_codes/handle_normalization/validate_with_real_map.py
"""
import asyncio, json, os, sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "navigator_schema_cache"))
import replay  # noqa: E402  (lefture_backend への path と .env の読み込みもここで済む)
from replay import nav, create_client  # noqa: E402

OPS = [
    {"op": "open", "handle": "C4/L6-L7"},          # 2026-11-06 に捨てられた実例
    {"op": "open", "handle": "C4/L4–L8"},
    {"op": "open", "handle": "c4/l6/t2"},
    {"op": "open", "handle": "C4/Topics"},
    {"op": "open", "handle": "C4/L6-L7/cards"},
    {"op": "open", "handle": "C4/L6 (Oct 13)"},
    {"op": "find", "target": "lecture.concept", "query": "closure", "within": "c4"},
    {"op": "open", "handle": "C4/L6-C5/L7"},       # 直さない(捨てられるべき)
]


async def main():
    admin = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    nav_input, _ = await replay.build_turn(admin)
    state = nav.NavState()
    reqs, dropped = nav.validate_operations(OPS, nav_input, state, need="explicit", fetch_from=["class"])
    lines = ["## validate_operations with the real student map",
             *[f"- ACCEPTED {r.label()}" for r in reqs],
             *[f"- DROPPED {json.dumps(d['op'], ensure_ascii=False)} reason={d['reason']}" for d in dropped]]
    text = "\n".join(lines)
    print(text)
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / f"{datetime.now():%Y%m%d_%H%M%S}_validate_real_map.md").write_text(text + "\n")

asyncio.run(main())
