# app/services/chat_navigator.py
"""
チャットの探索役: 地図を見て「探す / 開く / 日付で引く / 終わり」を1周ずつ選び、回答役に渡す
材料を集める。docs/chatbot_context_and_retrieval_roadmap.md の ステップ3〜4(3-1〜3-14)。

    仕分け役(chat_service._run_router) ── 情報が要る ──▶ 探索役(ここ、最大4周)
                                                           ↕ 1周ごとに
                                                     実行(LLMではなくコード)
                                                           ↓
                                                        回答役

- 探索役はGPT-6 Luna(reasoning_effort="none")。評価セット(contents_generation/test_codes/
  navigator_test)で2.5/3.1 Flash-Liteより正解が多く、推論を切った方が速くて強かった(3-9)。
- 選べる呼び名・操作・出どころはJSON Schemaのenumで縛る。存在しない場所は指定できず、
  取ってくるのは常にコード。すでに開いたものはenumから外す(もう一度開けない)。
- 探索役は毎周まっさらな状態で呼ばれるので、これまでの経過(<progress>)と次にできること
  (<next_options>)を毎周渡す。地図と前のターンで開いたものは1周目だけ(見送ったものが周を
  重ねても目の前にあると、それを開く方向に押してしまうため、3-6)。
- 出力は「足りているか」(status)と「まだ足りない具体的な情報」(missing)を操作より前に
  書かせる。need_more以外なら、ここで操作を捨てて終わりにする。

1周は「判断(decide_lap) → 検証(validate_operations) → 実行(execute_lap)」に分けてある。
評価ハーネスは台本の状態(NavState)を作ってdecide_lapだけを呼び、本番と同じプロンプト・
入力の組み立てで評価する(評価用に別の組み立てを持たない、3-14)。

今できる操作はCAPABILITIESで切り替える。プロンプトの該当部分(<!--IF:CAN_...-->)も
これに合わせて出し入れされる(3-12)。
"""

import asyncio
import re
import time
from dataclasses import dataclass, field
from datetime import date
from typing import Any, Awaitable, Callable, Optional, Union
from urllib.parse import urlparse

from app.services.chat_lecture_source import LectureSource, first_sentence
from app.services.chat_map import ChatMap, MapLecture, StudentMap
from app.services.chat_materials import Material, material_from_chunk
from app.services.chat_thread_source import ChatThreadSource
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

# 開いたときに見せる量(3-14)
COURSE_LINE_CHARS = 120
LECTURE_SUMMARY_CHARS = 2000
TOPIC_LINE_CHARS = 160
TOPIC_TEXT_CHARS = 4000
TRANSCRIPT_CONTEXT_SENTENCES = 1
TRANSCRIPT_CHARS = 1500
# 文字起こしの範囲として受け付ける最大の文の数(Deep Noteの引用・検索の当たりは十数文まで)
TRANSCRIPT_MAX_SENTENCES = 60
# 日付で引く範囲の上限(日数)
BY_DATE_MAX_DAYS = 400

# 探索役に見せる直近の会話
RECENT_CONVERSATION_MAX_MESSAGES = 6
RECENT_CONVERSATION_MAX_CHARS = 500

# チャットを開いたときの一覧1行(学生の発言・返答それぞれ)と、1往復を開いたときの全文
CHAT_TURN_LIST_USER_CHARS = 150
CHAT_TURN_LIST_ASSISTANT_CHARS = 300
CHAT_TURN_FULL_CHARS = 3000
# 前のターンで開いたスレッドの一覧プレビューは、直近の往復だけに絞る(長くなりすぎないように)
PREVIOUS_THREAD_PREVIEW_TURNS = 5

# Web(3-14 ⑤)。検索は1回$0.005なので1ターン2回まで(コードで止める)。1回の検索で見せるのは
# 上位5ページ。開くとそのページの断片すべて(Braveが抜き出し済みなので追加の通信は無い)。
MAX_WEB_SEARCHES_PER_TURN = 2
WEB_PAGES_PER_SEARCH = 5
WEB_PAGE_CHARS = 3000
# 検索で当たっただけ(開いていない)のページを回答役に渡すときの長さ
WEB_HIT_MATERIAL_CHARS = 1000

# 今の段階で使える操作(3-12の順に増やす)。プロンプトの<!--IF:CAN_...-->と対応する。
CAPABILITIES = {
    "CAN_OPEN": True,      # 目次を開く(lecture.outline)・文字起こしの範囲を開く
    "CAN_BY_DATE": True,   # 講義を日付で引く
    "CAN_CHAT": True,      # この会話の畳んだ部分・過去のチャット
    "CAN_WEB": True,       # Web検索
}

STATUSES = ["nothing_needed", "enough_now", "need_more"]
GROUNDS = ["explicit_request", "past_reference", "on_screen", "likely_in_course", "needs_external_info"]
RELATIONS = ["direct", "possible_link"]
NONE = "none"

# 講義の材料の種類(knowledge_chunks.source_type)。layer → 種類の組。
# allも講義の種類だけに絞る(チャットのチャンクが入ったときに講義の検索へ混ざらないように、3-14)。
LECTURE_SOURCE_TYPES = [
    "lecture_summary", "topic_summary", "deep_note", "keyword", "review_card",
    "fun_fact", "lecture_moment", "announcement", "transcript_topic",
]
LAYER_SOURCE_TYPES: dict[str, list[str]] = {
    "summaries": ["lecture_summary", "topic_summary"],
    "notes": ["deep_note", "keyword", "review_card", "fun_fact", "lecture_moment", "announcement"],
    "transcript": ["transcript_topic"],
    "all": LECTURE_SOURCE_TYPES,
}


def layer_source_types(layer: str, blocked: frozenset[str] = frozenset()) -> list[str]:
    """layerで検索する種類から、今のプランで使えないもの(plan_features)を除いたもの。"""
    return [t for t in (LAYER_SOURCE_TYPES.get(layer) or LECTURE_SOURCE_TYPES) if t not in blocked]


def available_layers(blocked: frozenset[str] = frozenset()) -> list[str]:
    """探索役が選べるlayer。今のプランで中身が1種類も残らないlayer(Lite以下のtranscript)は外す。"""
    return [layer for layer in LAYER_SOURCE_TYPES if layer_source_types(layer, blocked)]

_CITATION_BRACKET_RE = re.compile(r"⟦([^⟧]*)⟧")
_SID_PART_RE = re.compile(r"[sS]?0*(\d+)(?:\s*-\s*[sS]?0*(\d+))?")
_HANDLE_RE = re.compile(r"^(C\d+)(?:/(L\d+)(?:/(?:T(\d+)|s(\d+)(?:-(\d+))?))?)?$")
# S{n}(この会話の節) / S{n}/T{k}(その節の往復) / P{n}(過去のチャット) /
# P{n}/S{m}(その過去のチャットの節) / P{n}/T{k}(その過去のチャットの往復) /
# H{n}(この会話の2段目の節) / P{n}/H{m}(その過去のチャットの2段目の節)
_CHAT_HANDLE_RE = re.compile(r"^(S|P|H)(\d+)(?:/(?:S(\d+)|T(\d+)|H(\d+)))?$")
# W{n}(このターンのWeb検索で当たったページ。周をまたいで通し番号)
_WEB_HANDLE_RE = re.compile(r"^W\d+$")


def available_ops() -> list[str]:
    ops = ["find"]
    if CAPABILITIES["CAN_OPEN"]:
        ops.append("open")
    if CAPABILITIES["CAN_BY_DATE"]:
        ops.append("by_date")
    return ops


def available_targets(web_left: bool = True) -> list[str]:
    """web_left=False: このターンのWeb検索を使い切った(enumから外して選べなくする)。"""
    targets = ["lecture.concept"]
    if CAPABILITIES["CAN_CHAT"]:
        targets += ["chat.all", "chat.thread"]
    if CAPABILITIES["CAN_WEB"] and web_left:
        targets.append("web.search")
    return targets


# =========================================================
# 🧩 呼び名
# =========================================================

@dataclass
class ParsedHandle:
    kind: str  # course / lecture / topic / transcript
    course: str
    lecture: Optional[str] = None
    topic_index: Optional[int] = None
    sid_start: Optional[int] = None
    sid_end: Optional[int] = None


def parse_handle(handle: str) -> Optional[ParsedHandle]:
    m = _HANDLE_RE.match(handle or "")
    if not m:
        return None
    course, lec, topic, sid_a, sid_b = m.groups()
    if lec is None:
        return ParsedHandle("course", course)
    lecture = f"{course}/{lec}"
    if topic is not None:
        return ParsedHandle("topic", course, lecture, topic_index=int(topic))
    if sid_a is not None:
        a = int(sid_a)
        b = int(sid_b) if sid_b is not None else a
        return ParsedHandle("transcript", course, lecture, sid_start=min(a, b), sid_end=max(a, b))
    return ParsedHandle("lecture", course, lecture)


