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
import unicodedata
from dataclasses import dataclass, field
from datetime import date
from typing import Any, Awaitable, Callable, Optional, Union
from urllib.parse import urlparse

from app.services.chat_attachments import Attachment, Visibility, render_for_navigator, split_sections
from app.services.chat_links import Link, LinkPage, render_for_navigator as render_links_for_navigator
from app.services.chat_lecture_source import LectureSource, first_sentence
from app.services.chat_map import ChatMap, MapLecture, StudentMap
from app.services.chat_materials import (
    LINK_PAGE_MAX_CHARS,
    Material,
    format_lecture_review_cards,
    material_from_chunk,
)
from app.services.chat_thread_source import ChatThreadSource
from app.services.helpers.helpers import _load_prompt, _render_conditional_sections
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM


# =========================================================
# ⚙️ 設定
# =========================================================

NAVIGATOR_MODEL = "anthropic/claude-haiku-5-5"
NAVIGATOR_REASONING_EFFORT = "none"
# 2026-11-06に1500から3000へ(ユーザー判断)。弟のスレッド「Midterm 2 scope summary」で、全コースの
# by_date(26講義)の後の2周目が1500トークンで切れてJSONが壊れ(2回とも)、探索が打ち切られたため。
NAVIGATOR_MAX_COMPLETION_TOKENS = 3000

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
TRANSCRIPT_CHARS = 3000
# 文字起こしの範囲として受け付ける最大の文の数(Deep Noteの引用・検索の当たりは十数文まで)
TRANSCRIPT_MAX_SENTENCES = 60
# 日付で引く範囲の上限(日数)
BY_DATE_MAX_DAYS = 400
# 範囲の講義をまとめて取るとき(C{n}/L{a}-{b}、C{n}/L{a}-{b}/cards、by_date)に、回答役へ渡す材料の
# 1ターンの予算(estimate_tokensで数える)。回答役の材料全体の上限(MATERIALS_MAX_TOKENS=15,000)のうち、
# お知らせや検索結果のために約5,000を残す。入らなければ真ん中を削るのではなく、詳しさの段階を下げる
# (要約+トピック要約 → 要約+トピック名 → タイトルだけ)。カードは残りの予算で各講義に均等に配る。
# 2026-11-06: Formal logicの10月の7講義で、要約+トピック要約が約3,800、カード(core_why・gotcha)が約13,400。
RANGE_MATERIAL_BUDGET = 10_000

# 探索役に見せる直近の会話(未要約の全履歴が見えるように拡張)
RECENT_CONVERSATION_MAX_MESSAGES = 20
RECENT_CONVERSATION_MAX_CHARS = 1200

# チャットを開いたときの一覧1行(学生の発言・返答それぞれ)と、1往復を開いたときの全文
CHAT_TURN_LIST_USER_CHARS = 150
CHAT_TURN_LIST_ASSISTANT_CHARS = 300
CHAT_TURN_FULL_CHARS = 3000
# 前のターンで開いたスレッドの一覧プレビューは、直近の往復だけに絞る(長くなりすぎないように)
PREVIOUS_THREAD_PREVIEW_TURNS = 5

# Web(3-14 ⑤)。検索は1回$0.005なので1ターン2回まで(コードで止める)。1回の検索で見せるのは
# 上位5ページ。開くとそのページの断片すべて(Braveが抜き出し済みなので追加の通信は無い)。
MAX_WEB_SEARCHES_PER_TURN = 2
# 授業・チャットの検索(lecture.concept / chat.*)も1ターン2回まで(最初の1回と言い換えの1回)。
# 見つからないときに探し回るのを、プロンプトの指示だけでは止められなかった(2026-10-02の評価)。
MAX_SEARCHES_PER_TURN = 2
WEB_PAGES_PER_SEARCH = 5
WEB_PAGE_CHARS = 3000
# 検索で当たっただけ(開いていない)のページを回答役に渡すときの長さ
WEB_HIT_MATERIAL_CHARS = 1000

# 会話に出てきたリンク(U1…)を開く回数の上限(1ターン)。1回数秒かかり、Tavilyに頼むと無料枠を使う
MAX_LINK_OPENS_PER_TURN = 3
# 開いたリンクのページを探索役に見せる長さ(回答役にはchat_materials.LINK_PAGE_MAX_CHARSまで渡す)
LINK_NAVIGATOR_CHARS = 3000
# 回答役に渡しきれない長いページは、節(U1/S3)に区切って目次を探索役に見せる(課題が「9.3節を読め」と
# 指すような場合、先頭だけでは届かない。2026-10-16、Pythonのチュートリアル3.5万字で確認)
LINK_SECTION_TITLE_CHARS = 80
LINK_MAX_SECTIONS_SHOWN = 60

# 今の段階で使える操作(3-12の順に増やす)。プロンプトの<!--IF:CAN_...-->と対応する。
CAPABILITIES = {
    "CAN_OPEN": True,      # 目次を開く(lecture.outline)・文字起こしの範囲を開く
    "CAN_BY_DATE": True,   # 講義を日付で引く
    "CAN_CHAT": True,      # この会話の畳んだ部分・過去のチャット
    "CAN_WEB": True,       # Web検索
    "CAN_ATTACHMENTS": True,  # このスレッドに添付された資料(目次・節を開く。ロードマップ10章)
    "CAN_LINKS": True,     # 会話に出てきたリンクのページを開く(chat_links.py、2026-10-16)
}

STATUSES = ["nothing_needed", "enough_now", "need_more"]
# 取りに行く必要度(探索役が最初に選ぶ)。取りに行くのはexplicit(頼まれた)とimplied(意図から
# 明らかに必要)だけ。maybe(役に立つかもしれない)とnone(不要)は取りに行かない。maybeは
# 出どころ(fetch_from)と一緒に記録だけしておく(将来、裏で確かめて補足する機能のため)。
NEEDS = ["explicit", "implied", "maybe", "none"]
FETCH_NEEDS = ("explicit", "implied")
# 出どころ → 操作の行き先。選んだ出どころの外への操作(例: classだけなのにweb.search)はコードで捨てる。
_SOURCE_KINDS: dict[str, str] = {"class": "lecture", "web": "web", "past_chat": "chat", "attachment": "attachment",
                                  "link": "link"}

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
_COURSE_SUB_RE = re.compile(r"^(C\d+)/(topics|keywords|announcements)$")
_MULTI_CARDS_RE = re.compile(r"^(C\d+)/L(\d+)-(\d+)/cards$")
_LEC_RANGE_RE = re.compile(r"^(C\d+)/L(\d+)-(\d+)$")
_LEC_SUB_RE = re.compile(r"^(C\d+)/(L\d+)/(announcements|cards)$")
# S{n}(この会話の節) / S{n}/T{k}(その節の往復) / P{n}(過去のチャット) /
# P{n}/S{m}(その過去のチャットの節) / P{n}/T{k}(その過去のチャットの往復) /
# H{n}(この会話の2段目の節) / P{n}/H{m}(その過去のチャットの2段目の節)
_CHAT_HANDLE_RE = re.compile(r"^(S|P|H)(\d+)(?:/(?:S(\d+)|T(\d+)|H(\d+)))?$")
# W{n}(このターンのWeb検索で当たったページ。周をまたいで通し番号)
_WEB_HANDLE_RE = re.compile(r"^W\d+$")
# A{n}(このスレッドに添付された資料。開くと目次) / A{n}/S{k}(その資料の節の本文)
_ATTACHMENT_HANDLE_RE = re.compile(r"^A(\d+)(?:/S(\d+))?$")
# U{n}(この会話に出てきたリンク。開くとそのページの本文を今取ってくる) /
# U{n}/S{k}(長いページの節。開いたページから区切るので、取り直しはしない)
_LINK_HANDLE_RE = re.compile(r"^U\d+$")
_LINK_SECTION_RE = re.compile(r"^(U\d+)/S(\d+)$")


def available_ops() -> list[str]:
    ops = ["find"]
    if CAPABILITIES["CAN_OPEN"]:
        ops.append("open")
    if CAPABILITIES["CAN_BY_DATE"]:
        ops.append("by_date")
    return ops


def available_fetch_sources() -> list[str]:
    sources = ["class"]
    if CAPABILITIES["CAN_WEB"]:
        sources.append("web")
    if CAPABILITIES["CAN_CHAT"]:
        sources.append("past_chat")
    if CAPABILITIES["CAN_ATTACHMENTS"]:
        sources.append("attachment")
    if CAPABILITIES["CAN_LINKS"] and CAPABILITIES["CAN_OPEN"]:
        sources.append("link")
    return sources


def available_targets(web_left: bool = True, search_left: bool = True) -> list[str]:
    """web_left/search_left=False: このターンのWeb検索 / 授業・チャットの検索を使い切った(enumから外して選べなくする)。"""
    targets = ["lecture.concept"] if search_left else []
    if CAPABILITIES["CAN_CHAT"] and search_left:
        targets += ["chat.all", "chat.thread"]
    if CAPABILITIES["CAN_ATTACHMENTS"] and search_left:
        targets.append("attachment.search")
    if CAPABILITIES["CAN_WEB"] and web_left:
        targets.append("web.search")
    return targets


# =========================================================
# 🧩 呼び名
# =========================================================

@dataclass
class ParsedHandle:
    kind: str  # course / lecture / topic / transcript / course_topics / course_keywords / course_announcements / lecture_announcements / lecture_cards / multi_lecture_cards
    course: str
    lecture: Optional[str] = None
    topic_index: Optional[int] = None
    sid_start: Optional[int] = None
    sid_end: Optional[int] = None
    lecture_start: Optional[int] = None
    lecture_end: Optional[int] = None


def parse_handle(handle: str) -> Optional[ParsedHandle]:
    h = (handle or "").strip()
    m_course_sub = _COURSE_SUB_RE.match(h)
    if m_course_sub:
        c, sub = m_course_sub.groups()
        return ParsedHandle(kind=f"course_{sub}", course=c)
    m_multi = _MULTI_CARDS_RE.match(h)
    if m_multi:
        c, l1, l2 = m_multi.groups()
        a, b = int(l1), int(l2)
        return ParsedHandle(kind="multi_lecture_cards", course=c, lecture_start=min(a, b), lecture_end=max(a, b))
    m_range = _LEC_RANGE_RE.match(h)
    if m_range:
        c, l1, l2 = m_range.groups()
        a, b = int(l1), int(l2)
        return ParsedHandle(kind="lecture_range", course=c, lecture_start=min(a, b), lecture_end=max(a, b))
    m_lec_sub = _LEC_SUB_RE.match(h)
    if m_lec_sub:
        c, l, sub = m_lec_sub.groups()
        return ParsedHandle(kind=f"lecture_{sub}", course=c, lecture=f"{c}/{l}")
    m = _HANDLE_RE.match(h)
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


