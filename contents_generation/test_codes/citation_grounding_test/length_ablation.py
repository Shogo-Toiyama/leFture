"""
回答が短くなった原因の切り分け(2026-10-03)。

本番の会話の「短くなった返答」を、当時とまったく同じ入力(出典・会話・見ていたページ・選択テキスト・
探索役のゴール)で、回答役のプロンプトだけを変えて何回か作り直し、長さを比べる。
  a: 今のプロンプト(区切りの引用 ⟦2.5⟧・LaTeXの禁止なし)
  b: リリース前のプロンプト(838e296: [n] の引用・LaTeXの禁止あり)。出典にも区切りの印 ‹n.k› を付けない
  c: a + 長さのルールに「確認・思い出しの質問でも説明は省かない」を足したもの(直し方の候補)

対象は本人のアカウントの返答だけ(build_cases.OWN_USER_ID)。結果は results/(gitignore)。
実行: python length_ablation.py --samples 3
"""

import argparse
import asyncio
import json
import statistics
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

TEST_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TEST_DIR))

import build_cases as bc  # noqa: E402  (backendへのパス・.envの読み込みもここで済む)
from app.core.supabase import get_supabase_client  # noqa: E402
from app.services import chat_materials  # noqa: E402
from app.services import chat_service as cs  # noqa: E402
from app.services.chat_lecture_source import DbLectureSource  # noqa: E402
from app.services.chat_map import load_student_map, resolve_timezone  # noqa: E402
from app.services.chat_navigator import NavigatorInput  # noqa: E402
from app.services.chat_screen import ScreenRef, ScreenSelection, load_screen_page  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, StreamState, UnifiedLLM  # noqa: E402

PROMPTS = "lefture_backend/app/services/prompts"
PRE_RELEASE_COMMIT = "838e296"
# 短くなった返答の、直前のuserメッセージの先頭(同じスレッド)
TARGET_THREAD_QUESTION = "こんなこと先生言ってたっけ"
TARGET_QUESTIONS = ["こんなこと先生言ってたっけ", "これは何だっけ", "こんなこと先生説明してたっけ", "実際どうやって説明されてるか"]

C_LENGTH_OLD = "without padding or repeating yourself"
C_LENGTH_NEW = "without padding"


def git_show(path: str, commit: str) -> str:
    return subprocess.run(["git", "show", f"{commit}:{path}"], cwd=bc.REPO_ROOT, capture_output=True, text=True, check=True).stdout


def variant_prompts() -> dict[str, dict[str, str]]:
    cur_answer = (bc.REPO_ROOT / PROMPTS / "chat_answer_prompt.txt").read_text()
    cur_turn = (bc.REPO_ROOT / PROMPTS / "chat_answer_turn_prompt.txt").read_text()
    assert C_LENGTH_OLD in cur_answer
    return {"a_current": {"chat_answer_prompt.txt": cur_answer, "chat_answer_turn_prompt.txt": cur_turn}}


async def load_turns(admin) -> list[dict]:
    """対象の返答ごとに、回答役に渡した入力を組み立て直す(対象の質問が複数のスレッドに分かれていてもよい)。"""
    tids = {admin.table("chat_messages").select("thread_id").eq("user_id", bc.OWN_USER_ID)
            .ilike("content", f"{q}%").limit(1).execute().data[0]["thread_id"] for q in TARGET_QUESTIONS}
    rows = [r for tid in tids for r in admin.table("chat_messages").select("*").eq("thread_id", tid)
            .eq("user_id", bc.OWN_USER_ID).order("created_at").execute().data]
    rows.sort(key=lambda r: r["created_at"])
    smap = load_student_map(admin, bc.OWN_USER_ID, resolve_timezone(None))
    blocked = cs._load_blocked_source_types(bc.OWN_USER_ID)
    source = DbLectureSource(admin, bc.OWN_USER_ID, blocked)
    profile = cs._load_student_profile(admin, bc.OWN_USER_ID)

    turns = []
    for i, row in enumerate(rows):
        if row["role"] != "user" or not any(row["content"].startswith(q) for q in TARGET_QUESTIONS):
            continue
        reply = rows[i + 1]
        usage, ctx = reply.get("usage") or {}, row.get("context") or {}
        lecture_id = ctx.get("lecture_id")
        nav_input = NavigatorInput(message=row["content"], selected_text=ctx.get("selected_text"),
                                   screen_lecture_id=lecture_id, recent_conversation=[], today=None,
                                   student_map=smap, blocked_source_types=blocked)
        materials, how = [], []
        for k in usage.get("materials") or []:
            m, h = await bc.rebuild_material(k["key"], k.get("handle"), nav_input, source, admin, {})
            how.append(h)
            if m is not None:
                materials.append(m)
        materials = bc.truncate_like_select(materials)
        screen = ctx.get("screen")
        page = None
        if screen:
            sel = ScreenSelection(ctx["selected_text"]) if ctx.get("selected_text") else None
            page = load_screen_page(admin, bc.OWN_USER_ID, ScreenRef(screen["kind"], screen.get("id"), screen.get("topic_number")),
                                    lecture_id, sel, blocked)
        turns.append({
            "question": row["content"],
            "stored_chars": len(reply["content"]),
            "history_rows": [{k: r[k] for k in ("role", "content", "status")} for r in rows[:i]],
            "turn": SimpleNamespace(
                lecture_label=cs._lecture_label(admin, lecture_id, bc.OWN_USER_ID) if lecture_id else None,
                selected_text=ctx.get("selected_text"), content=row["content"], screen_page=page),
            "reply_language": (reply.get("router") or {}).get("reply_language") or "ja",
            "goal": (usage.get("navigator") or {}).get("goal") or None,
            "materials": materials,
            "rebuilt": how,
            "profile": profile,
        })
    return turns


