# app/services/chat_service.py
"""
横断チャットボット: 1メッセージを受けてから返答を返し終えるまで。

処理の順番(2026-09-28に合意、2026-09-30に仕分け役と探索役を分けた):
  0. 事前チェック(prepare_chat_turn): 文字数上限 / 資料の数・長さの上限 / 最低残高 / 送信頻度 /
     断られた回数 / スレッドの所有権 / 生成中の二重送信 / 再送の重複
  1. 保存: スレッド作成 or 読み込み → userメッセージ → 添付された資料(processing) → 返答用の空行(streaming)
  1.5 添付された資料があれば、審査・要約・目次を作る(chat_attachments.py)。どれかを断ったら
     そのターンごと断る(課金なし・断られた回数に数える)
  2. 仕分け役(Gemini 2.5 Flash-Lite, 構造化出力):
     {intent, needs_retrieval, needs_reasoning, reply_language, thread_title}
  3. 分岐(ここはLLMではなく普通のコード):
     blocked → 定型文(課金なし) / crisis → 共感の定型文+相談窓口(課金なし)
     それ以外 → needs_retrievalがtrueなら探索役(chat_navigator.py、GPT-6 Luna、最大4周)が
     地図を見て検索を選び、コードが実行する(検索は本人のJWTでRPC、Webは1ターン2回までBrave)
  4. 回答役(Gemini 3.5 Flash-Lite, ストリーミング)。needs_reasoningなら先に確かめ役(GPT-6 Luna)が
     答えを確かめたメモを作り、回答役はそれを根拠に書く(chat_reasoning.py)
  5. 締め: 本文・出典・原価を保存 → 原価×CHAT_CREDIT_MARKUP(1.5)のクレジットを消費 → done
     → 未要約が15往復以上なら、畳む処理(chat_summary.py)をCloud Tasksに積む

会話履歴: 古い往復は要約ブロック(chat_summary_blocks)として回答役のsystemの末尾に、
まだ畳んでいない往復(通常5〜14往復)は原文のまま渡す。
添付資料: 合計1万字以内なら全文、超えたら最後の1本だけ全文+残りは一覧を、最新のメッセージに入れる
(chat_attachments.plan_visibility)。確かめ役もsystem以外は同じメッセージを受け取るので、同じものが見える。

回答役が自由に何度も検索する形(エージェント型)にしていない理由:
- 危険/危機の判定は回答を作る前に確実に行いたい(仕分け役に残す)
- 探索役ができるのは決まった操作だけで、周の数と1周の操作数に上限がある。
  選べる場所はenumで縛り、実行は常にコードなので、存在しない場所を指定できず、
  費用・待ち時間の上限も決まっている
"""

import asyncio
import json
import re
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, Awaitable, Callable, Optional

from app.core.supabase import get_supabase_client
from app.services.chat_lecture_source import DbLectureSource
from app.services.chat_map import ChatMap, StudentMap, load_chat_map, load_student_map, resolve_timezone
from app.services.chat_materials import (
    Material,
    extract_citations,
    format_sources_block,
    material_from_chunk,
    normalize_citations,
    select_materials,
    sources_event,
)
from app.services.chat_navigator import (
    CAPABILITIES as NAVIGATOR_CAPABILITIES,
    LECTURE_SOURCE_TYPES,
    NavigationResult,
    NavigatorInput,
    NavigatorTools,
    make_chat_search,
    make_lecture_search,
    make_search,
    navigate,
    refs_from_materials,
    summarize_for_log,
)
from app.services.chat_reasoning import REASONING_CONFIG, CheckedWork, check_work, with_checked_work
from app.services.chat_attachments import (
    MAX_ATTACHMENT_CHARS,
    MAX_ATTACHMENT_TITLE_CHARS,
    MAX_ATTACHMENTS_PER_MESSAGE,
    MAX_ATTACHMENTS_PER_THREAD,
    READ_MAX_CONCURRENT_CALLS,
    Attachment,
    ReadResult,
    Visibility,
    assign_handles,
    history_marker,
    plan_visibility,
    read_attachment,
    render_for_answer,
    render_for_router,
)
from app.services.chat_screen import (
    MAX_SELECTION_CONTEXT_CHARS,
    SELECTED_CLOSE,
    SELECTED_OPEN,
    ScreenPage,
    ScreenRef,
    ScreenSelection,
    load_screen_page,
)
from app.services.chat_thread_source import DbChatThreadSource
from app.services.profile_store import load_chat_memory
from app.services.chat_summary import (
    FOLD_TRIGGER_TURNS,
    fetch_active_blocks,
    pair_turns,
    render_notes_for_answer,
    render_summary_for_answer,
    rows_after_fold_point,
)
from app.services.helpers.credits import (
    CHAT_MIN_BALANCE_CREDITS,
    MICRO_CREDITS_PER_CREDIT,
    consume_chat_credits,
)
from app.services.helpers.helpers import _load_prompt, _render_conditional_sections
from app.services.helpers.plan_features import TIER_FREE, blocked_knowledge_source_types, get_user_tier_level
from app.services.helpers.llm_unified import (
    BillingEngine,
    LLMOptions,
    Message,
    StreamState,
    UnifiedLLM,
)
from app.services.logic.web_search import brave_search
from app.services.knowledge_index import embed_queries


# =========================================================
# ⚙️ 設定
# =========================================================

ROUTER_MODEL = "gemini/gemini-2.5-flash-lite"
# 2026-10-02に3.1 Flash Lite(推論なし)から変更。同じ材料で比べると、最初の1文字までの時間は同じくらい
# (約0.6秒)で、「1文に出典は1つ」「同じ内容を言う出典は1つにまとめる」をよく守った(7回中まとめ付け0回)。
ANSWER_MODEL = "gemini/gemini-2.5-flash"
# 2026-10-04に3.5 Flash-Liteから変更。3.5 Flash-Liteは日本語の相談の会話で単語が崩れる事故が
# 複数回出た(「コミカカ」「走り抜けたちから」、評価では韓国語の文字が混入する例も)。同じ会話を
# 5回ずつ作り直す比較で、2.5 Flash(推論none)は崩れ0/5、3.5 Flash-Liteは1/5で再現した。
# 単価は3.5 Flash-Liteと同じ($0.30/$2.50)で、最初の1文字までの時間も変わらない(約0.4〜0.5秒)。
# ユーザー判断: contents_generation/test_codes/answer_reasoning_test/results/counseling_compare_20261004.md
# 2026-10-02にlowからnoneへ変更。同じ質問をlow/noneそれぞれ2回ずつ比べたところ、
# 6問中5問はlowがnoneと同じか安く、「詳しく教えて」系の1問だけlowが約+1credit高かった。
# その1問で中身を読み比べても、低い方(low)が考えた分だけ良い回答になっている様子は無く
# (むしろnoneの方が短い出力トークンでより詳しい回答を書いていた)、厚くする理由が無いと判断した。
ANSWER_REASONING_EFFORT = "none"
# max_tokensには思考のトークンも含まれるので、その分を足しておく(回答の途中で切れないように)
ANSWER_THINKING_TOKENS = 1024
ANSWER_MAX_OUTPUT_TOKENS = 2048
# 広い質問(探索役のゴールが多い・コースの講義一覧を開いた)だけ、回答の上限を引き上げる(3-8)
ANSWER_MAX_OUTPUT_TOKENS_WIDE = 4096
WIDE_GOAL_ITEMS = 4

# 悪意ある長文対策の本命。超えたらLLMを一切呼ばずに弾く。
MAX_MESSAGE_CHARS = 4000
MAX_SELECTED_TEXT_CHARS = 2000
# 履歴に残す選択テキストの上限(会話が流れても「何を選んでいたか」が分かる程度で十分)
MAX_SELECTED_TEXT_CHARS_IN_HISTORY = 200

# 送信頻度の制限(本人の直近N分のuserメッセージ数)
RATE_LIMIT_WINDOW_MINUTES = 10
RATE_LIMIT_MAX_MESSAGES = 20

# 断られた(blocked)回数の上限。超えたら一時的に送信を止める。
BLOCKED_WINDOW_HOURS = 24
BLOCKED_MAX_MESSAGES = 10

# 会話履歴として回答役・振り分け役に渡す量。古い往復は要約(chat_summary.py)に
# 畳まれるので、回答役に原文で渡すのは「まだ畳んでいない往復」だけ(通常5〜14往復)。
# RAW_MAX_TURNSは要約が遅れたとき・失敗し続けたときの上限。
RAW_MAX_TURNS = 20
RAW_FETCH_MESSAGES = RAW_MAX_TURNS * 4
HISTORY_MAX_CHARS_PER_MESSAGE = 2000
ROUTER_HISTORY_MAX_MESSAGES = 6
ROUTER_HISTORY_MAX_CHARS_PER_MESSAGE = 500

# 探索役が動かなかったときの予備の検索(本文そのもので1回だけ)
RETRIEVAL_MATCH_COUNT_PER_QUERY = 8
RETRIEVAL_TOP_K = 6

# 探索役のWeb検索(Brave)。返答の待ち時間に直に乗るので、Fun Factより短く切る。
WEB_SEARCH_TIMEOUT_SECONDS = 8

# 請求に含める、回数で数える原価(BillingEngine.add_count_cost)。Web検索は1回$0.005で、
# 1ターンのトークン原価と同じくらいになるので、トークンと同じく請求に含める。
CHARGEABLE_COUNT_RESOURCES = frozenset({"brave/llm_context"})

# この時間を過ぎてもstreamingのままの返答は、取り残されたものとみなす
# (二重送信ロックの判定と、patrolでのerror化の両方で使う)。
STREAMING_STALE_MINUTES = 10