def range_handle(lecture_handle: str, a: int, b: int) -> str:
    return f"{lecture_handle}/s{a}" if a == b else f"{lecture_handle}/s{a}-{b}"


@dataclass
class ParsedChatHandle:
    kind: str  # section / thread / thread_section / turn(S*/T*) / thread_turn(P*/T*) / group(H*) / thread_group(P*/H*)
    prefix: str  # "S{n}" / "P{n}" / "H{n}"
    number: int
    sub_section: Optional[int] = None  # P{n}/S{m}のm
    turn: Optional[int] = None  # .../T{k}のk
    sub_group: Optional[int] = None  # P{n}/H{m}のm


def parse_chat_handle(handle: str) -> Optional[ParsedChatHandle]:
    m = _CHAT_HANDLE_RE.match(handle or "")
    if not m:
        return None
    letter, num, sub_s, sub_t, sub_h = m.groups()
    prefix = f"{letter}{num}"
    if letter == "H":
        # H{n}は単独でだけ使う(中の節はS{m}のまま開く)
        return ParsedChatHandle("group", prefix, int(num)) if sub_s is None and sub_t is None and sub_h is None else None
    if sub_h is not None:
        return ParsedChatHandle("thread_group", prefix, int(num), sub_group=int(sub_h)) if letter == "P" else None
    if sub_s is not None:
        if letter != "P":
            return None  # S{n}/S{m}は無い
        return ParsedChatHandle("thread_section", prefix, int(num), sub_section=int(sub_s))
    if sub_t is not None:
        return ParsedChatHandle("turn" if letter == "S" else "thread_turn", prefix, int(num), turn=int(sub_t))
    return ParsedChatHandle("section" if letter == "S" else "thread", prefix, int(num))


def rewrite_citations(note: str, lecture_handle: str, can_transcript: bool = True) -> tuple[str, str, list[str]]:
    """
    Deep Note内の引用記号⟦s000325-s000331, s000341⟧を、探索役向けには呼び名
    [C2/L5/s325-331, C2/L5/s341]に書き換え、回答役向けには取り除く。
    can_transcript=False(今のプランで文字起こしを使えない)なら、探索役向けからも取り除く。
    返り値: (探索役に見せる本文, 回答役に渡す本文, 出てきた範囲の呼び名)
    """
    handles: list[str] = []

    def to_handles(m: "re.Match[str]") -> str:
        parts = []
        for part in m.group(1).split(","):
            pm = _SID_PART_RE.fullmatch(part.strip())
            if not pm:
                continue
            a = int(pm.group(1))
            b = int(pm.group(2)) if pm.group(2) else a
            h = range_handle(lecture_handle, min(a, b), max(a, b))
            parts.append(h)
            if h not in handles:
                handles.append(h)
        return f"[{', '.join(parts)}]" if parts else ""

    for_answerer = re.sub(r"[ \t]+\n", "\n", _CITATION_BRACKET_RE.sub("", note)).strip()
    if not can_transcript:
        return for_answerer, for_answerer, []
    for_navigator = _CITATION_BRACKET_RE.sub(to_handles, note)
    return for_navigator, for_answerer, handles


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
    chat_map: Optional[ChatMap] = None
    # 今のスレッドのID(chat.thread/chat.allの絞り込み・当たった往復がどのスレッドのものかの判定に使う)
    current_thread_id: Optional[str] = None
    # 前のターンで開いたもの(返答の行のcontext.openedに保存したUUIDの参照)
    previous_turn_refs: list[dict] = field(default_factory=list)
    # 画面で見ているトピックの番号(Deep Notesのページなど)。webappはまだ送っていない(講義だけ)。
    screen_topic_index: Optional[int] = None
    # 今のプランで使えない材料の種類(plan_features.blocked_knowledge_source_types)
    blocked_source_types: frozenset[str] = frozenset()

    @property
    def can_transcript(self) -> bool:
        return "transcript_topic" not in self.blocked_source_types

    def screen_topic_handle(self) -> Optional[str]:
        lec = self.student_map.lecture_handle(self.screen_lecture_id)
        return f"{lec}/T{self.screen_topic_index}" if lec and self.screen_topic_index is not None else None


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
        return ("find", self.target, _norm(self.query), self.layer, self.within)

    def label(self) -> str:
        scope = []
        if self.layer != "all":
            scope.append(f"layer {self.layer}")
        if self.within:
            scope.append(f"within {self.within}")
        return f"{self.target} \"{self.query}\"" + (f" ({', '.join(scope)})" if scope else "")


@dataclass
class OpenRequest:
    handle: str
    grounds: str
    grounds_quote: str
    relation: str
    quote_ok: bool

    def key(self) -> tuple:
        return ("open", self.handle)

    def label(self) -> str:
        return f"open {self.handle}"


@dataclass
class DateRequest:
    date_from: date
    date_to: date
    within: Optional[str]
    grounds: str
    grounds_quote: str
    relation: str
    quote_ok: bool

    def key(self) -> tuple:
        return ("by_date", self.date_from, self.date_to, self.within)

    def label(self) -> str:
        span = self.date_from.isoformat() if self.date_from == self.date_to else f"{self.date_from.isoformat()} to {self.date_to.isoformat()}"
        return f"by_date {span}" + (f" (within {self.within})" if self.within else "")


Request = Union[FindRequest, OpenRequest, DateRequest]


@dataclass
class Hit:
    handle: Optional[str]
    chunk: dict


@dataclass
class SearchOutcome:
    request: FindRequest
    hits: list[Hit]
    error: Optional[str] = None

    def render(self) -> str:
        head = self.request.label()
        if self.error:
            return f"{head}:\n(the search failed)"
        if not self.hits:
            return f"{head}:\n(no results)"
        lines = []
        for hit in self.hits[:HITS_SHOWN_PER_SEARCH]:
            header, body = _chunk_header_and_body(hit.chunk)
            snippet = re.sub(r"\s+", " ", body)[:SNIPPET_CHARS]
            lines.append(f"- {hit.handle or '(lecture outside the map)'} [{header}]: {snippet}")
        return f"{head}:\n" + "\n".join(lines)

    def summary(self) -> str:
        return f"{self.request.label()} → {len(self.hits)} result(s)"

    def surfaced(self) -> list[str]:
        return [h.handle for h in self.hits[:HITS_SHOWN_PER_SEARCH] if h.handle]


@dataclass
class DateOutcome:
    request: DateRequest
    lectures: list[MapLecture]
    course_titles: dict[str, str]

    def render(self) -> str:
        if not self.lectures:
            return f"{self.request.label()}:\n(no lectures in this range)"
        lines = [
            f"- {lec.handle} ({lec.date.isoformat() if lec.date else 'no date'}) {self.course_titles.get(lec.course_handle, '')} / {lec.title}"
            for lec in self.lectures
        ]
        return f"{self.request.label()}:\n" + "\n".join(lines)

    def summary(self) -> str:
        return f"{self.request.label()} → {len(self.lectures)} lecture(s)"

    def surfaced(self) -> list[str]:
        return []


@dataclass
class WebPage:
    handle: str
    title: str
    url: str
    snippets: list[str]

    @property
    def domain(self) -> str:
        host = urlparse(self.url).netloc
        return host[4:] if host.startswith("www.") else host

    def text(self, limit: int) -> str:
        return "\n".join(s.strip() for s in self.snippets if s and s.strip())[:limit].strip()

    def label(self) -> str:
        return f"{self.title or self.domain} ({self.domain})" if self.domain else (self.title or self.url)


@dataclass
class WebSearchOutcome:
    request: FindRequest
    pages: list[WebPage]
    error: Optional[str] = None

    def render(self) -> str:
        head = self.request.label()
        if self.error:
            return f"{head}:\n(the search failed)"
        if not self.pages:
            return f"{head}:\n(no results)"
        # Python 3.11(本番)はf-stringの式の中にバックスラッシュを書けない
        lines = [f"- {p.handle} [{p.label()}]: " + re.sub(r"\s+", " ", p.text(SNIPPET_CHARS)) for p in self.pages]
        return f"{head}:\n" + "\n".join(lines)

    def summary(self) -> str:
        return f"{self.request.label()} → {len(self.pages)} page(s)"

    def surfaced(self) -> list[str]:
        return [p.handle for p in self.pages]


Outcome = Union[SearchOutcome, DateOutcome, WebSearchOutcome]


@dataclass
class Opened:
    handle: str
    # 探索役に見せる本文
    text: str
    # 回答役に渡す材料(開けなかったときはNone)
    material: Optional[Material]
    # 中身に出てきた、次に開ける呼び名(トピック・引用範囲)
    surfaced: list[str] = field(default_factory=list)
    # 次のターンに持ち越す参照(UUID)
    ref: Optional[dict] = None


