"""
探索役(docs/chatbot_context_and_retrieval_roadmap.md ステップ3〜4、3-14)の評価ハーネス。

本番の探索役のコード(lefture_backend/app/services/chat_navigator.py)をそのまま呼ぶ。
プロンプト・JSON Schema・入力の組み立て・操作の検証はすべて本番のもの。差し替えるのは
データの出どころだけで、DBの代わりに台本の世界(cases/world.json)から返す。

- 各周の状態(開いたもの・検索結果・これまでの経過)は台本から作り、本番のdecide_lapを
  1回だけ呼ぶ(前の周は正しかったとして次の周を評価する)。開いた中身は本番のopen_handleで
  組み立てるので、探索役が見る文章も本番と同じ。
- 今使えない操作(CAPABILITIESがオフのチャット・Web)が要る周は採点しない。正解の候補から
  使えない操作を含むものを外し、候補が残らない周は飛ばす。
- 採点のルールはrun_eval_legacy.pyと同じ(README.md)。

実行: python run_eval.py [--set main|holdout|all] [--only case_id ...]
結果: results/prod_<日時>.json
"""

import argparse
import asyncio
import json
import re
import sys
import time
from datetime import date, datetime
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services import chat_navigator as nav  # noqa: E402
from app.services.chat_map import ChatGroup, ChatMap, ChatSection, ChatThreadRef, MapCourse, MapLecture, StudentMap  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, Message, UnifiedLLM  # noqa: E402

TEST_DIR = Path(__file__).resolve().parent
CASES_DIR = TEST_DIR / "cases"
RESULTS_DIR = TEST_DIR / "results"

WORLD = json.loads((CASES_DIR / "world.json").read_text(encoding="utf-8"))
CASES = json.loads((CASES_DIR / "cases.json").read_text(encoding="utf-8"))

sys.path.insert(0, str(TEST_DIR))
from run_eval_legacy import cumulative_steps, score  # noqa: E402


# =====================================================================
# 🌍 台本の世界 → 本番の地図とデータの出どころ
# =====================================================================

def build_student_map() -> StudentMap:
    courses = []
    for c in WORLD["courses"]:
        mc = MapCourse(handle=c["handle"], id=f"course-{c['handle']}", title=c["title"], term=c["term"],
                       recorded_language=c.get("recorded_language", "en"), notes_language=c.get("notes_language", "en"))
        for lec in c["lectures"]:
            mc.lectures.append(MapLecture(handle=lec["handle"], id=f"lec-{lec['handle']}", course_handle=c["handle"],
                                          title=lec["title"], date=date.fromisoformat(lec["date"])))
        courses.append(mc)
    return StudentMap.build(courses)


STUDENT_MAP = build_student_map()
LECTURE = {lec["handle"]: lec for c in WORLD["courses"] for lec in c["lectures"]}
COURSE_TITLE = {c["handle"]: c["title"] for c in WORLD["courses"]}


def _lecture_handle_of(lecture_id: str) -> str:
    return lecture_id.removeprefix("lec-")


def _split_sentences(text: str) -> list[str]:
    return [s.strip() for s in re.split(r"(?<=[.!?。！？])\s+", text) if s.strip()]


class WorldLectureSource:
    """本番のDbLectureSourceと同じ形のデータを、台本の世界から返す。"""

    async def lecture_summaries(self, lecture_ids: list[str]) -> dict[str, str]:
        return {i: LECTURE[_lecture_handle_of(i)]["summary"] for i in lecture_ids if _lecture_handle_of(i) in LECTURE}

    async def lecture_topics(self, lecture_id: str) -> list[dict]:
        lec = LECTURE.get(_lecture_handle_of(lecture_id))
        if not lec:
            return []
        return [{"id": f"topic-{t['handle']}", "index": int(t["handle"].rsplit("/T", 1)[1]), "title": t["title"],
                 "summary": t["summary"], "topic_type": "ACADEMIC"} for t in lec["topics"]]

    async def topic_detail(self, lecture_id: str, index: int) -> Optional[dict]:
        lec = LECTURE.get(_lecture_handle_of(lecture_id))
        t = next((t for t in (lec or {}).get("topics", []) if t["handle"].endswith(f"/T{index}")), None)
        if not t:
            return None
        return {"id": f"topic-{t['handle']}", "index": index, "title": t["title"], "summary": t["summary"],
                "topic_type": "ACADEMIC", "keywords": [(k, "") for k in t["keywords"]], "deep_note": t["deep_note"] or None}

    async def transcript(self, lecture_id: str) -> list[dict]:
        """台本の文字起こしは範囲ごとの文章なので、範囲の文番号に文を順に割り当てる。"""
        lec_h = _lecture_handle_of(lecture_id)
        out = []
        for h, text in WORLD["transcripts"].items():
            if not h.startswith(lec_h + "/s"):
                continue
            a, b = (int(x) for x in h.rsplit("/s", 1)[1].split("-"))
            sents = _split_sentences(text)
            for i, sid in enumerate(range(a, b + 1)):
                out.append({"sid": sid, "text": sents[i] if i < len(sents) else ""})
            if len(sents) > b - a + 1:
                out[-1]["text"] = " ".join(sents[b - a:])
        return sorted(out, key=lambda s: s["sid"])

    async def topic_indexes(self, topic_ids: list[str]) -> dict[str, tuple[str, int]]:
        out = {}
        for tid in topic_ids:
            h = tid.removeprefix("topic-")
            if "/T" in h:
                lec_h, idx = h.rsplit("/T", 1)
                out[tid] = (f"lec-{lec_h}", int(idx))
        return out


