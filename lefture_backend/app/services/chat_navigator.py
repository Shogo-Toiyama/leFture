# app/services/chat_navigator.py
"""
チャットの探索役: 地図を見て「探す / (開く) / 終わり」を1周ずつ選び、回答役に渡す材料を集める。
docs/chatbot_context_and_retrieval_roadmap.md の ステップ3〜4(3-1〜3-13)。

    仕分け役(chat_service._run_router) ── 情報が要る ──▶ 探索役(ここ、最大4周)
                                                           ↕ 1周ごとに
                                                     実行(LLMではなくコード)
                                                           ↓
                                                        回答役

- 探索役はGPT-6 Luna(reasoning_effort="none")。評価セット(contents_generation/test_codes/
  navigator_test)で2.5/3.1 Flash-Liteより正解が多く、推論を切った方が速くて強かった(3-9)。
- 選べる呼び名・操作・出どころはJSON Schemaのenumで縛る。存在しない場所は指定できず、
  取ってくるのは常にコード。
- 探索役は毎周まっさらな状態で呼ばれるので、これまでの経過(<progress>)と次にできること
  (<next_options>)を毎周渡す。地図は1周目だけ(見送ったものが周を重ねても目の前にあると、
  それを開く方向に押してしまうため、3-6)。
- 出力は「足りているか」(status)と「まだ足りない具体的な情報」(missing)を操作より前に
  書かせる。need_more以外なら、ここで操作を捨てて終わりにする。

今できる操作(CAPABILITIES)は、講義の類似検索(find lecture.concept)だけ。目次を開く・日付で
引く・チャット・Webは、プロンプトの該当部分(<!--IF:CAN_...-->)を出す形で後から足す(3-12)。
"""

import asyncio
import re
import time
from dataclasses import dataclass, field
from datetime import date
from typing import Any, Awaitable, Callable, Optional

from app.services.chat_map import StudentMap
from app.services.helpers.helpers import _load_prompt, _render_conditional_sections
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM


# =========================================================
# ⚙️ 設定
# =========================================================

NAVIGATOR_MODEL = "gpt-6-luna"
NAVIGATOR_REASONING_EFFORT = "none"
NAVIGATOR_MAX_COMPLETION_TOKENS = 1500

MAX_LAPS = 4
MAX_OPS_PER_LAP = 5
MAX_QUERY_CHARS = 200

# 1回の検索で取る件数と、そのうち探索役に見せる件数・断片の長さ
SEARCH_MATCH_COUNT = 8
HITS_SHOWN_PER_SEARCH = 5
SNIPPET_CHARS = 300
# 回答役に渡す材料の上限(全周の検索結果から)
ANSWER_SOURCES_MAX = 8

# 探索役に見せる直近の会話
RECENT_CONVERSATION_MAX_MESSAGES = 6
RECENT_CONVERSATION_MAX_CHARS = 500

# 今の段階で使える操作(3-12の順に増やす)。プロンプトの<!--IF:CAN_...-->と対応する。
CAPABILITIES = {
    "CAN_OPEN": False,     # 目次を開く(lecture.outline)・文字起こしの範囲を開く
    "CAN_BY_DATE": False,  # 講義を日付で引く
    "CAN_CHAT": False,     # この会話の畳んだ部分・過去のチャット
    "CAN_WEB": False,      # Web検索
}

STATUSES = ["nothing_needed", "enough_now", "need_more"]
GROUNDS = ["explicit_request", "past_reference", "on_screen", "likely_in_course", "needs_external_info"]
RELATIONS = ["direct", "possible_link"]
NONE = "none"

# layer → knowledge_chunks.source_type の組(Noneは絞らない)。source_typeの一覧は
# 20261001010000_add_knowledge_chunks.sql のCHECK制約と同じ。
LAYER_SOURCE_TYPES: dict[str, Optional[list[str]]] = {
    "summaries": ["lecture_summary", "topic_summary"],
    "notes": ["deep_note", "keyword", "review_card", "fun_fact", "lecture_moment", "announcement"],
    "transcript": ["transcript_topic"],
    "all": None,
}


def available_targets() -> list[str]:
    targets = ["lecture.concept"]
    if CAPABILITIES["CAN_CHAT"]:
        targets += ["chat.all", "chat.thread"]
    if CAPABILITIES["CAN_WEB"]:
        targets.append("web.search")
    return targets


# =========================================================
# 🧩 データの形
# =========================================================

