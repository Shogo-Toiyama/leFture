"""
出典の根拠箇所テストのケースを、本番の「出典付きの返答」から作る(LLMは使わない)。

各ケース = 1つの返答。回答役がそのとき見ていた材料を、保存されている材料の一覧
(chat_messages.usage.materials の key、回答役に渡した順)から組み立て直す。
  - chunk:{id}        → knowledge_chunks の行(本番と同じ material_from_chunk)
  - topic / lecture / transcript → 本番と同じ open_handle(今の地図で呼び名を引き直す)
  - web:{url}         → 今取り直すと中身が変わるので、保存済みの出典プレビューで代用
その後、本番の select_materials と同じ長さの切り詰めを、保存されている順のままかける。

組み立て直しが正しいかは、保存済みの出典(番号・ラベル・本文の先頭1,500字)と照合して
ケースごとに記録する(ずれた出典は run_eval.py で集計から外す)。

対象は本人のアカウント(lefture.app@gmail.com)だけ。本番の会話そのものなので、
cases/ と results/ は git に入れない(.gitignore)。

実行: python build_cases.py [--limit N]
"""

import argparse
import asyncio
import json
import sys
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
REPO_ROOT = TEST_DIR.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.core.supabase import get_supabase_client  # noqa: E402
from app.services import chat_service as cs  # noqa: E402
from app.services.chat_lecture_source import DbLectureSource  # noqa: E402
from app.services.chat_map import load_student_map, resolve_timezone  # noqa: E402
from app.services.chat_materials import (  # noqa: E402
    MATERIAL_MAX_CHARS,
    MATERIALS_MAX_CHARS,
    MATERIALS_MAX_ITEMS,
    Material,
    material_from_chunk,
    numbered,
)
from app.services.chat_navigator import NavigatorInput, open_handle  # noqa: E402

OWN_USER_ID = "5be0566d-9b7a-499f-b7d2-f1c736fd5082"  # lefture.app@gmail.com(本人。2026-10-02確認)
CASES_PATH = TEST_DIR / "cases" / "cases.json"
SNIPPET_CHARS = 1500  # Material.citation() のプレビューの長さ


def truncate_like_select(materials: list[Material]) -> list[Material]:
    """select_materials の切り詰めだけを、並べ替えずにかける(保存されている順が回答役に渡した順)。"""
    out, used = [], 0
    for m in materials[:MATERIALS_MAX_ITEMS]:
        room = MATERIALS_MAX_CHARS - used
        limit = min(MATERIAL_MAX_CHARS, room)
        if len(m.content) > limit:
            m.content = m.content[:limit].rstrip() + " …"
        out.append(m)
        used += len(m.content) + len(m.label)
    return out


async def rebuild_material(key: str, handle: str, nav_input: NavigatorInput, source, admin_client,
                           stored_by_key: dict) -> tuple[Material | None, str]:
    """1つの材料を組み立て直す。返り値の2つ目は取り方(記録用)。"""
    kind, _, rest = key.partition(":")
    if kind == "chunk":
        res = admin_client.table("knowledge_chunks").select("*").eq("id", rest).maybe_single().execute()
        row = res.data if res else None
        return (material_from_chunk(row, handle=handle), "chunk") if row else (None, "chunk_missing")
    if kind == "web":
        cited = stored_by_key.get(key)
        m = Material(key=key, kind="web", label=cited["label"] if cited else rest, url=rest,
                     content=(cited or {}).get("snippet") or "(page text unavailable in this test)",
                     source_type="web")
        return m, "web_snippet" if cited else "web_missing"
    smap = nav_input.student_map
    if kind == "topic":
        lec_id, idx = rest.rsplit(":", 1)
        h = smap.lecture_handle(lec_id)
        h = f"{h}/T{idx}" if h else None
    elif kind == "transcript":
        lec_id, rng = rest.rsplit(":", 1)
        a, b = rng.split("-")
        h = smap.lecture_handle(lec_id)
        h = (f"{h}/s{a}" if a == b else f"{h}/s{a}-{b}") if h else None
    elif kind == "lecture":
        h = smap.lecture_handle(rest)
    else:
        return None, f"unsupported:{kind}"
    if not h:
        return None, "handle_missing"
    opened = await open_handle(h, nav_input, source)
    return (opened.material, "opened") if opened.material else (None, "open_failed")


def snippet_matches(stored: str, rebuilt: str) -> bool:
    """保存済みのプレビュー(本文の先頭1,500字+…)と、組み立て直した本文の先頭が一致するか。"""
    s = (stored or "").strip()
    if s.endswith("…"):
        s = s[:-1]
    return rebuilt.strip()[:len(s)] == s