SOURCE = WorldLectureSource()


# ---------------------------------------------------------------------
# チャット: 台本の世界には往復の原文が無く、節の箇条書きだけがあるので、箇条書きを往復に見立てる
# (1箇条 = 1往復)。今の会話(thread_code / thread_career)は台本の節の往復番号をそのまま使い、
# 直前の会話を後ろの(まだ畳んでいない)往復として足す。
# ---------------------------------------------------------------------
CURRENT_THREAD_ID = "thread-current"
CHATS = {ch["handle"]: ch for ch in WORLD["recent_chats"] + WORLD["older_chats"]}


def _chat_thread_id(p_handle: str) -> str:
    return f"thread-{p_handle}"


def _past_chat_turns_and_sections(chat: dict) -> tuple[list[dict], list[dict]]:
    turns, sections = [], []
    for i, sec in enumerate(chat["sections"], start=1):
        numbers = []
        for b in sec["bullets"]:
            n = len(turns) + 1
            turns.append({"number": n, "user_content": f"({sec['title']})", "assistant_content": b, "created_at": chat["date"]})
            numbers.append(n)
        sections.append({"handle": i, "title": sec["title"], "bullets": sec["bullets"], "turns": numbers})
    if not turns:
        turns.append({"number": 1, "user_content": chat["title"], "assistant_content": f"(A chat about: {chat['title']})",
                      "created_at": chat["date"]})
    return turns, sections


def _current_thread_turns(case: dict) -> list[dict]:
    turns = []
    if case["thread"]:
        for sec in WORLD["threads"][case["thread"]]["sections"]:
            for i, n in enumerate(sec["turns"]):
                turns.append({"number": n, "user_content": f"({sec['title']})",
                              "assistant_content": sec["bullets"][min(i, len(sec["bullets"]) - 1)], "created_at": WORLD["today"]})
        conv = WORLD["threads"][case["thread"]]["recent_conversation"]
    else:
        conv = case["recent_conversation"]
    n = max((t["number"] for t in turns), default=0)
    for i in range(0, len(conv) - 1, 2):
        n += 1
        turns.append({"number": n, "user_content": conv[i][1], "assistant_content": conv[i + 1][1], "created_at": WORLD["today"]})
    return sorted(turns, key=lambda t: t["number"])


class WorldChatSource:
    """本番のDbChatThreadSourceと同じ形のデータを、台本の世界から返す(1ケース分)。"""

    def __init__(self, case: dict):
        self._case = case

    async def thread_meta(self, thread_id: str) -> Optional[dict]:
        ch = CHATS.get(thread_id.removeprefix("thread-"))
        return {"title": ch["title"], "date": ch["date"]} if ch else None

    async def thread_turns(self, thread_id: str) -> list[dict]:
        if thread_id == CURRENT_THREAD_ID:
            return _current_thread_turns(self._case)
        ch = CHATS.get(thread_id.removeprefix("thread-"))
        return _past_chat_turns_and_sections(ch)[0] if ch else []

    async def thread_sections(self, thread_id: str) -> list[dict]:
        ch = CHATS.get(thread_id.removeprefix("thread-"))
        return _past_chat_turns_and_sections(ch)[1] if ch else []

    async def thread_groups(self, thread_id: str) -> list[dict]:
        return []  # 台本の過去のチャットは短い(2段目が無い)

    async def recent_threads_with_trail(self, exclude_thread_id: Optional[str], limit: int) -> list[dict]:
        return []  # 地図はbuild_chat_mapで直接作る