async def generate(llm, t: dict, prompts: dict[str, str], variant: str) -> dict:
    orig_load, orig_mark = cs._load_prompt, chat_materials.mark_units
    cs._load_prompt = lambda name: prompts.get(name) or orig_load(name)
    if variant == "b_pre_release":
        chat_materials.mark_units = lambda text, units, ref: text  # リリース前は区切りの印を付けていない
    try:
        history = cs.build_history_messages(t["history_rows"], cs.RAW_MAX_TURNS, cs.HISTORY_MAX_CHARS_PER_MESSAGE)
        messages = cs._build_answer_messages(t["turn"], SimpleNamespace(reply_language=t["reply_language"]),
                                             cs.ConversationMemory(), history, t["profile"], t["materials"], t["goal"])
    finally:
        cs._load_prompt, chat_materials.mark_units = orig_load, orig_mark
    state = StreamState()
    opts = LLMOptions(max_tokens=cs._answer_max_tokens(None, t["materials"]) + cs.ANSWER_THINKING_TOKENS,
                      reasoning_effort=cs.ANSWER_REASONING_EFFORT)
    async for _ in llm.generate_stream(cs.ANSWER_MODEL, messages, state, opts):
        pass
    return {"variant": variant, "chars": len(state.output_text), "output_tokens": state.output_tokens,
            "finish": state.finish_reason, "text": state.output_text}


def without(t: dict, what: str) -> dict:
    """入力を1つ外したターン(--inputs用)。"""
    t = dict(t)
    if what == "no_goal":
        t["goal"] = None
    elif what == "no_screen":
        t["turn"] = SimpleNamespace(**{**vars(t["turn"]), "screen_page": None})
    elif what == "no_history":
        t["history_rows"] = []
    return t


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=3)
    ap.add_argument("--inputs", action="store_true",
                    help="プロンプトは今のまま、入力(探索役のゴール・見ているページ・会話の履歴)を1つずつ外して比べる")
    args = ap.parse_args()

    admin = get_supabase_client()
    turns = await load_turns(admin)
    variants = variant_prompts()
    if args.inputs:
        # 各ターンを「入力を1つ外した版」に差し替え、プロンプトは a_current だけ使う
        current = variants["a_current"]
        variants = {"no_goal": current, "no_screen": current, "no_history": current}
    llm = UnifiedLLM(BillingEngine(task_type="length_ablation"))
    for t in turns:
        print(f"• {t['question'][:30]!r} stored={t['stored_chars']} materials={len(t['materials'])} "
              f"rebuilt={sorted(set(t['rebuilt']))} screen={t['turn'].screen_page.title if t['turn'].screen_page else None}")

    jobs = [(ti, v) for ti in range(len(turns)) for v in variants for _ in range(args.samples)]
    sem = asyncio.Semaphore(4)

    async def run(ti, v):
        async with sem:
            t = without(turns[ti], v) if args.inputs else turns[ti]
            return ti, await generate(llm, t, variants[v], v)

    results = await asyncio.gather(*(run(ti, v) for ti, v in jobs))

    print(f"\n{'question':34s} {'stored':>6s} " + " ".join(f"{v:>16s}" for v in variants))
    for ti, t in enumerate(turns):
        cells = []
        for v in variants:
            lens = [r["chars"] for i, r in results if i == ti and r["variant"] == v]
            cells.append(f"{statistics.median(lens):6.0f} {str(lens):>9s}"[:16].rjust(16))
        print(f"{t['question'][:30]!r:34s} {t['stored_chars']:6d} " + " ".join(cells))
    for v in variants:
        lens = [r["chars"] for _, r in results if r["variant"] == v]
        print(f"  {v:16s} median {statistics.median(lens):.0f} chars  (all {lens})")

    out = TEST_DIR / "results" / f"length_ablation_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps([{"question": turns[i]["question"], **r} for i, r in results], ensure_ascii=False, indent=1))
    print(f"\ncost ${llm.billing.total_usd():.4f}\n→ {out.relative_to(TEST_DIR)}")


if __name__ == "__main__":
    asyncio.run(main())
