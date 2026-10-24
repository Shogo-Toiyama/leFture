"""
実環境チャット再現評価スクリプト:
実在ユーザー (5be0566d-9b7a-499f-b7d2-f1c736fd5082) のコース・講義・会話コンテキストをDBから完全復元し、
新プロンプト・新ハンドル下での探索役 (Navigator) の挙動、周回数 (Laps)、取得材料を計測する。
"""

import asyncio
from datetime import date, timezone
import json
import os
from pathlib import Path
import sys
import time

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from supabase import create_client
from app.services.chat_map import load_student_map
from app.services.chat_lecture_source import DbLectureSource
from app.services.chat_navigator import (
    NavigatorInput, NavigatorTools, navigate, make_search, make_lecture_search, make_chat_search
)
from app.services.helpers.llm_unified import UnifiedLLM, BillingEngine
from app.services.chat_attachments import estimate_tokens

ADMIN_CLIENT = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
USER_ID = "5be0566d-9b7a-499f-b7d2-f1c736fd5082"


async def main():
    print("=" * 70)
    print("🚀 実環境チャット再現評価: 探索役 (Navigator) ベンチマーク開始")
    print(f"User ID: {USER_ID}")
    print("=" * 70)

    # 1. ユーザーの実環境 StudentMap をDBから復元
    student_map = load_student_map(ADMIN_CLIENT, USER_ID, timezone.utc)
    print("\n📚 復元されたコース地図:")
    for c in student_map.courses:
        dates = [l.date for l in c.lectures if l.date]
        span = f" ({min(dates)} - {max(dates)})" if dates else ""
        print(f"  [{c.handle}] {c.title} ({len(c.lectures)} lectures){span} id={c.id}")

    # コースハンドルの特定
    net_course = next((c for c in student_map.courses if "network" in c.title.lower()), None)
    prog_course = next((c for c in student_map.courses if "programming" in c.title.lower()), None)
    assert net_course is not None, "Network Fundamental course not found"
    assert prog_course is not None, "Programming Language course not found"

    print(f"\nTarget Course for Network tests: {net_course.handle} ({net_course.title})")
    print(f"Target Course for Haskell tests: {prog_course.handle} ({prog_course.title})")

    # 2. 評価ケース定義
    cases = [
        {
            "id": "case1_network_overview",
            "name": "Case 1: コース全体の徹底理解（実在ネットワーク Turn 32 再現）",
            "course": net_course.handle,
            "message": "最後、この授業を徹底理解したいです。",
            "screen_lecture_id": net_course.lectures[10].id if len(net_course.lectures) > 10 else None,
            "user_goal": "The student wants a comprehensive overview and deep understanding of the entire Network Fundamental course.",
            "expected_handle_prefix": f"{net_course.handle}/topics",
            "old_laps": 4,
            "old_stop_reason": "max_laps",
            "old_note": "13講義を個別に開きまくり、4周上限 (max_laps) で力尽きていた",
        },
        {
            "id": "case2_haskell_syllabus",
            "name": "Case 2: 講義トピックの一覧・総復習（実在Haskell Turn 1 再現）",
            "course": prog_course.handle,
            "message": "授業で習ったHaskellについて、総復習したい。まずはどんなことを習ったか、一覧で出して欲しい。",
            "screen_lecture_id": None,
            "user_goal": "The student wants a structured list and syllabus of all Haskell and functional programming topics covered in the course.",
            "expected_handle_prefix": f"{prog_course.handle}/topics",
            "old_laps": 3,
            "old_stop_reason": "enough_now",
            "old_note": "15単語の過剰セマンティック検索を行い、講義4と6を手探りで開いて3周消費していた",
        },
        {
            "id": "case3_exam_hints",
            "name": "Case 3: 教授の試験ヒント・アナウンス（新機能の本命検証）",
            "course": net_course.handle,
            "message": "この授業で教授がテストに出そうって言ったところや注意点ってどこ？",
            "screen_lecture_id": None,
            "user_goal": "The student wants to know test tips, professor hints, and warnings about exam-relevant topics mentioned in class.",
            "expected_handle_prefix": f"{net_course.handle}/announcements",
            "old_laps": "N/A",
            "old_stop_reason": "failed/general",
            "old_note": "以前はアナウンスメント専用ハンドルがなく、文字起こしを闇雲に探すか一般的な回答しかできなかった",
        },
        {
            "id": "case4_multi_lecture_cards",
            "name": "Case 4: 複数講義の要点＆落とし穴復習（実在ネットワーク Turn 28 発展）",
            "course": net_course.handle,
            "message": "前半（講義1から講義5）の重要ポイントと、テストで引っかかりやすい罠をまとめて",
            "screen_lecture_id": net_course.lectures[4].id if len(net_course.lectures) > 4 else None,
            "user_goal": "The student wants a review of Core Why principles and common gotcha pitfalls across lectures 1 to 5.",
            "expected_handle_prefix": f"{net_course.handle}/L1-5/cards",
            "old_laps": 4,
            "old_stop_reason": "max_laps",
            "old_note": "講義1〜5を個別に開きまくり、大量の本文テキストで枠を圧迫していた",
        },
        {
            "id": "case5_concept_search_regression",
            "name": "Case 5: 特定概念の深掘り検索（退行防止の確認・実在Turn 30）",
            "course": net_course.handle,
            "message": "RTS/CTS、NAV、hidden terminal problemのコンセプトを詳しく知りたい",
            "screen_lecture_id": net_course.lectures[9].id if len(net_course.lectures) > 9 else None,
            "user_goal": "The student wants an in-depth conceptual explanation of RTS/CTS, NAV, and hidden terminal problem in wireless MAC.",
            "expected_handle_prefix": "lecture.concept",
            "old_laps": 1,
            "old_stop_reason": "enough_now",
            "old_note": "全体ハンドルに誤爆せず、適切に概念検索へ行けるかの退行防止テスト",
        },
    ]

    # 3. 探索役ツールのセットアップ
    billing = BillingEngine(task_type="CHAT_MESSAGE")
    llm = UnifiedLLM(billing)
    source = DbLectureSource(ADMIN_CLIENT, USER_ID)

    # 検索用モック（今回のハンドルテストで必要最小限）
    async def dummy_search(reqs):
        return [[] for _ in reqs]

    tools = NavigatorTools(
        search=dummy_search,
        source=source,
        chat_source=None,
        web_search=None,
        link_fetch=None,
    )

    results = []

    for idx, case in enumerate(cases, start=1):
        print("\n" + "=" * 70)
        print(f"▶️ [{idx}/{len(cases)}] {case['name']}")
        print(f"  Input: \"{case['message']}\"")
        print(f"  Target Course: {case['course']}")
        print(f"  Old Behavior: {case['old_note']} (Laps: {case['old_laps']})")
        print("-" * 70)

        nav_input = NavigatorInput(
            message=case["message"],
            selected_text="",
            screen_lecture_id=case["screen_lecture_id"],
            recent_conversation=[],
            today=date(2026, 10, 24),
            student_map=student_map,
            user_goal=case["user_goal"],
        )

        t_start = time.perf_counter()
        nav_res = await navigate(llm, nav_input, tools)
        elapsed_sec = time.perf_counter() - t_start

        lap_count = len(nav_res.laps)
        stop_reason = nav_res.stop_reason
        lap1_requests = nav_res.laps[0].requests if nav_res.laps else []
        lap1_req_strs = [
            r.label() if hasattr(r, 'label') else str(r)
            for r in lap1_requests
        ]

        # 取得された Material の評価
        mats = nav_res.materials
        total_tokens = sum(estimate_tokens(m.content or "") for m in mats)

        print(f"  ⏱ Elapsed: {elapsed_sec:.2f}s | Laps: {lap_count} | Stop Reason: {stop_reason}")
        for l_idx, lap in enumerate(nav_res.laps, start=1):
            req_labels = [r.label() if hasattr(r, 'label') else str(r) for r in lap.requests]
            print(f"     Lap {l_idx} [{lap.status}]: {req_labels} (Reasoning: \"{lap.reasoning}\")")
        print(f"  📦 Materials Fetched: {len(mats)} items (~{total_tokens:,} tokens)")
        for m in mats:
            print(f"     - [{m.kind}] {m.label} ({estimate_tokens(m.content)} tokens)")
            # 冒頭スニペット
            lines = (m.content or "").strip().splitlines()[:3]
            for l in lines:
                print(f"       {l}")

        # 成否判定
        is_hit = False
        if case["expected_handle_prefix"] == "lecture.concept":
            is_hit = any("lecture.concept" in s for s in lap1_req_strs)
        else:
            is_hit = any(case["expected_handle_prefix"] in s for s in lap1_req_strs)

        status_str = "✅ PASS" if is_hit else "⚠️ DRIFT"
        print(f"  Result: {status_str} (Expected prefix: {case['expected_handle_prefix']})")

        results.append({
            "case": case,
            "lap_count": lap_count,
            "stop_reason": stop_reason,
            "lap1_requests": lap1_req_strs,
            "materials_count": len(mats),
            "total_tokens": total_tokens,
            "elapsed_sec": round(elapsed_sec, 2),
            "is_hit": is_hit,
            "materials_summary": [{"kind": m.kind, "label": m.label, "tokens": estimate_tokens(m.content)} for m in mats],
            "goal": nav_res.goal,
        })

    # 4. サマリーとレポート出力
    print("\n" + "=" * 70)
    print("📊 総合結果サマリー")
    print("=" * 70)
    print(f"全 {len(cases)} ケース中: {sum(1 for r in results if r['is_hit'])} / {len(cases)} 合格")
    for r in results:
        c = r["case"]
        old_l = str(c["old_laps"])
        new_l = str(r["lap_count"])
        req_str = ", ".join(r["lap1_requests"]) or "(none)"
        print(f"- {c['name'][:30]}: Laps {old_l} -> {new_l} | Lap1: {req_str} | {r['total_tokens']:,} tok | {'✅' if r['is_hit'] else '❌'}")

    out_json = REPO_ROOT / "contents_generation" / "test_codes" / "real_chat_hierarchical_eval_result.json"
    out_json.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n詳細データを保存しました: {out_json}")


if __name__ == "__main__":
    asyncio.run(main())