def build_chat_map(case: dict) -> ChatMap:
    sections, groups = [], []
    if case["thread"]:
        sections = [ChatSection(handle=sec["handle"], title=sec["title"], turns=sec["turns"], bullets=sec["bullets"])
                    for sec in WORLD["threads"][case["thread"]]["sections"]]
        children_turns = {sec["handle"]: sec["turns"] for sec in WORLD["threads"][case["thread"]]["sections"]}
        groups = [ChatGroup(handle=g["handle"], title=g["title"], bullets=g["bullets"], children=g["children"],
                            turns=sorted(t for c in g["children"] for t in children_turns[c]))
                  for g in WORLD["threads"][case["thread"]].get("groups", [])]
    recent = [ChatThreadRef(handle=ch["handle"], id=_chat_thread_id(ch["handle"]), title=ch["title"], date=ch["date"],
                            trail=[sec["title"] for sec in ch["sections"] if sec["title"] != ch["title"]])
              for ch in WORLD["recent_chats"]]
    cm = ChatMap.build(sections, recent, groups)
    for ch in WORLD["older_chats"]:  # 検索でだけ見つかる古いチャット(地図の一覧には出さない)
        cm.add_thread(ChatThreadRef(handle=ch["handle"], id=_chat_thread_id(ch["handle"]), title=ch["title"],
                                    date=ch["date"], trail=[]))
    return cm


def chunk_for_hit(handle: str, snippet: str) -> Optional[dict]:
    """台本の検索結果(呼び名 + 断片)を、本番の検索が返すチャンクの形に。"""
    if handle[:1] == "P":
        ch = CHATS.get(handle.split("/")[0])
        if not ch:
            return None
        return {"id": f"chunk-{handle}", "source_type": "chat_turn", "source_id": None, "lecture_id": None, "course_id": None,
                "content": f"[Chat: {ch['title']} / {ch['date']}]\nStudent: ({ch['title']})\nAssistant: {snippet}",
                "metadata": {"thread_id": _chat_thread_id(ch["handle"]), "turn_number": 1}}
    parsed = nav.parse_handle(handle)
    if parsed is None or parsed.lecture not in LECTURE and parsed.kind != "course":
        return None
    lec_h = parsed.lecture or ""
    lec = LECTURE.get(lec_h, {})
    header = f"{COURSE_TITLE.get(parsed.course, '')} / {lec.get('title', '')}"
    chunk = {"id": f"chunk-{handle}", "lecture_id": f"lec-{lec_h}", "course_id": f"course-{parsed.course}", "metadata": {}}
    if parsed.kind == "transcript":
        chunk.update(source_type="transcript_topic", source_id=None, content=f"[{header} / Transcript]\n{snippet}",
                     metadata={"sid_start": parsed.sid_start, "sid_end": parsed.sid_end})
    elif parsed.kind == "topic":
        chunk.update(source_type="topic_summary", source_id=f"topic-{handle}", content=f"[{header} / Topic]\n{snippet}")
    else:
        chunk.update(source_type="lecture_summary", source_id=f"lec-{lec_h}", content=f"[{header} / Lecture Summary]\n{snippet}")
    return chunk


# =====================================================================
# 🧪 台本 → 本番の入力・状態
# =====================================================================

UNAVAILABLE_TARGETS = {t for t, cap in [("chat.all", "CAN_CHAT"), ("chat.thread", "CAN_CHAT"), ("web.search", "CAN_WEB")]
                       if not nav.CAPABILITIES[cap]}


def _op_available(op: dict) -> bool:
    if op["op"] == "open":
        h = op["handle"]
        if h[0] in "PS" and not nav.CAPABILITIES["CAN_CHAT"]:
            return False
        if h[0] == "W" and not nav.CAPABILITIES["CAN_WEB"]:
            return False
        return nav.CAPABILITIES["CAN_OPEN"]
    if op["op"] == "by_date":
        return nav.CAPABILITIES["CAN_BY_DATE"]
    return f"{op['source']}.{op['kind']}" not in UNAVAILABLE_TARGETS


def available_alternatives(step: dict) -> list[dict]:
    return [a for a in step["alternatives"] if all(_op_available(o) for o in a["must"] + a["one_of"])
            and (not a["one_of"] or any(_op_available(o) for o in a["one_of"]))]


