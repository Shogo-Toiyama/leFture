"""
【旧版】2026-09-30のモデル比較(2.5/3.1 Flash-Lite・GPT-6 Luna)に使ったハーネス。
評価用のプロンプト(navigator_prompt.txt)と入力の組み立てを自前で持っている。
今はrun_eval.py(本番の探索役のコードをそのまま呼ぶ)を使う。results/の2026-09-30分の再現用に残す。

探索役(docs/chatbot_context_and_retrieval_roadmap.md ステップ3〜4)の評価ハーネス。

cases/world.json と cases/cases.json(build_cases.pyで生成)から、各周で探索役に見せる入力を
組み立て、本番と同じUnifiedLLM + JSON Schema(呼び名はenumで縛る)で1周分の判断をさせ、
台本の正解の候補(alternatives)と照らし合わせて採点する。前の周は正しかったとして次の周を
評価する(周ごとに独立に呼ぶ)。

実行: python run_eval.py --model gemini/gemini-2.5-flash-lite --runs 3
結果: results/<モデル名>_<日時>.json
"""

import argparse
import asyncio
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

import litellm  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM, _cache_token_counts  # noqa: E402


async def _generate_with_reasoning_effort(llm: UnifiedLLM, model: str, messages: list, options: LLMOptions, reasoning: str):
    """gpt-6-lunaでreasoning_effortを指定するには、litellmにallowed_openai_paramsも渡す必要がある
    (本番のUnifiedLLM.generateは対応していないので、評価用にここだけ直接litellmを呼ぶ)。"""
    kwargs = llm._build_kwargs(model, messages, options)
    kwargs["reasoning_effort"] = reasoning
    kwargs["allowed_openai_params"] = ["reasoning_effort"]
    t0 = time.perf_counter()
    response = await litellm.acompletion(**kwargs)
    elapsed = time.perf_counter() - t0
    usage = getattr(response, "usage", None)
    in_tok = int(getattr(usage, "prompt_tokens", 0) or 0)
    out_tok = int(getattr(usage, "completion_tokens", 0) or 0)
    cache_read, cache_write = _cache_token_counts(usage)
    llm.billing.add_token_cost(model, in_tok, out_tok, cache_read, cache_write)
    text = response.choices[0].message.content or ""
    from app.services.helpers.helpers import extract_json_string
    try:
        out_json = json.loads(extract_json_string(text)) if text.strip() else None
        err = None
    except Exception as e:  # noqa: BLE001
        out_json, err = None, str(e)
    return out_json, err, {"input": in_tok, "output": out_tok}, elapsed

TEST_DIR = Path(__file__).resolve().parent
CASES_DIR = TEST_DIR / "cases"
RESULTS_DIR = TEST_DIR / "results"
PROMPT = (TEST_DIR / "navigator_prompt.txt").read_text(encoding="utf-8")

sys.path.insert(0, str(TEST_DIR))
from build_cases import MAX_LAPS, MAX_OPS_PER_LAP, chat_map_line, course_map_line  # noqa: E402

WORLD = json.loads((CASES_DIR / "world.json").read_text(encoding="utf-8"))
CASES = json.loads((CASES_DIR / "cases.json").read_text(encoding="utf-8"))

GROUNDS = ["explicit_request", "past_reference", "on_screen", "likely_in_course", "needs_external_info"]
TARGETS = ["lecture.concept", "chat.thread", "chat.all", "web.search"]
# nothing_needed: 何も取らずに答えられる / enough_now: ここまでで足りる / need_more: まだ足りない(操作を選ぶ)
STATUSES = ["nothing_needed", "enough_now", "need_more"]
LAYERS = ["summaries", "notes", "transcript", "all"]
NONE = "none"

# ---------------------------------------------------------------------
# 世界の索引
# ---------------------------------------------------------------------
COURSE = {c["handle"]: c for c in WORLD["courses"]}
LECTURE = {lec["handle"]: lec for c in WORLD["courses"] for lec in c["lectures"]}
TOPIC = {t["handle"]: t for lec in LECTURE.values() for t in lec["topics"]}
TRANSCRIPT = WORLD["transcripts"]
CHAT = {ch["handle"]: ch for ch in WORLD["recent_chats"] + WORLD["older_chats"]}
RECENT_P = [ch["handle"] for ch in WORLD["recent_chats"]]
CITATION = re.compile(r"⟦s0*(\d+)-s0*(\d+)⟧")