INTENTS = ("chitchat", "learning", "personal", "blocked", "crisis")

ROUTER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "intent": {"type": "string", "enum": list(INTENTS)},
        "needs_retrieval": {"type": "boolean"},
        "needs_reasoning": {"type": "boolean"},
        "reply_language": {"type": "string"},
        "thread_title": {"type": ["string", "null"]},
    },
    "required": ["intent", "needs_retrieval", "needs_reasoning", "reply_language", "thread_title"],
}


# =========================================================
# 📝 定型文(断る / 危機対応)
#
# 危機対応はLLMに生成させない(言ってはいけないことを言う可能性をゼロに
# したいため)。相談窓口の番号は2026-09-28に厚生労働省「まもろうよ こころ」
# (https://www.mhlw.go.jp/mamorouyokokoro/soudan/tel/)で確認した。
# 地域は分からないので返答言語で代用している(日本語→日本の窓口、
# それ以外→米国の988と国際的な窓口検索)。
# =========================================================

_BLOCKED_TEXT = {
    "ja": "ごめんなさい、その内容にはお答えできません。授業のことや、興味のあること・将来のことなら、何でも一緒に考えますよ。",
    "en": "Sorry, I can't help with that. I'm happy to think through anything about your classes, your interests, or your future, though.",
}

_CRISIS_TEXT = {
    "ja": (
        "話してくれてありがとう。とてもつらい気持ちの中にいるのかもしれませんね。\n\n"
        "あなたの安全が何より大切です。今すぐ危険な状態なら、迷わず **119** に電話してください。\n\n"
        "ひとりで抱えずに、話を聞いてくれる人につながってほしいです。\n"
        "- **#いのちSOS**：0120-061-338（24時間・無料）\n"
        "- **よりそいホットライン**：0120-279-338（24時間・無料）\n"
        "- **いのちの電話**：0570-783-556（10時〜22時）\n\n"
        "大学の学生相談室・保健センターや、信頼できる人に話すこともできます。"
    ),
    "en": (
        "Thank you for telling me. It sounds like you might be going through something really painful right now.\n\n"
        "Your safety matters most. If you are in immediate danger, please call your local emergency number (911 in the US) right away.\n\n"
        "You don't have to carry this alone — please reach out to someone who can listen:\n"
        "- **988 Suicide & Crisis Lifeline** (US): call or text **988**, 24/7\n"
        "- Outside the US: find a free, confidential helpline at **findahelpline.com**\n\n"
        "Your university's counseling center, or someone you trust, can also help."
    ),
}


def blocked_text(lang: Optional[str]) -> str:
    return _BLOCKED_TEXT["ja" if (lang or "").startswith("ja") else "en"]


def crisis_text(lang: Optional[str]) -> str:
    return _CRISIS_TEXT["ja" if (lang or "").startswith("ja") else "en"]


# =========================================================
# 🧩 純粋関数(ネットワーク・DBに触れない。単体で検証できる部分)
# =========================================================

class ChatRequestError(Exception):
    """事前チェックで弾くときの例外。エンドポイントがHTTPExceptionに変換する。"""
    def __init__(self, status_code: int, error_code: str, message: str, extra: Optional[dict] = None):
        super().__init__(message)
        self.status_code = status_code
        self.error_code = error_code
        self.message = message
        self.extra = extra or {}


@dataclass
class RouterDecision:
    """仕分け役の判断。何をどう探すかは探索役(chat_navigator.py)が決める。"""
    intent: str
    # 探索役を呼ぶかどうか(雑談・会話の続きで足りるもの・断る・危機対応ならFalse)
    needs_retrieval: bool
    reply_language: str
    thread_title: Optional[str]
    # 正しく答えるのに手順を追った検討が要るか(計算・コードの追跡・生徒の解答の正誤判定・押し返しなど)。
    # Trueなら回答役の前に確かめ役が答えを確かめる(chat_reasoning.py)
    needs_reasoning: bool = False
    # 振り分け役が正常に判断できず、既定値で先へ進めた場合にTrue
    fallback: bool = False
    # 振り分け役への入力が安全フィルタで遮断された場合にTrue
    provider_blocked: bool = False

    def to_json(self) -> dict:
        return {
            "intent": self.intent,
            "needs_retrieval": self.needs_retrieval,
            "needs_reasoning": self.needs_reasoning,
            "reply_language": self.reply_language,
            "thread_title": self.thread_title,
            "fallback": self.fallback,
            "provider_blocked": self.provider_blocked,
        }


def guess_language(text: str) -> str:
    """振り分け役が使えないときの返答言語の推定(ひらがな/カタカナ/漢字があれば日本語)。"""
    return "ja" if re.search(r"[぀-ヿ一-鿿]", text or "") else "en"


def fallback_router_decision(message: str) -> RouterDecision:
    """
    振り分け役の出力が読めなかったときの既定値。断る側ではなく「探索ありの
    通常の質問」に倒す: 普通のユーザーを巻き込んで断らないため。本当に
    危険な内容でも、次の回答役のsystem promptと安全フィルタでもう一度止まる。
    探索が不要なら探索役がnothing_neededで止める。
    """
    return RouterDecision(
        intent="learning",
        needs_retrieval=True,
        reply_language=guess_language(message),
        thread_title=None,
        fallback=True,
    )


def normalize_router_output(raw: Any, message: str, is_first_message: bool) -> RouterDecision:
    """
    振り分け役のJSONを検証し、壊れていれば既定値に倒す。構造化出力で
    縛っているので通常は正しい形で来るが、ここを信頼の境界にする。
    """
    if not isinstance(raw, dict) or raw.get("intent") not in INTENTS:
        return fallback_router_decision(message)

    intent = raw["intent"]
    needs_retrieval = bool(raw.get("needs_retrieval")) and intent not in ("chitchat", "blocked", "crisis")
    needs_reasoning = bool(raw.get("needs_reasoning")) and intent in ("learning", "personal")
    reply_language = raw.get("reply_language") if isinstance(raw.get("reply_language"), str) and raw.get("reply_language") else guess_language(message)

    title = raw.get("thread_title")
    if not is_first_message or not isinstance(title, str) or not title.strip():
        title = None
    else:
        title = title.strip()[:60]

    return RouterDecision(
        intent=intent,
        needs_retrieval=needs_retrieval,
        needs_reasoning=needs_reasoning,
        reply_language=reply_language[:10],
        thread_title=title,
    )


def merge_search_results(result_lists: list[list[dict]], top_k: int = RETRIEVAL_TOP_K) -> list[dict]:
    """複数クエリの検索結果を、チャンクidで重複除去(類似度は最大値を採用)して上位top_k件に絞る。"""
    best: dict[str, dict] = {}
    for results in result_lists:
        for row in results or []:
            chunk_id = row.get("id")
            if not chunk_id:
                continue
            if chunk_id not in best or (row.get("similarity") or 0) > (best[chunk_id].get("similarity") or 0):
                best[chunk_id] = row
    ranked = sorted(best.values(), key=lambda r: r.get("similarity") or 0, reverse=True)
    return ranked[:top_k]


def build_history_messages(
    rows: list[dict], max_turns: int, max_chars: int,
    attachment_titles: Optional[dict[str, list[str]]] = None,
) -> list[Message]:
    """
    まだ要約に畳んでいない会話を回答役に渡す形に変換する。完了した往復だけを使い、
    断った(blocked)・危機対応(crisis)・失敗(error)・生成中(streaming)の
    返答と、それに対応するuserメッセージは含めない(悪意ある長文で以降の
    入力トークンが膨らまないようにするため、および危機対応の文脈を
    通常の会話に持ち込まないため)。往復の数え方は要約側(pair_turns)と共通。
    attachment_titles(userメッセージのID → そのとき添付した資料の名前)があれば、
    「ここで資料を添付した」印を付ける(本文は資料の枠で渡るので、履歴には入れない)。
    """
    messages = []
    for t in pair_turns(rows)[-max_turns:]:
        user_content = t.user_content[:max_chars]
        # 選択していたテキストを残す(そのときの「これ」「ここ」の対象。後の往復で指示語が
        # 続いたときに、選択が外れていても何を指していたか分かるようにする)
        if t.user_selected_text:
            user_content = f"[Selected: {t.user_selected_text[:MAX_SELECTED_TEXT_CHARS_IN_HISTORY]}] {user_content}"
        titles = (attachment_titles or {}).get(t.user_message_id)
        if titles:
            user_content = f"{history_marker(titles)}{user_content}"
        messages.append(Message(role="user", content=user_content))
        messages.append(Message(role="assistant", content=t.assistant_content[:max_chars]))
    return messages


def format_router_conversation(history: list[Message]) -> str:
    if not history:
        return "(this is the first message of the conversation)"
    return "\n".join(
        f"{'Student' if m.role == 'user' else 'Assistant'}: {m.content[:ROUTER_HISTORY_MAX_CHARS_PER_MESSAGE]}"
        for m in history[-ROUTER_HISTORY_MAX_MESSAGES:]
    )


def format_screen_context(
    lecture_label: Optional[str],
    selected_text: Optional[str],
    page: Optional[ScreenPage] = None,
    *,
    full_page: bool = True,
) -> str:
    """
    画面の文脈。full_page=Trueは回答役用(見ているページの本文まで)、Falseは振り分け役用
    (ページの名前だけ。本文が回答役に見えていることが分かれば足りる)。
    選択テキストは本文の中で見つかれば<selected>で囲んであるので、別には添えない。
    """
    parts = []
    if lecture_label:
        parts.append(f"The student is viewing this lecture: {lecture_label}")
    if page and full_page:
        notes = []
        if page.selection_marked:
            notes.append(f"the part they selected is wrapped in {SELECTED_OPEN}…{SELECTED_CLOSE}")
        if page.truncated:
            notes.append("the page is long, so only the part around where they are is shown")
        extra = f" ({'; '.join(notes)})" if notes else ""
        parts.append(f"They have this page open: {page.title}. Its text, as they see it{extra}:\n"
                     f"<page>\n{page.text}\n</page>")
    elif page:
        parts.append(f"They have this page open: {page.title} (its full text is visible to the answerer).")
    if selected_text and not (page and full_page and page.selection_marked):
        parts.append(f"The student selected this text on screen:\n\"\"\"\n{selected_text}\n\"\"\"")
    return "\n\n".join(parts)