@dataclass
class NavigatorInput:
    message: str
    selected_text: Optional[str]
    screen_lecture_id: Optional[str]
    # 直近の会話(まだ要約に畳んでいない部分の最後の数往復)。回答役に渡すものと同じ。
    recent_conversation: list[Message]
    today: date
    student_map: StudentMap


@dataclass
class FindRequest:
    """コードが検証した後の検索1本。"""
    target: str
    query: str
    layer: str
    within: Optional[str]
    grounds: str
    grounds_quote: str
    relation: str
    quote_ok: bool

    def key(self) -> tuple:
        return (self.target, _norm(self.query), self.layer, self.within)

    def label(self) -> str:
        scope = []
        if self.layer != "all":
            scope.append(f"layer {self.layer}")
        if self.within:
            scope.append(f"within {self.within}")
        return f"{self.target} \"{self.query}\"" + (f" ({', '.join(scope)})" if scope else "")


@dataclass
class SearchOutcome:
    request: FindRequest
    chunks: list[dict]
    error: Optional[str] = None


@dataclass
class LapRecord:
    lap: int
    status: str
    missing: str
    reasoning: str
    goal: list[str]
    finds: list[FindRequest] = field(default_factory=list)
    outcomes: list[SearchOutcome] = field(default_factory=list)
    dropped: list[dict] = field(default_factory=list)
    elapsed_ms: int = 0
    llm_error: Optional[str] = None

    def to_json(self) -> dict:
        return {
            "lap": self.lap,
            "status": self.status,
            "missing": self.missing,
            "reasoning": self.reasoning,
            "goal": self.goal,
            "finds": [
                {**vars(o.request), "hits": [c.get("id") for c in o.chunks], "error": o.error}
                for o in self.outcomes
            ],
            "dropped": self.dropped,
            "elapsed_ms": self.elapsed_ms,
            "llm_error": self.llm_error,
        }


@dataclass
class NavigationResult:
    # 回答役に渡す材料(各チャンクに"relation"と"handle"を足してある)
    chunks: list[dict]
    goal: list[str]
    laps: list[LapRecord]
    # nothing_needed / enough_now / max_laps / llm_error
    stop_reason: str

    @property
    def failed_before_any_search(self) -> bool:
        """1周目で探索役自体が動かなかった(このときは呼び出し側が従来の検索に倒す)。"""
        return self.stop_reason == "llm_error" and not any(lap.outcomes for lap in self.laps)

    def to_json(self) -> dict:
        return {
            "model": NAVIGATOR_MODEL,
            "stop_reason": self.stop_reason,
            "goal": self.goal,
            "laps": [lap.to_json() for lap in self.laps],
        }


# 検索の実行(ネットワーク・DBに触れる部分)。呼び出し側がユーザー本人のJWTで作る。
SearchFn = Callable[[list[FindRequest]], Awaitable[list[SearchOutcome]]]


# =========================================================
# 🧩 純粋関数
# =========================================================

def _norm(s: Optional[str]) -> str:
    return re.sub(r"\s+", "", s or "").lower()


def quote_in_message(quote: str, message: str, selected_text: Optional[str]) -> bool:
    q = _norm(quote)
    return bool(q) and any(q in _norm(s) for s in [message, selected_text or ""])


def build_system_prompt() -> str:
    template = _render_conditional_sections(_load_prompt("chat_navigator_prompt.txt"), {
        **CAPABILITIES,
        "CAN_OPEN_CHAT": CAPABILITIES["CAN_OPEN"] and CAPABILITIES["CAN_CHAT"],
    })
    return template.replace("${MAX_LAPS}", str(MAX_LAPS)).replace("${MAX_OPS_PER_LAP}", str(MAX_OPS_PER_LAP))