def _lecture_of(handle: str) -> str:
    return "/".join(handle.split("/")[:2])


def _deep_note_for_navigator(topic_handle: str) -> tuple[str, list[str]]:
    """引用記号を呼び名に書き換えた Deep Note と、そこに出てくる文字起こし範囲の呼び名。"""
    lec = _lecture_of(topic_handle)
    ranges = []

    def repl(m):
        h = f"{lec}/s{m.group(1)}-{m.group(2)}"
        ranges.append(h)
        return f"[{h}]"

    return CITATION.sub(repl, TOPIC[topic_handle]["deep_note"]), ranges


def _title_of(handle: str) -> str:
    if handle in COURSE:
        return COURSE[handle]["title"]
    if handle in LECTURE:
        return f"{LECTURE[handle]['title']} ({LECTURE[handle]['date']})"
    if handle in TOPIC:
        return TOPIC[handle]["title"]
    return handle


def _one_level_down(handle: str) -> str:
    """前のターンで開いたものは、UUID保存された実際の中身(本番)にならって一段下まで見せる。
    コースなら講義の一覧(呼び名・日付・タイトル)、講義ならトピックの一覧。"""
    if handle in COURSE:
        rows = "\n".join(f"  {lec['handle']} ({lec['date']}) {lec['title']}" for lec in COURSE[handle]["lectures"])
        return f"\n{rows}"
    if handle in LECTURE and LECTURE[handle]["topics"]:
        rows = "\n".join(f"  {t['handle']} {t['title']}" for t in LECTURE[handle]["topics"])
        return f"\n{rows}"
    return ""


# ---------------------------------------------------------------------
# 開いた中身
# ---------------------------------------------------------------------

def render_open(handle: str, case: dict, step: dict) -> str:
    if handle in COURSE:
        lines = [f"{lec['handle']} ({lec['date']}) {lec['title']} — {lec['one_line']}" for lec in COURSE[handle]["lectures"]]
        return f"Course {handle}: {COURSE[handle]['title']}\n" + "\n".join(lines)
    if handle in LECTURE:
        lec = LECTURE[handle]
        out = [f"Lecture {handle}: {lec['title']} ({lec['date']})", f"Summary: {lec['summary']}"]
        if lec["topics"]:
            out.append("Topics:")
            out += [f"{t['handle']} {t['title']} — {t['summary']}" for t in lec["topics"]]
        else:
            out.append("(No topics recorded for this lecture.)")
        return "\n".join(out)
    if handle in TOPIC:
        t = TOPIC[handle]
        note, _ = _deep_note_for_navigator(handle)
        out = [f"Topic {handle}: {t['title']}", f"Summary: {t['summary']}", "Keywords: " + ", ".join(t["keywords"])]
        out.append("Deep Note:\n" + (note or "(none)"))
        return "\n".join(out)
    if handle in TRANSCRIPT:
        return f"Transcript {handle}:\n{TRANSCRIPT[handle]}"
    if case["thread"]:
        for s in WORLD["threads"][case["thread"]]["sections"]:
            if s["handle"] == handle:
                return f"Section {handle}: {s['title']} (turns {s['turns']})\n" + "\n".join(f"- {b}" for b in s["bullets"])
    if handle in CHAT:
        ch = CHAT[handle]
        if not ch["sections"]:
            return f"Chat {handle} ({ch['date']}) {ch['title']}\n(No summary yet.)"
        parts = [f"Chat {handle} ({ch['date']}) {ch['title']}"]
        for s in ch["sections"]:
            parts.append(f"## {s['title']}\n" + "\n".join(f"- {b}" for b in s["bullets"]))
        return "\n".join(parts)
    for f in step["found"]:
        for h in f["hits"]:
            if h["handle"] == handle:
                return f"{handle}:\n{h['snippet']}"
    raise KeyError(f"cannot render {handle}")


# ---------------------------------------------------------------------
# 周ごとの状態(前の周までの結果を積み上げる)
# ---------------------------------------------------------------------

def _found_key(f: dict) -> str:
    return f"{f['source']}.{f['kind']}|{f['query']}"


def _target_of(f: dict) -> str:
    return "by_date" if f["kind"] == "by_date" else f"{f['source']}.{f['kind']}"


