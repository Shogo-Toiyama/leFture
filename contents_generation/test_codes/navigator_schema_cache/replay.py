"""
探索役(Navigator)のスキーマ固定実験。

問題: build_schema が周ごとに変わる(open の handle enum = openable_handles が「開いたものを除く・検索で
出たものを足す」ので毎周変わる。find の target も検索の残り回数で変わる)。Anthropic の structured outputs は
output format が変わるとプロンプトキャッシュが無効になるため、system(約8.4k)を毎周キャッシュに書き込むだけで
読めていない(2026-11-06 「不変データ構造」スレッド最終ターン: 4周とも cache_read=0、7.25クレジット)。

試すこと: 1ターンの中で変わらないスキーマ(handle は自由な文字列、target は残り回数に関係なく固定)にして、
  1. 2周目以降(と同じターンを2回目に流したときの1周目)で cache_read が出るか
  2. enum が無くなって、開けない handle を出して捨てられる(handle_not_openable)ことが増えないか
を本番の部品で同じターンを再現して確かめる。開けるかどうかのチェックは本番の validate_operations のまま。

使い方:
  .venv/bin/python contents_generation/test_codes/navigator_schema_cache/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/navigator_schema_cache/replay.py --variant static --runs 2
"""

import argparse
import asyncio
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from supabase import ClientOptions, create_client

from app.services import chat_navigator as nav
from app.services import chat_service as cs
from app.services.chat_lecture_source import DbLectureSource
from app.services.chat_map import load_chat_map, load_student_map
from app.services.chat_summary import extract_source_turns_to_fetch, fetch_active_blocks, rows_after_fold_point
from app.services.chat_thread_source import DbChatThreadSource
from app.services.helpers.credits import CHAT_CREDIT_MARKUP, CREDITS_PER_USD
from app.services.helpers.llm_unified import BillingEngine, LLMResult, UnifiedLLM
from app.services.knowledge_index import embed_queries
from app.services.logic.web_search import brave_search

OUT_DIR = Path(__file__).resolve().parent / "results"

# 2026-11-06 「不変データ構造」スレッドの最終ターン(7.25クレジット)
THREAD_ID = "886879bc-3721-4c68-9ffd-df42021d77fa"
USER_MESSAGE_ID = "4fede6e4-6c30-4f13-87e4-175c51b9e507"
ASSISTANT_MESSAGE_ID = "2aebec6e-b6a8-4343-abbc-9b3fc39ab781"

PRODUCTION_BUILD_SCHEMA = nav.build_schema


# =========================================================
# 変える部分: 1ターンの中で変わらないスキーマ
# =========================================================