@dataclass
class LapRecord:
    lap: int
    status: str
    missing: str
    reasoning: str
    goal: list[str]
    requests: list[Request] = field(default_factory=list)
    dropped: list[dict] = field(default_factory=list)
    elapsed_ms: int = 0
    llm_error: Optional[str] = None
    # この周で実行したことの要約(<progress>用)
    done: list[str] = field(default_factory=list)

    def to_json(self) -> dict:
        def req_json(r: Request) -> dict:
            d = {k: (v.isoformat() if isinstance(v, date) else v) for k, v in vars(r).items()}
            d["op"] = {FindRequest: "find", OpenRequest: "open", DateRequest: "by_date"}[type(r)]
            return d
        return {
            "lap": self.lap,
            "status": self.status,
            "missing": self.missing,
            "reasoning": self.reasoning,
            "goal": self.goal,
            "requests": [req_json(r) for r in self.requests],
            "done": self.done,
            "dropped": self.dropped,
            "elapsed_ms": self.elapsed_ms,
            "llm_error": self.llm_error,
        }


@dataclass
class NavState:
    """探索の途中の状態。本番はnavigate()が周ごとに更新し、評価ハーネスは台本から作る。"""
    laps: list[LapRecord] = field(default_factory=list)
    opened: dict[str, Opened] = field(default_factory=dict)
    outcomes: list[Outcome] = field(default_factory=list)
    # 前のターンで開いたもの(1周目に見せる)と、そこから選べる呼び名
    previous_turn_text: str = ""
    previous_turn_handles: list[str] = field(default_factory=list)
    # 探索役の見えている材料(opened以外): 検索の当たり → 材料
    search_materials: list[Material] = field(default_factory=list)
    # このターンのWeb検索で当たったページ(呼び名 → ページ)
    web_pages: dict[str, WebPage] = field(default_factory=dict)

    def web_searches_left(self) -> int:
        used = sum(1 for o in self.outcomes if isinstance(o, WebSearchOutcome))
        return max(0, MAX_WEB_SEARCHES_PER_TURN - used)

    def already_run(self) -> set[tuple]:
        keys: set[tuple] = {("open", h) for h in self.opened}
        for o in self.outcomes:
            keys.add(o.request.key())
        return keys

    def surfaced_not_opened(self) -> list[str]:
        handles: list[str] = []
        for op in self.opened.values():
            handles += op.surfaced
        for o in self.outcomes:
            handles += o.surfaced()
        return [h for h in _dedupe(handles) if h not in self.opened]


@dataclass
class NavigationResult:
    materials: list[Material]
    goal: list[str]
    laps: list[LapRecord]
    # nothing_needed / enough_now / max_laps / llm_error
    stop_reason: str
    # 次のターンに持ち越す参照(返答の行のcontext.openedに保存する)
    opened_refs: list[dict]

    @property
    def failed_before_any_fetch(self) -> bool:
        """1周目で探索役自体が動かなかった(このときは呼び出し側が従来の検索に倒す)。"""
        return self.stop_reason == "llm_error" and not any(lap.done for lap in self.laps)

    def to_json(self) -> dict:
        return {
            "model": NAVIGATOR_MODEL,
            "stop_reason": self.stop_reason,
            "goal": self.goal,
            "laps": [lap.to_json() for lap in self.laps],
        }


# 検索の実行(ネットワーク・DBに触れる部分)。呼び出し側がユーザー本人のJWTで作る。
# 返り値は検索ごとのチャンクの一覧(失敗した検索はException)。
SearchFn = Callable[[list[FindRequest]], Awaitable[list[Union[list[dict], Exception]]]]
# Web検索1回(クエリ → [{title, url, snippets}])。失敗は例外。
WebSearchFn = Callable[[str], Awaitable[list[dict]]]


@dataclass
class NavigatorTools:
    search: SearchFn
    source: LectureSource
    chat_source: Optional[ChatThreadSource] = None
    web_search: Optional[WebSearchFn] = None


# =========================================================
# 🧩 純粋関数
# =========================================================

def _norm(s: Optional[str]) -> str:
    return re.sub(r"\s+", "", s or "").lower()


def _dedupe(items: list[str]) -> list[str]:
    seen, out = set(), []
    for x in items:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def quote_in_message(quote: str, message: str, selected_text: Optional[str]) -> bool:
    q = _norm(quote)
    return bool(q) and any(q in _norm(s) for s in [message, selected_text or ""])


def _chunk_header_and_body(chunk: dict) -> tuple[str, str]:
    content = (chunk.get("content") or "").strip()
    lines = content.splitlines()
    if lines and lines[0].startswith("[") and lines[0].endswith("]"):
        return lines[0].strip("[]"), "\n".join(lines[1:]).strip()
    return "", content


def build_system_prompt(can_transcript: bool = True) -> str:
    template = _render_conditional_sections(_load_prompt("chat_navigator_prompt.txt"), {
        **CAPABILITIES,
        "CAN_TRANSCRIPT": can_transcript,
        # 条件ブロックは入れ子にできないので、CAN_OPENの中の分岐は組み合わせで持つ
        "CAN_OPEN_TRANSCRIPT": CAPABILITIES["CAN_OPEN"] and can_transcript,
        "CAN_OPEN_NO_TRANSCRIPT": CAPABILITIES["CAN_OPEN"] and not can_transcript,
        "CAN_OPEN_CHAT": CAPABILITIES["CAN_OPEN"] and CAPABILITIES["CAN_CHAT"],
        "CAN_OPEN_WEB": CAPABILITIES["CAN_OPEN"] and CAPABILITIES["CAN_WEB"],
    })
    return template.replace("${MAX_LAPS}", str(MAX_LAPS)).replace("${MAX_OPS_PER_LAP}", str(MAX_OPS_PER_LAP))


def openable_handles(nav_input: NavigatorInput, state: NavState) -> list[str]:
    """開ける呼び名: 全コース・全講義・この会話の節・最近のチャット・中身や検索結果に
    出てきたもの・前のターンのもの。開いたものは除く。"""
    m = nav_input.student_map
    screen_topic = [nav_input.screen_topic_handle()] if nav_input.screen_topic_handle() else []
    chat_scope = nav_input.chat_map.scope_handles() if nav_input.chat_map and CAPABILITIES["CAN_CHAT"] else []
    handles = m.scope_handles() + chat_scope + screen_topic + state.previous_turn_handles + state.surfaced_not_opened()
    return [h for h in _dedupe(handles) if h not in state.opened and _plan_allows_handle(nav_input, h)]


def _plan_allows_handle(nav_input: NavigatorInput, handle: str) -> bool:
    """文字起こしの範囲(C1/L2/s10-20)は、今のプランで文字起こしを使えるときだけ開ける。"""
    parsed = parse_handle(handle)
    return nav_input.can_transcript or parsed is None or parsed.kind != "transcript"