# --- 探索役が書いた呼び名を、正しい形に直す ---
# handleは自由な文字列(build_schema)なので、見た目が同じでも形の違う書き方が来る(2026-11-06に
# "C4/L6-L7" が handle_not_openable で捨てられ、その周が丸ごと無駄になった。正しくは "C4/L6-7")。
# 正しい形の呼び名はそのまま返す(何度通しても同じ)。直せないものは、そのあとの検証で今までどおり捨てる。
_HANDLE_DASH_TABLE = str.maketrans({ch: "-" for ch in "‐‑‒–—―−﹣ー〜~"})  # NFKCの後(全角の－～は-~になる)
_HANDLE_WRAP_CHARS = "`'\"“”‘’「」『』[](){}<>⟦⟧*"
_HANDLE_RANGE_WORD_RE = re.compile(r"(?<=\d)\s*(?:\.{2,3}|…|-|\bto\b|\bthrough\b|\bthru\b|から)\s*(?=[A-Za-z]?\s*\d)",
                                   re.IGNORECASE)
# 1つの区切り: 文字+番号、範囲なら2つめの番号の前に同じ文字があってもよい(L6-L7 / s10-s20)
_HANDLE_SEGMENT_RE = re.compile(r"^([A-Za-z])0*(\d+)(?:-(?:([A-Za-z]))?0*(\d+))?$")
_HANDLE_WORD_PREFIX = {"course": "C", "lecture": "L", "lec": "L", "topic": "T"}
_HANDLE_SUB_WORDS = {
    "topic": "topics", "topics": "topics",
    "keyword": "keywords", "keywords": "keywords",
    "announcement": "announcements", "announcements": "announcements",
    "card": "cards", "cards": "cards", "reviewcard": "cards", "reviewcards": "cards",
}
# 同じコースを2回書いた範囲(C4/L6-C4/L7)
_HANDLE_REPEATED_COURSE_RE = re.compile(r"^(C\d+)/L(\d+)-(C\d+)/L(\d+)(/.*)?$")


def _normalize_handle_segment(seg: str, index: int, segs: list[str]) -> str:
    low = seg.lower().replace("_", "").replace("-", "") if not any(c.isdigit() for c in seg) else seg.lower()
    if low in _HANDLE_SUB_WORDS:
        return _HANDLE_SUB_WORDS[low]
    for word, letter in _HANDLE_WORD_PREFIX.items():
        if low.startswith(word) and low[len(word):].lstrip()[:1].isdigit():
            seg = letter + seg[len(word):].strip()
            break
    m = _HANDLE_SEGMENT_RE.match(seg)
    if not m:
        return seg
    letter, a, letter_b, b = m.groups()
    if letter_b is not None and letter_b.lower() != letter.lower():
        return seg  # L6-C4 のような別の文字の範囲は直さない
    # C{n}/L{m}/s{a}-{b}(文字起こしの文)だけは小文字のs。他(A1/S2・U1/S2・P1/S2・S3)は大文字
    is_sentence = (index == 2 and letter.lower() == "s"
                   and segs[0][:1].upper() == "C" and segs[1][:1].upper() == "L")
    letter = "s" if is_sentence else letter.upper()
    if b is None:
        return f"{letter}{int(a)}"
    lo, hi = sorted((int(a), int(b)))
    if is_sentence and lo == hi:
        return f"{letter}{lo}"  # range_handleと同じく、1文だけの範囲は s{a}
    return f"{letter}{lo}-{hi}"


def normalize_handle(handle: Any) -> str:
    """探索役が書いた呼び名を正しい形にする(全角・ダッシュの種類・大文字小文字・前のゼロ・空白・引用符・
    範囲の2つめの文字の繰り返し(L6-L7)・"L6 to L7"・単数形(topic/card)・後ろに付けた名前など)。"""
    if not isinstance(handle, str):
        return ""
    h = unicodedata.normalize("NFKC", handle).translate(_HANDLE_DASH_TABLE).strip()
    h = re.sub(r"^(?:open|handle)(?:\s*[:=]\s*|\s+)", "", h, flags=re.IGNORECASE)
    h = h.strip().strip(_HANDLE_WRAP_CHARS).strip()
    h = re.split(r"[(\[{<「『:]", h, maxsplit=1)[0]  # "C4/L6(10月13日)" / "C4/L6: Haskell" の後ろを捨てる
    h = re.sub(r"\s*([/\\])\s*", "/", h)
    h = _HANDLE_RANGE_WORD_RE.sub("-", h)
    h = re.sub(r"(?<=[A-Za-z])\s+(?=\d)", "", h)  # "Lecture 6" / "L 6"
    h = h.split()[0] if h.split() else ""  # 後ろに付けた講義名や説明("C4/L6 (Oct 13)")は捨てる
    h = h.strip(_HANDLE_WRAP_CHARS + ".,;:/")
    if not h:
        return ""
    segs = [s for s in h.split("/") if s]
    segs = [_normalize_handle_segment(s, i, segs) for i, s in enumerate(segs)]
    h = "/".join(segs)
    m = _HANDLE_REPEATED_COURSE_RE.match(h)
    if m and m.group(1) == m.group(3):
        lo, hi = sorted((int(m.group(2)), int(m.group(4))))
        h = f"{m.group(1)}/L{lo}-{hi}{m.group(5) or ''}"
    return h


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
    current_time_str: Optional[str] = None
    chat_map: Optional[ChatMap] = None
    # 今のスレッドのID(chat.thread/chat.allの絞り込み・当たった往復がどのスレッドのものかの判定に使う)
    current_thread_id: Optional[str] = None
    # 前のターンで開いたもの(返答の行のcontext.openedに保存したUUIDの参照)
    previous_turn_refs: list[dict] = field(default_factory=list)
    # 画面で見ているトピックの番号(Deep Notes・復習カードのページ)
    screen_topic_index: Optional[int] = None
    # コースの画面から送ったときのコース(講義を見ているときはNone。screen_lecture_idからコースが分かる)
    screen_course_id: Optional[str] = None
    # 見ているページ(chat_screen.py)の名前と抜粋。全文は回答役にだけ渡す
    screen_page_title: Optional[str] = None
    screen_page_excerpt: Optional[str] = None
    # 今のプランで使えない材料の種類(plan_features.blocked_knowledge_source_types)
    blocked_source_types: frozenset[str] = frozenset()
    # このスレッドに添付された資料(呼び名A1…を振ったもの)と、回答役に全文で見せている資料
    attachments: list[Attachment] = field(default_factory=list)
    attachment_visibility: Optional[Visibility] = None
    # 推論が要るターンで、全文が見えていない資料がある: 資料の該当箇所を取ってくるよう明示する(10章)
    must_check_attachments: bool = False
    # この会話に出てきたリンク(呼び名U1…を振ったもの。chat_links.collect_links)
    links: list[Link] = field(default_factory=list)
    # 仕分け役が整理した、このターンの生徒の真の目的と文脈アンカー
    user_goal: Optional[str] = None
    # 過去の会話ノートから引き継がれた重要な原文ターン(アジェンダなど)
    referenced_sources: Optional[str] = None

    @property
    def can_transcript(self) -> bool:
        return "transcript_topic" not in self.blocked_source_types

    def attachment(self, handle: str) -> Optional[Attachment]:
        return next((a for a in self.attachments if a.handle == handle), None)

    def link(self, handle: str) -> Optional[Link]:
        return next((x for x in self.links if x.handle == handle), None)

    def link_handles(self) -> list[str]:
        if not (CAPABILITIES["CAN_LINKS"] and CAPABILITIES["CAN_OPEN"]):
            return []
        return [x.handle for x in self.links]

    def attachment_scope_handles(self) -> list[str]:
        """1周目から開ける資料: 回答役に全文で見せていないものだけ(全文で見えているものは開く意味が無い)。"""
        if not CAPABILITIES["CAN_ATTACHMENTS"]:
            return []
        vis = self.attachment_visibility
        return [a.handle for a in self.attachments if vis is None or not vis.is_full(a)]

    def mentioned_unseen_handles(self) -> list[str]:
        """生徒が文中で指した資料のうち、回答役に全文で見せていないもの(その中を探しに行く)。"""
        if not CAPABILITIES["CAN_ATTACHMENTS"] or self.attachment_visibility is None:
            return []
        vis = self.attachment_visibility
        return [a.handle for a in self.attachments if vis.is_mentioned(a) and not vis.is_full(a)]

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
    # 回答役に渡す範囲の概要(build_range_overview)。探索役には中身ではなくoverview_noteだけ見せる
    overview_body: str = ""
    overview_tokens: int = 0
    overview_note: str = ""

    def render(self) -> str:
        if not self.lectures:
            return f"{self.request.label()}:\n(no lectures in this range)"
        lines = [
            f"- {lec.handle} ({lec.format_when() if hasattr(lec, 'format_when') else (lec.date.isoformat() if lec.date else 'no date')}) {self.course_titles.get(lec.course_handle, '')} / {lec.title}"
            for lec in self.lectures
        ]
        note = f"\n{self.overview_note}" if self.overview_note else ""
        return f"{self.request.label()}:\n" + "\n".join(lines) + note

    def to_material(self) -> Optional[Material]:
        """日付で引いた講義の一覧を、回答役に見せる材料(Material)に変換する。"""
        if not self.lectures:
            return None
        lines = []
        for lec in self.lectures:
            when = lec.format_when() if hasattr(lec, "format_when") else (lec.date.isoformat() if lec.date else "no date")
            course_title = self.course_titles.get(lec.course_handle, "")
            lines.append(f"- {lec.handle} ({when}) {course_title} / {lec.title}")
        span_str = f"{self.request.date_from} to {self.request.date_to}"
        # 回答役に渡す本文なので、コースは呼び名(C7)ではなく名前で書く
        within_str = f" in {self.course_titles.get(self.request.within, self.request.within)}" if self.request.within else ""
        if self.overview_body:
            body = f"Lectures recorded ({span_str}{within_str}):\n\n{self.overview_body}"
        else:
            body = f"Lectures recorded ({span_str}{within_str}):\n" + "\n".join(lines)
        return Material(
            key=f"by_date:{self.request.date_from}:{self.request.date_to}:{self.request.within or 'all'}",
            kind="lecture_range" if self.overview_body else "lecture",
            label=f"Lectures ({span_str})",
            content=body,
            source_type="lecture_summary",
        )

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
    # 範囲の材料の予算から使った量(estimate_tokens)
    range_tokens: int = 0


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
    # 取りに行く必要度(explicit / implied / maybe / none)と出どころ(class / web / past_chat)
    need: str = ""
    fetch_from: list[str] = field(default_factory=list)
    # 速度の計測(どこで時間がかかっているか): decide_ms/attempts/トークン数(判断のLLM)、
    # execute_ms(実行の合計)とfind_ms/web_ms/open_ms(並列に走る実行の内訳)
    timing: dict = field(default_factory=dict)

    def to_json(self) -> dict:
        def req_json(r: Request) -> dict:
            d = {k: (v.isoformat() if isinstance(v, date) else v) for k, v in vars(r).items()}
            d["op"] = {FindRequest: "find", OpenRequest: "open", DateRequest: "by_date"}[type(r)]
            return d
        return {
            "lap": self.lap,
            "need": self.need,
            "fetch_from": self.fetch_from,
            "status": self.status,
            "missing": self.missing,
            "reasoning": self.reasoning,
            "goal": self.goal,
            "requests": [req_json(r) for r in self.requests],
            "done": self.done,
            "dropped": self.dropped,
            "elapsed_ms": self.elapsed_ms,
            "timing": self.timing,
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
    # 開いたリンクの結果(取れた・取れなかった・どの取り方か。記録用)
    link_fetches: list[dict] = field(default_factory=list)
    # 開けなかったリンク(URL, 理由)。回答役に「開こうとしたが読めなかった」と伝える
    link_failures: list[tuple[str, str]] = field(default_factory=list)
    # 節に区切った長いページ(U1 → (ページの名前, URL, 本文, 節の位置))
    link_sections: dict[str, tuple[str, str, str, list[tuple[int, int]]]] = field(default_factory=dict)
    # 範囲の講義をまとめて取る材料(by_date・C{n}/L{a}-{b}・…/cards)の、このターンの残り予算
    range_budget_left: int = RANGE_MATERIAL_BUDGET

    def link_opens_left(self) -> int:
        used = sum(1 for h in self.opened if _LINK_HANDLE_RE.match(h))
        return max(0, MAX_LINK_OPENS_PER_TURN - used)

    def web_searches_left(self) -> int:
        used = sum(1 for o in self.outcomes if isinstance(o, WebSearchOutcome))
        return max(0, MAX_WEB_SEARCHES_PER_TURN - used)

    def searches_left(self) -> int:
        """授業・チャットの検索の残り回数。"""
        used = sum(1 for o in self.outcomes if isinstance(o, SearchOutcome))
        return max(0, MAX_SEARCHES_PER_TURN - used)

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
    # 1周目の前に前のターンで開いたものを読み直した時間(速度の計測用)
    prepare_ms: int = 0
    # 開いたリンクの結果(どのサイトがよく失敗するかを見て、専用の取り方を足すため)
    links: list[dict] = field(default_factory=list)
    # 開けなかったリンク(URL, 理由)。回答役に渡す
    link_failures: list[tuple[str, str]] = field(default_factory=list)

    @property
    def failed_before_any_fetch(self) -> bool:
        """1周目で探索役自体が動かなかった(このときは呼び出し側が従来の検索に倒す)。"""
        return self.stop_reason == "llm_error" and not any(lap.done for lap in self.laps)

    def to_json(self) -> dict:
        return {
            "model": NAVIGATOR_MODEL,
            "stop_reason": self.stop_reason,
            "goal": self.goal,
            "prepare_ms": self.prepare_ms,
            "laps": [lap.to_json() for lap in self.laps],
            **({"links": self.links} if self.links else {}),
        }


# 検索の実行(ネットワーク・DBに触れる部分)。呼び出し側がユーザー本人のJWTで作る。
# 返り値は検索ごとのチャンクの一覧(失敗した検索はException)。
SearchFn = Callable[[list[FindRequest]], Awaitable[list[Union[list[dict], Exception]]]]
# Web検索1回(クエリ → [{title, url, snippets}])。失敗は例外。
WebSearchFn = Callable[[str], Awaitable[list[dict]]]
# リンク先の本文を取る(chat_links.fetch_link)。例外は投げず、取れなかったらLinkPage.errorに理由
LinkFetchFn = Callable[[str], Awaitable[LinkPage]]


@dataclass
class NavigatorTools:
    search: SearchFn
    source: LectureSource
    chat_source: Optional[ChatThreadSource] = None
    web_search: Optional[WebSearchFn] = None
    link_fetch: Optional[LinkFetchFn] = None


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
        "CAN_OPEN_ATTACHMENTS": CAPABILITIES["CAN_OPEN"] and CAPABILITIES["CAN_ATTACHMENTS"],
        "CAN_OPEN_LINKS": CAPABILITIES["CAN_OPEN"] and CAPABILITIES["CAN_LINKS"],
    })
    return template.replace("${MAX_LAPS}", str(MAX_LAPS)).replace("${MAX_OPS_PER_LAP}", str(MAX_OPS_PER_LAP))