def build_schema(student_map: StudentMap) -> dict[str, Any]:
    """項目の順番がそのまま出力の順番になる(GeminiとLunaで確認済み)。操作を選ぶ前に、
    「足りているか」と「何が足りないか」を先に書かせる。"""
    op = {
        "type": "object",
        "properties": {
            "op": {"type": "string", "enum": ["find"]},
            "target": {"type": "string", "enum": available_targets()},
            "query": {"type": "string"},
            "layer": {"type": "string", "enum": list(LAYER_SOURCE_TYPES) + [NONE]},
            "within": {"type": "string", "enum": student_map.scope_handles() + [NONE]},
            "grounds": {"type": "string", "enum": GROUNDS},
            "grounds_quote": {"type": "string"},
            "relation": {"type": "string", "enum": RELATIONS},
        },
        "required": ["op", "target", "query", "layer", "within", "grounds", "grounds_quote", "relation"],
    }
    return {
        "type": "object",
        "properties": {
            "reasoning": {"type": "string"},
            "status": {"type": "string", "enum": STATUSES},
            "missing": {"type": "string"},
            "operations": {"type": "array", "items": op},
            "goal": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["reasoning", "status", "missing", "operations", "goal"],
    }


def validate_operations(
    raw_ops: Any,
    student_map: StudentMap,
    already_run: set[tuple],
    nav_input: NavigatorInput,
) -> tuple[list[FindRequest], list[dict]]:
    """
    探索役の操作を検証して、実行してよい検索に変換する。捨てたものは理由つきで返す(記録用)。
    構造化出力で縛っているので通常は正しい形で来るが、ここを信頼の境界にする。
    根拠の引用が発言に無い操作は捨てずに記録だけする(言い換え程度のずれで検索を
    落とすより、評価のときに見られる方が良い)。
    """
    finds: list[FindRequest] = []
    dropped: list[dict] = []
    seen = set(already_run)
    targets = set(available_targets())
    scope = set(student_map.scope_handles())

    for raw in raw_ops if isinstance(raw_ops, list) else []:
        if not isinstance(raw, dict):
            continue
        if raw.get("op") != "find" or raw.get("target") not in targets:
            dropped.append({"op": raw, "reason": "unsupported_operation"})
            continue
        query = (raw.get("query") or "").strip()[:MAX_QUERY_CHARS]
        if not query:
            dropped.append({"op": raw, "reason": "empty_query"})
            continue
        layer = raw.get("layer") if raw.get("layer") in LAYER_SOURCE_TYPES else "all"
        within = raw.get("within") if raw.get("within") in scope else None
        req = FindRequest(
            target=raw["target"], query=query, layer=layer, within=within,
            grounds=raw.get("grounds") if raw.get("grounds") in GROUNDS else "past_reference",
            grounds_quote=(raw.get("grounds_quote") or "")[:300],
            relation=raw.get("relation") if raw.get("relation") in RELATIONS else "direct",
            quote_ok=quote_in_message(raw.get("grounds_quote") or "", nav_input.message, nav_input.selected_text),
        )
        # 同じ検索の繰り返しは捨てる(前の周と同じ・同じ周の中で重複)
        if req.key() in seen:
            dropped.append({"op": raw, "reason": "repeated_search"})
            continue
        if len(finds) >= MAX_OPS_PER_LAP:
            dropped.append({"op": raw, "reason": "too_many_operations"})
            continue
        seen.add(req.key())
        finds.append(req)
    return finds, dropped


def hit_handle(chunk: dict, student_map: StudentMap) -> Optional[str]:
    return student_map.lecture_handle(chunk.get("lecture_id"))


def _chunk_header_and_body(chunk: dict) -> tuple[str, str]:
    content = (chunk.get("content") or "").strip()
    lines = content.splitlines()
    if lines and lines[0].startswith("[") and lines[0].endswith("]"):
        return lines[0].strip("[]"), "\n".join(lines[1:]).strip()
    return "", content


def render_search_block(outcome: SearchOutcome, student_map: StudentMap) -> str:
    head = outcome.request.label()
    if outcome.error:
        return f"{head}:\n(the search failed)"
    if not outcome.chunks:
        return f"{head}:\n(no results)"
    lines = []
    for chunk in outcome.chunks[:HITS_SHOWN_PER_SEARCH]:
        header, body = _chunk_header_and_body(chunk)
        where = hit_handle(chunk, student_map) or "(lecture outside the map)"
        snippet = re.sub(r"\s+", " ", body)[:SNIPPET_CHARS]
        lines.append(f"- {where} [{header}]: {snippet}")
    return f"{head}:\n" + "\n".join(lines)


def build_user_message(nav_input: NavigatorInput, laps: list[LapRecord], lap: int) -> str:
    m = nav_input.student_map
    parts = [f"<today>{nav_input.today.isoformat()}</today>"]

    if lap == 1:
        parts.append("<map>\nCourses:\n" + m.render_courses() + "\n</map>")

    if nav_input.recent_conversation:
        conv = "\n".join(
            f"{'student' if msg.role == 'user' else 'assistant'}: {msg.content[:RECENT_CONVERSATION_MAX_CHARS]}"
            for msg in nav_input.recent_conversation[-RECENT_CONVERSATION_MAX_MESSAGES:]
        )
        parts.append(f"<recent_conversation>\n{conv}\n</recent_conversation>")
    else:
        parts.append("<recent_conversation>(This is the first message of a new conversation.)</recent_conversation>")

    screen = []
    screen_handle = m.lecture_handle(nav_input.screen_lecture_id)
    if screen_handle:
        screen.append(f"The student is viewing {m.describe(screen_handle)}")
    if nav_input.selected_text:
        screen.append(f"Selected text: {nav_input.selected_text}")
    if screen:
        parts.append("<screen>\n" + "\n".join(screen) + "\n</screen>")

    parts.append(f"<student_message>\n{nav_input.message}\n</student_message>")

    done_laps = [lp for lp in laps if lp.outcomes]
    if done_laps:
        progress = []
        for lp in done_laps:
            acts = [f"{o.request.label()} → {len(o.chunks)} result(s)" for o in lp.outcomes]
            looking = f" (you were looking for: {lp.missing})" if lp.missing else ""
            progress.append(f"Lap {lp.lap}{looking}: " + "; ".join(acts))
        parts.append("<progress>\n" + "\n".join(progress) + "\n</progress>")
        blocks = [render_search_block(o, m) for lp in done_laps for o in lp.outcomes]
        parts.append("<search_results>\n" + "\n\n".join(blocks) + "\n</search_results>")

    nxt = [f"This is lap {lap} of {MAX_LAPS}."]
    if lap == MAX_LAPS:
        nxt.append("This is the last lap. After it, the answerer writes the reply with whatever you have fetched.")
    else:
        nxt.append(f"{MAX_LAPS - lap} more lap(s) after this one. After lap {MAX_LAPS}, "
                   "the answerer writes the reply with whatever you have fetched.")
    runs = [o.request.label() for lp in done_laps for o in lp.outcomes]
    nxt.append("Searches already run (do not repeat them): " + ("; ".join(runs) or "none yet"))
    parts.append("<next_options>\n" + "\n".join(nxt) + "\n</next_options>")
    return "\n\n".join(parts)


def collect_answer_chunks(laps: list[LapRecord], student_map: StudentMap) -> list[dict]:
    """
    全周の検索結果から回答役に渡す材料を選ぶ。同じチャンクは1つにまとめ(類似度は最大、
    どれか1つでもdirectで取っていればdirect)、direct → possible_linkの順に類似度で並べる。
    """
    best: dict[str, dict] = {}
    for lp in laps:
        for o in lp.outcomes:
            for chunk in o.chunks:
                cid = chunk.get("id")
                if not cid:
                    continue
                cur = best.get(cid)
                relation = o.request.relation
                if cur is None:
                    best[cid] = {**chunk, "relation": relation, "handle": hit_handle(chunk, student_map)}
                    continue
                if (chunk.get("similarity") or 0) > (cur.get("similarity") or 0):
                    cur["similarity"] = chunk.get("similarity")
                if relation == "direct":
                    cur["relation"] = "direct"
    ranked = sorted(best.values(), key=lambda c: (c["relation"] != "direct", -(c.get("similarity") or 0)))
    return ranked[:ANSWER_SOURCES_MAX]


# =========================================================
# 🔎 検索の実行
# =========================================================

def make_lecture_search(
    user_client,
    student_map: StudentMap,
    embed: Callable[[list[str]], Awaitable[list[list[float]]]],
) -> SearchFn:
    """
    lecture.conceptの検索を実行する関数を作る。search_knowledge_chunksは必ずユーザー本人の
    JWTで作ったクライアントで呼ぶ(auth.uid()で本人の行だけに絞る設計、chat_service._retrieveと同じ)。
    embedは課金を記録する埋め込み関数(knowledge_index.embed_queriesにbillingを渡したもの)。
    """
    def _rpc(embedding: list[float], req: FindRequest) -> list[dict]:
        params: dict[str, Any] = {"query_embedding": embedding, "match_count": SEARCH_MATCH_COUNT}
        source_types = LAYER_SOURCE_TYPES.get(req.layer)
        if source_types:
            params["filter_source_types"] = source_types
        if req.within:
            lec = student_map.lecture(req.within)
            if lec:
                params["filter_lecture_id"] = lec.id
            else:
                course = student_map.course(req.within)
                if course:
                    params["filter_course_id"] = course.id
        res = user_client.rpc("search_knowledge_chunks", params).execute()
        return res.data or []

    async def search(requests: list[FindRequest]) -> list[SearchOutcome]:
        if not requests:
            return []
        embeddings = await embed([r.query for r in requests])
        results = await asyncio.gather(
            *[asyncio.to_thread(_rpc, emb, req) for emb, req in zip(embeddings, requests)],
            return_exceptions=True,
        )
        outcomes = []
        for req, res in zip(requests, results):
            if isinstance(res, Exception):
                print(f"⚠️ [chat] navigator search failed ({req.label()}): {res}")
                outcomes.append(SearchOutcome(request=req, chunks=[], error=str(res)[:300]))
            else:
                outcomes.append(SearchOutcome(request=req, chunks=res))
        return outcomes

    return search


# =========================================================
# 🧭 本体: 最大4周
# =========================================================

async def _decide(llm: UnifiedLLM, system: str, schema: dict, user: str) -> tuple[Optional[dict], Optional[str]]:
    """1周分の判断。読めない出力は1回だけやり直す。"""
    options = LLMOptions(
        # gpt-6-lunaはtemperatureの既定値(1)以外を受け付けない
        temperature=1.0,
        output_type="json",
        json_schema=schema,
        max_completion_tokens=NAVIGATOR_MAX_COMPLETION_TOKENS,
        reasoning_effort=NAVIGATOR_REASONING_EFFORT,
    )
    messages = [Message(role="system", content=system), Message(role="user", content=user)]
    last_error = None
    for _attempt in range(2):
        try:
            result = await llm.generate(NAVIGATOR_MODEL, messages, options)
        except Exception as e:
            last_error = str(e)[:300]
            continue
        out = result.output_json
        if isinstance(out, dict) and out.get("status") in STATUSES:
            return out, None
        last_error = result.json_parse_error or f"unreadable output (finish_reason={result.finish_reason})"
    return None, last_error


async def navigate(
    llm: UnifiedLLM,
    nav_input: NavigatorInput,
    search: SearchFn,
    on_lap: Optional[Callable[[int], Awaitable[None]]] = None,
) -> NavigationResult:
    """
    探索役を最大MAX_LAPS周まわす。1周ごとに「判断(LLM) → 検証(コード) → 実行(コード)」。
    途中の周で探索役が動かなくなったら、そこまでに集めたもので終わる。
    """
    system = build_system_prompt()
    schema = build_schema(nav_input.student_map)
    laps: list[LapRecord] = []
    already_run: set[tuple] = set()
    goal: list[str] = []
    stop_reason = "max_laps"

    for lap in range(1, MAX_LAPS + 1):
        if on_lap is not None:
            await on_lap(lap)
        t0 = time.perf_counter()
        out, err = await _decide(llm, system, schema, build_user_message(nav_input, laps, lap))
        if out is None:
            print(f"⚠️ [chat] navigator lap {lap} failed: {err}")
            laps.append(LapRecord(lap=lap, status="", missing="", reasoning="", goal=[],
                                  elapsed_ms=round((time.perf_counter() - t0) * 1000), llm_error=err))
            stop_reason = "llm_error"
            break

        record = LapRecord(
            lap=lap,
            status=out["status"],
            missing=(out.get("missing") or "").strip()[:300],
            reasoning=(out.get("reasoning") or "").strip()[:500],
            goal=[g.strip()[:200] for g in out.get("goal") or [] if isinstance(g, str) and g.strip()][:8],
        )
        laps.append(record)
        if record.goal:
            goal = record.goal

        if record.status != "need_more":
            stop_reason = record.status
            record.elapsed_ms = round((time.perf_counter() - t0) * 1000)
            break

        record.finds, record.dropped = validate_operations(out.get("operations"), nav_input.student_map, already_run, nav_input)
        if not record.finds:
            # need_moreと言いつつ実行できる操作が無い(全部繰り返し等): ここまでで答える
            stop_reason = "enough_now"
            record.elapsed_ms = round((time.perf_counter() - t0) * 1000)
            break
        already_run.update(f.key() for f in record.finds)
        record.outcomes = await search(record.finds)
        record.elapsed_ms = round((time.perf_counter() - t0) * 1000)

    return NavigationResult(
        chunks=collect_answer_chunks(laps, nav_input.student_map),
        goal=goal,
        laps=laps,
        stop_reason=stop_reason,
    )


def summarize_for_log(result: NavigationResult) -> str:
    parts = [f"stop={result.stop_reason}"]
    for lp in result.laps:
        parts.append(f"lap{lp.lap}:{lp.status or 'error'}:{len(lp.outcomes)}finds:{lp.elapsed_ms}ms")
    return " ".join(parts)