def _ref_for_handle(handle: str) -> Optional[dict]:
    parsed = nav.parse_handle(handle)
    if parsed is None:
        return None
    if parsed.kind == "course":
        return {"type": "course", "id": f"course-{parsed.course}"}
    if parsed.kind == "lecture":
        return {"type": "lecture", "id": f"lec-{parsed.lecture}"}
    if parsed.kind == "topic":
        return {"type": "topic", "lecture_id": f"lec-{parsed.lecture}", "index": parsed.topic_index}
    return {"type": "transcript", "lecture_id": f"lec-{parsed.lecture}", "sid_start": parsed.sid_start, "sid_end": parsed.sid_end}


def build_nav_input(case: dict) -> nav.NavigatorInput:
    if case["thread"]:
        conv = WORLD["threads"][case["thread"]]["recent_conversation"]
    else:
        conv = case["recent_conversation"]
    screen = case["screen"] or {}
    topic = screen.get("topic")
    return nav.NavigatorInput(
        message=case["message"],
        selected_text=screen.get("selected_text"),
        screen_lecture_id=f"lec-{screen['lecture']}" if screen.get("lecture") else None,
        recent_conversation=[Message(role="user" if r == "user" else "assistant", content=t) for r, t in conv],
        today=date.fromisoformat(WORLD["today"]),
        student_map=STUDENT_MAP,
        chat_map=build_chat_map(case),
        current_thread_id=CURRENT_THREAD_ID,
        previous_turn_refs=[r for r in (_ref_for_handle(h) for h in case["previous_turn_opened"]) if r],
        screen_topic_index=int(topic.rsplit("/T", 1)[1]) if topic else None,
    )


def _web_page(h: dict) -> nav.WebPage:
    return nav.WebPage(handle=h["handle"], title=h.get("title") or "", url=h.get("url") or f"https://example.org/{h['handle']}",
                       snippets=[h["snippet"]])


def _outcome_for_found(f: dict, state: Optional[nav.NavState] = None) -> Optional[nav.Outcome]:
    """stateを渡すと、Webのページをstate.web_pagesにも登録する(開けるように)。"""
    target = f"{f['source']}.{f['kind']}"
    common = dict(grounds="past_reference", grounds_quote="", relation="direct", quote_ok=True)
    if target == "web.search" and target not in UNAVAILABLE_TARGETS:
        req = nav.FindRequest(target=target, query=f["query"], layer="all", within=None, **common)
        pages = []
        for h in f["hits"]:
            page = (state.web_pages.get(h["handle"]) if state else None) or _web_page(h)
            if state is not None:
                state.web_pages[page.handle] = page
            pages.append(page)
        return nav.WebSearchOutcome(request=req, pages=pages)
    if f["kind"] == "by_date":
        m = re.findall(r"\d{4}-\d{2}-\d{2}", f["query"])
        within = re.search(r"\((C\d+)\)", f["query"])
        req = nav.DateRequest(date_from=date.fromisoformat(m[0]), date_to=date.fromisoformat(m[-1]),
                              within=within.group(1) if within else None, **common)
        return nav.DateOutcome(request=req, lectures=[STUDENT_MAP.lecture(h["handle"]) for h in f["hits"]],
                               course_titles=COURSE_TITLE)
    if target in UNAVAILABLE_TARGETS:
        return None
    req = nav.FindRequest(target=target, query=f["query"], layer="all", within=None, **common)
    hits = [nav.Hit(handle=h["handle"], chunk=c) for h in f["hits"] if (c := chunk_for_hit(h["handle"], h["snippet"]))]
    return nav.SearchOutcome(request=req, hits=hits)


async def build_state(case: dict, step: dict, nav_input: nav.NavigatorInput) -> Optional[nav.NavState]:
    """台本の周の状態を、本番のNavStateとして組み立てる。使えない出どころが混ざる周はNone。"""
    state = nav.NavState()
    chat_source = WorldChatSource(case)
    if nav_input.previous_turn_refs:
        await nav.prepare_previous_turn(nav_input, SOURCE, chat_source, state)
    for f in step["found"]:
        o = _outcome_for_found(f, state)
        if o is None:
            return None
        state.outcomes.append(o)
    for h in step["opened"]:
        if h[0] in "PS" and not nav.CAPABILITIES["CAN_CHAT"]:
            return None
        if h[0] == "W":
            if h not in state.web_pages:
                return None
            state.opened[h] = nav.open_web_page(state.web_pages[h], "direct")
            continue
        state.opened[h] = await nav.open_handle(h, "direct", nav_input, SOURCE, chat_source)
    for hist in step["history"]:
        done = [f"open {h}" for h in hist["opened"]]
        for f in hist["found"]:
            o = _outcome_for_found(f)
            if o is not None:
                done.append(o.summary())
        state.laps.append(nav.LapRecord(lap=hist["lap"], status="need_more", missing=hist.get("looking_for") or "",
                                        reasoning="", goal=[], done=done))
    return state