def openable_handles(nav_input: NavigatorInput, state: NavState) -> list[str]:
    """開ける呼び名: 全コース・全講義・各コース集約・この会話の節・最近のチャット・中身や検索結果に
    出てきたもの・前のターンのもの。開いたものは除く。"""
    m = nav_input.student_map
    screen_topic = [nav_input.screen_topic_handle()] if nav_input.screen_topic_handle() else []
    chat_scope = nav_input.chat_map.scope_handles() if nav_input.chat_map and CAPABILITIES["CAN_CHAT"] else []
    links = nav_input.link_handles() if state.link_opens_left() > 0 else []

    course_sub_handles: list[str] = []
    for c in m.courses:
        course_sub_handles.extend([
            f"{c.handle}/topics",
            f"{c.handle}/keywords",
            f"{c.handle}/announcements",
        ])
        n_lecs = len(c.lectures)
        if n_lecs > 1:
            course_sub_handles.append(f"{c.handle}/L1-{n_lecs}/cards")
        for lec in c.lectures:
            course_sub_handles.append(f"{lec.handle}/announcements")
            course_sub_handles.append(f"{lec.handle}/cards")

    handles = (
        m.scope_handles()
        + course_sub_handles
        + chat_scope
        + nav_input.attachment_scope_handles()
        + links
        + screen_topic
        + state.previous_turn_handles
        + state.surfaced_not_opened()
    )
    return [h for h in _dedupe(handles) if h not in state.opened and _plan_allows_handle(nav_input, h)]


def _plan_allows_handle(nav_input: NavigatorInput, handle: str) -> bool:
    """文字起こし・キーワード・カード等は、今のプランで使えるときだけ開ける。"""
    parsed = parse_handle(handle)
    if parsed is None:
        return True
    if parsed.kind == "transcript" and not nav_input.can_transcript:
        return False
    if parsed.kind == "course_keywords" and "keyword" in nav_input.blocked_source_types:
        return False
    if parsed.kind in ("lecture_cards", "multi_lecture_cards") and "review_card" in nav_input.blocked_source_types:
        return False
    return True


def build_schema(nav_input: NavigatorInput, state: NavState) -> dict[str, Any]:
    """
    項目の順番がそのまま出力の順番になる(GeminiとLunaで確認済み)。操作を選ぶ前に、
    取りに行く必要度(need)と出どころ(fetch_from)、「足りているか」を先に書かせる。
    操作は種類ごとに別の形(anyOf)にして、使わない項目を"none"で埋めさせない(出力が短くなる)。

    1ターンの中ではスキーマを変えない(stateに依存させない)。Anthropicのstructured outputsは
    output formatが変わるとプロンプトキャッシュが無効になり、以前はopenのhandle(開けるものの一覧)と
    findのtarget(検索の残り回数)が周ごとに変わっていたため、systemを毎周キャッシュに書くだけで
    一度も読めていなかった。handleは自由な文字列にし、開けるか・回数の上限はvalidate_operationsで判定する
    (2026-11-06、contents_generation/test_codes/navigator_schema_cache/: 4周のターンで2周目以降が
    キャッシュから読まれ、探索役の原価が$0.0111→$0.0062、開けないhandleで捨てた操作は0件)。
    """
    def enum(values: list[str]) -> dict[str, Any]:
        return {"type": "string", "enum": values} if values else {"type": "string"}

    scope = nav_input.student_map.scope_handles()
    op_shapes: list[dict[str, Any]] = []
    targets = available_targets()
    # 資料の中の検索は、全文で見えていない資料があるときだけ選べる
    if not nav_input.attachment_scope_handles():
        targets = [t for t in targets if t != "attachment.search"]
    if targets:
        op_shapes.append({"type": "object", "properties": {
            "op": {"type": "string", "enum": ["find"]},
            "target": enum(targets),
            "query": {"type": "string"},
            "layer": enum(available_layers(nav_input.blocked_source_types)),
            "within": enum(scope),
        }, "required": ["op", "target", "query"]})
    if CAPABILITIES["CAN_OPEN"]:
        op_shapes.append({"type": "object", "properties": {
            "op": {"type": "string", "enum": ["open"]},
            "handle": {"type": "string"},
        }, "required": ["op", "handle"]})
    if CAPABILITIES["CAN_BY_DATE"]:
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
            "need": {"type": "string", "enum": NEEDS},
            "fetch_from": {"type": "array", "items": {"type": "string", "enum": available_fetch_sources()}},
            "status": {"type": "string", "enum": STATUSES},
            "missing": {"type": "string"},
            "operations": {"type": "array", "items": {"anyOf": op_shapes} if op_shapes else {"type": "object"}},
            "goal": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["reasoning", "need", "fetch_from", "status", "missing", "operations", "goal"],
    }


def _parse_date(value: Any) -> Optional[date]:
    try:
        return date.fromisoformat(str(value).strip()[:10])
    except ValueError:
        return None


def _op_kind(raw: dict) -> Optional[str]:
    """操作がどの出どころに行くか: lecture / web / chat。"""
    op = raw.get("op")
    if op == "by_date":
        return "lecture"
    if op == "find":
        target = raw.get("target") or ""
        if target == "attachment.search":
            return "attachment"
        return "web" if target == "web.search" else "chat" if target.startswith("chat.") else "lecture"
    if op == "open":
        handle = raw.get("handle") or ""
        if _WEB_HANDLE_RE.match(handle):
            return "web"
        if _ATTACHMENT_HANDLE_RE.match(handle):
            return "attachment"
        if _LINK_HANDLE_RE.match(handle) or _LINK_SECTION_RE.match(handle):
            return "link"
        return "chat" if handle[:1] in ("S", "P", "H") else "lecture"
    return None