async def build_case(admin_client, row: dict, smap, blocked: frozenset[str]) -> dict:
    usage = row.get("usage") or {}
    keys = usage.get("materials") or []
    stored_by_n = {str(c["n"]): c for c in row.get("citations") or []}

    # その返答の直前のuserメッセージと、それより前の会話(本番と同じ往復の組み方)
    thread = admin_client.table("chat_messages").select("id, role, content, status, created_at, context") \
        .eq("thread_id", row["thread_id"]).is_("deleted_at", "null") \
        .lt("created_at", row["created_at"]).order("created_at").execute().data or []
    user_row = next((r for r in reversed(thread) if r["role"] == "user"), None)
    history_rows = thread[:thread.index(user_row)] if user_row else thread
    user_ctx = (user_row or {}).get("context") or {}
    lecture_label = cs._lecture_label(admin_client, user_ctx["lecture_id"], OWN_USER_ID) if user_ctx.get("lecture_id") else None

    nav_input = NavigatorInput(
        message=(user_row or {}).get("content", ""), selected_text=user_ctx.get("selected_text"),
        screen_lecture_id=user_ctx.get("lecture_id"), recent_conversation=[], today=None,
        student_map=smap, blocked_source_types=blocked,
    )
    source = DbLectureSource(admin_client, OWN_USER_ID, blocked)

    # web の材料は、保存済みの出典のうちラベル/URLが一致するものでプレビューを引く
    stored_web = {f"web:{c.get('url')}": c for c in row.get("citations") or [] if c.get("source_type") == "web"}
    materials, how = [], []
    for k in keys:
        m, h = await rebuild_material(k["key"], k.get("handle"), nav_input, source, admin_client, stored_web)
        how.append(h)
        if m is not None:
            materials.append(m)
    materials = truncate_like_select(materials)

    # 照合: 保存済みの出典(番号→ラベル・プレビュー)と、組み立て直した番号付きの材料
    checks = {}
    rebuilt_by_n = {str(n): m for n, m in numbered(materials)}
    for n, c in stored_by_n.items():
        m = rebuilt_by_n.get(n)
        checks[n] = {
            "label_ok": bool(m) and m.label == c["label"],
            "content_ok": bool(m) and snippet_matches(c.get("snippet") or "", m.content),
            "source_type": c["source_type"],
        }

    nav = usage.get("navigator") or {}
    return {
        "message_id": row["id"],
        "thread_id": row["thread_id"],
        "created_at": row["created_at"],
        "question": (user_row or {}).get("content", ""),
        "selected_text": user_ctx.get("selected_text"),
        "lecture_label": lecture_label,
        "reply_language": (row.get("router") or {}).get("reply_language") or "ja",
        "goal": nav.get("goal") or None,
        "history_rows": [{k: r[k] for k in ("role", "content", "status")} for r in history_rows],
        "answer": row["content"],
        "stored_citations": row.get("citations") or [],
        "materials": [
            {"n": str(n), "key": m.key, "kind": m.kind, "label": m.label, "content": m.content,
             "source_type": m.source_type, "url": m.url}
            for n, m in numbered(materials)
        ],
        "rebuild": {"how": how, "checks": checks,
                    "all_cited_ok": all(c["label_ok"] and c["content_ok"] for c in checks.values())},
        "baseline_output_tokens": usage.get("answer_output_tokens"),
    }


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args()

    admin_client = get_supabase_client()
    rows = admin_client.table("chat_messages").select("*") \
        .eq("user_id", OWN_USER_ID).eq("role", "assistant").eq("status", "complete") \
        .neq("citations", "[]").is_("deleted_at", "null").order("created_at").execute().data or []
    if args.limit:
        rows = rows[-args.limit:]
    smap = load_student_map(admin_client, OWN_USER_ID, resolve_timezone(None))
    blocked = cs._load_blocked_source_types(OWN_USER_ID)

    cases = []
    for row in rows:
        case = await build_case(admin_client, row, smap, blocked)
        cases.append(case)
        bad = [n for n, c in case["rebuild"]["checks"].items() if not (c["label_ok"] and c["content_ok"])]
        print(f"{row['id'][:8]} materials={len(case['materials'])} how={sorted(set(case['rebuild']['how']))} "
              f"cited={len(case['rebuild']['checks'])} mismatched={bad or '-'}")

    CASES_PATH.parent.mkdir(exist_ok=True)
    CASES_PATH.write_text(json.dumps(cases, ensure_ascii=False, indent=1))
    ok = sum(c["rebuild"]["all_cited_ok"] for c in cases)
    print(f"\n{len(cases)} cases → {CASES_PATH.relative_to(TEST_DIR)} (fully rebuilt: {ok})")


if __name__ == "__main__":
    asyncio.run(main())