def cumulative_steps(case: dict) -> list[dict]:
    """台本の各周の状態を、それまでの周の結果を足し込んだ形にし、周ごとの経過(history)を付ける。
    lap jで何をしたか = lap j+1の状態で新しく増えたもの。"""
    opened, found, history, out = [], [], [], []
    for idx, st in enumerate(case["steps"]):
        new_open = [h for h in st["opened"] if h not in opened]
        keys = {_found_key(f) for f in found}
        new_found = [f for f in st["found"] if _found_key(f) not in keys]
        if idx > 0:
            history.append({"lap": case["steps"][idx - 1]["lap"], "opened": new_open, "found": new_found,
                            "looking_for": st.get("looking_for")})
        opened += new_open
        found += new_found
        out.append({**st, "opened": list(opened), "found": list(found), "history": list(history)})
    return out


def _dedupe_handles(handles: list[str]) -> list[str]:
    seen, out = set(), []
    for h in handles:
        if h not in seen:
            seen.add(h)
            out.append(h)
    return out


def surfaced_not_opened(case: dict, step: dict) -> list[str]:
    """見えているがまだ開いていない呼び名(開いた講義のトピック、Deep Noteの引用範囲、検索結果、画面のトピック)。"""
    handles = []
    screen = case["screen"]
    if screen and screen.get("topic"):
        handles.append(screen["topic"])
    for h in step["opened"]:
        if h in LECTURE:
            handles += [t["handle"] for t in LECTURE[h]["topics"]]
        if h in TOPIC:
            handles += _deep_note_for_navigator(h)[1]
    for f in step["found"]:
        handles += [x["handle"] for x in f["hits"]]
    return [h for h in _dedupe_handles(handles) if h not in step["opened"]]


def visible_handles(case: dict, step: dict) -> list[str]:
    """enumに入れる呼び名。すでに開いたものは入れない(もう一度開けない)。"""
    handles = list(COURSE) + list(LECTURE) + RECENT_P
    if case["thread"]:
        handles += [s["handle"] for s in WORLD["threads"][case["thread"]]["sections"]]
    handles += surfaced_not_opened(case, step)
    return [h for h in _dedupe_handles(handles) if h not in step["opened"]]


def available_targets(case: dict) -> list[str]:
    # この会話に畳んだ部分が無ければ、この会話の中を検索する意味が無い
    return [t for t in TARGETS if t != "chat.thread" or case["thread"]]