def validate_operations(
    raw_ops: Any, nav_input: NavigatorInput, state: NavState,
    need: Optional[str] = None, fetch_from: Optional[list[str]] = None,
) -> tuple[list[Request], list[dict]]:
    """
    探索役の操作を検証して、実行してよい操作に変換する。捨てたものは理由つきで返す(記録用)。
    構造化出力で縛っているので通常は正しい形で来るが、ここを信頼の境界にする。
    needを渡すと、取りに行く必要度がexplicit/implied以外なら全部捨て、fetch_fromの外への操作も捨てる。
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
    search_left = state.searches_left()
    link_left = state.link_opens_left()

    allowed_kinds = None
    if need is not None:
        allowed_kinds = ({_SOURCE_KINDS[f] for f in fetch_from or [] if f in _SOURCE_KINDS}
                         if need in FETCH_NEEDS else set())
    source_label = f"{need}:{'+'.join(fetch_from or [])}" if need else ""
    for raw in raw_ops if isinstance(raw_ops, list) else []:
        if not isinstance(raw, dict):
            continue
        op = raw.get("op")
        # 操作の種類の欄に検索先の名前を書いてくることがある(Lunaは出力の型を守り切らない。2026-10-08に
        # {"op": "attachment.search"} が2ターン続けて捨てられ、資料を読めないまま答えた): findとして読み替える
        if op not in ops and op in targets:
            raw = {**raw, "op": "find", "target": raw.get("target") or op}
            op = "find"
        # 呼び名の書き方の揺れ(L6-L7・全角・小文字など)を正しい形に直してから検証する(normalize_handle)
        fixed = {k: normalize_handle(raw[k]) for k in ("handle", "within")
                 if isinstance(raw.get(k), str) and raw[k] and normalize_handle(raw[k]) != raw[k]}
        if fixed:
            print(f"🔧 [chat] navigator handle normalized: "
                  + ", ".join(f"{raw[k]!r} -> {v!r}" for k, v in fixed.items()))
            raw = {**raw, **fixed, "as_written": {k: raw[k] for k in fixed}}
        # grounds(根拠の種類)は、必要度と出どころ(例: implied:class+web)を入れて記録だけに使う。
        common = dict(grounds=source_label, grounds_quote="", quote_ok=True)
        req: Optional[Request] = None
        reason = None
        if allowed_kinds is not None and _op_kind(raw) not in allowed_kinds:
            reason = "not_needed" if need not in FETCH_NEEDS else "outside_fetch_from"
        elif op not in ops:
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
            elif raw["target"] == "attachment.search":
                if not nav_input.attachment_scope_handles():
                    reason = "no_attachment_to_search"
                else:
                    # 資料の中の検索には層・コースの絞り込みが無い(今のスレッドの資料だけを探す)
                    req = FindRequest(target="attachment.search", query=query, layer="all", within=None, **common)
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
            is_attachment = CAPABILITIES["CAN_ATTACHMENTS"] and bool(_ATTACHMENT_HANDLE_RE.match(handle or ""))
            is_link = ((bool(_LINK_HANDLE_RE.match(handle or "")) and handle in nav_input.link_handles())
                       or _link_section(handle or "", state) is not None)
            is_valid_multi_cards = (
                parsed is not None and parsed.kind in ("multi_lecture_cards", "lecture_range")
                and m.course(parsed.course) is not None
            )
            if not _plan_allows_handle(nav_input, handle or ""):
                reason = "transcript_not_in_plan"
            elif ((handle not in openable and not is_valid_multi_cards)
                  or (parsed is None and parsed_chat is None and not is_web and not is_attachment and not is_link)):
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
        if isinstance(req, FindRequest) and req.target != "web.search":
            if search_left <= 0:
                dropped.append({"op": raw, "reason": "search_limit"})
                continue
            search_left -= 1
        if isinstance(req, FindRequest) and req.target == "web.search":
            if web_left <= 0:
                dropped.append({"op": raw, "reason": "web_search_limit"})
                continue
            web_left -= 1
        if isinstance(req, OpenRequest) and _LINK_HANDLE_RE.match(req.handle):
            if link_left <= 0:
                dropped.append({"op": raw, "reason": "link_limit"})
                continue
            link_left -= 1
        seen.add(req.key())
        requests.append(req)
    return requests, dropped


def build_user_message(nav_input: NavigatorInput, state: NavState, lap: int) -> str:
    m = nav_input.student_map
    parts = []

    # 1. 地図 (静的・不変: Courses, ChatMap, Attachments, Links)
    if lap == 1:
        map_text = "Courses:\n" + m.render_courses()
        if CAPABILITIES["CAN_CHAT"] and nav_input.chat_map is not None and nav_input.chat_map.has_anything:
            map_text += "\n\n" + nav_input.chat_map.render()
        if CAPABILITIES["CAN_ATTACHMENTS"] and nav_input.attachments:
            map_text += "\n\n" + render_for_navigator(
                nav_input.attachments, nav_input.attachment_visibility or Visibility(full=set()))
        if nav_input.link_handles():
            map_text += "\n\n" + render_links_for_navigator(nav_input.links)
        parts.append(f"<map>\n{map_text}\n</map>")

    # 2. 直近の会話 (累積型: 過去ログは完全一致し末尾に追記されるためプレフィックスキャッシュが持続)
    if nav_input.recent_conversation:
        conv = "\n".join(
            f"{'student' if msg.role == 'user' else 'assistant'}: {msg.content[:RECENT_CONVERSATION_MAX_CHARS]}"
            for msg in nav_input.recent_conversation[-RECENT_CONVERSATION_MAX_MESSAGES:]
        )
        parts.append(f"<recent_conversation>\n{conv}\n</recent_conversation>")
    else:
        parts.append("<recent_conversation>(This is the first message of a new conversation.)</recent_conversation>")

    # 3. 画面情報 (動的: 画面・トピック・選択テキスト)
    screen = []
    screen_handle = m.lecture_handle(nav_input.screen_lecture_id)
    if screen_handle:
        topic = nav_input.screen_topic_handle()
        screen.append(f"The student is viewing {m.describe(screen_handle)}"
                      + (f", on topic {topic}" if topic else ""))
    else:
        course_handle = m.course_handle(nav_input.screen_course_id)
        course = m.course(course_handle) if course_handle else None
        if course:
            screen.append(f"The student is viewing the course page of {course.handle} ({course.title})")
    if nav_input.screen_page_title:
        screen.append(f"Open page: {nav_input.screen_page_title}. The answerer already sees its full text"
                      " (excerpt below; the selected part, if any, is in <selected>), so never fetch it again.")
        if nav_input.screen_page_excerpt:
            screen.append(nav_input.screen_page_excerpt)
    if nav_input.selected_text and "<selected>" not in (nav_input.screen_page_excerpt or ""):
        screen.append(f"Selected text: {nav_input.selected_text}")
    if screen:
        parts.append("<screen>\n" + "\n".join(screen) + "\n</screen>")

    # 4. 直前ターンで開いたもの & 目的 (動的)
    if lap == 1:
        if state.previous_turn_text and CAPABILITIES["CAN_OPEN"]:
            parts.append(f"<previous_turn_opened>\n{state.previous_turn_text}\n</previous_turn_opened>")
        if nav_input.user_goal:
            parts.append(f"<user_goal>\n{nav_input.user_goal}\n</user_goal>")
        if nav_input.referenced_sources:
            parts.append(f"<referenced_sources>\n{nav_input.referenced_sources}\n</referenced_sources>")

    # 5. 現在時刻 (todayはcurrent_timeに含まれるためtodayタグは省略)
    cur_time = nav_input.current_time_str or nav_input.today.isoformat()
    parts.append(f"<current_time>{cur_time}</current_time>")

    # 6. 最新の学生メッセージ
    parts.append(f"<student_message>\n{nav_input.message}\n</student_message>")
    mentioned = nav_input.mentioned_unseen_handles()
    if lap == 1 and mentioned:
        parts.append(f"<mention_note>The student points at {', '.join(mentioned)} in their message, and the answerer "
                     "does not see it in full. Fetch the parts of it that the message is about: attachment.search "
                     "within it with the term or line in question, or open its table of contents and then the "
                     "section. If the message only asks about it as a whole, its table of contents is enough."
                     "</mention_note>")
    if lap == 1 and nav_input.must_check_attachments and nav_input.attachment_scope_handles():
        parts.append("<check_note>This message needs careful checking, and the answerer does not see the attached "
                     "material in full. Unless the message clearly has nothing to do with the material, fetch the "
                     "parts it depends on: attachment.search with a distinctive line of what the student pasted or "
                     "the term in question, or open the section from the table of contents. Without them, the "
                     "checking step can only guess.</check_note>")

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
    nxt.append(f"Budget left for lecture-range overviews (by_date, C{{n}}/L{{a}}-{{b}}): about {state.range_budget_left:,} of "
               f"{RANGE_MATERIAL_BUDGET:,} tokens (a smaller budget gives shorter overviews)")
    nxt.append("Searches already run (do not repeat them): "
               + ("; ".join(o.request.label() for o in state.outcomes) or "none yet"))
    left = state.searches_left()
    nxt.append(f"Class and chat searches left for this reply: {left} of {MAX_SEARCHES_PER_TURN}"
               + (" (no more searching; if the results do not contain the answer, choose enough_now)" if left == 0 else ""))
    if CAPABILITIES["CAN_WEB"]:
        left = state.web_searches_left()
        nxt.append(f"Web searches left for this reply: {left} of {MAX_WEB_SEARCHES_PER_TURN}"
                   + (" (web.search is no longer available)" if left == 0 else ""))
    if nav_input.link_handles():
        left = state.link_opens_left()
        unopened = [h for h in nav_input.link_handles() if h not in state.opened]
        nxt.append(f"Links you can still open for this reply: {left} of {MAX_LINK_OPENS_PER_TURN}"
                   + (f" (not opened yet: {', '.join(unopened)})" if left and unopened else ""))
    if CAPABILITIES["CAN_OPEN"]:
        nxt.append("Seen but not opened yet (open one only if it likely holds what is still missing): "
                   + (", ".join(state.surfaced_not_opened()) or "nothing"))
    parts.append("<next_options>\n" + "\n".join(nxt) + "\n</next_options>")
    return "\n\n".join(parts)


# =========================================================
# 📂 開く(講義の目次・文字起こし)
# =========================================================

def _lecture_number(lec: MapLecture) -> int:
    try:
        return int(lec.handle.rsplit("/L", 1)[1])
    except (ValueError, IndexError):
        return -1


_RANGE_LEVEL_TEXT = {
    "overview": "each lecture's summary and topic summaries",
    "summary": "each lecture's summary and topic titles (topic summaries did not fit)",
    "titles": "lecture titles only (summaries did not fit)",
}


@dataclass
class RangeOverview:
    body: str
    tokens: int
    level: str  # overview / summary / titles
    lectures: int
    cards_included: int
    cards_total: int
    cards_only: bool = False

    def note(self) -> str:
        cards = (f"{self.cards_included} of {self.cards_total} key Review Cards (Core Why / Gotcha)"
                 if self.cards_total else "no key Review Cards")
        what = cards if self.cards_only else f"{_RANGE_LEVEL_TEXT[self.level]}, plus {cards}"
        return (f"Attached for the answerer ({self.lectures} lectures): {what}. Their text is not shown to you; "
                "open a single lecture or topic only if a specific part needs more detail.")


async def build_range_overview(
    lectures: list[MapLecture], m: StudentMap, source: LectureSource, budget: int, cards_only: bool = False,
) -> RangeOverview:
    """
    範囲の講義を、予算(estimate_tokens)に収まる一番詳しい段階でまとめる。段階は範囲全体でそろえる
    (要約+トピック要約 → 要約+トピック名 → タイトルだけ)。残りの予算で、カード(core_why・gotcha)を
    講義の順に1枚ずつ配る(均等になるように)。入らなかったカードの数は本文の最後に書く。
    """
    from app.services.chat_attachments import estimate_tokens
    from app.services.chat_units import strip_citations

    ids = [x.id for x in lectures]
    summaries: dict[str, str] = {}
    topics: list[list[dict]] = [[] for _ in lectures]
    if not cards_only:
        summaries, topic_lists = await asyncio.gather(
            source.lecture_summaries(ids), asyncio.gather(*[source.lecture_topics(i) for i in ids]))
        topics = list(topic_lists)
    cards_map = await source.multi_lecture_review_cards(ids, card_types=("core_why", "gotcha"))

    # 本文は回答役にだけ渡すので、呼び名(C4/L11・T1)は書かない。回答役は何も開かないので呼び名は要らず、
    # 書いてあると回答にそのまま写してしまう(生徒には意味が分からない)。探索役にはOpened.textの一覧で見せる
    def header(lec: MapLecture) -> str:
        when = lec.format_when() if hasattr(lec, "format_when") else (lec.date.isoformat() if lec.date else "no date")
        course = m.course(lec.course_handle)
        return f"### {when} — {course.title if course else ''} / {lec.title or 'untitled lecture'}"

    def block(i: int, level: str) -> str:
        parts = [header(lectures[i])]
        if level in ("overview", "summary"):
            summary = (summaries.get(ids[i]) or "").strip()
            if summary:
                parts.append(f"Summary: {summary}")
            lines = [f"- {t['title']}" + (f" — {t['summary']}" if level == "overview" and t.get("summary") else "")
                     for t in topics[i]]
            if lines:
                parts.append("Topics:\n" + "\n".join(lines))
        return "\n".join(parts)

    ladder = ["titles"] if cards_only else ["overview", "summary", "titles"]
    for level in ladder:
        blocks = [block(i, level) for i in range(len(lectures))]
        used = sum(estimate_tokens(b) for b in blocks)
        if used <= budget:
            break

    queues: list[list[tuple[str, int]]] = []
    for lid in ids:
        ordered = sorted(cards_map.get(lid, []),
                         key=lambda c: (c.get("topic_number") or 0, 0 if c.get("card_type") == "core_why" else 1))
        q = []
        for c in ordered:
            text = strip_citations(format_lecture_review_cards([c]))
            q.append((text, estimate_tokens(text)))
        queues.append(q)
    chosen: list[list[str]] = [[] for _ in lectures]
    added_order: list[int] = []
    left = budget - used
    pos = [0] * len(lectures)
    added = True
    while added:
        added = False
        for i, q in enumerate(queues):
            if pos[i] >= len(q):
                continue
            text, tok = q[pos[i]]
            if tok <= left:
                chosen[i].append(text)
                added_order.append(i)
                left -= tok
                pos[i] += 1
                added = True
            else:
                pos[i] = len(q)  # この講義はここまで(残りは他の講義に回す)
    cards_total = sum(len(q) for q in queues)

    def assemble() -> str:
        sections = []
        for i in range(len(lectures)):
            sec = blocks[i]
            if chosen[i]:
                sec += f"\nKey Review Cards ({len(chosen[i])} of {len(queues[i])}):\n" + "\n\n".join(chosen[i])
            sections.append(sec)
        text = "\n\n".join(sections)
        left_out = cards_total - sum(len(c) for c in chosen)
        if left_out:
            text += f"\n\n({left_out} more key Review Cards in this range were left out to fit.)"
        return text

    # 見出し・区切りの分で予算を超えたら、最後に足したカードから外す
    body = assemble()
    while added_order and estimate_tokens(body) > budget:
        chosen[added_order.pop()].pop()
        body = assemble()
    included = sum(len(c) for c in chosen)
    return RangeOverview(body=body, tokens=estimate_tokens(body), level=level, lectures=len(lectures),
                         cards_included=included, cards_total=cards_total, cards_only=cards_only)


async def open_handle(
    handle: str, nav_input: NavigatorInput, source: LectureSource,
    chat_source: Optional[ChatThreadSource] = None, range_budget: int = RANGE_MATERIAL_BUDGET,
) -> Opened:
    if handle[:1] in ("S", "P", "H") and chat_source is not None:
        return await chat_open_handle(handle, nav_input, chat_source)
    if _ATTACHMENT_HANDLE_RE.match(handle):
        return attachment_open_handle(handle, nav_input)
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
            + (f"\n  Summary: {summaries[x.id].strip()}" if summaries.get(x.id) else "")
            for x in course.lectures
        ]
        body = "\n".join(lines) or "(No lectures recorded yet.)"
        sub_surfaced = [f"{handle}/topics", f"{handle}/keywords", f"{handle}/announcements"]
        return Opened(
            handle=handle,
            text=f"Course {handle}: {course.title}\n{body}",
            material=Material(key=f"course:{course.id}", kind="course", label=f"{course.title} / Lectures",
                              content=body, source_type="course", course_id=course.id, handle=handle),
            surfaced=sub_surfaced + [x.handle for x in course.lectures],
            ref={"type": "course", "id": course.id},
        )

    if parsed.kind == "course_topics":
        topics_map = await source.course_topics([x.id for x in course.lectures])
        lines = [f"# {course.title} — Course Topics & Syllabus Tree"]
        surfaced = []
        for x in course.lectures:
            t_list = topics_map.get(x.id, [])
            when = f" ({x.date.isoformat()})" if x.date else ""
            lines.append(f"- {x.handle}: {x.title}{when}")
            for t in t_list:
                t_idx = t.get("index")
                t_title = t.get("title") or "Untitled"
                lines.append(f"  - T{t_idx}: {t_title}")
                surfaced.append(f"{x.handle}/T{t_idx}")
        body = "\n".join(lines)
        return Opened(
            handle=handle,
            text=f"Course Topics {handle}: {course.title}\n{body}",
            material=Material(
                key=f"course_topics:{course.id}",
                kind="course_topics",
                label=f"{course.title} / Syllabus & Topics",
                content=body,
                source_type="course_topics",
                course_id=course.id,
                handle=handle,
            ),
            surfaced=surfaced,
            ref={"type": "course", "id": course.id},
        )

    if parsed.kind == "course_keywords":
        kws_map = await source.course_keywords([x.id for x in course.lectures])
        lines = [f"# {course.title} — Key Terms & Glossary"]
        count = 0
        for x in course.lectures:
            k_list = kws_map.get(x.id, [])
            if not k_list:
                continue
            lines.append(f"\n### {x.handle}: {x.title}")
            for k in k_list:
                count += 1
                if count > 120:
                    lines.append("- *(Remaining keywords omitted for brevity)*")
                    break
                kw = k.get("keyword", "")
                df = k.get("definition", "")
                if df:
                    lines.append(f"- **{kw}**: {df}")
                else:
                    lines.append(f"- **{kw}**")
            if count > 120:
                break
        body = "\n".join(lines)
        return Opened(
            handle=handle,
            text=f"Course Glossary {handle}: {course.title}\n{body}",
            material=Material(
                key=f"course_keywords:{course.id}",
                kind="course_keywords",
                label=f"{course.title} / Glossary & Key Terms",
                content=body,
                source_type="course_keywords",
                course_id=course.id,
                handle=handle,
            ),
            ref={"type": "course", "id": course.id},
        )

    if parsed.kind == "course_announcements":
        lec_ids = [x.id for x in course.lectures]
        anns = await source.announcements(lec_ids)
        lines = [f"# {course.title} — Class Announcements & Exam Hints"]
        anns_by_lec: dict[str, list[dict]] = {}
        for a in anns:
            anns_by_lec.setdefault(a["lecture_id"], []).append(a)

        def _type_pri(t: str) -> int:
            return {"HINT": 0, "EVENT": 1, "TODO": 2, "INFO": 3}.get((t or "").upper(), 4)

        has_any = False
        for x in course.lectures:
            items = anns_by_lec.get(x.id, [])
            if not items:
                continue
            has_any = True
            lines.append(f"\n### {x.handle}: {x.title}")
            sorted_items = sorted(items, key=lambda it: _type_pri(it.get("type")))
            for item in sorted_items[:10]:
                itype = (item.get("type") or "INFO").upper()
                ititle = (item.get("title") or "").strip()
                idesc = (item.get("description") or "").strip()
                loc = f" (Ref: {item['location']})" if item.get("location") else ""
                lines.append(f"- **[{itype}] {ititle}**: {idesc}{loc}")

        if not has_any:
            lines.append("(No announcements recorded for this course.)")

        body = "\n".join(lines)
        return Opened(
            handle=handle,
            text=f"Course Announcements {handle}: {course.title}\n{body}",
            material=Material(
                key=f"course_announcements:{course.id}",
                kind="course_announcements",
                label=f"{course.title} / Announcements & Hints",
                content=body,
                source_type="course_announcements",
                course_id=course.id,
                handle=handle,
            ),
            ref={"type": "course", "id": course.id},
        )

    if parsed.kind in ("multi_lecture_cards", "lecture_range"):
        start_idx, end_idx = parsed.lecture_start, parsed.lecture_end
        target_lecs = sorted((x for x in course.lectures if start_idx <= _lecture_number(x) <= end_idx),
                             key=_lecture_number)
        if not target_lecs:
            return Opened(handle=handle, text=f"{handle}: (no lectures found in range L{start_idx}-L{end_idx})", material=None)
        cards_only = parsed.kind == "multi_lecture_cards"
        ov = await build_range_overview(target_lecs, m, source, range_budget, cards_only=cards_only)
        name = "Review Cards" if cards_only else "Lecture Overviews"
        listing = "\n".join(f"- {x.handle} ({x.format_when() if hasattr(x, 'format_when') else (x.date.isoformat() if x.date else 'no date')}) {x.title}"
                            for x in target_lecs)
        # 回答役(と出典の表示)には呼び名ではなく日付の範囲で示す
        dates = [x.date for x in target_lecs if x.date]
        span = f"{min(dates).isoformat()} to {max(dates).isoformat()}" if dates else f"{len(target_lecs)} lectures"
        return Opened(
            handle=handle,
            text=f"{name} {handle}: {course.title}, L{start_idx} to L{end_idx}\n{listing}\n{ov.note()}",
            material=Material(
                key=f"{'review_cards' if cards_only else 'lecture_range'}:{course.id}:L{start_idx}-L{end_idx}",
                kind="review_cards" if cards_only else "lecture_range",
                label=f"{course.title} / {name} ({span})",
                content=f"# {course.title} — {name} ({span})\n\n{ov.body}",
                source_type="review_cards" if cards_only else "lecture_summary",
                course_id=course.id,
                handle=handle,
            ),
            surfaced=[x.handle for x in target_lecs],
            ref={"type": "course", "id": course.id},
            range_tokens=ov.tokens,
        )

    when = lec.format_when() if hasattr(lec, "format_when") else (lec.date.isoformat() if lec.date else "no date")
    if parsed.kind == "lecture_announcements":
        anns = await source.announcements([lec.id])
        lines = [f"# {lec.title} ({when}) — Lecture Announcements & Hints"]
        if not anns:
            lines.append("(No announcements recorded for this lecture.)")
        else:
            def _type_pri(t: str) -> int:
                return {"HINT": 0, "EVENT": 1, "TODO": 2, "INFO": 3}.get((t or "").upper(), 4)
            sorted_items = sorted(anns, key=lambda it: _type_pri(it.get("type")))
            for item in sorted_items:
                itype = (item.get("type") or "INFO").upper()
                ititle = (item.get("title") or "").strip()
                idesc = (item.get("description") or "").strip()
                loc = f" (Ref: {item['location']})" if item.get("location") else ""
                lines.append(f"- **[{itype}] {ititle}**: {idesc}{loc}")
        body = "\n".join(lines)
        return Opened(
            handle=handle,
            text=f"Lecture Announcements {handle}: {lec.title}\n{body}",
            material=Material(
                key=f"announcements:{lec.id}",
                kind="announcements",
                label=f"{course.title} / {lec.title} ({when}) / Announcements",
                content=body,
                source_type="announcements",
                lecture_id=lec.id,
                course_id=course.id,
                handle=handle,
            ),
            ref={"type": "lecture", "id": lec.id},
        )

    if parsed.kind == "lecture_cards":
        cards = await source.lecture_review_cards(lec.id, card_types=("core_why", "gotcha"))
        cards_section = format_lecture_review_cards(cards) or "(No Core Why or Gotcha review cards recorded for this lecture.)"
        body = f"# {lec.title} ({when}) — Review Cards\n\n{cards_section}"
        return Opened(
            handle=handle,
            text=f"Review Cards {handle}: {lec.title}\n{body}",
            material=Material(
                key=f"review_cards:{lec.id}",
                kind="review_cards",
                label=f"{course.title} / {lec.title} ({when}) / Review Cards",
                content=body,
                source_type="review_cards",
                lecture_id=lec.id,
                course_id=course.id,
                handle=handle,
            ),
            ref={"type": "lecture", "id": lec.id},
        )

    if parsed.kind == "lecture":
        summary = (await source.lecture_summaries([lec.id])).get(lec.id, "")
        topics = await source.lecture_topics(lec.id)
        topic_lines = [
            f"{handle}/T{t['index']} {t['title']}"
            + (f" — {t['summary'].strip()}" if t.get("summary") else "")
            for t in topics
        ]
        # ReviewCards (core_why, gotcha) を取得して講義マテリアルに同梱
        cards = await source.lecture_review_cards(lec.id, card_types=("core_why", "gotcha"))
        cards_section = format_lecture_review_cards(cards)

        body_parts = [f"Summary: {summary or '(no summary)'}"]
        if topic_lines:
            body_parts.append("Topics:\n" + "\n".join(topic_lines))
        if cards_section:
            body_parts.append("Key Review Cards (Core Why & Gotchas):\n" + cards_section)

        body = "\n\n".join(body_parts)
        return Opened(
            handle=handle,
            text=f"Lecture {handle}: {lec.title} ({when})\n{body}",
            material=Material(key=f"lecture:{lec.id}", kind="lecture",
                              label=f"{course.title} / {lec.title} ({when}) / Lecture Overview & Review Cards",
                              content=f"Lecture date: {when}\n{body}",
                              source_type="lecture_summary", source_id=lec.id, lecture_id=lec.id,
                              course_id=course.id, handle=handle),
            surfaced=[f"{handle}/announcements", f"{handle}/cards"] + [f"{handle}/T{t['index']}" for t in topics],
            ref={"type": "lecture", "id": lec.id},
        )

    if parsed.kind == "topic":
        detail = await source.topic_detail(lec.id, parsed.topic_index)
        if detail is None:
            return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
        note_nav, note_ans, ranges = rewrite_citations(detail.get("deep_note") or "", parsed.lecture, nav_input.can_transcript)
        keywords = "; ".join(f"{k}: {d}" if d else k for k, d in detail.get("keywords") or [])
        head = f"Summary: {detail['summary'] or '(no summary)'}" + (f"\nKeywords: {keywords}" if keywords else "")
        text = f"Topic {handle}: {detail['title']}\n{head}\nDeep Note:\n{note_nav or '(none)'}"
        content = f"Lecture date: {when}\n{head}" + (f"\nDeep Note:\n{note_ans}" if note_ans else "")
        return Opened(
            handle=handle,
            text=text,
            material=Material(key=f"topic:{lec.id}:{parsed.topic_index}", kind="topic",
                              label=f"{course.title} / {lec.title} ({when}) / Topic: {detail['title']}",
                              content=content,
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
                          label=f"{course.title} / {lec.title} ({when}) / Transcript",
                          content=f"Lecture date: {when}\n{body}",
                          source_type="transcript_topic", lecture_id=lec.id, course_id=course.id,
                          metadata={"sid_start": parsed.sid_start, "sid_end": parsed.sid_end}, handle=handle),
        ref={"type": "transcript", "lecture_id": lec.id, "sid_start": parsed.sid_start, "sid_end": parsed.sid_end},
    )


def attachment_open_handle(handle: str, nav_input: NavigatorInput) -> Opened:
    """
    添付資料を開く。A2 → 目次(節ごとの呼び名・名前・何が書いてあるか)、A2/S3 → その節の本文と、
    前後の節の呼び名(「続き」を読めるように)。本文は資料の行にあるので、DBは読まない。
    """
    m = _ATTACHMENT_HANDLE_RE.match(handle)
    a = nav_input.attachment(f"A{m.group(1)}") if m else None
    if a is None:
        return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
    label = a.title or "Attached material"
    if m.group(2) is None:
        lines = [f"{a.handle}/S{s.index} {s.title}" + (f" — {s.description}" if s.description else "") for s in a.sections]
        toc = "\n".join(lines) or "(no sections)"
        return Opened(
            handle=handle,
            text=f"Material {a.handle}: {label} ({a.char_count:,} characters)\nSummary: {a.summary or '(none)'}\n"
                 f"Sections:\n{toc}",
            material=Material(key=f"attachment:{a.id}", kind="attachment_toc", label=f"{label} / Contents",
                              content=f"Summary: {a.summary or '(none)'}\nSections:\n"
                                      + "\n".join(f"{s.index}. {s.title}" + (f" — {s.description}" if s.description else "")
                                                   for s in a.sections),
                              source_type="chat_attachment", source_id=a.id, thread_id=nav_input.current_thread_id,
                              metadata={"attachment_id": a.id}, handle=handle),
            surfaced=[f"{a.handle}/S{s.index}" for s in a.sections],
            ref={"type": "attachment", "id": a.id},
        )
    k = int(m.group(2))
    sec = a.section(k)
    if sec is None:
        return Opened(handle=handle, text=f"{handle}: (not found)", material=None)
    body = a.section_text(sec)
    neighbors = [f"{a.handle}/S{i}" for i in (k - 1, k + 1) if a.section(i)]
    return Opened(
        handle=handle,
        text=f"Material {handle}: {label} — section {k} of {len(a.sections)}: {sec.title}\n{body}",
        material=Material(key=f"attachment:{a.id}:{k}", kind="attachment_section", label=f"{label} / {sec.title}",
                          content=body, source_type="chat_attachment", source_id=a.id,
                          thread_id=nav_input.current_thread_id,
                          metadata={"attachment_id": a.id, "section": k}, handle=handle),
        surfaced=neighbors,
        ref={"type": "attachment_section", "id": a.id, "index": k},
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


async def chat_open_handle(handle: str, nav_input: NavigatorInput, chat_source: ChatThreadSource) -> Opened:
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
                              label=f"This conversation / {section.title}", content=body,
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
                              label=f"This conversation / {group.title}", content=body,
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
                              label=f"{p_ref.title} / {group['title']}", content=body,
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
                              content=body, source_type="chat_turn", thread_id=ref.id,
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
                              label=f"{p_ref.title} / {section['title']}", content=body,
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
                          label=f"{thread_title} / Turn {parsed.turn}", content=body,
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
    lecture_chunks = [c for c in chunks if c.get("source_type") not in ("chat_turn", "chat_attachment")]
    chat_chunks = [c for c in chunks if c.get("source_type") == "chat_turn"]
    attachment_chunks = [c for c in chunks if c.get("source_type") == "chat_attachment"]

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

    # 資料の節。全文で回答役に見えている資料(と外した資料)に当たったものは捨てる
    searchable = set(nav_input.attachment_scope_handles())
    for c in attachment_chunks:
        meta = c.get("metadata") or {}
        a = next((x for x in nav_input.attachments if x.id == meta.get("attachment_id")), None)
        if a is None or a.handle not in searchable or not isinstance(meta.get("section"), int):
            continue
        hits.append(Hit(handle=f"{a.handle}/S{meta['section']}", chunk=c))
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
        if kind in ("attachment", "attachment_section") and CAPABILITIES["CAN_ATTACHMENTS"]:
            a = next((x for x in nav_input.attachments if x.id == ref.get("id")), None)
            # 全文で回答役に見えている資料は、前のターンで開いていても見せない(開く意味が無い)
            if a is None or a.handle not in nav_input.attachment_scope_handles():
                continue
            if kind == "attachment":
                blocks.append(f"{a.handle} — the table of contents of the attached material \"{a.title}\"")
                handles.append(a.handle)
            elif isinstance(ref.get("index"), int) and a.section(ref["index"]):
                k = ref["index"]
                nxt = f", next: {a.handle}/S{k + 1}" if a.section(k + 1) else " (the last section)"
                blocks.append(f"{a.handle}/S{k} — section {k} of {len(a.sections)} of the attached material "
                              f"\"{a.title}\": {a.section(k).title}{nxt}")
                handles += [a.handle, f"{a.handle}/S{k}"] + ([f"{a.handle}/S{k + 1}"] if a.section(k + 1) else [])
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
    rpc_ms: Optional[list[int]] = None,
) -> SearchFn:
    """
    lecture.conceptの検索を実行する関数を作る。search_knowledge_chunksは必ずユーザー本人の
    JWTで作ったクライアントで呼ぶ(auth.uid()で本人の行だけに絞る設計、chat_service._retrieveと同じ)。
    embedは課金を記録する埋め込み関数(knowledge_index.embed_queriesにbillingを渡したもの)。
    今のプランで使えない種類(blocked_source_types)は、どのlayerでも検索しない。
    rpc_msを渡すと、検索RPC1本ごとの所要時間を足していく(速度の計測用)。
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
        t = time.perf_counter()
        res = user_client.rpc("search_knowledge_chunks", params).execute()
        if rpc_ms is not None:
            rpc_ms.append(_ms_since(t))
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
    rpc_ms: Optional[list[int]] = None,
) -> SearchFn:
    """
    chat.all/chat.thread/attachment.searchの検索。chat.threadと資料の中の検索は、今のスレッドに絞る
    (RPCのfilter_thread_id。資料はスレッドごとなので、ほかのスレッドの資料は探さない)。
    """
    def _rpc(embedding: list[float], req: FindRequest) -> list[dict]:
        source_type = "chat_attachment" if req.target == "attachment.search" else "chat_turn"
        params: dict[str, Any] = {
            "query_embedding": embedding, "match_count": SEARCH_MATCH_COUNT, "filter_source_types": [source_type],
        }
        if req.target in ("chat.thread", "attachment.search") and current_thread_id:
            params["filter_thread_id"] = current_thread_id
        t = time.perf_counter()
        res = user_client.rpc("search_knowledge_chunks", params).execute()
        if rpc_ms is not None:
            rpc_ms.append(_ms_since(t))
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
        # 資料の中の検索も、スレッドで絞るのでチャットの検索と同じ関数で行う
        lecture_reqs = [r for r in requests if r.target.startswith("lecture.")]
        chat_reqs = [r for r in requests if not r.target.startswith("lecture.")]
        lecture_results, chat_results = await asyncio.gather(lecture_search(lecture_reqs), chat_search(chat_reqs))
        li, ci = iter(lecture_results), iter(chat_results)
        return [next(li) if r.target.startswith("lecture.") else next(ci) for r in requests]

    return search


