"""
ステップ1: 範囲の材料の組み立てだけを確かめる(LLMは呼ばない。費用$0)。

各ケースで、予算の中でどの段階(要約+トピック要約 / 要約+トピック名 / タイトルだけ)になったか、
カードが何枚中何枚入ったか(講義ごと)、トークン数(estimate_tokens)、探索役に見せる文を出し、
本文ごと results/ に保存する。

  .venv/bin/python contents_generation/test_codes/range_overview_eval/check_materials.py
"""

import asyncio
import json
import os
import re
from datetime import date, datetime
from zoneinfo import ZoneInfo

from load_patched import HERE, install

nav, cs = install()

from supabase import create_client  # noqa: E402

from app.services.chat_attachments import estimate_tokens  # noqa: E402
from app.services.chat_lecture_source import DbLectureSource  # noqa: E402
from app.services.chat_map import load_student_map  # noqa: E402

BROTHER = "a29fe924-9adf-4baa-b84a-7c8906944d7b"
PL_THREAD = "886879bc-3721-4c68-9ffd-df42021d77fa"
TZ = ZoneInfo("America/Los_Angeles")


def course_handle(m, title_part: str) -> str:
    return next(c.handle for c in m.courses if title_part.lower() in c.title.lower())


def per_lecture_cards(body: str) -> list[str]:
    return re.findall(r"Key Review Cards \((\d+ of \d+)\)", body)


async def main():
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    pl_user = c.table("chat_threads").select("user_id").eq("id", PL_THREAD).execute().data[0]["user_id"]
    rows = []
    for uid in (BROTHER, pl_user):
        m = load_student_map(c, uid, TZ)
        source = DbLectureSource(c, uid, cs._load_blocked_source_types(uid))
        ni = nav.NavigatorInput(message="", selected_text=None, screen_lecture_id=None, recent_conversation=[],
                                today=date(2026, 11, 6), student_map=m)
        cases = []
        if uid == BROTHER:
            fl = course_handle(m, "Formal logic")
            fl_course = m.course(fl)
            n = len(fl_course.lectures)
            cases += [
                ("by_date 10/1-10/30 within Formal logic", "by_date", (date(2026, 10, 1), date(2026, 10, 30), fl), nav.RANGE_MATERIAL_BUDGET),
                ("by_date 10/1-10/30 all courses", "by_date", (date(2026, 10, 1), date(2026, 10, 30), None), nav.RANGE_MATERIAL_BUDGET),
                (f"open {fl}/L1-{n}/cards (existing op, whole course)", "open", f"{fl}/L1-{n}/cards", nav.RANGE_MATERIAL_BUDGET),
                (f"open {fl}/L1-{n} (new op, whole course)", "open", f"{fl}/L1-{n}", nav.RANGE_MATERIAL_BUDGET),
                ("by_date 10/1-10/30 Formal logic, budget split with another range op (5,000)", "by_date",
                 (date(2026, 10, 1), date(2026, 10, 30), fl), nav.RANGE_MATERIAL_BUDGET // 2),
            ]
        else:
            pl = course_handle(m, "Programming Language")
            n = len(m.course(pl).lectures)
            cases += [(f"open {pl}/L1-{n} (Programming Language, whole course)", "open", f"{pl}/L1-{n}", nav.RANGE_MATERIAL_BUDGET)]

        for name, kind, arg, budget in cases:
            if kind == "by_date":
                d_from, d_to, within = arg
                lecs = m.lectures_between(d_from, d_to, within)
                ov = await nav.build_range_overview(lecs, m, source, budget)
                body, note, tokens = ov.body, ov.note(), ov.tokens
                stats = {"level": ov.level, "lectures": ov.lectures, "cards": f"{ov.cards_included}/{ov.cards_total}"}
            else:
                op = await nav.open_handle(arg, ni, source, range_budget=budget)
                body, note, tokens = op.material.content, op.text.splitlines()[-1], op.range_tokens
                stats = {"lectures": len(op.surfaced)}
            row = {"case": name, "budget": budget, "tokens": tokens, "material_tokens": estimate_tokens(body),
                   **stats, "cards_per_lecture": per_lecture_cards(body), "navigator_sees": note, "body": body}
            rows.append(row)
            print(f"\n## {name}\n  budget={budget:,} used={tokens:,} {json.dumps(stats, ensure_ascii=False)}")
            print(f"  cards per lecture: {row['cards_per_lecture']}")
            print(f"  navigator sees: {note}")

    out = HERE / "results" / f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_check_materials.json"
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print("\nsaved", out)


if __name__ == "__main__":
    asyncio.run(main())