def build_schema(handles: list[str], targets: list[str]) -> dict:
    op = {
        "type": "object",
        "properties": {
            "op": {"type": "string", "enum": ["open", "find", "by_date"]},
            "handle": {"type": "string", "enum": handles + [NONE]},
            "target": {"type": "string", "enum": targets + [NONE]},
            "query": {"type": "string"},
            "layer": {"type": "string", "enum": LAYERS + [NONE]},
            "within": {"type": "string", "enum": list(COURSE) + list(LECTURE) + [NONE]},
            "date_from": {"type": "string"},
            "date_to": {"type": "string"},
            "grounds": {"type": "string", "enum": GROUNDS},
            "grounds_quote": {"type": "string"},
            "relation": {"type": "string", "enum": ["direct", "possible_link"]},
        },
        "required": ["op", "handle", "target", "query", "layer", "within", "date_from", "date_to", "grounds", "grounds_quote", "relation"],
    }
    return {
        "type": "object",
        "properties": {
            # 項目の順番がそのまま出力の順番になる(Geminiで確認済み)。操作を選ぶ前に、
            # 「今あるもので足りるか」と「何が足りないか」を先に言わせる。
            "reasoning": {"type": "string"},
            "status": {"type": "string", "enum": STATUSES},
            "missing": {"type": "string"},
            "operations": {"type": "array", "items": op},
            "goal": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["reasoning", "status", "missing", "operations", "goal"],
    }


def build_user_message(case: dict, step: dict) -> str:
    parts = [f"<today>{WORLD['today']}</today>"]
    # 地図と前のターンで開いたものは1周目だけ。何がグラウンドになるかは生徒の発言そのものから決まり
    # (3-3)、発言は周を重ねても変わらないので、1周目で選ばれなかったものが2周目以降に選ばれることは
    # 構造的に起きない(2026-09-30の見直しで確認)。むしろ、見送ったはずの選択肢が周を重ねても
    # 目の前にあると、それが開く方向に押してしまう(outline_semester_overviewで実測)。
    # 講義・コースの呼び名自体はvisible_handles()で毎周選べるので、地図を出さなくても
    # 「第6回」への直接ジャンプや検索結果からの展開はそのまま動く。
    if step["lap"] == 1:
        m = ["Courses:"] + [course_map_line(c) for c in WORLD["courses"]]
        if case["thread"]:
            m += ["", "Folded sections of this conversation:"]
            m += [f"{s['handle']} {s['title']}" for s in WORLD["threads"][case["thread"]]["sections"]]
        m += ["", "Recent chats:"] + [chat_map_line(ch) for ch in WORLD["recent_chats"]]
        parts.append("<map>\n" + "\n".join(m) + "\n</map>")
        if case["previous_turn_opened"]:
            parts.append("<previous_turn_opened>\n" + "\n".join(
                f"{h} — {_title_of(h)}{_one_level_down(h)}" for h in case["previous_turn_opened"]
            ) + "\n</previous_turn_opened>")
    if case["thread"]:
        conv = WORLD["threads"][case["thread"]]["recent_conversation"]
        parts.append("<recent_conversation>\n" + "\n".join(f"{r}: {t}" for r, t in conv) + "\n</recent_conversation>")
    elif case["recent_conversation"]:
        parts.append("<recent_conversation>\n" + "\n".join(f"{r}: {t}" for r, t in case["recent_conversation"]) + "\n</recent_conversation>")
    else:
        parts.append("<recent_conversation>(This is the first message of a new conversation.)</recent_conversation>")
    if case["screen"]:
        s = case["screen"]
        where = s["topic"] or s["lecture"]
        line = f"The student is viewing {where} ({_title_of(where)})" + (f", course {_lecture_of(where).split('/')[0]}" if "/" in where else "")
        if s["selected_text"]:
            line += f"\nSelected text: {s['selected_text']}"
        parts.append(f"<screen>\n{line}\n</screen>")
    parts.append(f"<student_message>\n{case['message']}\n</student_message>")

    # これまでの経過: 周ごとに何をして、何件出たか(事実だけ。関係あるかの判断は探索役に任せる)
    if step["history"]:
        lines = []
        for h in step["history"]:
            acts = [f"open {x}" for x in h["opened"]]
            for f in h["found"]:
                hits = ", ".join(x["handle"] for x in f["hits"]) or "none"
                acts.append(f"{_target_of(f)} \"{f['query']}\" → {len(f['hits'])} result(s): {hits}")
            head = f"Lap {h['lap']}" + (f" (you were looking for: {h['looking_for']})" if h.get("looking_for") else "")
            lines.append(f"{head}: " + "; ".join(acts))
        parts.append("<progress>\n" + "\n".join(lines) + "\n</progress>")
    if step["opened"]:
        parts.append("<opened>\n" + "\n\n".join(render_open(h, case, step) for h in step["opened"]) + "\n</opened>")
    if step["found"]:
        blocks = []
        for f in step["found"]:
            hits = "\n".join(f"- {h['handle']}: {h['snippet']}" for h in f["hits"]) or "(no results)"
            blocks.append(f"{_target_of(f)} \"{f['query']}\":\n{hits}")
        parts.append("<search_results>\n" + "\n\n".join(blocks) + "\n</search_results>")

    # 次にできること
    lap = step["lap"]
    nxt = [f"This is lap {lap} of {MAX_LAPS}."]
    if lap == MAX_LAPS:
        nxt.append("This is the last lap. After it, the answerer writes the reply with whatever you have fetched.")
    else:
        nxt.append(f"{MAX_LAPS - lap} more lap(s) after this one. After lap {MAX_LAPS}, the answerer writes the reply with whatever you have fetched.")
    nxt.append("Already opened (content is in <opened>; cannot be opened again): " + (", ".join(step["opened"]) or "nothing yet"))
    runs = [f"{_target_of(f)} \"{f['query']}\"" for f in step["found"]]
    nxt.append("Searches already run (do not repeat them): " + ("; ".join(runs) or "none yet"))
    nxt.append("Seen but not opened yet (open one only if it likely holds what is still missing): "
               + (", ".join(surfaced_not_opened(case, step)) or "nothing"))
    parts.append("<next_options>\n" + "\n".join(nxt) + "\n</next_options>")
    return "\n\n".join(parts)


# ---------------------------------------------------------------------
# 採点
# ---------------------------------------------------------------------

def _norm(s: str) -> str:
    return re.sub(r"\s+", "", s or "").lower()


def quote_ok(quote: str, case: dict) -> bool:
    q = _norm(quote)
    if not q:
        return False
    sources = [case["message"]]
    if case["screen"] and case["screen"].get("selected_text"):
        sources.append(case["screen"]["selected_text"])
    return any(q in _norm(s) for s in sources)


def _none(v):
    return None if v in (None, "", NONE) else v


def op_matches(model_op: dict, spec: dict, strict: bool) -> bool:
    """strict=Falseなら、関係を無視して「何をしたか」だけを見る(間違いの分類用)。
    根拠の種類は合否に入れない(境目があいまいで、取りに行くかどうかにも効かない)。レポートにだけ出す。"""
    kind = model_op.get("op")
    if kind != spec["op"]:
        return False
    if spec["op"] == "open":
        if model_op.get("handle") != spec["handle"]:
            return False
    elif spec["op"] == "find":
        if model_op.get("target") != f"{spec['source']}.{spec['kind']}":
            return False
        q = (model_op.get("query") or "").lower()
        if not any(k.lower() in q for k in spec["query_any"]):
            return False
        if spec["layer_any"] and (_none(model_op.get("layer")) or "all") not in spec["layer_any"]:
            return False
        if spec["within_any"] is not None and _none(model_op.get("within")) not in spec["within_any"]:
            return False
    elif spec["op"] == "by_date":
        if model_op.get("date_from") != spec["from"] or model_op.get("date_to") != spec["to"]:
            return False
        if spec["within_any"] is not None and _none(model_op.get("within")) not in spec["within_any"]:
            return False
    if strict and model_op.get("relation") != spec["relation"]:
        return False
    return True


def grounds_agree(ops: list[dict], a: dict) -> bool:
    """合った候補の操作と、根拠の種類まで一致しているか(レポート用)。"""
    specs = a["must"] + a["one_of"] + a["may"]
    return all(any(op_matches(o, s, True) and o.get("grounds") in s["grounds"] for s in specs) for o in ops)


def apply_code_guard(step: dict, out: dict) -> tuple[dict, list[dict]]:
    """本番のコードがやる防御: すでに走らせた検索と同じ検索を捨てる。全部捨てたら「終わり」扱い。
    (開いたものの再オープンはenumから外してあるので起きない)"""
    ran = {(_target_of(f), _norm(f["query"])) for f in step["found"]}
    kept, dropped = [], []
    for o in out.get("operations") or []:
        if o.get("op") == "find" and (o.get("target"), _norm(o.get("query"))) in ran:
            dropped.append(o)
        else:
            kept.append(o)
    if dropped:
        out = {**out, "operations": kept, "status": out.get("status") if kept else "enough_now"}
    return out, dropped


def alt_matches(ops: list[dict], done: bool, a: dict, strict: bool) -> bool:
    if a["done"]:
        return done
    if done:
        return False
    allowed = a["must"] + a["one_of"] + a["may"]
    for spec in a["must"]:
        if not any(op_matches(o, spec, strict) for o in ops):
            return False
    if a["one_of"] and not any(op_matches(o, spec, strict) for o in ops for spec in a["one_of"]):
        return False
    return all(any(op_matches(o, spec, strict) for spec in allowed) for o in ops)


def _dedupe(ops: list[dict]) -> list[dict]:
    seen, out = set(), []
    for o in ops:
        key = json.dumps({k: o.get(k) for k in ("op", "handle", "target", "query", "date_from", "date_to", "within", "layer")}, sort_keys=True)
        if key not in seen:
            seen.add(key)
            out.append(o)
    return out


def score(case: dict, step: dict, out: dict | None) -> dict:
    if not out:
        return {"pass": False, "error": "no_output"}
    ops = _dedupe(out.get("operations") or [])
    # 本番のコードと同じく、need_more以外なら操作は捨てて終わり
    done = out.get("status") != "need_more" or not ops
    if done:
        ops = []
    result = {"done": done, "n_ops": len(ops)}
    if len(ops) > MAX_OPS_PER_LAP:
        return {**result, "pass": False, "error": "too_many_ops"}
    bad_quotes = [o.get("grounds_quote") for o in ops if not quote_ok(o.get("grounds_quote", ""), case)]
    for i, a in enumerate(step["alternatives"]):
        if alt_matches(ops, done, a, strict=True):
            if bad_quotes:
                return {**result, "pass": False, "error": "quote_not_in_message", "matched_alt": i, "bad_quotes": bad_quotes}
            return {**result, "pass": True, "matched_alt": i, "detour": a["detour"], "grounds_agree": grounds_agree(ops, a)}
    for i, a in enumerate(step["alternatives"]):
        if alt_matches(ops, done, a, strict=False):
            return {**result, "pass": False, "error": "grounds_or_relation", "matched_alt": i}
    if done:
        return {**result, "pass": False, "error": "stopped_too_early"}
    if not any(not a["done"] for a in step["alternatives"]):
        return {**result, "pass": False, "error": "fetched_when_should_stop"}
    return {**result, "pass": False, "error": "wrong_operations"}


# ---------------------------------------------------------------------
# 実行
# ---------------------------------------------------------------------

async def run_step(llm: UnifiedLLM, model: str, case: dict, step: dict, sem: asyncio.Semaphore, reasoning: str | None) -> dict:
    handles = visible_handles(case, step)
    user = build_user_message(case, step)
    schema = build_schema(handles, available_targets(case))
    if model.startswith("gpt-"):
        # gpt-6-lunaはtemperatureの既定値(1)以外を受け付けず、max_tokensではなくmax_completion_tokensを使う
        # (chat_summary.pyと同じ扱い)。
        options = LLMOptions(temperature=1.0, output_type="json", json_schema=schema, max_completion_tokens=1500)
    else:
        # Gemini 3系はllm_unifiedがtemperatureを外すので、温度0にはならない(毎回同じ判断になるとは限らない)
        options = LLMOptions(temperature=0.0, output_type="json", json_schema=schema, max_tokens=1500, reasoning_effort=reasoning)
    messages = [Message("system", PROMPT), Message("user", user)]
    async with sem:
        try:
            if model.startswith("gpt-") and reasoning:
                out, err, usage, elapsed = await _generate_with_reasoning_effort(llm, model, messages, options, reasoning)
            else:
                t0 = time.perf_counter()
                res = await llm.generate(model, messages, options)
                elapsed = time.perf_counter() - t0
                out, err = res.output_json, res.json_parse_error
                usage = {"input": res.input_tokens, "output": res.output_tokens}
        except Exception as e:  # noqa: BLE001
            out, err, usage, elapsed = None, str(e), {}, 0.0
    guarded, dropped = apply_code_guard(step, out) if out else (out, [])
    s = score(case, step, guarded)
    if dropped:
        s["guard_dropped"] = len(dropped)
    if err and not out:
        s["error"] = f"llm_error: {err[:200]}"
    return {"case": case["id"], "category": case["category"], "lap": step["lap"], "elapsed": round(elapsed, 2),
            "usage": usage, "output": out, "score": s}


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="gemini/gemini-2.5-flash-lite")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--concurrency", type=int, default=6)
    ap.add_argument("--only", nargs="*", help="case ids")
    ap.add_argument("--set", choices=["main", "holdout", "all"], default="main", help="holdoutはプロンプトの調整に使わない確認用")
    ap.add_argument("--reasoning", default=None, help='e.g. "none" for Gemini 3.1 (本番の回答役と同じ)')
    args = ap.parse_args()

    billing = BillingEngine(task_type="navigator_eval")
    llm = UnifiedLLM(billing)
    sem = asyncio.Semaphore(args.concurrency)
    cases = [c for c in CASES if (args.set == "all" or c["set"] == args.set) and (not args.only or c["id"] in args.only)]

    runs = []
    for r in range(args.runs):
        tasks = [run_step(llm, args.model, c, st, sem, args.reasoning) for c in cases for st in cumulative_steps(c)]
        rows = await asyncio.gather(*tasks)
        n_pass = sum(1 for x in rows if x["score"]["pass"])
        print(f"run {r + 1}: {n_pass}/{len(rows)} steps passed")
        runs.append(rows)

    RESULTS_DIR.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    name = args.model.split("/")[-1] + ("" if args.set == "main" else f"_{args.set}")
    path = RESULTS_DIR / f"{name}_{stamp}.json"
    path.write_text(json.dumps({"model": args.model, "reasoning": args.reasoning, "set": args.set, "runs": runs, "cost_usd": billing.total_usd()}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"cost ${billing.total_usd():.4f}  → {path.relative_to(TEST_DIR)}")


if __name__ == "__main__":
    asyncio.run(main())