# =========================================================
# 🧭 本体: 最大4周
# =========================================================

async def decide_lap(
    llm: UnifiedLLM, nav_input: NavigatorInput, state: NavState, lap: int, metrics: Optional[dict] = None,
) -> tuple[Optional[dict], Optional[str]]:
    """
    1周分の判断(LLM)。読めない出力は1回だけやり直す。評価ハーネスもこれを呼ぶ。
    metricsを渡すと、試行回数と最後の呼び出しのトークン数を書き込む(速度の計測用)。
    """
    options = LLMOptions(
        # gpt-6-lunaはtemperatureの既定値(1)以外を受け付けない
        temperature=1.0,
        output_type="json",
        json_schema=build_schema(nav_input, state),
        max_completion_tokens=NAVIGATOR_MAX_COMPLETION_TOKENS,
        reasoning_effort=NAVIGATOR_REASONING_EFFORT,
    )
    sys_msg = Message(role="system", content=build_system_prompt(nav_input.can_transcript))
    user_msg = Message(role="user", content=build_user_message(nav_input, state, lap))
    if NAVIGATOR_MODEL.startswith("anthropic/"):
        sys_msg.cache_control = {"type": "ephemeral", "ttl": "1h"}
    messages = [sys_msg, user_msg]
    last_error = None
    for _attempt in range(2):
        if metrics is not None:
            metrics["attempts"] = _attempt + 1
        try:
            result = await llm.generate(NAVIGATOR_MODEL, messages, options)
        except Exception as e:
            last_error = str(e)[:300]
            continue
        if metrics is not None:
            metrics.update(input_tokens=result.input_tokens, cache_read_tokens=result.cache_read_tokens,
                           output_tokens=result.output_tokens)
        out = result.output_json
        if isinstance(out, dict) and out.get("status") in STATUSES:
            return out, None
        last_error = result.json_parse_error or f"unreadable output (finish_reason={result.finish_reason})"
    return None, last_error