_PLACEHOLDER_RE = re.compile(r"\$\{(\w+)\}")


def fill_placeholders(template: str, values: dict[str, str]) -> str:
    """${NAME}を一度に置換する。差し込んだ本文(ユーザーの入力や出典)の中の${...}は置換しない。"""
    return _PLACEHOLDER_RE.sub(lambda m: values.get(m.group(1), m.group(0)), template)


def sse_event(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


# =========================================================
# 🚦 事前チェック + 保存 (ここで弾くものはHTTPのエラーとして返る)
# =========================================================

class TurnTimer:
    """
    1ターンの段階ごとの経過時間(リクエスト受信からのms)。どこで時間が
    かかっているかを見るためのもの。chat_messages.usage.timings と
    Cloud Runのログ(⏱️ [chat])の両方に残す。
    """
    def __init__(self) -> None:
        self._t0 = time.perf_counter()
        self.started_at = _now_iso()
        self.marks: dict[str, int] = {}
        # 段階の中身の内訳(並列に走るものそれぞれの所要時間・トークン数など)。marksは時刻、こちらは量。
        self.details: dict[str, Any] = {}

    def mark(self, name: str) -> None:
        self.marks[name] = round((time.perf_counter() - self._t0) * 1000)

    def to_json(self) -> dict:
        return {"started_at": self.started_at, "ms": dict(self.marks), "details": self.details}

    def log_line(self, message_id: str) -> str:
        parts, prev = [], 0
        for name, ms in self.marks.items():
            parts.append(f"{name}={ms}ms(+{ms - prev})")
            prev = ms
        line = f"⏱️ [chat] message={message_id} " + " ".join(parts)
        if self.details:
            line += " | " + json.dumps(self.details, ensure_ascii=False, separators=(",", ":"))
        return line


@dataclass
class NewAttachment:
    """この送信で添付された資料(審査の前)。titleは本人が付けた名前(無ければNone)。"""
    title: Optional[str]
    content: str


# 本文を書かずに資料だけ送ったときに、振り分け役・探索役・回答役へ渡す本文の代わり
ATTACHMENT_ONLY_MESSAGE = "(The student attached material without writing a message.)"


@dataclass
class PreparedTurn:
    user_id: str
    thread_id: str
    is_new_thread: bool
    thread_has_title: bool
    user_message_id: str
    assistant_message_id: str
    content: str
    selected_text: Optional[str]
    lecture_label: Optional[str]
    context_lecture_id: Optional[str]
    # クライアントが送ってきたIANAのタイムゾーン名(「昨日」「今学期」の解決に使う)。無ければUTC。
    timezone_name: Optional[str] = None
    # まだ要約に畳んでいない部分だけ(古い順)
    history_rows: list[dict] = field(default_factory=list)
    summary_blocks: list[dict] = field(default_factory=list)
    # 2段目の要約(1段目のブロック10個をさらに畳んだもの)。1段目は消さないので、
    # summary_blocksには2段目に入った1段目も含まれる
    summary_level2: list[dict] = field(default_factory=list)
    timer: TurnTimer = field(default_factory=lambda: TurnTimer())
    # 事前チェックと並行で読み始める、ユーザーIDだけで読めるもの(振り分け役の前に揃っているように)
    student_map_task: "Optional[asyncio.Task[StudentMap]]" = None
    blocked_task: "Optional[asyncio.Task[frozenset[str]]]" = None
    # 見ているページ(chat_screen.py)。本文はprepare_chat_turnで読み始め、run_chat_turnの
    # 振り分け役の前にscreen_pageへ入れる
    screen_ref: Optional[ScreenRef] = None
    screen_task: "Optional[asyncio.Task[Optional[ScreenPage]]]" = None
    screen_page: Optional[ScreenPage] = None
    # このスレッドの使える資料(審査を通ったもの、添付順)と、この送信で添付された資料の行(processing)
    attachments: list[Attachment] = field(default_factory=list)
    new_attachment_rows: list[dict] = field(default_factory=list)

    @property
    def message_for_prompt(self) -> str:
        """LLMに渡す本文(資料だけ送ったときは、その旨の一文)。"""
        return self.content or ATTACHMENT_ONLY_MESSAGE

    def language_hint(self) -> str:
        """振り分け役を通る前に返答言語を推すための文(本文、無ければ添付した資料の冒頭)。"""
        return self.content or " ".join((r.get("content") or "")[:200] for r in self.new_attachment_rows)


def _now_iso(delta: timedelta = timedelta(0)) -> str:
    return (datetime.now(timezone.utc) + delta).isoformat()


def _lecture_label(admin_client, lecture_id: str, user_id: str) -> Optional[str]:
    """本人の講義なら「コース / 講義名」を返す。他人の講義・存在しない講義はNone。"""
    res = admin_client.table("lectures").select(
        "user_id, course_id, title, title_generated, deleted_at"
    ).eq("id", lecture_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("user_id") != user_id or row.get("deleted_at"):
        return None
    course_title = None
    if row.get("course_id"):
        c = admin_client.table("courses").select("course_title").eq("id", row["course_id"]).maybe_single().execute()
        course_title = (c.data or {}).get("course_title") if c else None
    lecture_title = (row.get("title") or row.get("title_generated") or "").strip()
    return " / ".join(p for p in [course_title or "", lecture_title] if p) or None


def _fetch_balance_micro(admin_client, user_id: str) -> int:
    summary_res = admin_client.rpc("get_credit_summary", {"p_user_id": user_id}).execute()
    summary_row = (summary_res.data or [{}])[0] if summary_res.data else {}
    return summary_row.get("credit_balance") or 0


def _fetch_rate_limit_count(admin_client, user_id: str) -> int:
    recent = admin_client.table("chat_messages").select("id", count="exact") \
        .eq("user_id", user_id).eq("role", "user") \
        .gte("created_at", _now_iso(-timedelta(minutes=RATE_LIMIT_WINDOW_MINUTES))) \
        .limit(1).execute()
    return recent.count or 0


def _fetch_blocked_count(admin_client, user_id: str) -> int:
    blocked = admin_client.table("chat_messages").select("id", count="exact") \
        .eq("user_id", user_id).eq("status", "blocked") \
        .gte("created_at", _now_iso(-timedelta(hours=BLOCKED_WINDOW_HOURS))) \
        .limit(1).execute()
    return blocked.count or 0


def _fetch_dup_row(admin_client, user_id: str, client_message_id: str) -> Optional[dict]:
    dup = admin_client.table("chat_messages").select("id, thread_id") \
        .eq("user_id", user_id).eq("client_message_id", client_message_id).limit(1).execute()
    return dup.data[0] if dup.data else None


def _fetch_thread_row(admin_client, thread_id: str) -> Optional[dict]:
    t = admin_client.table("chat_threads").select("id, user_id, title, deleted_at, context_lecture_id") \
        .eq("id", thread_id).maybe_single().execute()
    return t.data if t else None


def _fetch_busy(admin_client, thread_id: str) -> bool:
    busy = admin_client.table("chat_messages").select("id") \
        .eq("thread_id", thread_id).eq("status", "streaming") \
        .gte("created_at", _now_iso(-timedelta(minutes=STREAMING_STALE_MINUTES))) \
        .limit(1).execute()
    return bool(busy.data)


def _fetch_history_rows(admin_client, thread_id: str) -> list[dict]:
    h = admin_client.table("chat_messages").select("id, role, content, status, created_at, context") \
        .eq("thread_id", thread_id).is_("deleted_at", "null") \
        .order("created_at", desc=True).limit(RAW_FETCH_MESSAGES).execute()
    return list(reversed(h.data or []))


ATTACHMENT_COLUMNS = "id, title, content, summary, sections, message_id, created_at, status"


def _fetch_thread_attachments(admin_client, thread_id: str) -> list[dict]:
    """このスレッドの資料(外していないもの)。使えるのはreadyだけだが、上限はprocessingも含めて数える。"""
    res = admin_client.table("chat_attachments").select(ATTACHMENT_COLUMNS) \
        .eq("thread_id", thread_id).is_("deleted_at", "null").in_("status", ["ready", "processing"]) \
        .order("created_at").limit(MAX_ATTACHMENTS_PER_THREAD + MAX_ATTACHMENTS_PER_MESSAGE).execute()
    return res.data or []


def _write_turn_rows(
    admin_client,
    is_new_thread: bool,
    thread_id: Optional[str],
    user_id: str,
    content: str,
    client_message_id: str,
    context_lecture_id: Optional[str],
    selected_text: Optional[str],
    screen_ref: Optional[ScreenRef] = None,
    attachments: Optional[list[NewAttachment]] = None,
) -> tuple[str, str, str, list[dict]]:
    """
    スレッド作成(新規のみ) → userメッセージ → 添付された資料(processing) → 返答用の空行。
    どれも書き込みなので逐次。資料の行(審査前)も返す。
    """
    if is_new_thread:
        t = admin_client.table("chat_threads").insert({
            "user_id": user_id,
            "mode": "learning",
            "context_lecture_id": context_lecture_id,
        }).execute()
        thread_id = t.data[0]["id"]

    message_context = {}
    if context_lecture_id:
        message_context["lecture_id"] = context_lecture_id
    if selected_text:
        message_context["selected_text"] = selected_text
    if screen_ref:
        message_context["screen"] = {
            k: v for k, v in {"kind": screen_ref.kind, "id": screen_ref.id,
                              "topic_number": screen_ref.topic_number}.items() if v is not None
        }

    try:
        u = admin_client.table("chat_messages").insert({
            "thread_id": thread_id,
            "user_id": user_id,
            "role": "user",
            "content": content,
            "status": "complete",
            "client_message_id": client_message_id,
            "context": message_context,
        }).execute()
    except Exception as e:
        # この送信のために作ったばかりのスレッドは、中身が空のまま残さない
        if is_new_thread:
            try:
                admin_client.table("chat_threads").delete().eq("id", thread_id).execute()
            except Exception:
                pass
        # 上の重複チェックと同時に同じclient_message_idが来た競合(ユニーク制約)
        if "uq_chat_messages_client_message_id" in str(e) or "duplicate key" in str(e):
            raise ChatRequestError(409, "DUPLICATE_MESSAGE", "This message was already received.")
        raise
    user_message_id = u.data[0]["id"]

    attachment_rows: list[dict] = []
    if attachments:
        # 同じ送信の資料は、添付した順に1msずつずらした時刻にする(同じ時刻だと「最後に添付した1本」と
        # 呼び名A1…の順が決まらない。2026-10-04の通しテストで、後に添付した方を最後と判定しなかった)
        base = datetime.now(timezone.utc)
        res = admin_client.table("chat_attachments").insert([{
            "user_id": user_id,
            "thread_id": thread_id,
            "message_id": user_message_id,
            "kind": "text",
            "status": "processing",
            "title": att.title,
            "content": att.content,
            "char_count": len(att.content),
            "created_at": (base + timedelta(milliseconds=i)).isoformat(),
        } for i, att in enumerate(attachments)]).execute()
        attachment_rows = res.data or []

    a = admin_client.table("chat_messages").insert({
        "thread_id": thread_id,
        "user_id": user_id,
        "role": "assistant",
        "content": "",
        "status": "streaming",
    }).execute()
    assistant_message_id = a.data[0]["id"]

    return thread_id, user_message_id, assistant_message_id, attachment_rows


async def prepare_chat_turn(
    user_id: str,
    thread_id: Optional[str],
    client_message_id: str,
    content: str,
    context_lecture_id: Optional[str],
    selected_text: Optional[str],
    timer: TurnTimer,
    timezone_name: Optional[str] = None,
    screen_ref: Optional[ScreenRef] = None,
    selection_before: Optional[str] = None,
    selection_after: Optional[str] = None,
    attachments: Optional[list[NewAttachment]] = None,
) -> PreparedTurn:
    """
    事前チェック→保存。お互いに依存しない読み取り(残高・送信頻度・断られた
    回数・重複・見ている講義・既存スレッドの行・生成中判定・履歴)は全部
    asyncio.gatherで並列に投げる(計測したら合計2秒近く、Supabaseへの往復を
    1本ずつ直列に待っていたのが原因だった)。エラーの優先順位は元の逐次
    コードと同じ(残高→頻度→断られ過ぎ→重複→スレッド無し→二重送信)にする。
    書き込み(スレッド作成・メッセージ保存)は依存関係があるので逐次のまま。
    """
    content = (content or "").strip()
    selected_text = (selected_text or "").strip() or None
    attachments = [
        NewAttachment(title=((a.title or "").strip()[:MAX_ATTACHMENT_TITLE_CHARS] or None), content=(a.content or "").strip())
        for a in attachments or []
    ]

    # --- 入力の上限(LLMはおろかDBも呼ぶ前に弾く) ---
    # 資料だけを送るのは許す(「これを一緒に読みたい」と書かずに貼ることもある)
    if not content and not attachments:
        raise ChatRequestError(400, "EMPTY_MESSAGE", "Message is empty.")
    if len(attachments) > MAX_ATTACHMENTS_PER_MESSAGE:
        raise ChatRequestError(413, "TOO_MANY_ATTACHMENTS",
                               f"At most {MAX_ATTACHMENTS_PER_MESSAGE} attachments per message.",
                               {"max_attachments": MAX_ATTACHMENTS_PER_MESSAGE})
    for att in attachments:
        if not att.content:
            raise ChatRequestError(400, "EMPTY_ATTACHMENT", "An attachment is empty.")
        if len(att.content) > MAX_ATTACHMENT_CHARS:
            raise ChatRequestError(413, "ATTACHMENT_TOO_LONG", f"An attachment exceeds {MAX_ATTACHMENT_CHARS} characters.",
                                   {"max_chars": MAX_ATTACHMENT_CHARS})
    if len(content) > MAX_MESSAGE_CHARS:
        raise ChatRequestError(413, "MESSAGE_TOO_LONG", f"Message exceeds {MAX_MESSAGE_CHARS} characters.",
                               {"max_chars": MAX_MESSAGE_CHARS})
    if selected_text and len(selected_text) > MAX_SELECTED_TEXT_CHARS:
        raise ChatRequestError(413, "SELECTED_TEXT_TOO_LONG",
                               f"Selected text exceeds {MAX_SELECTED_TEXT_CHARS} characters.",
                               {"max_chars": MAX_SELECTED_TEXT_CHARS})

    admin_client = get_supabase_client()
    is_new_thread = thread_id is None

    # 地図(コース一覧)と今のプランは、ユーザーIDだけで読めるので事前チェックと並行で読み始める。
    # 振り分け役がコース一覧を使うので、ここで始めておくと振り分け役の開始を待たせない。
    # 事前チェックで弾かれたときは読み込みが無駄になるが、DBを1回読むだけなので許容する。
    student_map_task = asyncio.create_task(asyncio.to_thread(
        load_student_map, admin_client, user_id, resolve_timezone(timezone_name)))
    student_map_task.add_done_callback(_ignore_task_exception)
    student_map_task.add_done_callback(lambda _t: timer.mark("map_loaded"))
    blocked_task = asyncio.create_task(asyncio.to_thread(_load_blocked_source_types, user_id))
    blocked_task.add_done_callback(_ignore_task_exception)
    blocked_task.add_done_callback(lambda _t: timer.mark("plan_loaded"))
    # 見ているページの本文も同じく並行で読む(プランで使えない種類なら読まない)。
    # 本人の行かどうかはload_screen_page自身が確かめる
    screen_task = None
    if screen_ref:
        selection = ScreenSelection(
            text=selected_text,
            before=(selection_before or "")[-MAX_SELECTION_CONTEXT_CHARS:],
            after=(selection_after or "")[:MAX_SELECTION_CONTEXT_CHARS],
        ) if selected_text else None

        async def _load_screen() -> Optional[ScreenPage]:
            blocked = await blocked_task
            return await asyncio.to_thread(
                load_screen_page, admin_client, user_id, screen_ref, context_lecture_id, selection, blocked)
        screen_task = asyncio.create_task(_load_screen())
        screen_task.add_done_callback(_ignore_task_exception)
        screen_task.add_done_callback(lambda _t: timer.mark("screen_loaded"))

    prep_ms: dict[str, int] = {}
    timer.details["prep_ms"] = prep_ms

    async def to_thread(fn, *args):
        """並列に投げる読み取りそれぞれの所要時間をtimer.details.prep_msに残す(どれが律速かを見るため)。"""
        t = time.perf_counter()
        try:
            return await asyncio.to_thread(fn, *args)
        finally:
            name = fn.__name__.removeprefix("_fetch_").lstrip("_")
            # 同じ関数を並列に2回呼ぶもの(fetch_active_blocksの1段目/2段目)は遅い方を残す
            prep_ms[name] = max(prep_ms.get(name, 0), round((time.perf_counter() - t) * 1000))

    async def none() -> None:
        return None

    (
        balance_micro, rate_count, blocked_count, dup_row, lecture_label,
        thread_row, is_busy, history_rows, summary_blocks, summary_level2, attachment_rows,
    ) = await asyncio.gather(
        to_thread(_fetch_balance_micro, admin_client, user_id),
        to_thread(_fetch_rate_limit_count, admin_client, user_id),
        to_thread(_fetch_blocked_count, admin_client, user_id),
        to_thread(_fetch_dup_row, admin_client, user_id, client_message_id),
        to_thread(_lecture_label, admin_client, context_lecture_id, user_id) if context_lecture_id else none(),
        to_thread(_fetch_thread_row, admin_client, thread_id) if not is_new_thread else none(),
        to_thread(_fetch_busy, admin_client, thread_id) if not is_new_thread else none(),
        to_thread(_fetch_history_rows, admin_client, thread_id) if not is_new_thread else none(),
        to_thread(fetch_active_blocks, admin_client, thread_id) if not is_new_thread else none(),
        to_thread(fetch_active_blocks, admin_client, thread_id, 2) if not is_new_thread else none(),
        to_thread(_fetch_thread_attachments, admin_client, thread_id) if not is_new_thread else none(),
    )
    timer.mark("prep_checks")
    summary_blocks = summary_blocks or []
    history_rows = rows_after_fold_point(
        history_rows or [], summary_blocks[-1]["end_message_id"] if summary_blocks else None
    )

    if context_lecture_id and lecture_label is None:
        context_lecture_id = None

    # --- エラーの優先順位は元の逐次コードと同じ ---
    if balance_micro < CHAT_MIN_BALANCE_CREDITS * MICRO_CREDITS_PER_CREDIT:
        raise ChatRequestError(402, "INSUFFICIENT_CREDITS", "Insufficient credits to send a chat message.",
                               {"credit_balance": balance_micro, "min_credits": CHAT_MIN_BALANCE_CREDITS})
    if rate_count >= RATE_LIMIT_MAX_MESSAGES:
        raise ChatRequestError(429, "CHAT_RATE_LIMITED", "Too many messages. Please wait a moment.",
                               {"window_minutes": RATE_LIMIT_WINDOW_MINUTES, "max_messages": RATE_LIMIT_MAX_MESSAGES})
    if blocked_count >= BLOCKED_MAX_MESSAGES:
        raise ChatRequestError(429, "CHAT_BLOCKED_COOLDOWN",
                               "Chat is temporarily unavailable for this account.",
                               {"window_hours": BLOCKED_WINDOW_HOURS})
    if dup_row:
        raise ChatRequestError(409, "DUPLICATE_MESSAGE", "This message was already received.",
                               {"message_id": dup_row["id"], "thread_id": dup_row["thread_id"]})

    thread_has_title = False
    if not is_new_thread:
        if not thread_row or thread_row.get("user_id") != user_id or thread_row.get("deleted_at"):
            raise ChatRequestError(404, "THREAD_NOT_FOUND", "Thread not found.")
        thread_has_title = bool(thread_row.get("title"))
        # 画面から講義が送られていなければ、スレッド開始時の講義を使う
        if context_lecture_id is None and thread_row.get("context_lecture_id"):
            context_lecture_id = thread_row["context_lecture_id"]
            lecture_label = await to_thread(_lecture_label, admin_client, context_lecture_id, user_id)
            if lecture_label is None:
                context_lecture_id = None
        # 生成中の返答があれば二重送信として弾く(取り残されたものは無視)
        if is_busy:
            raise ChatRequestError(409, "THREAD_BUSY", "A reply is still being generated in this thread.")

    attachment_rows = attachment_rows or []
    if attachments and len(attachment_rows) + len(attachments) > MAX_ATTACHMENTS_PER_THREAD:
        raise ChatRequestError(409, "THREAD_ATTACHMENT_LIMIT",
                               f"A conversation can hold at most {MAX_ATTACHMENTS_PER_THREAD} attachments.",
                               {"max_attachments": MAX_ATTACHMENTS_PER_THREAD})

    timer.mark("prep_thread")

    thread_id, user_message_id, assistant_message_id, new_attachment_rows = await to_thread(
        _write_turn_rows, admin_client, is_new_thread, thread_id, user_id, content,
        client_message_id, context_lecture_id, selected_text, screen_ref, attachments,
    )
    timer.mark("prep_saved")

    return PreparedTurn(
        user_id=user_id,
        thread_id=thread_id,
        is_new_thread=is_new_thread,
        thread_has_title=thread_has_title,
        user_message_id=user_message_id,
        assistant_message_id=assistant_message_id,
        content=content,
        selected_text=selected_text,
        lecture_label=lecture_label,
        context_lecture_id=context_lecture_id,
        timezone_name=(timezone_name or "").strip()[:64] or None,
        history_rows=history_rows,
        summary_blocks=summary_blocks,
        summary_level2=summary_level2 or [],
        timer=timer,
        student_map_task=student_map_task,
        blocked_task=blocked_task,
        screen_ref=screen_ref,
        screen_task=screen_task,
        attachments=[Attachment.from_row(r) for r in attachment_rows if r.get("status") == "ready"],
        new_attachment_rows=new_attachment_rows,
    )


# =========================================================
# 🧠 本体: 振り分け → 検索 → 回答 → 締め
# =========================================================

def _load_student_profile(admin_client, user_id: str) -> str:
    """
    回答役に渡すプロフィール。講義パイプラインの_get_student_profileは、
    空のときに「CS専攻の学生」という既定文を返すが、チャットでそれを使うと
    本人でない人物像で話しかけてしまうので、空なら空と明示する。
    """
    res = admin_client.table("user_profiles").select("bio, interests, future_goals") \
        .eq("id", user_id).maybe_single().execute()
    row = (res.data if res else None) or {}
    parts = []
    if (row.get("bio") or "").strip():
        parts.append(f"About: {row['bio'].strip()}")
    if (row.get("interests") or "").strip():
        parts.append(f"Interests: {row['interests'].strip()}")
    if (row.get("future_goals") or "").strip():
        parts.append(f"Future goals: {row['future_goals'].strip()}")
    return "\n".join(parts) if parts else "(The student has not shared any profile information yet.)"


def router_courses_text(student_map: Optional[StudentMap]) -> str:
    """
    振り分け役に渡すコースの一覧(コース名と学期だけ)。振り分け役は「検索する価値があるか」を
    決めるだけなので、講義数や日付は渡さない(それは探索役の地図で見る)。
    """
    if student_map is None:
        return "(unknown)"
    if not student_map.courses:
        return "(The student has no courses yet.)"
    return "\n".join(f"- {c.title} ({c.term or 'term not set'})" for c in student_map.courses)


async def _run_router(
    llm: UnifiedLLM,
    turn: PreparedTurn,
    memory: "ConversationMemory",
    history: list[Message],
    courses_text: str = "(unknown)",
    attachments_text: str = "(none)",
) -> RouterDecision:
    is_first_message = turn.is_new_thread or not turn.thread_has_title
    # 指示文は毎ターン同じsystemに置き、変わる入力はすべて後ろのuserに入れる
    # (先頭が一致する部分にだけプロンプトキャッシュが効くため)。
    user_input = fill_placeholders(_load_prompt("chat_router_input_prompt.txt"), {
        "EARLIER_CONVERSATION": memory.for_router(),
        "RECENT_CONVERSATION": format_router_conversation(history),
        "SCREEN_CONTEXT": format_screen_context(
            turn.lecture_label, turn.selected_text, turn.screen_page, full_page=False) or "(none)",
        "COURSES": courses_text,
        "ATTACHMENTS": attachments_text,
        "IS_FIRST_MESSAGE": "true" if is_first_message else "false",
        "NEW_MESSAGE": turn.message_for_prompt,
    })
    options = LLMOptions(output_type="json", json_schema=ROUTER_SCHEMA, temperature=0.0)
    messages = [
        Message(role="system", content=_load_prompt("chat_router_prompt.txt")),
        Message(role="user", content=user_input),
    ]

    for _attempt in range(2):
        try:
            result = await llm.generate(ROUTER_MODEL, messages, options)
        except Exception as e:
            print(f"⚠️ [chat] router call failed (attempt {_attempt + 1}): {e}")
            turn.timer.mark(f"router_failed_{_attempt + 1}")
            continue
        turn.timer.details["router"] = {
            "attempts": _attempt + 1, "in": result.input_tokens,
            "cache": result.cache_read_tokens, "out": result.output_tokens,
        }
        if result.finish_reason == "content_filter":
            decision = RouterDecision(
                intent="blocked", needs_retrieval=False,
                reply_language=guess_language(turn.language_hint()),
                thread_title=None, provider_blocked=True,
            )
            return decision
        if isinstance(result.output_json, dict) and result.output_json.get("intent") in INTENTS:
            return normalize_router_output(result.output_json, turn.language_hint(), is_first_message)

    return fallback_router_decision(turn.language_hint())


def _search_sync(user_client, embedding: list[float], lecture_id: Optional[str], source_types: list[str]) -> list[dict]:
    params: dict[str, Any] = {
        "query_embedding": embedding,
        "match_count": RETRIEVAL_MATCH_COUNT_PER_QUERY,
        "filter_source_types": source_types,
    }
    if lecture_id:
        params["filter_lecture_id"] = lecture_id
    res = user_client.rpc("search_knowledge_chunks", params).execute()
    return res.data or []


async def _retrieve(
    user_client,
    billing: BillingEngine,
    queries: list[str],
    context_lecture_id: Optional[str],
    blocked_source_types: frozenset[str] = frozenset(),
) -> list[dict]:
    """
    検索は必ずユーザー本人のJWTで作ったクライアント(user_client)で呼ぶ。
    search_knowledge_chunksはauth.uid()で本人の行だけに絞る設計なので、
    ここでサービスロールを使うと0件になる(=他人のデータが混ざる余地が無い)。
    見ている講義があれば、最初のクエリでその講義に絞った検索も1本足す。
    今のプランで使えない種類(blocked_source_types)は検索しない。
    """
    source_types = [t for t in [*LECTURE_SOURCE_TYPES, "chat_turn"] if t not in blocked_source_types]
    embeddings = await embed_queries(queries, billing=billing)
    tasks = [asyncio.to_thread(_search_sync, user_client, emb, None, source_types) for emb in embeddings]
    if context_lecture_id and embeddings:
        tasks.append(asyncio.to_thread(_search_sync, user_client, embeddings[0], context_lecture_id, source_types))
    results = await asyncio.gather(*tasks, return_exceptions=True)
    ok_results = []
    for r in results:
        if isinstance(r, Exception):
            print(f"⚠️ [chat] search failed: {r}")
            continue
        ok_results.append(r)
    return merge_search_results(ok_results)


def _load_blocked_source_types(user_id: str) -> frozenset[str]:
    """今のプランでチャットの材料にしてはいけない種類。プランが読めなければ最も制限された側(Free)に倒す。"""
    try:
        tier = get_user_tier_level(user_id)
    except Exception as e:
        print(f"⚠️ [chat] failed to load the plan tier, treating as Free: {e}")
        tier = TIER_FREE
    return blocked_knowledge_source_types(tier, user_id=user_id)


def _ignore_task_exception(task: "asyncio.Task") -> None:
    """待たれずに終わったタスクの例外で「Task exception was never retrieved」を出さない。"""
    if not task.cancelled():
        task.exception()


def _screen_topic_index(turn: PreparedTurn) -> Optional[int]:
    """見ているページのトピック番号(探索役の地図で「今のトピック」を示す)。画面の講義のものだけ。"""
    page = turn.screen_page
    if page and page.topic_number is not None and page.lecture_id == turn.context_lecture_id:
        return page.topic_number
    return None


async def _gather_materials(
    llm: UnifiedLLM,
    billing: BillingEngine,
    user_client,
    turn: PreparedTurn,
    history: list[Message],
    map_task: "asyncio.Task[StudentMap]",
    chat_map_task: "asyncio.Task[ChatMap]",
    blocked_source_types: frozenset[str],
    on_fetch: Optional[Callable[[dict], Awaitable[None]]] = None,
    attachment_visibility: Optional[Visibility] = None,
) -> tuple[list[Material], Optional[NavigationResult]]:
    """
    探索役(chat_navigator.py)で回答役に渡す材料を集める。探索役が1周目から動かない
    (地図が読めない・LLMの出力が読めない)ときだけ、従来どおり本文そのもので検索する。
    検索が落ちても、出典なしで答える方がユーザーにとって良いので例外は外に出さない。
    返す材料はselect_materialsで量を絞った後のもの。

    今のプランで使えない種類(blocked_source_types)は、検索・開く(DbLectureSource)の
    両方で読まないようにしてあるが、回答役に渡す直前にもう一度落とす(最後の安全網)。
    """
    def allowed(materials: list[Material]) -> list[Material]:
        return [m for m in materials if m.source_type not in blocked_source_types]

    student_map: Optional[StudentMap] = None
    chat_map: Optional[ChatMap] = None
    try:
        student_map, chat_map = await asyncio.gather(map_task, chat_map_task)
    except Exception as e:
        print(f"⚠️ [chat] failed to load the student/chat map: {e}")

    navigation: Optional[NavigationResult] = None
    has_lectures = bool(student_map and student_map.has_lectures)
    has_chats = bool(chat_map and chat_map.has_anything)
    # Webは講義・チャットがまだ無い人にも使えるので、探索役は常に呼ぶ
    if has_lectures or has_chats or NAVIGATOR_CAPABILITIES["CAN_WEB"]:
        admin_client = get_supabase_client()
        chat_source = DbChatThreadSource(admin_client, turn.user_id)
        nav_input = NavigatorInput(
            message=turn.message_for_prompt,
            selected_text=turn.selected_text,
            screen_lecture_id=turn.context_lecture_id,
            recent_conversation=history,
            today=datetime.now(resolve_timezone(turn.timezone_name)).date(),
            student_map=student_map or StudentMap(),
            chat_map=chat_map or ChatMap(),
            current_thread_id=turn.thread_id,
            previous_turn_refs=_previous_turn_refs(turn.history_rows),
            blocked_source_types=blocked_source_types,
            screen_topic_index=_screen_topic_index(turn),
            screen_page_title=turn.screen_page.title if turn.screen_page else None,
            screen_page_excerpt=turn.screen_page.excerpt() if turn.screen_page else None,
            attachments=turn.attachments,
            attachment_visibility=attachment_visibility,
        )
        # 速度の計測: ベクトル化1回ごと・検索RPC1本ごとの所要時間(ユーザー用クライアントの
        # 1本目が接続の張り直しで遅いかどうかも、rpc_msの先頭で分かる)
        embed_ms: list[int] = turn.timer.details.setdefault("embed_ms", [])
        rpc_ms: list[int] = turn.timer.details.setdefault("rpc_ms", [])

        async def embed(qs: list[str]) -> list[list[float]]:
            t = time.perf_counter()
            try:
                return await embed_queries(qs, billing=billing)
            finally:
                embed_ms.append(round((time.perf_counter() - t) * 1000))

        tools = NavigatorTools(
            search=make_search(
                make_lecture_search(user_client, nav_input.student_map, embed, blocked_source_types, rpc_ms),
                make_chat_search(user_client, turn.thread_id, embed, rpc_ms),
            ),
            source=DbLectureSource(admin_client, turn.user_id, blocked_source_types),
            chat_source=chat_source,
            web_search=lambda q: brave_search(q, billing, timeout=WEB_SEARCH_TIMEOUT_SECONDS),
        )

        async def on_lap(lap: int) -> None:
            turn.timer.mark(f"navigator_lap{lap}")

        try:
            navigation = await navigate(llm, nav_input, tools, on_lap=on_lap, on_fetch=on_fetch)
            print(f"🧭 [chat] message={turn.assistant_message_id} {summarize_for_log(navigation)}")
            if not navigation.failed_before_any_fetch:
                return select_materials(allowed(navigation.materials)), navigation
        except Exception as e:
            print(f"⚠️ [chat] navigator failed, falling back to plain search: {e}")

    if not turn.content:
        return [], navigation  # 資料だけの送信: 本文で検索するものが無い
    try:
        chunks = await _retrieve(user_client, billing, [turn.content[:200]], turn.context_lecture_id, blocked_source_types)
    except Exception as e:
        print(f"⚠️ [chat] retrieval failed, answering without sources: {e}")
        chunks = []
    return select_materials(allowed([material_from_chunk(c) for c in chunks])), navigation


def _answer_max_tokens(navigation: Optional[NavigationResult], materials: list[Material]) -> int:
    """コース全体の概観のような広い質問だけ長く書けるようにする(普段は短く速く)。"""
    wide = (navigation is not None and len(navigation.goal) >= WIDE_GOAL_ITEMS) or any(m.kind == "course" for m in materials)
    return ANSWER_MAX_OUTPUT_TOKENS_WIDE if wide else ANSWER_MAX_OUTPUT_TOKENS


def _previous_turn_refs(history_rows: list[dict]) -> list[dict]:
    """直前の返答(完了したもの)の行に保存した「開いたもの」(context.opened)。"""
    for row in reversed(history_rows):
        if row.get("role") == "assistant" and row.get("status") == "complete":
            opened = (row.get("context") or {}).get("opened")
            return [r for r in opened if isinstance(r, dict)] if isinstance(opened, list) else []
    return []


@dataclass
class ConversationMemory:
    """要約に畳んだ部分。回答役・振り分け役に渡す形(IDや節の呼び名は含まない)。"""
    summary: str = ""
    notes: str = ""

    @classmethod
    def from_blocks(cls, blocks: list[dict], level2: Optional[list[dict]] = None) -> "ConversationMemory":
        if not blocks:
            return cls()
        return cls(summary=render_summary_for_answer(blocks, level2),
                   notes=render_notes_for_answer(blocks[-1].get("header")))

    def for_router(self) -> str:
        return "\n\n".join(x for x in [self.summary, self.notes] if x) or "(none)"


def _format_student_memos(memos: list[dict]) -> str:
    lines = []
    for m in memos:
        if m.get("kind") == "situation":
            until = f" (until {m['expires_at']})" if m.get("expires_at") else ""
            lines.append(f"- Right now: {m['content']}{until}")
        else:
            lines.append(f"- {m['content']}")
    return "\n".join(lines)


def _build_answer_messages(
    turn: PreparedTurn,
    decision: RouterDecision,
    memory: ConversationMemory,
    history: list[Message],
    profile: str,
    materials: list[Material],
    goal: Optional[list[str]] = None,
    student_memos: Optional[list[dict]] = None,
    open_questions: Optional[list[str]] = None,
    attachment_visibility: Optional[Visibility] = None,
) -> list[Message]:
    """
    並びは「system(固定の指示+プロフィール → 要約 → 会話の前提) → 原文の履歴 → 今回の文脈+質問」。
    student_memos / open_questions は自分像プロフィール(ロードマップ9章)の覚え書きと確かめたい仮説。
    どちらもまとめ役が動いたときにしか変わらないので、プロフィールと同じくキャッシュされる先頭に置く。
    プロンプトキャッシュは先頭が完全一致する部分にだけ効くので、毎ターン変わる
    出典・画面の文脈・添付資料・返答言語はすべて最後のuserメッセージに入れる。要約はsystemの
    末尾にあり、変わるのは畳んだときだけ。履歴に残るuserメッセージは本人が打った
    本文だけなので、次のターンでも先頭がずれない。
    """
    system_template = _render_conditional_sections(_load_prompt("chat_answer_prompt.txt"), {
        "HAS_MEMORY": bool(memory.summary),
        "HAS_NOTES": bool(memory.notes),
        "HAS_STUDENT_MEMOS": bool(student_memos),
        "HAS_OPEN_QUESTIONS": bool(open_questions),
    })
    system = fill_placeholders(system_template, {
        "STUDENT_PROFILE": profile,
        "STUDENT_MEMOS": _format_student_memos(student_memos or []),
        "OPEN_QUESTIONS": "\n".join(f"- {q}" for q in open_questions or []),
        "CONVERSATION_SUMMARY": memory.summary,
        "CONVERSATION_NOTES": memory.notes,
    })
    screen_context = format_screen_context(turn.lecture_label, turn.selected_text, turn.screen_page)
    # 資料は毎ターン変わりうる(添付・外す・全文で渡す1本の入れ替わり)ので最後のメッセージに置く。
    # 確かめ役(chat_reasoning)はsystemだけ差し替えるので、同じ資料が見える
    attachments_text = render_for_answer(turn.attachments, attachment_visibility or plan_visibility(turn.attachments))
    turn_template = _render_conditional_sections(_load_prompt("chat_answer_turn_prompt.txt"), {
        "HAS_SOURCES": bool(materials),
        "HAS_GOAL": bool(goal),
        "HAS_ATTACHMENTS": bool(attachments_text),
        "HAS_SCREEN_CONTEXT": bool(screen_context),
    })
    turn_message = fill_placeholders(turn_template, {
        "SOURCES": format_sources_block(materials),
        "GOAL": "\n".join(f"- {g}" for g in goal or []),
        "ATTACHMENTS": attachments_text,
        "SCREEN_CONTEXT": screen_context,
        "REPLY_LANGUAGE": decision.reply_language,
        "MESSAGE": turn.message_for_prompt,
    })
    return [Message(role="system", content=system), *history, Message(role="user", content=turn_message)]


async def _finalize(
    admin_client,
    turn: PreparedTurn,
    *,
    content: str,
    status: str,
    decision: Optional[RouterDecision],
    citations: list[dict],
    billing: BillingEngine,
    usage_extra: dict,
    charge: bool,
    message_context: Optional[dict] = None,
) -> int:
    """
    返答行の確定・スレッド更新・課金。消費したμクレジットを返す。

    請求の元にするのはLLM/Embedding APIのトークン原価と、Web検索(Brave)の回数の原価だけ。UnifiedLLMが
    一緒に記録するCloud Runの実行時間コストは「実際より少し高めの概算」
    なので、ユーザーへの請求には含めず、記録(cost_usd列・usage)にだけ残す。
    """
    cost_usd = billing.total_usd()
    chargeable_usd = sum(r.cost_usd for r in billing.records
                         if r.dimension == "tokens" or (r.dimension == "count" and r.resource in CHARGEABLE_COUNT_RESOURCES))
    breakdown = [vars(r) for r in billing.records]

    charged_micro = 0
    if charge and status == "complete" and chargeable_usd > 0:
        try:
            charged_micro = await asyncio.to_thread(
                consume_chat_credits, turn.user_id, turn.thread_id,
                turn.assistant_message_id, chargeable_usd, breakdown,
            )
        except Exception as e:
            # 課金の失敗で返答自体を失敗扱いにはしない(講義のFINALIZE_JOBと同じ方針)
            print(f"⚠️ [chat] failed to consume credits for message {turn.assistant_message_id}: {e}")

    await asyncio.to_thread(
        lambda: admin_client.table("chat_messages").update({
            "content": content,
            "status": status,
            "citations": citations,
            "router": decision.to_json() if decision else None,
            "usage": {"records": breakdown, "chargeable_usd": chargeable_usd, **usage_extra},
            "cost_usd": cost_usd,
            "credits_charged_micro": charged_micro,
            **({"context": message_context} if message_context else {}),
        }).eq("id", turn.assistant_message_id).execute()
    )

    thread_update: dict[str, Any] = {"last_message_at": _now_iso()}
    if decision and decision.thread_title and not turn.thread_has_title:
        thread_update["title"] = decision.thread_title
    await asyncio.to_thread(
        lambda: admin_client.table("chat_threads").update(thread_update).eq("id", turn.thread_id).execute()
    )
    return charged_micro


async def _read_new_attachments(llm: UnifiedLLM, admin_client, turn: PreparedTurn) -> tuple[bool, list[dict]]:
    """
    この送信で添付された資料を読み(審査・目次・要約)、行を確定する。
    返り値は(断ったか, 1本ごとの原価の記録)。どれかを断ったら、断った資料はblocked、
    ほかはfailed(このターンごと断るので使わない)にする。
    読むのに失敗したら、全部failedにして例外を出す(呼び出し側がそのターンをerrorにする)。
    通った資料はturn.attachmentsの後ろに足す。
    資料どうしも並列に読み、Lunaへの同時呼び出しはREAD_MAX_CONCURRENT_CALLSまでに抑える
    (2026-10-04の通しテストで、9千字と5.4万字の2本を1本ずつ読むと約19秒かかった)。
    """
    rows = turn.new_attachment_rows
    limiter = asyncio.Semaphore(READ_MAX_CONCURRENT_CALLS)
    results: list[ReadResult] = list(await asyncio.gather(
        *[read_attachment(llm, row["content"], limiter) for row in rows]))
    usage = [res.usage_json() for res in results]
    blocked = any(res.blocked for res in results)
    error = next((res.error for res in results if res.error), None)

    if blocked or error:
        def mark_unusable() -> None:
            for i, row in enumerate(rows):
                res = results[i] if i < len(results) else None
                admin_client.table("chat_attachments").update({
                    "status": "blocked" if res and res.blocked else "failed",
                    "usage": res.usage_json() if res else None,
                }).eq("id", row["id"]).execute()
        await asyncio.to_thread(mark_unusable)
        if blocked:
            return True, usage
        raise RuntimeError(f"failed to read an attachment: {error}")

    def save() -> None:
        for row, res in zip(rows, results):
            admin_client.table("chat_attachments").update({
                "status": "ready",
                # 本人が付けた名前を優先し、無ければ要約役が付けた名前
                "title": row.get("title") or res.title or None,
                "summary": res.summary,
                "sections": [sec.to_json() for sec in res.sections],
                "usage": res.usage_json(),
            }).eq("id", row["id"]).execute()
    await asyncio.to_thread(save)
    for row, res in zip(rows, results):
        turn.attachments.append(Attachment(
            id=row["id"], title=row.get("title") or res.title, content=row["content"], summary=res.summary,
            sections=res.sections, message_id=row.get("message_id"), created_at=row.get("created_at") or "",
        ))
    return False, usage


def _mark_new_attachments_failed(admin_client, turn: PreparedTurn) -> None:
    """ターンが途中で失敗したとき、processingのまま残った資料をfailedにする(上限の数に入り続けないように)。"""
    ids = [r["id"] for r in turn.new_attachment_rows]
    if ids:
        admin_client.table("chat_attachments").update({"status": "failed"}) \
            .in_("id", ids).eq("status", "processing").execute()


def _attachment_titles_by_message(attachments: list[Attachment]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for a in attachments:
        if a.message_id:
            out.setdefault(a.message_id, []).append(a.title)
    return out


EnqueueSummary = Callable[[str, int], Awaitable[None]]


async def _maybe_enqueue_summary(turn: PreparedTurn, enqueue_summary: Optional[EnqueueSummary]) -> None:
    """
    今回の往復を含めて未要約が15往復以上なら、畳む処理をCloud Tasksに積む。
    畳むのが遅れても次のターンは原文を少し多めに送るだけなので、ここで失敗しても
    返答自体には影響させない(次のターンでまた積まれる)。
    """
    if enqueue_summary is None:
        return
    unsummarized = len(pair_turns(turn.history_rows)) + 1
    if unsummarized < FOLD_TRIGGER_TURNS:
        return
    next_block_index = (turn.summary_blocks[-1]["block_index"] + 1) if turn.summary_blocks else 1
    try:
        await enqueue_summary(turn.thread_id, next_block_index)
    except Exception as e:
        print(f"⚠️ [chat] failed to enqueue summary for thread {turn.thread_id}: {e}")


async def run_chat_turn(
    turn: PreparedTurn,
    user_client,
    queue: "asyncio.Queue[Optional[str]]",
    enqueue_summary: Optional[EnqueueSummary] = None,
) -> None:
    """
    SSEで送るイベントをqueueに積みながら1ターンを最後まで実行する。
    エンドポイントとは別のasyncioタスクで動かすので、途中でクライアントが
    切断しても締め処理(保存・課金)まで走り切る。最後に必ずNoneを積む。

    イベント: meta → status(reading_attachments/thinking/searching/reasoning/writing) → sources → delta… →
              (replace) → done  /  失敗時は error
    """
    admin_client = get_supabase_client()
    billing = BillingEngine(task_type="CHAT_MESSAGE")
    llm = UnifiedLLM(billing)
    decision: Optional[RouterDecision] = None
    timer = turn.timer

    async def emit(event: str, data: dict) -> None:
        await queue.put(sse_event(event, data))

    try:
        await emit("meta", {
            "thread_id": turn.thread_id,
            "user_message_id": turn.user_message_id,
            "assistant_message_id": turn.assistant_message_id,
        })
        # --- 1.5 添付された資料を読む(審査・目次・要約)。断ったらそのターンごと断る(課金なし) ---
        attachments_read: list[dict] = []
        if turn.new_attachment_rows:
            await emit("status", {"stage": "reading_attachments"})
            attachments_blocked, attachments_read = await _read_new_attachments(llm, admin_client, turn)
            timer.mark("attachments_read")
            if attachments_blocked:
                decision = RouterDecision(intent="blocked", needs_retrieval=False,
                                          reply_language=guess_language(turn.language_hint()), thread_title=None)
                text = blocked_text(decision.reply_language)
                await emit("delta", {"text": text})
                await _finalize(
                    admin_client, turn, content=text, status="blocked", decision=decision, citations=[], billing=billing,
                    usage_extra={"attachments_blocked": True, "attachments_read": attachments_read,
                                 "timings": timer.to_json()}, charge=False,
                )
                await emit("done", {"status": "blocked", "credits_charged": 0})
                return

        await emit("status", {"stage": "thinking"})

        # 資料の呼び名(A1…)と、このターンに全文で渡す資料
        turn.attachments = assign_handles(turn.attachments)
        attachment_visibility = plan_visibility(turn.attachments)
        history = build_history_messages(turn.history_rows, RAW_MAX_TURNS, HISTORY_MAX_CHARS_PER_MESSAGE,
                                         _attachment_titles_by_message(turn.attachments))
        memory = ConversationMemory.from_blocks(turn.summary_blocks, turn.summary_level2)
        # 地図(コース一覧)とプランはprepare_chat_turnで事前チェックと並行に読み始めている。
        # 無い場合(テスト等で直接PreparedTurnを作ったとき)だけここで読む。
        map_task = turn.student_map_task
        if map_task is None:
            tz = resolve_timezone(turn.timezone_name)
            map_task = asyncio.create_task(asyncio.to_thread(load_student_map, admin_client, turn.user_id, tz))
            map_task.add_done_callback(_ignore_task_exception)
            map_task.add_done_callback(lambda _t: timer.mark("map_loaded"))
        # 今のプランで使えない材料の種類(探索で使う)。失敗時はFree扱いで例外は出さない。
        # 回答役にはプランを伝えない(プランの話を回答に持ち込ませない。案内は画面側の固定の注意書き)
        blocked_task = turn.blocked_task
        if blocked_task is None:
            blocked_task = asyncio.create_task(asyncio.to_thread(_load_blocked_source_types, turn.user_id))
            blocked_task.add_done_callback(_ignore_task_exception)
            blocked_task.add_done_callback(lambda _t: timer.mark("plan_loaded"))

        async def _build_chat_map() -> ChatMap:
            recent = await DbChatThreadSource(admin_client, turn.user_id).recent_threads_with_trail(turn.thread_id, 20)
            return load_chat_map(turn.summary_blocks, recent, turn.summary_level2)
        chat_map_task = asyncio.create_task(_build_chat_map())
        chat_map_task.add_done_callback(_ignore_task_exception)
        chat_map_task.add_done_callback(lambda _t: timer.mark("chat_map_loaded"))

        profile = await asyncio.to_thread(_load_student_profile, admin_client, turn.user_id)
        try:
            student_memos, open_questions = await asyncio.to_thread(load_chat_memory, admin_client, turn.user_id)
        except Exception as e:
            # 覚え書きが読めなくても答えは出す(テーブルがまだ無い環境も含む)
            print(f"⚠️ [chat] failed to load memos/hypotheses: {e}")
            student_memos, open_questions = [], []
        timer.mark("context_loaded")
        if turn.screen_task is not None and turn.screen_page is None:
            try:
                turn.screen_page = await turn.screen_task
            except Exception as e:
                # 読めなくても、講義名と選択テキストだけで今まで通り答える
                print(f"⚠️ [chat] failed to load the page on screen: {e}")

        # --- 2. 仕分け ---
        # 振り分け役にもコースの一覧を見せる(授業と関係の無い話で探索役を呼ばないため)。
        # 地図の読み込みは並行で走っていて、振り分け役の開始より0.2〜0.4秒ほど遅れて終わる。
        try:
            router_map: Optional[StudentMap] = await map_task
        except Exception as e:
            print(f"⚠️ [chat] failed to load the student map for the router: {e}")
            router_map = None
        decision = await _run_router(llm, turn, memory, history, router_courses_text(router_map),
                                     render_for_router(turn.attachments, attachment_visibility))
        timer.mark("router_done")

        # --- 3. 分岐: 断る / 危機対応(LLMの回答は作らない、課金しない) ---
        if decision.intent in ("blocked", "crisis"):
            text = blocked_text(decision.reply_language) if decision.intent == "blocked" else crisis_text(decision.reply_language)
            await emit("delta", {"text": text})
            await _finalize(
                admin_client, turn, content=text, status=decision.intent,
                decision=decision, citations=[], billing=billing,
                usage_extra={"router_model": ROUTER_MODEL, "timings": timer.to_json()}, charge=False,
            )
            await emit("done", {"status": decision.intent, "credits_charged": 0})
            return

        # --- 3. 分岐: 探索 ---
        materials: list[Material] = []
        navigation: Optional[NavigationResult] = None
        if decision.needs_retrieval:
            await emit("status", {"stage": "searching"})

            async def on_fetch(info: dict) -> None:
                # 何を探しているか(講義 / 過去のチャット / Web)とクエリなどを画面に出す
                payload = {"stage": "searching", "detail": info.get("kinds", [])}
                if info.get("query"):
                    payload["query"] = info["query"]
                if info.get("target"):
                    payload["target"] = info["target"]
                if info.get("layer"):
                    payload["layer"] = info["layer"]
                if info.get("handle"):
                    payload["handle"] = info["handle"]
                await emit("status", payload)

            materials, navigation = await _gather_materials(
                llm, billing, user_client, turn, history, map_task, chat_map_task, await blocked_task, on_fetch,
                attachment_visibility)
            timer.mark("retrieval_done")
            await emit("sources", {"sources": sources_event(materials)})

        # --- 4. 回答 ---
        messages = _build_answer_messages(
            turn, decision, memory, history, profile, materials, navigation.goal if navigation else None,
            student_memos=student_memos, open_questions=open_questions,
            attachment_visibility=attachment_visibility,
        )
        answer_model, answer_effort = ANSWER_MODEL, ANSWER_REASONING_EFFORT
        checked: Optional[CheckedWork] = None
        # 推論が要るターン: 二段構えなら確かめ役のメモを足し、一段ならそのモデルで直接答える(chat_reasoning.py)
        if decision.needs_reasoning:
            if REASONING_CONFIG.mode == "two_stage":
                await emit("status", {"stage": "reasoning"})
                checked = await check_work(llm, messages)
                timer.mark("reasoning_done")
                if checked.notes:
                    messages = with_checked_work(messages, checked.notes)
                else:
                    # メモが無くても答えは出す(ふだんの回答役だけで答える)
                    print(f"⚠️ [chat] checking step failed for message {turn.assistant_message_id}: {checked.error}")
            elif REASONING_CONFIG.single_model:
                answer_model, answer_effort = REASONING_CONFIG.single_model, REASONING_CONFIG.single_effort
        await emit("status", {"stage": "writing"})
        state = StreamState()
        # 3.1 Flash Liteでは reasoning_effort="low" で最初の1文字までが数秒遅くなった(2026-09-29)が、
        # 3.5 Flash Liteのlowは約0.6秒で、推論なしの3.1と変わらなかった(2026-10-02に計測)。
        # 2.5 Flash(現在のANSWER_MODEL)も推論noneで最初の1文字は約0.4〜0.5秒(2026-10-04に計測)。
        options = LLMOptions(max_tokens=_answer_max_tokens(navigation, materials) + ANSWER_THINKING_TOKENS,
                             reasoning_effort=answer_effort)
        timer.mark("answer_started")
        async for delta in llm.generate_stream(answer_model, messages, state, options):
            if "answer_first_token" not in timer.marks:
                timer.mark("answer_first_token")
            await emit("delta", {"text": delta})
        timer.mark("answer_done")

        usage_extra = {
            "router_model": ROUTER_MODEL,
            "navigator": navigation.to_json() if navigation else None,
            "answer_model": answer_model,
            "reasoning": {"mode": REASONING_CONFIG.mode, "checked_work": checked.to_json() if checked else None}
            if decision.needs_reasoning else None,
            "answer_input_tokens": state.input_tokens,
            "answer_output_tokens": state.output_tokens,
            "answer_cache_read_tokens": state.cache_read_tokens,
            "answer_cache_write_tokens": state.cache_write_tokens,
            "usage_estimated": state.usage_estimated,
            "materials": [{"key": m.key, "handle": m.handle} for m in materials],
            "attachments": {
                "count": len(turn.attachments),
                "full": [a.handle for a in turn.attachments if attachment_visibility.is_full(a)],
                "read": attachments_read,
            } if turn.attachments else None,
            "timings": timer.to_json(),
        }

        # 回答役の段階で安全フィルタに止められた: 断る扱いにして課金しない
        if state.finish_reason == "content_filter":
            text = blocked_text(decision.reply_language)
            await emit("replace", {"text": text})
            await _finalize(
                admin_client, turn, content=text, status="blocked",
                decision=decision, citations=[], billing=billing,
                usage_extra={**usage_extra, "answer_blocked_by_provider": True}, charge=False,
            )
            await emit("done", {"status": "blocked", "credits_charged": 0})
            return

        answer_text = state.output_text
        if not answer_text.strip():
            raise RuntimeError(f"Empty answer (finish_reason={state.finish_reason})")

        # 引用の書き方をそろえる([W2, W3]を分ける・実在しない番号を消す)。変わったら画面の本文も差し替える
        normalized = normalize_citations(answer_text, materials)
        if normalized != answer_text:
            answer_text = normalized
            await emit("replace", {"text": answer_text})
        citations = extract_citations(answer_text, materials)
        # 次のターンの「その次の回」「3番目」のために、開いたもの(無ければ使った材料)をUUIDで残す
        opened_refs = (navigation.opened_refs if navigation else []) or refs_from_materials(materials)
        charged_micro = await _finalize(
            admin_client, turn, content=answer_text, status="complete",
            decision=decision, citations=citations, billing=billing,
            usage_extra={**usage_extra, "finish_reason": state.finish_reason}, charge=True,
            message_context={"opened": opened_refs} if opened_refs else None,
        )
        await emit("done", {
            "status": "complete",
            "citations": citations,
            "credits_charged": charged_micro / MICRO_CREDITS_PER_CREDIT,
        })
        await _maybe_enqueue_summary(turn, enqueue_summary)

    except Exception as e:
        print(f"❌ [chat] turn failed for message {turn.assistant_message_id}: {e}")
        try:
            await asyncio.to_thread(_mark_new_attachments_failed, admin_client, turn)
        except Exception as mark_error:
            print(f"⚠️ [chat] failed to mark attachments as failed for message {turn.assistant_message_id}: {mark_error}")
        try:
            await _finalize(
                admin_client, turn, content="", status="error",
                decision=decision, citations=[], billing=billing,
                usage_extra={"error": str(e)[:1000], "timings": timer.to_json()}, charge=False,
            )
        except Exception as finalize_error:
            # ここでも失敗したら、行はstreamingのまま残り、patrolがerrorにする
            print(f"❌ [chat] failed to mark message {turn.assistant_message_id} as error: {finalize_error}")
        await emit("error", {"error_code": "CHAT_FAILED", "message": "Failed to generate a reply."})
    finally:
        timer.mark("finalized")
        print(timer.log_line(turn.assistant_message_id))
        await queue.put(None)
