# app/services/chat_service.py
"""
横断チャットボット: 1メッセージを受けてから返答を返し終えるまで。

処理の順番(2026-09-28に合意、2026-09-30に仕分け役と探索役を分けた):
  0. 事前チェック(prepare_chat_turn): 文字数上限 / 最低残高 / 送信頻度 /
     断られた回数 / スレッドの所有権 / 生成中の二重送信 / 再送の重複
  1. 保存: スレッド作成 or 読み込み → userメッセージ → 返答用の空行(streaming)
  2. 仕分け役(Gemini 2.5 Flash-Lite, 構造化出力):
     {intent, needs_retrieval, reply_language, thread_title}
  3. 分岐(ここはLLMではなく普通のコード):
     blocked → 定型文(課金なし) / crisis → 共感の定型文+相談窓口(課金なし)
     それ以外 → needs_retrievalがtrueなら探索役(chat_navigator.py、GPT-6 Luna、最大4周)が
     地図を見て検索を選び、コードが実行する(検索は本人のJWTでRPC)
  4. 回答役(Gemini 3.1 Flash-Lite, ストリーミング)
  5. 締め: 本文・出典・原価を保存 → 原価×2のクレジットを消費 → done
     → 未要約が15往復以上なら、畳む処理(chat_summary.py)をCloud Tasksに積む

会話履歴: 古い往復は要約ブロック(chat_summary_blocks)として回答役のsystemの末尾に、
まだ畳んでいない往復(通常5〜14往復)は原文のまま渡す。

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
from app.services.chat_map import StudentMap, load_student_map
from app.services.chat_navigator import (
    NavigationResult,
    NavigatorInput,
    make_lecture_search,
    navigate,
    summarize_for_log,
)
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
from app.services.helpers.llm_unified import (
    BillingEngine,
    LLMOptions,
    Message,
    StreamState,
    UnifiedLLM,
)
from app.services.knowledge_index import embed_queries


# =========================================================
# ⚙️ 設定
# =========================================================

ROUTER_MODEL = "gemini/gemini-2.5-flash-lite"
ANSWER_MODEL = "gemini/gemini-3.1-flash-lite"
ANSWER_MAX_OUTPUT_TOKENS = 2048

# 悪意ある長文対策の本命。超えたらLLMを一切呼ばずに弾く。
MAX_MESSAGE_CHARS = 4000
MAX_SELECTED_TEXT_CHARS = 2000

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

# この時間を過ぎてもstreamingのままの返答は、取り残されたものとみなす
# (二重送信ロックの判定と、patrolでのerror化の両方で使う)。
STREAMING_STALE_MINUTES = 10

INTENTS = ("chitchat", "learning", "personal", "blocked", "crisis")

ROUTER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "intent": {"type": "string", "enum": list(INTENTS)},
        "needs_retrieval": {"type": "boolean"},
        "reply_language": {"type": "string"},
        "thread_title": {"type": ["string", "null"]},
    },
    "required": ["intent", "needs_retrieval", "reply_language", "thread_title"],
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
    # 振り分け役が正常に判断できず、既定値で先へ進めた場合にTrue
    fallback: bool = False
    # 振り分け役への入力が安全フィルタで遮断された場合にTrue
    provider_blocked: bool = False

    def to_json(self) -> dict:
        return {
            "intent": self.intent,
            "needs_retrieval": self.needs_retrieval,
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
    reply_language = raw.get("reply_language") if isinstance(raw.get("reply_language"), str) and raw.get("reply_language") else guess_language(message)

    title = raw.get("thread_title")
    if not is_first_message or not isinstance(title, str) or not title.strip():
        title = None
    else:
        title = title.strip()[:60]

    return RouterDecision(
        intent=intent,
        needs_retrieval=needs_retrieval,
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


def format_sources_block(chunks: list[dict]) -> str:
    """回答役に渡す出典一覧。番号は1始まりで、本文中の[n]と対応する。"""
    lines = []
    for n, chunk in enumerate(chunks, start=1):
        lines.append(f"[{n}] {chunk.get('content', '').strip()}")
    return "\n\n".join(lines)


_CITATION_RE = re.compile(r"\[(\d{1,2})\]")


def extract_citations(answer_text: str, chunks: list[dict]) -> list[dict]:
    """
    本文中で実際に使われた[n]だけを出典として残す。範囲外の番号(回答役が
    作ってしまった番号)は捨てる。画面で講義へ飛べるよう、元の行の
    種類・id・講義idを持たせる。
    """
    used: list[int] = []
    for m in _CITATION_RE.finditer(answer_text or ""):
        n = int(m.group(1))
        if 1 <= n <= len(chunks) and n not in used:
            used.append(n)

    citations = []
    for n in sorted(used):
        chunk = chunks[n - 1]
        content = chunk.get("content") or ""
        first_line = content.splitlines()[0] if content else ""
        citations.append({
            "n": n,
            "chunk_id": chunk.get("id"),
            "source_type": chunk.get("source_type"),
            "source_id": chunk.get("source_id"),
            "lecture_id": chunk.get("lecture_id"),
            "course_id": chunk.get("course_id"),
            # "[CS 161 / Lecture 3 / Deep Note: Heaps]" の角括弧を外して見出しに使う
            "label": first_line.strip().strip("[]"),
            "similarity": chunk.get("similarity"),
            # 画面から該当ページへ直接飛ぶため(deep_noteのtopic_number等)
            "metadata": chunk.get("metadata") or {},
        })
    return citations


def build_history_messages(rows: list[dict], max_turns: int, max_chars: int) -> list[Message]:
    """
    まだ要約に畳んでいない会話を回答役に渡す形に変換する。完了した往復だけを使い、
    断った(blocked)・危機対応(crisis)・失敗(error)・生成中(streaming)の
    返答と、それに対応するuserメッセージは含めない(悪意ある長文で以降の
    入力トークンが膨らまないようにするため、および危機対応の文脈を
    通常の会話に持ち込まないため)。往復の数え方は要約側(pair_turns)と共通。
    """
    messages = []
    for t in pair_turns(rows)[-max_turns:]:
        messages.append(Message(role="user", content=t.user_content[:max_chars]))
        messages.append(Message(role="assistant", content=t.assistant_content[:max_chars]))
    return messages


def format_router_conversation(history: list[Message]) -> str:
    if not history:
        return "(this is the first message of the conversation)"
    return "\n".join(
        f"{'Student' if m.role == 'user' else 'Assistant'}: {m.content[:ROUTER_HISTORY_MAX_CHARS_PER_MESSAGE]}"
        for m in history[-ROUTER_HISTORY_MAX_MESSAGES:]
    )


def format_screen_context(lecture_label: Optional[str], selected_text: Optional[str]) -> str:
    parts = []
    if lecture_label:
        parts.append(f"The student is viewing this lecture: {lecture_label}")
    if selected_text:
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

    def mark(self, name: str) -> None:
        self.marks[name] = round((time.perf_counter() - self._t0) * 1000)

    def to_json(self) -> dict:
        return {"started_at": self.started_at, "ms": dict(self.marks)}

    def log_line(self, message_id: str) -> str:
        parts, prev = [], 0
        for name, ms in self.marks.items():
            parts.append(f"{name}={ms}ms(+{ms - prev})")
            prev = ms
        return f"⏱️ [chat] message={message_id} " + " ".join(parts)


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
    # まだ要約に畳んでいない部分だけ(古い順)
    history_rows: list[dict] = field(default_factory=list)
    summary_blocks: list[dict] = field(default_factory=list)
    timer: TurnTimer = field(default_factory=lambda: TurnTimer())


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
    h = admin_client.table("chat_messages").select("id, role, content, status, created_at") \
        .eq("thread_id", thread_id).is_("deleted_at", "null") \
        .order("created_at", desc=True).limit(RAW_FETCH_MESSAGES).execute()
    return list(reversed(h.data or []))


def _write_turn_rows(
    admin_client,
    is_new_thread: bool,
    thread_id: Optional[str],
    user_id: str,
    content: str,
    client_message_id: str,
    context_lecture_id: Optional[str],
    selected_text: Optional[str],
) -> tuple[str, str, str]:
    """スレッド作成(新規のみ) → userメッセージ → 返答用の空行。3つとも書き込みなので逐次。"""
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

    a = admin_client.table("chat_messages").insert({
        "thread_id": thread_id,
        "user_id": user_id,
        "role": "assistant",
        "content": "",
        "status": "streaming",
    }).execute()
    assistant_message_id = a.data[0]["id"]

    return thread_id, user_message_id, assistant_message_id


async def prepare_chat_turn(
    user_id: str,
    thread_id: Optional[str],
    client_message_id: str,
    content: str,
    context_lecture_id: Optional[str],
    selected_text: Optional[str],
    timer: TurnTimer,
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

    # --- 入力の上限(LLMはおろかDBも呼ぶ前に弾く) ---
    if not content:
        raise ChatRequestError(400, "EMPTY_MESSAGE", "Message is empty.")
    if len(content) > MAX_MESSAGE_CHARS:
        raise ChatRequestError(413, "MESSAGE_TOO_LONG", f"Message exceeds {MAX_MESSAGE_CHARS} characters.",
                               {"max_chars": MAX_MESSAGE_CHARS})
    if selected_text and len(selected_text) > MAX_SELECTED_TEXT_CHARS:
        raise ChatRequestError(413, "SELECTED_TEXT_TOO_LONG",
                               f"Selected text exceeds {MAX_SELECTED_TEXT_CHARS} characters.",
                               {"max_chars": MAX_SELECTED_TEXT_CHARS})

    admin_client = get_supabase_client()
    is_new_thread = thread_id is None

    def to_thread(fn, *args):
        return asyncio.to_thread(fn, *args)

    async def none() -> None:
        return None

    (
        balance_micro, rate_count, blocked_count, dup_row, lecture_label,
        thread_row, is_busy, history_rows, summary_blocks,
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

    timer.mark("prep_thread")

    thread_id, user_message_id, assistant_message_id = await to_thread(
        _write_turn_rows, admin_client, is_new_thread, thread_id, user_id, content,
        client_message_id, context_lecture_id, selected_text,
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
        history_rows=history_rows,
        summary_blocks=summary_blocks,
        timer=timer,
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


async def _run_router(
    llm: UnifiedLLM,
    turn: PreparedTurn,
    memory: "ConversationMemory",
    history: list[Message],
) -> RouterDecision:
    is_first_message = turn.is_new_thread or not turn.thread_has_title
    # 指示文は毎ターン同じsystemに置き、変わる入力はすべて後ろのuserに入れる
    # (先頭が一致する部分にだけプロンプトキャッシュが効くため)。
    user_input = fill_placeholders(_load_prompt("chat_router_input_prompt.txt"), {
        "EARLIER_CONVERSATION": memory.for_router(),
        "RECENT_CONVERSATION": format_router_conversation(history),
        "SCREEN_CONTEXT": format_screen_context(turn.lecture_label, turn.selected_text) or "(none)",
        "IS_FIRST_MESSAGE": "true" if is_first_message else "false",
        "NEW_MESSAGE": turn.content,
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
        if result.finish_reason == "content_filter":
            decision = RouterDecision(
                intent="blocked", needs_retrieval=False,
                reply_language=guess_language(turn.content),
                thread_title=None, provider_blocked=True,
            )
            return decision
        if isinstance(result.output_json, dict) and result.output_json.get("intent") in INTENTS:
            return normalize_router_output(result.output_json, turn.content, is_first_message)

    return fallback_router_decision(turn.content)


def _search_sync(user_client, embedding: list[float], lecture_id: Optional[str]) -> list[dict]:
    params: dict[str, Any] = {
        "query_embedding": embedding,
        "match_count": RETRIEVAL_MATCH_COUNT_PER_QUERY,
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
) -> list[dict]:
    """
    検索は必ずユーザー本人のJWTで作ったクライアント(user_client)で呼ぶ。
    search_knowledge_chunksはauth.uid()で本人の行だけに絞る設計なので、
    ここでサービスロールを使うと0件になる(=他人のデータが混ざる余地が無い)。
    見ている講義があれば、最初のクエリでその講義に絞った検索も1本足す。
    """
    embeddings = await embed_queries(queries, billing=billing)
    tasks = [asyncio.to_thread(_search_sync, user_client, emb, None) for emb in embeddings]
    if context_lecture_id and embeddings:
        tasks.append(asyncio.to_thread(_search_sync, user_client, embeddings[0], context_lecture_id))
    results = await asyncio.gather(*tasks, return_exceptions=True)
    ok_results = []
    for r in results:
        if isinstance(r, Exception):
            print(f"⚠️ [chat] search failed: {r}")
            continue
        ok_results.append(r)
    return merge_search_results(ok_results)


def _ignore_task_exception(task: "asyncio.Task") -> None:
    """待たれずに終わったタスクの例外で「Task exception was never retrieved」を出さない。"""
    if not task.cancelled():
        task.exception()


async def _gather_materials(
    llm: UnifiedLLM,
    billing: BillingEngine,
    user_client,
    turn: PreparedTurn,
    history: list[Message],
    map_task: "asyncio.Task[StudentMap]",
) -> tuple[list[dict], Optional[NavigationResult]]:
    """
    探索役(chat_navigator.py)で回答役に渡す材料を集める。探索役が1周目から動かない
    (地図が読めない・LLMの出力が読めない)ときだけ、従来どおり本文そのもので検索する。
    検索が落ちても、出典なしで答える方がユーザーにとって良いので例外は外に出さない。
    """
    student_map: Optional[StudentMap] = None
    try:
        student_map = await map_task
    except Exception as e:
        print(f"⚠️ [chat] failed to load the student map: {e}")

    navigation: Optional[NavigationResult] = None
    if student_map is not None:
        if not student_map.has_lectures:
            return [], None  # 探す材料がまだ無い
        nav_input = NavigatorInput(
            message=turn.content,
            selected_text=turn.selected_text,
            screen_lecture_id=turn.context_lecture_id,
            recent_conversation=history,
            today=datetime.now(timezone.utc).date(),
            student_map=student_map,
        )
        search = make_lecture_search(user_client, student_map, lambda qs: embed_queries(qs, billing=billing))

        async def on_lap(lap: int) -> None:
            turn.timer.mark(f"navigator_lap{lap}")

        try:
            navigation = await navigate(llm, nav_input, search, on_lap=on_lap)
            print(f"🧭 [chat] message={turn.assistant_message_id} {summarize_for_log(navigation)}")
            if not navigation.failed_before_any_search:
                return navigation.chunks, navigation
        except Exception as e:
            print(f"⚠️ [chat] navigator failed, falling back to plain search: {e}")

    try:
        chunks = await _retrieve(user_client, billing, [turn.content[:200]], turn.context_lecture_id)
    except Exception as e:
        print(f"⚠️ [chat] retrieval failed, answering without sources: {e}")
        chunks = []
    return chunks, navigation


@dataclass
class ConversationMemory:
    """要約に畳んだ部分。回答役・振り分け役に渡す形(IDや節の呼び名は含まない)。"""
    summary: str = ""
    notes: str = ""

    @classmethod
    def from_blocks(cls, blocks: list[dict]) -> "ConversationMemory":
        if not blocks:
            return cls()
        return cls(summary=render_summary_for_answer(blocks), notes=render_notes_for_answer(blocks[-1].get("header")))

    def for_router(self) -> str:
        return "\n\n".join(x for x in [self.summary, self.notes] if x) or "(none)"


def _build_answer_messages(
    turn: PreparedTurn,
    decision: RouterDecision,
    memory: ConversationMemory,
    history: list[Message],
    profile: str,
    chunks: list[dict],
) -> list[Message]:
    """
    並びは「system(固定の指示+プロフィール → 要約 → 会話の前提) → 原文の履歴 → 今回の文脈+質問」。
    プロンプトキャッシュは先頭が完全一致する部分にだけ効くので、毎ターン変わる
    出典・画面の文脈・返答言語はすべて最後のuserメッセージに入れる。要約はsystemの
    末尾にあり、変わるのは畳んだときだけ。履歴に残るuserメッセージは本人が打った
    本文だけなので、次のターンでも先頭がずれない。
    """
    system_template = _render_conditional_sections(_load_prompt("chat_answer_prompt.txt"), {
        "HAS_MEMORY": bool(memory.summary),
        "HAS_NOTES": bool(memory.notes),
    })
    system = fill_placeholders(system_template, {
        "STUDENT_PROFILE": profile,
        "CONVERSATION_SUMMARY": memory.summary,
        "CONVERSATION_NOTES": memory.notes,
    })
    screen_context = format_screen_context(turn.lecture_label, turn.selected_text)
    turn_template = _render_conditional_sections(_load_prompt("chat_answer_turn_prompt.txt"), {
        "HAS_SOURCES": bool(chunks),
        "HAS_SCREEN_CONTEXT": bool(screen_context),
    })
    turn_message = fill_placeholders(turn_template, {
        "SOURCES": format_sources_block(chunks),
        "SCREEN_CONTEXT": screen_context,
        "REPLY_LANGUAGE": decision.reply_language,
        "MESSAGE": turn.content,
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
) -> int:
    """
    返答行の確定・スレッド更新・課金。消費したμクレジットを返す。

    請求の元にするのはLLM/Embedding APIのトークン原価だけ。UnifiedLLMが
    一緒に記録するCloud Runの実行時間コストは「実際より少し高めの概算」
    なので、ユーザーへの請求には含めず、記録(cost_usd列・usage)にだけ残す。
    """
    cost_usd = billing.total_usd()
    chargeable_usd = sum(r.cost_usd for r in billing.records if r.dimension == "tokens")
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
        }).eq("id", turn.assistant_message_id).execute()
    )

    thread_update: dict[str, Any] = {"last_message_at": _now_iso()}
    if decision and decision.thread_title and not turn.thread_has_title:
        thread_update["title"] = decision.thread_title
    await asyncio.to_thread(
        lambda: admin_client.table("chat_threads").update(thread_update).eq("id", turn.thread_id).execute()
    )
    return charged_micro


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

    イベント: meta → status(thinking/searching/writing) → sources → delta… →
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
        await emit("status", {"stage": "thinking"})

        history = build_history_messages(turn.history_rows, RAW_MAX_TURNS, HISTORY_MAX_CHARS_PER_MESSAGE)
        memory = ConversationMemory.from_blocks(turn.summary_blocks)
        # 地図(コース・講義の呼び名)は探索役を呼ぶときだけ使うが、仕分け役を待つ間に
        # 並行で読み込んでおく(探索が要るターンの待ち時間を増やさないため)。
        map_task = asyncio.create_task(asyncio.to_thread(load_student_map, admin_client, turn.user_id))
        map_task.add_done_callback(_ignore_task_exception)
        profile = await asyncio.to_thread(_load_student_profile, admin_client, turn.user_id)
        timer.mark("context_loaded")

        # --- 2. 仕分け ---
        decision = await _run_router(llm, turn, memory, history)
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
        chunks: list[dict] = []
        navigation: Optional[NavigationResult] = None
        if decision.needs_retrieval:
            await emit("status", {"stage": "searching"})
            chunks, navigation = await _gather_materials(llm, billing, user_client, turn, history, map_task)
            timer.mark("retrieval_done")
            await emit("sources", {"sources": [
                {
                    "n": n,
                    "chunk_id": c.get("id"),
                    "source_type": c.get("source_type"),
                    "source_id": c.get("source_id"),
                    "lecture_id": c.get("lecture_id"),
                    "label": ((c.get("content") or "").splitlines() or [""])[0].strip().strip("[]"),
                    "metadata": c.get("metadata") or {},
                    "relation": c.get("relation") or "direct",
                }
                for n, c in enumerate(chunks, start=1)
            ]})

        # --- 4. 回答 ---
        await emit("status", {"stage": "writing"})
        messages = _build_answer_messages(turn, decision, memory, history, profile, chunks)
        state = StreamState()
        # reasoning_effort="low"でもGeminiには thinkingLevel: low, includeThoughts: True
        # が送られ、答え本文の前に思考の文章を生成する分、最初の1文字までが数秒遅くなる
        # (2026-09-29に計測、TurnTimerのanswer_first_tokenで確認)。"none"だと
        # thinkingLevel: minimal, includeThoughts: False になり、雑談程度の速さで
        # 十分なこの役には合っている。
        options = LLMOptions(max_tokens=ANSWER_MAX_OUTPUT_TOKENS, reasoning_effort="none")
        timer.mark("answer_started")
        async for delta in llm.generate_stream(ANSWER_MODEL, messages, state, options):
            if "answer_first_token" not in timer.marks:
                timer.mark("answer_first_token")
            await emit("delta", {"text": delta})
        timer.mark("answer_done")

        usage_extra = {
            "router_model": ROUTER_MODEL,
            "navigator": navigation.to_json() if navigation else None,
            "answer_model": ANSWER_MODEL,
            "answer_input_tokens": state.input_tokens,
            "answer_output_tokens": state.output_tokens,
            "answer_cache_read_tokens": state.cache_read_tokens,
            "answer_cache_write_tokens": state.cache_write_tokens,
            "usage_estimated": state.usage_estimated,
            "retrieved_chunk_ids": [c.get("id") for c in chunks],
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

        citations = extract_citations(answer_text, chunks)
        charged_micro = await _finalize(
            admin_client, turn, content=answer_text, status="complete",
            decision=decision, citations=citations, billing=billing,
            usage_extra={**usage_extra, "finish_reason": state.finish_reason}, charge=True,
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