def web_material(page: WebPage, opened: bool) -> Material:
    """Webのページを回答役の材料に。開いたページは断片すべて、当たっただけのページは最初の方だけ。"""
    return Material(
        key=f"web:{page.url}",
        kind="web_page" if opened else "web",
        label=page.label(),
        content=page.text(WEB_PAGE_CHARS if opened else WEB_HIT_MATERIAL_CHARS),
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


def open_web_page(page: WebPage) -> Opened:
    text = f"{page.handle} — {page.label()}\n{page.url}\n{page.text(WEB_PAGE_CHARS) or '(no text extracted)'}"
    return Opened(handle=page.handle, text=text, material=web_material(page, opened=True))


# 取れなかった理由 → 探索役に見せる説明(回答役には、開けなかったことをgoalで伝える)
_LINK_ERRORS = {
    "login_required": "the page needs a login (a course site or a private document)",
    "not_found": "the page does not exist (check the link)",
    "blocked": "the site blocks automated access",
    "no_text": "no readable text could be taken from it",
    "unsafe_url": "this link cannot be opened",
    "too_large": "the file is too large",
    "unsupported_type": "the file type cannot be read",
    "unreadable_pdf": "the PDF could not be read",
}


async def open_link(link: Link, fetch: Optional[LinkFetchFn], state: NavState) -> Opened:
    """会話に出てきたリンクを開く。取れたら本文を材料に、取れなければ理由だけを探索役に見せる。"""
    if fetch is None:
        return Opened(handle=link.handle, text=f"{link.handle}: (links cannot be opened right now)", material=None)
    page = await fetch(link.url)
    state.link_fetches.append({"handle": link.handle, **page.log()})
    if not page.ok:
        reason = _LINK_ERRORS.get(page.error or "", "it could not be read")
        state.link_failures.append((link.url, reason))
        return Opened(handle=link.handle, material=None,
                      text=f"{link.handle} {link.url}: could not be opened — {reason}. The reply should say so and "
                           "ask the student to paste the part they need or attach the file.")
    domain = link.domain
    title = page.title or domain
    label = f"{title} ({domain})" if domain and title != domain else title
    shown = page.text[:LINK_NAVIGATOR_CHARS]
    more, surfaced = "", []
    if len(page.text) > LINK_PAGE_MAX_CHARS:
        # 回答役にも先頭しか渡らない長いページ: 節の目次を見せ、要る節を開けるようにする
        bounds = split_sections(page.text)
        state.link_sections[link.handle] = (label, link.url, page.text, bounds)
        rows = [f"{link.handle}/S{i} {_section_title(page.text[a:b])} ({b - a} chars)"
                for i, (a, b) in enumerate(bounds, start=1)][:LINK_MAX_SECTIONS_SHOWN]
        surfaced = [r.split(" ", 1)[0] for r in rows]
        more = (f"\n(the page continues; the answerer sees only the first {LINK_PAGE_MAX_CHARS} characters. "
                "If the message is about a later part, open that section.)\nSections:\n" + "\n".join(rows))
    elif len(page.text) > LINK_NAVIGATOR_CHARS:
        more = "\n(the page continues; the answerer sees all of it)"
    return Opened(
        handle=link.handle,
        text=f"{link.handle} — {label}\n{link.url}\n{shown}{more}",
        material=Material(key=f"link:{link.url}", kind="link_page", label=label, content=page.text,
                          source_type="web", url=link.url,
                          metadata={"title": page.title, "domain": domain, "via": page.via}, handle=link.handle),
        surfaced=surfaced,
    )


def _section_title(text: str) -> str:
    """節の名前: 最初の空でない行(見出しのことが多い)。"""
    first = next((ln.strip().lstrip("#").strip() for ln in text.splitlines() if ln.strip()), "")
    return first[:LINK_SECTION_TITLE_CHARS] + ("…" if len(first) > LINK_SECTION_TITLE_CHARS else "")


def _link_section(handle: str, state: NavState) -> Optional[tuple[str, int]]:
    """U1/S3 → ("U1", 3)。そのページを開いて節に区切ってあり、番号が範囲内のときだけ。"""
    m = _LINK_SECTION_RE.match(handle)
    if not m or m.group(1) not in state.link_sections:
        return None
    index = int(m.group(2))
    return (m.group(1), index) if 1 <= index <= len(state.link_sections[m.group(1)][3]) else None


def open_link_section(handle: str, state: NavState) -> Opened:
    base, index = _link_section(handle, state)
    label, url, text, bounds = state.link_sections[base]
    a, b = bounds[index - 1]
    body = text[a:b].strip()
    title = _section_title(body)
    return Opened(
        handle=handle,
        text=f"{handle} — {label} / {title}\n{body[:LINK_NAVIGATOR_CHARS]}",
        material=Material(key=f"link:{url}#S{index}", kind="link_page", label=f"{label} — {title}", content=body,
                          source_type="web", url=url, metadata={"section": index}, handle=handle),
    )


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

    m = nav_input.student_map
    titles = {c.handle: c.title for c in m.courses}
    date_outcomes = [DateOutcome(request=r, lectures=m.lectures_between(r.date_from, r.date_to, r.within), course_titles=titles)
                     for r in dates]
    # 範囲の材料(C{n}/L{a}-{b}・…/cards・講義のあるby_date)は、このターンの残り予算をこの周の操作で等分する
    range_opens = [r for r in opens if (p := parse_handle(r.handle)) and p.kind in ("multi_lecture_cards", "lecture_range")]
    n_range = len(range_opens) + sum(1 for o in date_outcomes if o.lectures)
    per_range = state.range_budget_left // n_range if n_range else 0

    async def attach_overview(o: DateOutcome) -> None:
        try:
            ov = await build_range_overview(o.lectures, m, tools.source, per_range)
        except Exception as e:
            print(f"⚠️ [chat] by_date overview failed ({o.request.label()}): {e}")
            return
        o.overview_body, o.overview_tokens, o.overview_note = ov.body, ov.tokens, ov.note()

    async def run_open(req: OpenRequest) -> Opened:
        if req.handle in state.web_pages:
            return open_web_page(state.web_pages[req.handle])
        link = nav_input.link(req.handle)
        if link is not None:
            return await open_link(link, tools.link_fetch, state)
        if _link_section(req.handle, state) is not None:
            return open_link_section(req.handle, state)
        try:
            return await open_handle(req.handle, nav_input, tools.source, tools.chat_source, range_budget=per_range)
        except Exception as e:
            print(f"⚠️ [chat] navigator open failed ({req.handle}): {e}")
            return Opened(handle=req.handle, text=f"{req.handle}: (could not be opened)", material=None)

    async def timed(key: str, coro):
        """並列に走る実行の内訳(検索・Web・開く)をrecord.timingに残す。開くは一番遅いもの。"""
        t = time.perf_counter()
        try:
            return await coro
        finally:
            record.timing[key] = max(record.timing.get(key, 0), _ms_since(t))

    find_outcomes, web_results, _dates, *opened = await asyncio.gather(
        timed("find_ms", run_finds()) if finds else run_finds(),
        timed("web_ms", asyncio.gather(*[run_web(r) for r in web_finds])) if web_finds else asyncio.gather(),
        asyncio.gather(*[attach_overview(o) for o in date_outcomes if o.lectures]),
        *[timed("open_ms", run_open(r)) for r in opens])
    state.range_budget_left = max(0, state.range_budget_left - sum(op.range_tokens for op in opened)
                                  - sum(o.overview_tokens for o in date_outcomes))

    # 呼び名は依頼の順に振る(並列に返ってきた順ではなく)
    web_outcomes: list[WebSearchOutcome] = []
    for req, res in zip(web_finds, web_results):
        if isinstance(res, Exception):
            print(f"⚠️ [chat] navigator web search failed ({req.label()}): {res}")
            web_outcomes.append(WebSearchOutcome(request=req, pages=[], error=str(res)[:300]))
        else:
            web_outcomes.append(WebSearchOutcome(request=req, pages=add_web_pages(state, res)))

    for op in opened:
        state.opened[op.handle] = op
    for o in find_outcomes:
        state.outcomes.append(o)
        for hit in o.hits:
            state.search_materials.append(material_from_chunk(hit.chunk, handle=hit.handle, student_map=m))
    for o in web_outcomes:
        state.outcomes.append(o)
        for page in o.pages:
            state.search_materials.append(web_material(page, opened=False))
    state.outcomes += date_outcomes
    for o in date_outcomes:
        mat = o.to_material()
        if mat:
            state.search_materials.append(mat)
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
    t_prepare = time.perf_counter()
    if nav_input.previous_turn_refs and CAPABILITIES["CAN_OPEN"]:
        try:
            await prepare_previous_turn(nav_input, tools.source, tools.chat_source, state)
        except Exception as e:
            print(f"⚠️ [chat] failed to prepare the previous turn's materials: {e}")
    prepare_ms = _ms_since(t_prepare)
    goal: list[str] = []
    stop_reason = "max_laps"

    for lap in range(1, MAX_LAPS + 1):
        if on_lap is not None:
            await on_lap(lap)
        t0 = time.perf_counter()
        timing: dict = {}
        out, err = await decide_lap(llm, nav_input, state, lap, timing)
        timing["decide_ms"] = _ms_since(t0)
        if out is None:
            print(f"⚠️ [chat] navigator lap {lap} failed: {err}")
            state.laps.append(LapRecord(lap=lap, status="", missing="", reasoning="", goal=[],
                                        elapsed_ms=round((time.perf_counter() - t0) * 1000), llm_error=err,
                                        timing=timing))
            stop_reason = "llm_error"
            break

        record = LapRecord(
            lap=lap,
            status=out["status"],
            missing=(out.get("missing") or "").strip()[:300],
            reasoning=(out.get("reasoning") or "").strip()[:500],
            goal=[g.strip()[:200] for g in out.get("goal") or [] if isinstance(g, str) and g.strip()][:8],
            need=out.get("need") if out.get("need") in NEEDS else "",
            fetch_from=[f for f in out.get("fetch_from") or [] if f in available_fetch_sources()],
            timing=timing,
        )
        state.laps.append(record)
        if record.goal:
            goal = record.goal

        if record.status != "need_more":
            stop_reason = record.status
            record.elapsed_ms = round((time.perf_counter() - t0) * 1000)
            break

        record.requests, record.dropped = validate_operations(
            out.get("operations"), nav_input, state, record.need or None, record.fetch_from)
        if not record.requests:
            # need_moreと言いつつ実行できる操作が無い(全部繰り返し・取りに行く必要が無い等): ここまでで答える
            stop_reason = "enough_now" if record.need in FETCH_NEEDS else "nothing_needed"
            record.elapsed_ms = round((time.perf_counter() - t0) * 1000)
            break
        if on_fetch is not None:
            await on_fetch(fetch_info(record.requests))
        t_exec = time.perf_counter()
        await execute_lap(record, nav_input, state, tools)
        timing["execute_ms"] = _ms_since(t_exec)
        record.elapsed_ms = round((time.perf_counter() - t0) * 1000)

    opened_materials = [op.material for op in state.opened.values() if op.material]
    materials = opened_materials + [m for m in state.search_materials if not _covered_by_opened(m, opened_materials)]
    refs = [op.ref for op in state.opened.values() if op.ref]
    return NavigationResult(materials=materials, goal=goal, laps=state.laps, stop_reason=stop_reason,
                            opened_refs=refs, prepare_ms=prepare_ms, links=state.link_fetches,
                            link_failures=state.link_failures)


def _covered_by_opened(hit: Material, opened: list[Material]) -> bool:
    """
    検索の断片が、開いた中身にもう含まれているか(同じ箇所が別の番号の出典として二重に並ぶのを防ぐ)。
    同じ呼び名(トピック・講義・チャットの往復など)か、開いた文字起こしの範囲に収まる文字起こしの断片。
    """
    if not hit.handle:
        return False
    hit_range = parse_handle(hit.handle)
    for m in opened:
        if not m.handle:
            continue
        if m.handle == hit.handle:
            return True
        opened_range = parse_handle(m.handle)
        if (hit_range and opened_range and hit_range.kind == opened_range.kind == "transcript"
                and hit_range.lecture == opened_range.lecture
                and opened_range.sid_start <= hit_range.sid_start and hit_range.sid_end <= opened_range.sid_end):
            return True
    return False


def _ms_since(t0: float) -> int:
    return round((time.perf_counter() - t0) * 1000)


def _find_kind(target: str) -> str:
    """検索の種類(画面の表示用): web / attachments / chats / lectures。"""
    if target == "web.search":
        return "web"
    if target == "attachment.search":
        return "attachments"
    return "chats" if target.startswith("chat.") else "lectures"


def _open_kind(handle: str) -> str:
    """開く呼び名の種類(画面の表示用): web / attachments / chats / lectures。"""
    # リンクを開くのも、画面ではWebを見ている表示にする(Web・Flutterどちらの画面もそのまま出せる)
    if _WEB_HANDLE_RE.match(handle) or _LINK_HANDLE_RE.match(handle) or _LINK_SECTION_RE.match(handle):
        return "web"
    if _ATTACHMENT_HANDLE_RE.match(handle):
        return "attachments"
    return "chats" if handle[:1] in ("S", "P", "H") else "lectures"


def fetch_kinds(requests: list[Request]) -> list[str]:
    """この周で何を探すか(画面の「〜を検索中」用): web / attachments / chats / lectures。"""
    kinds: list[str] = []
    for r in requests:
        if isinstance(r, FindRequest):
            kind = _find_kind(r.target)
        elif isinstance(r, OpenRequest):
            kind = _open_kind(r.handle)
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
        info["target"] = _find_kind(selected_r.target)
        info["layer"] = selected_r.layer
    elif isinstance(selected_r, OpenRequest):
        info["target"] = _open_kind(selected_r.handle)
        info["handle"] = selected_r.handle

    return info


def summarize_for_log(result: NavigationResult) -> str:
    """
    例: stop=enough_now prep=120ms lap1:need_more:1ops:3100ms[llm=2400ms in=7200/cache=3000 out=210 exec=700ms find=650ms]
    llmが2回以上なら試行回数(x2)を付ける。execの内訳は並列に走ったものそれぞれの時間。
    """
    parts = [f"stop={result.stop_reason}", f"prep={result.prepare_ms}ms"]
    for lp in result.laps:
        t = lp.timing
        detail = [f"llm={t.get('decide_ms', '?')}ms" + (f"x{t['attempts']}" if t.get("attempts", 1) > 1 else ""),
                  f"in={t.get('input_tokens', '?')}/cache={t.get('cache_read_tokens', '?')}",
                  f"out={t.get('output_tokens', '?')}"]
        if "execute_ms" in t:
            detail.append(f"exec={t['execute_ms']}ms")
            detail += [f"{k[:-3]}={t[k]}ms" for k in ("find_ms", "web_ms", "open_ms") if k in t]
        need = f"{lp.need or '?'}{'(' + '+'.join(lp.fetch_from) + ')' if lp.fetch_from else ''}"
        parts.append(f"lap{lp.lap}:{need}:{lp.status or 'error'}:{len(lp.done)}ops:"
                     f"{lp.elapsed_ms}ms[{' '.join(detail)}]")
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