# =====================================================================
# 🧮 採点(本番の検証を通した後の操作を、旧ハーネスの採点に渡す)
# =====================================================================

def _request_to_op(r: nav.Request) -> dict:
    base = {"grounds": r.grounds, "relation": r.relation}
    if r.grounds_quote:
        base["grounds_quote"] = r.grounds_quote
    if isinstance(r, nav.FindRequest):
        return {**base, "op": "find", "target": r.target, "query": r.query, "layer": r.layer, "within": r.within or "none"}
    if isinstance(r, nav.OpenRequest):
        return {**base, "op": "open", "handle": r.handle}
    return {**base, "op": "by_date", "date_from": r.date_from.isoformat(), "date_to": r.date_to.isoformat(),
            "within": r.within or "none"}


async def run_step(llm: UnifiedLLM, case: dict, step: dict, sem: asyncio.Semaphore) -> Optional[dict]:
    alternatives = available_alternatives(step)
    if not alternatives:
        return None
    nav_input = build_nav_input(case)
    state = await build_state(case, step, nav_input)
    if state is None:
        return None
    async with sem:
        t0 = time.perf_counter()
        out, err = await nav.decide_lap(llm, nav_input, state, step["lap"])
        elapsed = time.perf_counter() - t0
    if out is None:
        return {"case": case["id"], "category": case["category"], "lap": step["lap"], "elapsed": round(elapsed, 2),
                "output": None, "score": {"pass": False, "error": f"llm_error: {err}"}}
    requests, dropped = nav.validate_operations(out.get("operations"), nav_input, state,
                                                out.get("need"), out.get("fetch_from"))
    scored_out = {"status": out["status"], "operations": [_request_to_op(r) for r in requests]}
    s = score(case, {**step, "alternatives": alternatives}, scored_out)
    if dropped:
        s["dropped"] = [d["reason"] for d in dropped]
    return {"case": case["id"], "category": case["category"], "lap": step["lap"], "elapsed": round(elapsed, 2),
            "output": out, "score": s}


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", choices=["main", "holdout", "all"], default="main")
    ap.add_argument("--only", nargs="*", help="case ids")
    ap.add_argument("--concurrency", type=int, default=6)
    ap.add_argument("--model", help="探索役のモデルを差し替えて比べる(例: gemini/gemini-2.5-flash-lite)")
    args = ap.parse_args()
    if args.model:
        nav.NAVIGATOR_MODEL = args.model

    billing = BillingEngine(task_type="navigator_eval")
    llm = UnifiedLLM(billing)
    sem = asyncio.Semaphore(args.concurrency)
    cases = [c for c in CASES if (args.set == "all" or c["set"] == args.set) and (not args.only or c["id"] in args.only)]
    tasks = [run_step(llm, c, st, sem) for c in cases for st in cumulative_steps(c)]
    rows = [r for r in await asyncio.gather(*tasks) if r is not None]
    skipped = len(tasks) - len(rows)
    n_pass = sum(1 for r in rows if r["score"]["pass"])
    caps = ",".join(k for k, v in nav.CAPABILITIES.items() if v)
    print(f"{n_pass}/{len(rows)} steps passed ({skipped} skipped: need {', '.join(sorted(UNAVAILABLE_TARGETS)) or '-'}) "
          f"model={nav.NAVIGATOR_MODEL} caps={caps}")

    RESULTS_DIR.mkdir(exist_ok=True)
    prefix = "prod" if not args.model else "prod-" + args.model.split("/")[-1]
    path = RESULTS_DIR / f"{prefix}_{args.set}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    path.write_text(json.dumps({"model": nav.NAVIGATOR_MODEL, "capabilities": nav.CAPABILITIES, "set": args.set,
                                "runs": [rows], "cost_usd": billing.total_usd()}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"cost ${billing.total_usd():.4f}  → {path.relative_to(TEST_DIR)}")


if __name__ == "__main__":
    asyncio.run(main())