def build_schema_static(nav_input: nav.NavigatorInput, state: nav.NavState) -> dict[str, Any]:
    """本番の build_schema から、周ごとに変わる部分(state に依存する部分)だけを取り除いたもの。
    - open.handle: openable_handles の enum → 自由な文字列(開けるかは validate_operations が判定)
    - find.target: 検索の残り回数で減らさない(上限は validate_operations の search_limit / web_search_limit)
    - open の形: 開けるものが無くても常に残す
    scope(within)・layer・資料の検索の有無は1ターンの中で変わらないので、本番のまま。"""
    def enum(values: list[str]) -> dict[str, Any]:
        return {"type": "string", "enum": values} if values else {"type": "string"}

    scope = nav_input.student_map.scope_handles()
    op_shapes: list[dict[str, Any]] = []
    targets = nav.available_targets()
    if not nav_input.attachment_scope_handles():
        targets = [t for t in targets if t != "attachment.search"]
    if targets:
        op_shapes.append({"type": "object", "properties": {
            "op": {"type": "string", "enum": ["find"]},
            "target": enum(targets),
            "query": {"type": "string"},
            "layer": enum(nav.available_layers(nav_input.blocked_source_types)),
            "within": enum(scope),
        }, "required": ["op", "target", "query"]})
    if nav.CAPABILITIES["CAN_OPEN"]:
        op_shapes.append({"type": "object", "properties": {
            "op": {"type": "string", "enum": ["open"]},
            "handle": {"type": "string"},
        }, "required": ["op", "handle"]})
    if nav.CAPABILITIES["CAN_BY_DATE"]:
        op_shapes.append({"type": "object", "properties": {
            "op": {"type": "string", "enum": ["by_date"]},
            "date_from": {"type": "string"},
            "date_to": {"type": "string"},
            "within": enum(scope),
        }, "required": ["op", "date_from", "date_to"]})
    return {
        "type": "object",
        "properties": {
            "reasoning": {"type": "string"},
            "need": {"type": "string", "enum": nav.NEEDS},
            "fetch_from": {"type": "array", "items": {"type": "string", "enum": nav.available_fetch_sources()}},
            "status": {"type": "string", "enum": nav.STATUSES},
            "missing": {"type": "string"},
            "operations": {"type": "array", "items": {"anyOf": op_shapes} if op_shapes else {"type": "object"}},
            "goal": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["reasoning", "need", "fetch_from", "status", "missing", "operations", "goal"],
    }


def schema_hash(schema: dict) -> str:
    return hashlib.sha256(json.dumps(schema, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:12]


# =========================================================
# 本番と同じ入力を組み立てる(chat_service.run_chat_turn / _gather_materials と同じ部品)
# =========================================================

def user_jwt(admin, user_id: str) -> str:
    """search_knowledge_chunks は本人のJWT(auth.uid())で絞るので、本人のセッションを作る(メールは送られない)。"""
    email = admin.auth.admin.get_user_by_id(user_id).user.email
    link = admin.auth.admin.generate_link({"type": "magiclink", "email": email})
    auth_client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    res = auth_client.auth.verify_otp({"type": "magiclink", "token_hash": link.properties.hashed_token})
    return res.session.access_token, auth_client


async def build_turn(admin):
    user_row = admin.table("chat_messages").select("*").eq("id", USER_MESSAGE_ID).execute().data[0]
    asst_row = admin.table("chat_messages").select("router, usage").eq("id", ASSISTANT_MESSAGE_ID).execute().data[0]
    user_id = user_row["user_id"]
    turn_at = user_row["created_at"]

    # 履歴: そのターンを送った時点までの行(今の質問は含まない。本番は質問の行を書く前に読む)
    rows = [r for r in cs._fetch_history_rows(admin, THREAD_ID) if r["created_at"] < turn_at]
    blocks = [b for b in fetch_active_blocks(admin, THREAD_ID) if b["end_message_created_at"] < turn_at]
    level2 = [b for b in fetch_active_blocks(admin, THREAD_ID, 2) if b["end_message_created_at"] < turn_at]
    history_rows = rows_after_fold_point(rows, blocks[-1]["end_message_id"] if blocks else None)
    history = cs.build_history_messages(history_rows, cs.RAW_MAX_TURNS, None, {})

    active_header = blocks[-1].get("header") if blocks else None
    source_turns = extract_source_turns_to_fetch(active_header)
    referenced_sources = (await cs._fetch_referenced_source_turns(admin, THREAD_ID, source_turns)) if source_turns else ""

    tz = timezone.utc  # 送信時のタイムゾーンは保存されていない(現在時刻の1行だけに効く)
    student_map = load_student_map(admin, user_id, tz)
    recent = await DbChatThreadSource(admin, user_id).recent_threads_with_trail(THREAD_ID, 20)
    chat_map = load_chat_map(blocks, recent, level2)
    blocked = cs._load_blocked_source_types(user_id)
    now = datetime.fromisoformat(turn_at).astimezone(tz)

    nav_input = nav.NavigatorInput(
        message=user_row["content"],
        selected_text=None,
        screen_lecture_id=(user_row.get("context") or {}).get("lecture_id"),
        recent_conversation=history,
        today=now.date(),
        student_map=student_map,
        current_time_str=now.strftime("%Y-%m-%d (%a) %H:%M"),
        chat_map=chat_map,
        current_thread_id=THREAD_ID,
        previous_turn_refs=cs._previous_turn_refs(history_rows),
        blocked_source_types=blocked,
        screen_topic_index=None,  # 画面のトピック番号は保存されていない
        screen_page_title=None,
        screen_page_excerpt=None,
        attachments=[],  # このスレッドの資料は failed の1件だけ(本番でも使われない)
        attachment_visibility=None,
        must_check_attachments=False,
        links=[],
        user_goal=(asst_row.get("router") or {}).get("user_goal"),
        referenced_sources=referenced_sources,
    )
    info = {"user_id": user_id, "turn_at": turn_at, "history_rows": len(history_rows), "summary_blocks": len(blocks),
            "previous_turn_refs": nav_input.previous_turn_refs, "blocked": sorted(blocked),
            "user_goal": nav_input.user_goal, "referenced_sources_chars": len(referenced_sources)}
    return nav_input, info


def build_tools(admin, user_client, nav_input, billing: BillingEngine, dry_run: bool) -> nav.NavigatorTools:
    async def embed(qs):
        return await embed_queries(qs, billing=billing)

    if dry_run:
        async def search(reqs):
            return [[] for _ in reqs]
    else:
        search = nav.make_search(
            nav.make_lecture_search(user_client, nav_input.student_map, embed, nav_input.blocked_source_types),
            nav.make_chat_search(user_client, THREAD_ID, embed),
        )
    return nav.NavigatorTools(
        search=search,
        source=DbLectureSource(admin, _USER_ID[0], nav_input.blocked_source_types),
        chat_source=DbChatThreadSource(admin, _USER_ID[0]),
        web_search=(lambda q: brave_search(q, billing)) if not dry_run else None,
        link_fetch=None,
    )


_USER_ID: list[str] = [""]


# =========================================================
# LLMの呼び出しを記録する(周ごとのスキーマ・キャッシュ・時間)
# =========================================================

class RecordingLLM:
    def __init__(self, inner, calls: list[dict]):
        self.inner = inner
        self.calls = calls

    async def generate(self, model, messages, options):
        t = time.perf_counter()
        result: LLMResult = await self.inner.generate(model, messages, options)
        self.calls.append({
            "schema_hash": schema_hash(options.json_schema),
            "system_chars": len(messages[0].content),
            "user_chars": len(messages[1].content),
            "input_tokens": result.input_tokens,
            "cache_read_tokens": result.cache_read_tokens,
            "cache_write_tokens": result.cache_write_tokens,
            "output_tokens": result.output_tokens,
            "latency_ms": round((time.perf_counter() - t) * 1000),
        })
        return result


class MockLLM:
    """ドライラン用: 本番の周回(find → open → open → enough_now)を真似た出力を返す。APIは呼ばない。"""
    def __init__(self, nav_input: nav.NavigatorInput):
        lec = nav_input.student_map.lecture_handle(nav_input.screen_lecture_id) or "C1"
        course = lec.split("/")[0]
        self.script = [
            {"op": "find", "target": "lecture.concept", "query": "Go interface implicit satisfaction", "within": course},
            {"op": "open", "handle": lec},
            {"op": "open", "handle": f"{lec}/cards"},
            None,
        ]
        self.i = 0

    async def generate(self, model, messages, options):
        op = self.script[min(self.i, len(self.script) - 1)]
        self.i += 1
        out = {"reasoning": "mock", "need": "explicit", "fetch_from": ["class"],
               "status": "need_more" if op else "enough_now", "missing": "", "operations": [op] if op else [],
               "goal": [] if op else ["mock goal"]}
        return LLMResult(output_text=json.dumps(out), output_json=out, model_used=model)


# =========================================================
# 実行
# =========================================================

def summarize_run(result: nav.NavigationResult, calls: list[dict], billing: BillingEngine, wall_ms: int) -> dict:
    nav_cost = sum(r.cost_usd for r in billing.records if r.resource == nav.NAVIGATOR_MODEL)
    other_cost = sum(r.cost_usd for r in billing.records if r.dimension == "tokens" and r.resource != nav.NAVIGATOR_MODEL)
    laps = []
    for lap, call in zip(result.laps, calls):
        laps.append({
            "lap": lap.lap, "status": lap.status, "need": lap.need,
            "requests": [nav_requests_repr(r) for r in lap.requests],
            "dropped": lap.dropped, "missing": lap.missing, "reasoning": lap.reasoning,
            "goal": lap.goal, "llm_error": lap.llm_error, **call,
        })
    return {
        "stop_reason": result.stop_reason,
        "laps": laps,
        "materials": [m.key for m in result.materials],
        "navigator_cost_usd": nav_cost,
        "other_cost_usd": other_cost,
        "navigator_credits": nav_cost * CHAT_CREDIT_MARKUP * CREDITS_PER_USD,
        "dropped_handle_not_openable": sum(1 for l in result.laps for d in l.dropped
                                           if d.get("reason") == "handle_not_openable"),
        "wall_ms": wall_ms,
    }


def nav_requests_repr(r) -> dict:
    d = {"kind": type(r).__name__}
    for k in ("target", "query", "within", "handle", "date_from", "date_to"):
        if hasattr(r, k):
            d[k] = str(getattr(r, k))
    return d


async def run_once(admin, user_client, nav_input, variant: str, dry_run: bool) -> dict:
    nav.build_schema = build_schema_static if variant == "static" else PRODUCTION_BUILD_SCHEMA
    billing = BillingEngine(task_type="CHAT_MESSAGE")
    calls: list[dict] = []
    inner = MockLLM(nav_input) if dry_run else UnifiedLLM(billing)
    llm = RecordingLLM(inner, calls)
    tools = build_tools(admin, user_client, nav_input, billing, dry_run)

    # 周ごとに、本番のスキーマと固定スキーマの両方のハッシュも残す(実際に送ったのは variant の方)
    hashes: list[dict] = []
    orig_decide = nav.decide_lap

    async def decide_lap_logged(llm_, nav_input_, state, lap, metrics=None):
        hashes.append({"lap": lap, "production": schema_hash(PRODUCTION_BUILD_SCHEMA(nav_input_, state)),
                       "static": schema_hash(build_schema_static(nav_input_, state)),
                       "openable_count": len(nav.openable_handles(nav_input_, state))})
        return await orig_decide(llm_, nav_input_, state, lap, metrics)

    nav.decide_lap = decide_lap_logged
    t0 = time.perf_counter()
    try:
        result = await nav.navigate(llm, nav_input, tools)
    finally:
        nav.decide_lap = orig_decide
        nav.build_schema = PRODUCTION_BUILD_SCHEMA
    summary = summarize_run(result, calls, billing, round((time.perf_counter() - t0) * 1000))
    summary["schema_hashes"] = hashes
    return summary


def check_search_auth(user_client) -> int:
    """JWTで検索RPCが本人の行を返すか(埋め込みAPIは呼ばない。ダミーのベクトルで並び順は無意味)。"""
    res = user_client.rpc("search_knowledge_chunks",
                          {"query_embedding": [0.001] * 768, "match_count": 3}).execute()
    return len(res.data or [])


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=["production", "static"], default="static")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    admin = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    nav_input, info = await build_turn(admin)
    _USER_ID[0] = info["user_id"]
    print("turn:", json.dumps(info, ensure_ascii=False, default=str))

    token, auth_client = user_jwt(admin, info["user_id"])
    user_client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"],
                                options=ClientOptions(headers={"Authorization": f"Bearer {token}"}))
    try:
        print("search auth check: rows =", check_search_auth(user_client))
        system_prompt = nav.build_system_prompt(nav_input.can_transcript)
        print(f"system prompt: {len(system_prompt)} chars")

        variants = ["production", "static"] if args.dry_run else [args.variant]
        runs = []
        for variant in variants:
            for i in range(args.runs):
                s = await run_once(admin, user_client, nav_input, variant, args.dry_run)
                s.update(variant=variant, run=i + 1)
                runs.append(s)
                print(f"\n== {variant} run {i + 1}: stop={s['stop_reason']} wall={s['wall_ms']}ms "
                      f"nav=${s['navigator_cost_usd']:.5f} ({s['navigator_credits']:.2f} cr) "
                      f"dropped_not_openable={s['dropped_handle_not_openable']}")
                for h in s["schema_hashes"]:
                    print(f"   lap{h['lap']} schema prod={h['production']} static={h['static']} openable={h['openable_count']}")
                for l in s["laps"]:
                    print(f"   lap{l['lap']} {l['status']:<11} sent={l['schema_hash']} in={l['input_tokens']} "
                          f"read={l['cache_read_tokens']} write={l['cache_write_tokens']} out={l['output_tokens']} "
                          f"{l['latency_ms']}ms req={l['requests']} dropped={l['dropped']}")
    finally:
        auth_client.auth.sign_out()  # 実験用に作ったセッションを消す

    OUT_DIR.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    name = f"{stamp}_{'dryrun' if args.dry_run else args.variant}.json"
    (OUT_DIR / name).write_text(json.dumps({"turn": info, "runs": runs}, ensure_ascii=False, indent=1, default=str),
                                encoding="utf-8")
    print(f"\nsaved: {OUT_DIR / name}")


if __name__ == "__main__":
    asyncio.run(main())