def build_schema(nav_input: NavigatorInput, state: NavState) -> dict[str, Any]:
    """項目の順番がそのまま出力の順番になる(GeminiとLunaで確認済み)。操作を選ぶ前に、
    「足りているか」と「何が足りないか」を先に書かせる。"""
    props: dict[str, Any] = {
        "op": {"type": "string", "enum": available_ops()},
        "target": {"type": "string", "enum": available_targets(state.web_searches_left() > 0) + [NONE]},
        "query": {"type": "string"},
        "layer": {"type": "string", "enum": available_layers(nav_input.blocked_source_types) + [NONE]},
        "within": {"type": "string", "enum": nav_input.student_map.scope_handles() + [NONE]},
    }
    if CAPABILITIES["CAN_OPEN"]:
        props["handle"] = {"type": "string", "enum": openable_handles(nav_input, state) + [NONE]}
    if CAPABILITIES["CAN_BY_DATE"]:
        props["date_from"] = {"type": "string"}
        props["date_to"] = {"type": "string"}
    props.update({
        "grounds": {"type": "string", "enum": GROUNDS},
        "grounds_quote": {"type": "string"},
        "relation": {"type": "string", "enum": RELATIONS},
    })
    return {
        "type": "object",
        "properties": {
            "reasoning": {"type": "string"},
            "status": {"type": "string", "enum": STATUSES},
            "missing": {"type": "string"},
            "operations": {"type": "array", "items": {"type": "object", "properties": props, "required": list(props)}},
            "goal": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["reasoning", "status", "missing", "operations", "goal"],
    }


def _parse_date(value: Any) -> Optional[date]:
    try:
        return date.fromisoformat(str(value).strip()[:10])
    except ValueError:
        return None


def validate_operations(raw_ops: Any, nav_input: NavigatorInput, state: NavState) -> tuple[list[Request], list[dict]]:
    """
    探索役の操作を検証して、実行してよい操作に変換する。捨てたものは理由つきで返す(記録用)。
    構造化出力で縛っているので通常は正しい形で来るが、ここを信頼の境界にする。
    根拠の引用が発言に無い操作は捨てずに記録だけする(言い換え程度のずれで取りこぼす
    より、評価のときに見られる方が良い)。
    """
    m = nav_input.student_map
    requests: list[Request] = []
    dropped: list[dict] = []
    seen = state.already_run()
    ops = set(available_ops())
    targets = set(available_targets())
    scope = set(m.scope_handles())
    openable = set(openable_handles(nav_input, state))
    layers = set(available_layers(nav_input.blocked_source_types))
    web_left = state.web_searches_left()

    for raw in raw_ops if isinstance(raw_ops, list) else []:
        if not isinstance(raw, dict):
            continue
        op = raw.get("op")
        common = dict(
            grounds=raw.get("grounds") if raw.get("grounds") in GROUNDS else "past_reference",
            grounds_quote=(raw.get("grounds_quote") or "")[:300],
            relation=raw.get("relation") if raw.get("relation") in RELATIONS else "direct",
            quote_ok=quote_in_message(raw.get("grounds_quote") or "", nav_input.message, nav_input.selected_text),
        )
        req: Optional[Request] = None
        reason = None
        if op not in ops:
            reason = "unsupported_operation"
        elif op == "find":
            query = (raw.get("query") or "").strip()[:MAX_QUERY_CHARS]
            if raw.get("target") not in targets:
                reason = "unsupported_target"
            elif not query:
                reason = "empty_query"
            elif raw["target"] == "web.search":
                # Webには絞り込みが無い。1ターンの回数の上限はここで数える(繰り返しの判定の後)
                req = FindRequest(target="web.search", query=query, layer="all", within=None, **common)
            else:
                req = FindRequest(
                    target=raw["target"], query=query,
                    layer=raw.get("layer") if raw.get("layer") in layers else "all",
                    within=raw.get("within") if raw.get("within") in scope else None,
                    **common,
                )
        elif op == "open":
            handle = raw.get("handle")
            parsed = parse_handle(handle or "")
            parsed_chat = parse_chat_handle(handle or "") if CAPABILITIES["CAN_CHAT"] else None
            is_web = bool(_WEB_HANDLE_RE.match(handle or "")) and handle in state.web_pages
            if not _plan_allows_handle(nav_input, handle or ""):
                reason = "transcript_not_in_plan"
            elif handle not in openable or (parsed is None and parsed_chat is None and not is_web):
                reason = "handle_not_openable"
            elif parsed and parsed.kind == "transcript" and parsed.sid_end - parsed.sid_start + 1 > TRANSCRIPT_MAX_SENTENCES:
                reason = "transcript_range_too_long"
            else:
                req = OpenRequest(handle=handle, **common)
        elif op == "by_date":
            d_from, d_to = _parse_date(raw.get("date_from")), _parse_date(raw.get("date_to") or raw.get("date_from"))
            if d_from is None or d_to is None:
                reason = "bad_date"
            else:
                d_from, d_to = min(d_from, d_to), max(d_from, d_to)
                if (d_to - d_from).days > BY_DATE_MAX_DAYS:
                    reason = "date_range_too_long"
                else:
                    req = DateRequest(date_from=d_from, date_to=d_to,
                                      within=raw.get("within") if raw.get("within") in scope else None, **common)
        if req is None:
            dropped.append({"op": raw, "reason": reason})
            continue
        # 同じ操作の繰り返しは捨てる(前の周と同じ・同じ周の中で重複)
        if req.key() in seen:
            dropped.append({"op": raw, "reason": "repeated"})
            continue
        if len(requests) >= MAX_OPS_PER_LAP:
            dropped.append({"op": raw, "reason": "too_many_operations"})
            continue
        if isinstance(req, FindRequest) and req.target == "web.search":
            if web_left <= 0:
                dropped.append({"op": raw, "reason": "web_search_limit"})
                continue
            web_left -= 1
        seen.add(req.key())
        requests.append(req)
    return requests, dropped


def build_user_message(nav_input: NavigatorInput, state: NavState, lap: int) -> str:
    m = nav_input.student_map
    parts = [f"<today>{nav_input.today.isoformat()}</today>"]

    if lap == 1:
        map_text = "Courses:\n" + m.render_courses()
        if CAPABILITIES["CAN_CHAT"] and nav_input.chat_map is not None and nav_input.chat_map.has_anything:
            map_text += "\n\n" + nav_input.chat_map.render()
        parts.append(f"<map>\n{map_text}\n</map>")
        if state.previous_turn_text and CAPABILITIES["CAN_OPEN"]:
            parts.append(f"<previous_turn_opened>\n{state.previous_turn_text}\n</previous_turn_opened>")

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
        topic = nav_input.screen_topic_handle()
        screen.append(f"The student is viewing {m.describe(screen_handle)}"
                      + (f", on topic {topic} (its Deep Note page)" if topic else ""))
    if nav_input.selected_text:
        screen.append(f"Selected text: {nav_input.selected_text}")
    if screen:
        parts.append("<screen>\n" + "\n".join(screen) + "\n</screen>")

    parts.append(f"<student_message>\n{nav_input.message}\n</student_message>")

    done_laps = [lp for lp in state.laps if lp.done]
    if done_laps:
        progress = []
        for lp in done_laps:
            looking = f" (you were looking for: {lp.missing})" if lp.missing else ""
            progress.append(f"Lap {lp.lap}{looking}: " + "; ".join(lp.done))
        parts.append("<progress>\n" + "\n".join(progress) + "\n</progress>")
    if state.opened:
        parts.append("<opened>\n" + "\n\n".join(op.text for op in state.opened.values()) + "\n</opened>")
    if state.outcomes:
        parts.append("<search_results>\n" + "\n\n".join(o.render() for o in state.outcomes) + "\n</search_results>")

    nxt = [f"This is lap {lap} of {MAX_LAPS}."]
    if lap == MAX_LAPS:
        nxt.append("This is the last lap. After it, the answerer writes the reply with whatever you have fetched.")
    else:
        nxt.append(f"{MAX_LAPS - lap} more lap(s) after this one. After lap {MAX_LAPS}, "
                   "the answerer writes the reply with whatever you have fetched.")
    if CAPABILITIES["CAN_OPEN"]:
        nxt.append("Already opened (content is in <opened>; cannot be opened again): "
                   + (", ".join(state.opened) or "nothing yet"))
    nxt.append("Searches already run (do not repeat them): "
               + ("; ".join(o.request.label() for o in state.outcomes) or "none yet"))
    if CAPABILITIES["CAN_WEB"]:
        left = state.web_searches_left()
        nxt.append(f"Web searches left for this reply: {left} of {MAX_WEB_SEARCHES_PER_TURN}"
                   + (" (web.search is no longer available)" if left == 0 else ""))
    if CAPABILITIES["CAN_OPEN"]:
        nxt.append("Seen but not opened yet (open one only if it likely holds what is still missing): "
                   + (", ".join(state.surfaced_not_opened()) or "nothing"))
    parts.append("<next_options>\n" + "\n".join(nxt) + "\n</next_options>")
    return "\n\n".join(parts)


# =========================================================
# 📂 開く(講義の目次・文字起こし)
# =========================================================

async def open_handle(
    handle: str, relation: str, nav_input: NavigatorInput, source: LectureSource,
    chat_source: Optional[ChatThreadSource] = None,
) -> Opened:
    if handle[:1] in ("S", "P", "H") and chat_source is not None:
        return await chat_open_handle(handle, relation, nav_input, chat_source)
    m = nav_input.student_map
    parsed = parse_handle(handle)
    course = m.course(parsed.course) if parsed else None
    lec = m.lecture(parsed.lecture) if parsed and parsed.lecture else None
    if parsed is None or course is None or (parsed.lecture and lec is None):
        return Opened(handle=handle, text=f"{handle}: (not found)", material=None)

    if parsed.kind == "course":
        summaries = await source.lecture_summaries([x.id for x in course.lectures])
        lines = [
            f"{x.handle} ({x.date.isoformat() if x.date else 'no date'}) {x.title}"
            + (f" — {first_sentence(summaries.get(x.id), COURSE_LINE_CHARS)}" if summaries.get(x.id) else "")
            for x in course.lectures
        ]
        body = "\n".join(lines) or "(No lectures recorded yet.)"
        return Opened(
            handle=handle,
            text=f"Course {handle}: {course.title}\n{body}",
            material=Material(key=f"course:{course.id}", kind="course", label=f"{course.title} / Lectures",
                              content=body, relation=relation, source_type="course", course_id=course.id, handle=handle),
            ref={"type": "course", "id": course.id},
        )

    when = lec.date.isoformat() if lec.date else "no date"
    if parsed.kind == "lecture":
        summary = (await source.lecture_summaries([lec.id])).get(lec.id, "")[:LECTURE_SUMMARY_CHARS]
        topics = await source.lecture_topics(lec.id)
        topic_lines = [f"{handle}/T{t['index']} {t['title']}"
                       + (f" — {first_sentence(t['summary'], TOPIC_LINE_CHARS)}" if t["summary"] else "")
                       for t in topics]
        body = f"Summary: {summary or '(no summary)'}\n" + (
            "Topics:\n" + "\n".join(topic_lines) if topic_lines else "(No topics recorded for this lecture.)")
        return Opened(
            handle=handle,
            text=f"Lecture {handle}: {lec.title} ({when})\n{body}",
            material=Material(key=f"lecture:{lec.id}", kind="lecture",
                              label=f"{course.title} / {lec.title} / Lecture Summary",
                              content=f"Lecture date: {when}\n{body}", relation=relation,
                              source_type="lecture_summary", source_id=lec.id, lecture_id=lec.id,
                              course_id=course.id, handle=handle),
            surfaced=[f"{handle}/T{t['index']}" for t in topics],
            ref={"type": "lecture", "id": lec.id},
        )

    if parsed.kind == "topic":
        detail = await source.topic_detail(lec.id, parsed.topic_index)
        if detail is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        note_nav, note_ans, ranges = rewrite_citations(detail.get("deep_note") or "", parsed.lecture, nav_input.can_transcript)
        keywords = "; ".join(f"{k}: {d}" if d else k for k, d in detail.get("keywords") or [])
        head = f"Summary: {detail['summary'] or '(no summary)'}" + (f"\nKeywords: {keywords}" if keywords else "")
        text = f"Topic {handle}: {detail['title']}\n{head}\nDeep Note:\n{note_nav[:TOPIC_TEXT_CHARS] or '(none)'}"
        content = f"{head}" + (f"\nDeep Note:\n{note_ans}" if note_ans else "")
        return Opened(
            handle=handle,
            text=text,
            material=Material(key=f"topic:{lec.id}:{parsed.topic_index}", kind="topic",
                              label=f"{course.title} / {lec.title} / Topic: {detail['title']}",
                              content=content[:TOPIC_TEXT_CHARS], relation=relation,
                              source_type="deep_note" if note_ans else "topic_summary",
                              source_id=detail.get("id"), lecture_id=lec.id, course_id=course.id,
                              metadata={"topic_number": parsed.topic_index}, handle=handle),
            surfaced=ranges,
            ref={"type": "topic", "lecture_id": lec.id, "index": parsed.topic_index},
        )

    # 文字起こしの範囲: 前後1文を足して、講義の話の流れが分かるようにする
    if not nav_input.can_transcript:
        return Opened(handle=handle, text=f"{handle}: (not available on the student's plan)", material=None)
    sentences = await source.transcript(lec.id)
    a = parsed.sid_start - TRANSCRIPT_CONTEXT_SENTENCES
    b = parsed.sid_end + TRANSCRIPT_CONTEXT_SENTENCES
    picked = [s["text"] for s in sentences if a <= s["sid"] <= b and s["text"]]
    if not picked:
        return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
    body = " ".join(picked)[:TRANSCRIPT_CHARS]
    return Opened(
        handle=handle,
        text=f"Transcript {handle} ({course.title} / {lec.title}, {when}):\n{body}",
        material=Material(key=f"transcript:{lec.id}:{parsed.sid_start}-{parsed.sid_end}", kind="transcript",
                          label=f"{course.title} / {lec.title} / Transcript", content=body, relation=relation,
                          source_type="transcript_topic", lecture_id=lec.id, course_id=course.id,
                          metadata={"sid_start": parsed.sid_start, "sid_end": parsed.sid_end}, handle=handle),
        ref={"type": "transcript", "lecture_id": lec.id, "sid_start": parsed.sid_start, "sid_end": parsed.sid_end},
    )


async def chat_thread_handle_for(nav_input: NavigatorInput, chat_source: Optional[ChatThreadSource], thread_id: str) -> Optional[str]:
    """あるスレッドIDのP{k}を、地図に無ければその場で(P21…を)割り当てて返す。"""
    cm = nav_input.chat_map
    if cm is None:
        return None
    handle = cm.thread_handle(thread_id)
    if handle or chat_source is None:
        return handle
    meta = await chat_source.thread_meta(thread_id)
    return cm.handle_for_new_thread(thread_id, meta["title"], meta["date"]) if meta else None


async def chat_section_owner_handle(
    nav_input: NavigatorInput, chat_source: Optional[ChatThreadSource], thread_id: str, section_number: int,
) -> Optional[str]:
    """あるスレッドの、ある節番号を「S{n}」(今の会話)か「P{k}/S{m}」(過去のチャット)に直す。"""
    if thread_id == nav_input.current_thread_id:
        return f"S{section_number}"
    p_handle = await chat_thread_handle_for(nav_input, chat_source, thread_id)
    return f"{p_handle}/S{section_number}" if p_handle else None


def _section_list_lines(sections: list[tuple[str, str, list[str]]]) -> str:
    """(呼び名, タイトル, 箇条書き)の一覧。節は要約なので箇条書きまで見せる(3-14 ④)。"""
    return "\n".join(f"{h} {title}" + "".join(f"\n  - {b}" for b in bullets) for h, title, bullets in sections) or "(No sections.)"


def _turn_list_lines(turns: list[dict], prefix: str) -> str:
    lines = []
    for t in turns:
        user = re.sub(r"\s+", " ", t["user_content"])[:CHAT_TURN_LIST_USER_CHARS]
        assistant = re.sub(r"\s+", " ", t["assistant_content"])[:CHAT_TURN_LIST_ASSISTANT_CHARS]
        lines.append(f"{prefix}/T{t['number']} Student: {user} | Assistant: {assistant}")
    return "\n".join(lines) if lines else "(No turns.)"


async def chat_open_handle(handle: str, relation: str, nav_input: NavigatorInput, chat_source: ChatThreadSource) -> Opened:
    """この会話の畳んだ節・過去のチャットを開く。「一覧 → 中身」の2段(3-14 ④)。"""
    cm = nav_input.chat_map
    parsed = parse_chat_handle(handle)
    if parsed is None or cm is None:
        return Opened(handle=handle, text=f"{handle}: (not found)", material=None)

    if parsed.kind == "section":
        section = cm.section(handle)
        if section is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        turns = [t for t in await chat_source.thread_turns(nav_input.current_thread_id) if t["number"] in section.turns]
        body = _turn_list_lines(turns, handle)
        return Opened(
            handle=handle, text=f"Section {handle}: {section.title}\n{body}",
            material=Material(key=f"chat_section:{nav_input.current_thread_id}:{parsed.number}", kind="chat_section",
                              label=f"This conversation / {section.title}", content=body, relation=relation,
                              source_type="chat_turn", thread_id=nav_input.current_thread_id,
                              metadata={"thread_id": nav_input.current_thread_id, "section_handle": parsed.number}, handle=handle),
            surfaced=[f"{handle}/T{t['number']}" for t in turns],
            ref={"type": "chat_section", "thread_id": nav_input.current_thread_id, "section_handle": parsed.number},
        )

    if parsed.kind == "group":
        group = cm.group(handle)
        if group is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        children = [c for c in (cm.section(h) for h in group.children) if c]
        body = _section_list_lines([(c.handle, c.title, c.bullets) for c in children])
        return Opened(
            handle=handle, text=f"Condensed part {handle}: {group.title}\nSections:\n{body}",
            material=Material(key=f"chat_group:{nav_input.current_thread_id}:{parsed.number}", kind="chat_thread",
                              label=f"This conversation / {group.title}", content=body, relation=relation,
                              source_type="chat_turn", thread_id=nav_input.current_thread_id,
                              metadata={"thread_id": nav_input.current_thread_id}, handle=handle),
            surfaced=[c.handle for c in children],
        )

    if parsed.kind == "thread_group":
        p_ref = cm.thread(parsed.prefix)
        if p_ref is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        group = next((g for g in await chat_source.thread_groups(p_ref.id) if g["handle"] == parsed.sub_group), None)
        if group is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        by_number = {sec["handle"]: sec for sec in await chat_source.thread_sections(p_ref.id)}
        children = [by_number[c] for c in group["children"] if c in by_number]
        body = _section_list_lines([(f"{parsed.prefix}/S{c['handle']}", c["title"], c["bullets"]) for c in children])
        return Opened(
            handle=handle, text=f"Condensed part {handle}: {group['title']} (in {p_ref.title})\nSections:\n{body}",
            material=Material(key=f"chat_group:{p_ref.id}:{parsed.sub_group}", kind="chat_thread",
                              label=f"{p_ref.title} / {group['title']}", content=body, relation=relation,
                              source_type="chat_turn", thread_id=p_ref.id, metadata={"thread_id": p_ref.id}, handle=handle),
            surfaced=[f"{parsed.prefix}/S{c['handle']}" for c in children],
        )

    if parsed.kind == "thread":
        ref = cm.thread(handle)
        if ref is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        turns, own_sections, own_groups = await asyncio.gather(
            chat_source.thread_turns(ref.id), chat_source.thread_sections(ref.id), chat_source.thread_groups(ref.id))
        # 過去のスレッド自身の畳んだ節(そのスレッド固有の番号体系。都度取得)
        folded_numbers = {n for s in own_sections for n in s["turns"]}
        trailing = [t for t in turns if t["number"] not in folded_numbers]
        parts = [f"Thread {handle}: {ref.title} ({ref.date or 'no date'})"]
        surfaced = []
        if own_groups:
            # 長いスレッド: 古い部分は2段目の節で見せ、2段目に入った1段目の節は出さない
            parts.append("Older parts (condensed; open one to see its sections):\n" + _section_list_lines(
                [(f"{handle}/H{g['handle']}", g["title"], g["bullets"]) for g in own_groups]))
            surfaced += [f"{handle}/H{g['handle']}" for g in own_groups]
            covered = {c for g in own_groups for c in g["children"]}
            own_sections = [sec for sec in own_sections if sec["handle"] not in covered]
        if own_sections:
            # 節はタイトルと箇条書き(要約)まで見せる。原文が要るときだけ節・往復を開けばよい(3-14 ④)
            parts.append("Folded sections:\n" + "\n".join(
                f"{handle}/S{s['handle']} {s['title']}" + "".join(f"\n  - {b}" for b in s["bullets"])
                for s in own_sections))
            surfaced += [f"{handle}/S{s['handle']}" for s in own_sections]
        if trailing or not (own_sections or own_groups):
            parts.append(("Recent turns:\n" if (own_sections or own_groups) else "") + _turn_list_lines(trailing, handle))
        surfaced += [f"{handle}/T{t['number']}" for t in trailing]
        body = "\n\n".join(parts[1:])
        return Opened(
            handle=handle, text="\n".join(parts),
            material=Material(key=f"chat_thread:{ref.id}", kind="chat_thread", label=f"{ref.title} / Chat",
                              content=body, relation=relation, source_type="chat_turn", thread_id=ref.id,
                              metadata={"thread_id": ref.id}, handle=handle),
            surfaced=surfaced, ref={"type": "thread", "id": ref.id},
        )

    if parsed.kind == "thread_section":
        p_ref = cm.thread(parsed.prefix)
        if p_ref is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        own_sections = await chat_source.thread_sections(p_ref.id)
        section = next((s for s in own_sections if s["handle"] == parsed.sub_section), None)
        if section is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        turns = [t for t in await chat_source.thread_turns(p_ref.id) if t["number"] in section["turns"]]
        body = _turn_list_lines(turns, handle)
        return Opened(
            handle=handle, text=f"Section {handle}: {section['title']} (in {p_ref.title})\n{body}",
            material=Material(key=f"chat_section:{p_ref.id}:{parsed.sub_section}", kind="chat_section",
                              label=f"{p_ref.title} / {section['title']}", content=body, relation=relation,
                              source_type="chat_turn", thread_id=p_ref.id,
                              metadata={"thread_id": p_ref.id, "section_handle": parsed.sub_section}, handle=handle),
            surfaced=[f"{handle}/T{t['number']}" for t in turns],
            ref={"type": "chat_section", "thread_id": p_ref.id, "section_handle": parsed.sub_section},
        )

    # turn / thread_turn: 1往復の全文
    thread_id = nav_input.current_thread_id if parsed.kind == "turn" else (cm.thread(parsed.prefix).id if cm.thread(parsed.prefix) else None)
    thread_title = "This conversation" if parsed.kind == "turn" else (cm.thread(parsed.prefix).title if cm.thread(parsed.prefix) else "")
    if thread_id is None:
        return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
    turn = next((t for t in await chat_source.thread_turns(thread_id) if t["number"] == parsed.turn), None)
    if turn is None:
        return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
    body = f"Student: {turn['user_content'][:CHAT_TURN_FULL_CHARS]}\nAssistant: {turn['assistant_content'][:CHAT_TURN_FULL_CHARS]}"
    return Opened(
        handle=handle, text=f"Turn {handle} ({(turn['created_at'] or '')[:10]}):\n{body}",
        material=Material(key=f"chat_turn:{thread_id}:{parsed.turn}", kind="chat_turn",
                          label=f"{thread_title} / Turn {parsed.turn}", content=body, relation=relation,
                          source_type="chat_turn", thread_id=thread_id,
                          metadata={"thread_id": thread_id, "turn_number": parsed.turn}, handle=handle),
        ref={"type": "chat_turn", "thread_id": thread_id, "turn_number": parsed.turn},
    )


async def resolve_hit_handles(
    chunks: list[dict], nav_input: NavigatorInput, source: LectureSource, chat_source: Optional[ChatThreadSource] = None,
) -> list[Hit]:
    """
    検索の当たりを、分かるところまで細かい呼び名に直す。
    - 講義: 文字起こしは文の範囲(metadata.sid_start/sid_end)、Deep Note・キーワード・復習カードは
      metadata.topic_number、トピックの要約・文字起こし(範囲なし)はsource_id = lecture_topics.id。
    - チャット: metadata.thread_id/turn_number。今のスレッドの、まだ畳んでいない部分(どの節にも
      属さない)に当たったものは、原文で既に見えているので捨てる(3-14 ④)。
    """
    m = nav_input.student_map
    lecture_chunks = [c for c in chunks if c.get("source_type") != "chat_turn"]
    chat_chunks = [c for c in chunks if c.get("source_type") == "chat_turn"]

    topic_ids = [c.get("source_id") for c in lecture_chunks
                 if c.get("source_type") in ("topic_summary", "transcript_topic") and c.get("source_id")]
    topic_index = await source.topic_indexes(topic_ids) if topic_ids else {}
    hits = []
    for c in lecture_chunks:
        lec_handle = m.lecture_handle(c.get("lecture_id"))
        handle = lec_handle
        meta = c.get("metadata") or {}
        if lec_handle:
            if c.get("source_type") == "transcript_topic" and isinstance(meta.get("sid_start"), int) and isinstance(meta.get("sid_end"), int):
                handle = range_handle(lec_handle, meta["sid_start"], meta["sid_end"])
            elif isinstance(meta.get("topic_number"), int):
                handle = f"{lec_handle}/T{meta['topic_number']}"
            elif c.get("source_id") in topic_index:
                handle = f"{lec_handle}/T{topic_index[c['source_id']][1]}"
        hits.append(Hit(handle=handle, chunk=c))

    for c in chat_chunks:
        meta = c.get("metadata") or {}
        thread_id, turn_number = meta.get("thread_id"), meta.get("turn_number")
        if not thread_id or not isinstance(turn_number, int) or nav_input.chat_map is None:
            continue
        if thread_id == nav_input.current_thread_id:
            section = next((s for s in nav_input.chat_map.sections if turn_number in s.turns), None)
            if section is None:
                continue  # まだ畳んでいない部分。<recent_conversation>に既に見えている
            hits.append(Hit(handle=f"{section.handle}/T{turn_number}", chunk=c))
        else:
            p_handle = await chat_thread_handle_for(nav_input, chat_source, thread_id)
            if p_handle:
                hits.append(Hit(handle=f"{p_handle}/T{turn_number}", chunk=c))
    return hits


async def prepare_previous_turn(
    nav_input: NavigatorInput, source: LectureSource, chat_source: Optional[ChatThreadSource], state: NavState,
) -> None:
    """
    前のターンで開いたもの(UUIDの参照)を今の呼び名に直し、一段下の一覧を付けて見せる
    (コースなら講義の一覧、講義ならトピックの一覧、スレッドなら直近の往復)。「その次の回」
    「3番目」を正確な呼び名に結びつけるため(評価で効いた形、3-6)。
    """
    m = nav_input.student_map
    blocks, handles = [], []
    for ref in nav_input.previous_turn_refs[:5]:
        kind = ref.get("type")
        if kind == "course":
            h = m.course_handle(ref.get("id"))
            course = m.course(h) if h else None
            if not course:
                continue
            rows = [f"  {x.handle} ({x.date.isoformat() if x.date else 'no date'}) {x.title}" for x in course.lectures]
            blocks.append(f"{h} — {course.title}\n" + "\n".join(rows))
            handles += [h] + [x.handle for x in course.lectures]
            continue
        if kind == "thread" and CAPABILITIES["CAN_CHAT"] and chat_source is not None:
            p_handle = await chat_thread_handle_for(nav_input, chat_source, ref.get("id"))
            t_ref = nav_input.chat_map.thread(p_handle) if p_handle and nav_input.chat_map else None
            if not t_ref:
                continue
            turns = (await chat_source.thread_turns(t_ref.id))[-PREVIOUS_THREAD_PREVIEW_TURNS:]
            rows = [f"  {p_handle}/T{t['number']} Student: {t['user_content'][:80]}" for t in turns]
            blocks.append(f"{p_handle} — {t_ref.title} ({t_ref.date or 'no date'})" + ("\n" + "\n".join(rows) if rows else ""))
            handles += [p_handle] + [f"{p_handle}/T{t['number']}" for t in turns]
            continue
        if kind == "chat_section" and CAPABILITIES["CAN_CHAT"] and chat_source is not None:
            h = await chat_section_owner_handle(nav_input, chat_source, ref.get("thread_id"), ref.get("section_handle"))
            if not h:
                continue
            blocks.append(f"{h} — a folded section of a conversation")
            handles.append(h)
            continue
        if kind == "chat_turn" and CAPABILITIES["CAN_CHAT"] and chat_source is not None:
            thread_id = ref.get("thread_id")
            n = ref.get("turn_number")
            if thread_id == nav_input.current_thread_id:
                h = f"S?/T{n}"  # 属する節が分からなければ、探索役はSの節を開いてから辿れる
                if nav_input.chat_map:
                    section = next((s for s in nav_input.chat_map.sections if n in s.turns), None)
                    h = f"{section.handle}/T{n}" if section else None
            else:
                p_handle = await chat_thread_handle_for(nav_input, chat_source, thread_id)
                h = f"{p_handle}/T{n}" if p_handle else None
            if not h or not isinstance(n, int):
                continue
            blocks.append(f"{h} — a turn of a past conversation")
            handles.append(h)
            continue
        lec_h = m.lecture_handle(ref.get("id") if kind == "lecture" else ref.get("lecture_id"))
        lec = m.lecture(lec_h) if lec_h else None
        if not lec:
            continue
        title = f"{lec.title} ({lec.date.isoformat() if lec.date else 'no date'})"
        if kind == "lecture":
            topics = await source.lecture_topics(lec.id)
            rows = [f"  {lec_h}/T{t['index']} {t['title']}" for t in topics]
            blocks.append(f"{lec_h} — {title}" + ("\n" + "\n".join(rows) if rows else ""))
            handles += [lec_h] + [f"{lec_h}/T{t['index']}" for t in topics]
        elif kind == "topic" and isinstance(ref.get("index"), int):
            h = f"{lec_h}/T{ref['index']}"
            blocks.append(f"{h} — a topic of {lec_h} {title}")
            handles.append(h)
        elif (kind == "transcript" and nav_input.can_transcript
              and isinstance(ref.get("sid_start"), int) and isinstance(ref.get("sid_end"), int)):
            h = range_handle(lec_h, ref["sid_start"], ref["sid_end"])
            blocks.append(f"{h} — part of the transcript of {lec_h} {title}")
            handles.append(h)
    state.previous_turn_text = "\n".join(blocks)
    state.previous_turn_handles = _dedupe(handles)


# =========================================================
# 🔎 検索の実行(本番)
# =========================================================

def make_lecture_search(
    user_client,
    student_map: StudentMap,
    embed: Callable[[list[str]], Awaitable[list[list[float]]]],
    blocked_source_types: frozenset[str] = frozenset(),
) -> SearchFn:
    """
    lecture.conceptの検索を実行する関数を作る。search_knowledge_chunksは必ずユーザー本人の
    JWTで作ったクライアントで呼ぶ(auth.uid()で本人の行だけに絞る設計、chat_service._retrieveと同じ)。
    embedは課金を記録する埋め込み関数(knowledge_index.embed_queriesにbillingを渡したもの)。
    今のプランで使えない種類(blocked_source_types)は、どのlayerでも検索しない。
    """
    def _rpc(embedding: list[float], req: FindRequest) -> list[dict]:
        types = layer_source_types(req.layer, blocked_source_types)
        if not types:
            return []
        params: dict[str, Any] = {
            "query_embedding": embedding,
            "match_count": SEARCH_MATCH_COUNT,
            "filter_source_types": types,
        }
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

    async def search(requests: list[FindRequest]) -> list[Union[list[dict], Exception]]:
        if not requests:
            return []
        embeddings = await embed([r.query for r in requests])
        return await asyncio.gather(
            *[asyncio.to_thread(_rpc, emb, req) for emb, req in zip(embeddings, requests)],
            return_exceptions=True,
        )

    return search


def make_chat_search(
    user_client,
    current_thread_id: Optional[str],
    embed: Callable[[list[str]], Awaitable[list[list[float]]]],
) -> SearchFn:
    """chat.all/chat.threadの検索。chat.threadだけ今のスレッドに絞る(RPCのfilter_thread_id)。"""
    def _rpc(embedding: list[float], req: FindRequest) -> list[dict]:
        params: dict[str, Any] = {
            "query_embedding": embedding, "match_count": SEARCH_MATCH_COUNT, "filter_source_types": ["chat_turn"],
        }
        if req.target == "chat.thread" and current_thread_id:
            params["filter_thread_id"] = current_thread_id
        res = user_client.rpc("search_knowledge_chunks", params).execute()
        return res.data or []

    async def search(requests: list[FindRequest]) -> list[Union[list[dict], Exception]]:
        if not requests:
            return []
        embeddings = await embed([r.query for r in requests])
        return await asyncio.gather(
            *[asyncio.to_thread(_rpc, emb, req) for emb, req in zip(embeddings, requests)],
            return_exceptions=True,
        )

    return search


def make_search(lecture_search: SearchFn, chat_search: SearchFn) -> SearchFn:
    """探索役に渡す1つの検索関数。target(lecture.* / chat.*)ごとに実際の検索へ振り分け、
    結果は元の順番のまま返す。"""
    async def search(requests: list[FindRequest]) -> list[Union[list[dict], Exception]]:
        lecture_reqs = [r for r in requests if r.target.startswith("lecture.")]
        chat_reqs = [r for r in requests if r.target.startswith("chat.")]
        lecture_results, chat_results = await asyncio.gather(lecture_search(lecture_reqs), chat_search(chat_reqs))
        li, ci = iter(lecture_results), iter(chat_results)
        return [next(li) if r.target.startswith("lecture.") else next(ci) for r in requests]

    return search


# =========================================================
# 🧭 本体: 最大4周
# =========================================================

async def decide_lap(llm: UnifiedLLM, nav_input: NavigatorInput, state: NavState, lap: int) -> tuple[Optional[dict], Optional[str]]:
    """1周分の判断(LLM)。読めない出力は1回だけやり直す。評価ハーネスもこれを呼ぶ。"""
    options = LLMOptions(
        # gpt-6-lunaはtemperatureの既定値(1)以外を受け付けない
        temperature=1.0,
        output_type="json",
        json_schema=build_schema(nav_input, state),
        max_completion_tokens=NAVIGATOR_MAX_COMPLETION_TOKENS,
        reasoning_effort=NAVIGATOR_REASONING_EFFORT,
    )
    messages = [
        Message(role="system", content=build_system_prompt(nav_input.can_transcript)),
        Message(role="user", content=build_user_message(nav_input, state, lap)),
    ]
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


def web_material(page: WebPage, relation: str, opened: bool) -> Material:
    """Webのページを回答役の材料に。開いたページは断片すべて、当たっただけのページは最初の方だけ。"""
    return Material(
        key=f"web:{page.url}",
        kind="web_page" if opened else "web",
        label=page.label(),
        content=page.text(WEB_PAGE_CHARS if opened else WEB_HIT_MATERIAL_CHARS),
        relation=relation,
        source_type="web",
        url=page.url,
        metadata={"title": page.title, "domain": page.domain},
        handle=page.handle,
    )


def add_web_pages(state: NavState, raw_pages: list[dict]) -> list[WebPage]:
    """
    Web検索の結果に呼び名W{n}を振ってstateに足す(周をまたいで通し番号)。同じURLが
    前の検索にも出ていたら、同じ呼び名を使う。上位WEB_PAGES_PER_SEARCH件だけ。
    """
    by_url = {p.url: p for p in state.web_pages.values()}
    pages: list[WebPage] = []
    for raw in raw_pages:
        url = (raw.get("url") or "").strip()
        if not url or url in {p.url for p in pages}:
            continue
        page = by_url.get(url)
        if page is None:
            snippets = [x for x in raw.get("snippets") or [] if isinstance(x, str)]
            page = WebPage(handle=f"W{len(state.web_pages) + 1}", title=(raw.get("title") or "").strip(), url=url, snippets=snippets)
            state.web_pages[page.handle] = page
            by_url[url] = page
        pages.append(page)
        if len(pages) >= WEB_PAGES_PER_SEARCH:
            break
    return pages


def open_web_page(page: WebPage, relation: str) -> Opened:
    text = f"{page.handle} — {page.label()}\n{page.url}\n{page.text(WEB_PAGE_CHARS) or '(no text extracted)'}"
    return Opened(handle=page.handle, text=text, material=web_material(page, relation, opened=True))


async def execute_lap(record: LapRecord, nav_input: NavigatorInput, state: NavState, tools: NavigatorTools) -> None:
    """検証済みの操作を並列に実行し、stateに足す。"""
    finds = [r for r in record.requests if isinstance(r, FindRequest) and r.target != "web.search"]
    web_finds = [r for r in record.requests if isinstance(r, FindRequest) and r.target == "web.search"]
    opens = [r for r in record.requests if isinstance(r, OpenRequest)]
    dates = [r for r in record.requests if isinstance(r, DateRequest)]

    async def run_finds() -> list[SearchOutcome]:
        if not finds:
            return []
        try:
            results = await tools.search(finds)
        except Exception as e:
            results = [e] * len(finds)
        outcomes = []
        for req, res in zip(finds, results):
            if isinstance(res, Exception):
                print(f"⚠️ [chat] navigator search failed ({req.label()}): {res}")
                outcomes.append(SearchOutcome(request=req, hits=[], error=str(res)[:300]))
            else:
                outcomes.append(SearchOutcome(request=req, hits=await resolve_hit_handles(res, nav_input, tools.source, tools.chat_source)))
        return outcomes

    async def run_web(req: FindRequest) -> Union[list[dict], Exception]:
        if tools.web_search is None:
            return RuntimeError("web search is not available")
        try:
            return await tools.web_search(req.query)
        except Exception as e:
            return e

    async def run_open(req: OpenRequest) -> Opened:
        if req.handle in state.web_pages:
            return open_web_page(state.web_pages[req.handle], req.relation)
        try:
            return await open_handle(req.handle, req.relation, nav_input, tools.source, tools.chat_source)
        except Exception as e:
            print(f"⚠️ [chat] navigator open failed ({req.handle}): {e}")
            return Opened(handle=req.handle, text=f"{req.handle}: (could not be opened)", material=None)

    find_outcomes, web_results, *opened = await asyncio.gather(
        run_finds(), asyncio.gather(*[run_web(r) for r in web_finds]), *[run_open(r) for r in opens])

    # 呼び名は依頼の順に振る(並列に返ってきた順ではなく)
    web_outcomes: list[WebSearchOutcome] = []
    for req, res in zip(web_finds, web_results):
        if isinstance(res, Exception):
            print(f"⚠️ [chat] navigator web search failed ({req.label()}): {res}")
            web_outcomes.append(WebSearchOutcome(request=req, pages=[], error=str(res)[:300]))
        else:
            web_outcomes.append(WebSearchOutcome(request=req, pages=add_web_pages(state, res)))

    m = nav_input.student_map
    titles = {c.handle: c.title for c in m.courses}
    date_outcomes = [DateOutcome(request=r, lectures=m.lectures_between(r.date_from, r.date_to, r.within), course_titles=titles)
                     for r in dates]

    for op in opened:
        state.opened[op.handle] = op
    for o in find_outcomes:
        state.outcomes.append(o)
        for hit in o.hits:
            state.search_materials.append(material_from_chunk(hit.chunk, relation=o.request.relation, handle=hit.handle))
    for o in web_outcomes:
        state.outcomes.append(o)
        for page in o.pages:
            state.search_materials.append(web_material(page, o.request.relation, opened=False))
    state.outcomes += date_outcomes
    record.done = ([f"open {op.handle}" for op in opened] + [o.summary() for o in find_outcomes]
                   + [o.summary() for o in web_outcomes] + [o.summary() for o in date_outcomes])


async def navigate(
    llm: UnifiedLLM,
    nav_input: NavigatorInput,
    tools: NavigatorTools,
    on_lap: Optional[Callable[[int], Awaitable[None]]] = None,
    on_fetch: Optional[Callable[[dict], Awaitable[None]]] = None,
) -> NavigationResult:
    """
    探索役を最大MAX_LAPS周まわす。1周ごとに「判断(LLM) → 検証(コード) → 実行(コード)」。
    途中の周で探索役が動かなくなったら、そこまでに集めたもので終わる。
    """
    state = NavState()
    if nav_input.previous_turn_refs and CAPABILITIES["CAN_OPEN"]:
        try:
            await prepare_previous_turn(nav_input, tools.source, tools.chat_source, state)
        except Exception as e:
            print(f"⚠️ [chat] failed to prepare the previous turn's materials: {e}")
    goal: list[str] = []
    stop_reason = "max_laps"

    for lap in range(1, MAX_LAPS + 1):
        if on_lap is not None:
            await on_lap(lap)
        t0 = time.perf_counter()
        out, err = await decide_lap(llm, nav_input, state, lap)
        if out is None:
            print(f"⚠️ [chat] navigator lap {lap} failed: {err}")
            state.laps.append(LapRecord(lap=lap, status="", missing="", reasoning="", goal=[],
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
        state.laps.append(record)
        if record.goal:
            goal = record.goal

        if record.status != "need_more":
            stop_reason = record.status
            record.elapsed_ms = round((time.perf_counter() - t0) * 1000)
            break

        record.requests, record.dropped = validate_operations(out.get("operations"), nav_input, state)
        if not record.requests:
            # need_moreと言いつつ実行できる操作が無い(全部繰り返し等): ここまでで答える
            stop_reason = "enough_now"
            record.elapsed_ms = round((time.perf_counter() - t0) * 1000)
            break
        if on_fetch is not None:
            await on_fetch(fetch_info(record.requests))
        await execute_lap(record, nav_input, state, tools)
        record.elapsed_ms = round((time.perf_counter() - t0) * 1000)

    materials = [op.material for op in state.opened.values() if op.material] + state.search_materials
    refs = [op.ref for op in state.opened.values() if op.ref]
    return NavigationResult(materials=materials, goal=goal, laps=state.laps, stop_reason=stop_reason, opened_refs=refs)


def fetch_kinds(requests: list[Request]) -> list[str]:
    """この周で何を探すか(画面の「〜を検索中」用): web / chats / lectures。"""
    kinds: list[str] = []
    for r in requests:
        if isinstance(r, FindRequest):
            kind = "web" if r.target == "web.search" else "chats" if r.target.startswith("chat.") else "lectures"
        elif isinstance(r, OpenRequest):
            kind = "web" if _WEB_HANDLE_RE.match(r.handle) else "chats" if r.handle[:1] in ("S", "P", "H") else "lectures"
        else:
            kind = "lectures"
        if kind not in kinds:
            kinds.append(kind)
    return kinds


def fetch_info(requests: list[Request]) -> dict:
    """この周で実行する操作の詳細(画面の『〜を検索中』用)"""
    kinds = fetch_kinds(requests)
    info: dict = {
        "kinds": kinds,
        "query": None,
        "target": None,
        "layer": None,
        "handle": None,
    }
    selected_r = None
    for r in requests:
        if isinstance(r, FindRequest):
            if r.target == "web.search":
                selected_r = r
                break
            elif r.layer == "transcript" and (selected_r is None or getattr(selected_r, "layer", None) != "transcript"):
                selected_r = r
            elif selected_r is None:
                selected_r = r
        elif isinstance(r, OpenRequest) and selected_r is None:
            selected_r = r

    if isinstance(selected_r, FindRequest):
        info["query"] = selected_r.query
        info["target"] = "web" if selected_r.target == "web.search" else "chats" if selected_r.target.startswith("chat.") else "lectures"
        info["layer"] = selected_r.layer
    elif isinstance(selected_r, OpenRequest):
        info["target"] = "web" if _WEB_HANDLE_RE.match(selected_r.handle) else "chats" if selected_r.handle[:1] in ("S", "P", "H") else "lectures"
        info["handle"] = selected_r.handle

    return info


def summarize_for_log(result: NavigationResult) -> str:
    parts = [f"stop={result.stop_reason}"]
    for lp in result.laps:
        parts.append(f"lap{lp.lap}:{lp.status or 'error'}:{len(lp.done)}ops:{lp.elapsed_ms}ms")
    return " ".join(parts)


def refs_from_materials(materials: list[Material], limit: int = 5) -> list[dict]:
    """何も開かなかったターンの「前のターンで開いたもの」: 回答に使った材料の講義・トピック・チャット。"""
    refs: list[dict] = []
    for mat in materials:
        meta = mat.metadata or {}
        if mat.thread_id:
            turn = meta.get("turn_number")
            section = meta.get("section_handle")
            if isinstance(turn, int):
                ref = {"type": "chat_turn", "thread_id": mat.thread_id, "turn_number": turn}
            elif isinstance(section, int):
                ref = {"type": "chat_section", "thread_id": mat.thread_id, "section_handle": section}
            else:
                ref = {"type": "thread", "id": mat.thread_id}
        elif mat.lecture_id:
            topic = meta.get("topic_number")
            ref = ({"type": "topic", "lecture_id": mat.lecture_id, "index": topic} if isinstance(topic, int)
                   else {"type": "lecture", "id": mat.lecture_id})
        else:
            continue
        if ref not in refs:
            refs.append(ref)
        if len(refs) >= limit:
            break
    return refs

