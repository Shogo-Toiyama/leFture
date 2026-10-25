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
  4. 回答役(GPT-6 Luna, ストリーミング)。needs_reasoning(計算・コード・提出物の確認・難しい質問)なら推論lowで
     一段で答える(chat_reasoning.py。二段構え=確かめ役のメモ→別のモデルが書く、にも設定で戻せる)
  5. 締め: 本文・出典・原価を保存 → 原価×CHAT_CREDIT_MARKUP(1.5)のクレジットを消費 → done
     → 未要約が15往復以上なら、畳む処理(chat_summary.py)をCloud Tasksに積む

会話履歴: 古い往復は要約ブロック(chat_summary_blocks)として回答役のsystemの末尾に、
まだ畳んでいない往復(通常5〜14往復)は原文のまま渡す。
添付資料: 本人が選んだ(selected)資料は全文、それ以外は一覧を、最新のメッセージに入れる
(chat_attachments.plan_visibility)。選んだ画像の資料は画像そのものも最新のメッセージに付ける(chat_files.py)。
確かめ役もsystem以外は同じメッセージを受け取るので、同じものが見える。

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
import uuid
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
    select_materials_async,
    sources_event,
)
from app.services.chat_compressor import compress_attachment_content_if_needed
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
    MAX_MENTIONS_PER_MESSAGE,
    READ_MAX_CONCURRENT_CALLS,
    Attachment,
    ReadResult,
    Section,
    Visibility,
    answer_image_attachments,
    assign_handles,
    estimate_tokens,
    history_marker,
    mention_ids,
    plain_mentions,
    plan_pins,
    plan_visibility,
    read_attachment,
    render_ai_code_rule,
    render_for_answer,
    render_for_router,
    render_mentions,
    rewrite_mentions,
)
from app.services.chat_files import (
    answer_image,
    image_tokens,
    transcribe_file,
    units_from_json,
)
from app.services.chat_screen import (
    MAX_SELECTION_CONTEXT_CHARS,
    SELECTED_CLOSE,
    SELECTED_OPEN,
    ScreenPage,
    ScreenRef,
    ScreenSelection,
    build_reply_quote,
    load_screen_page,
)
from app.services.chat_thread_source import DbChatThreadSource
from app.services.chat_links import collect_links, fetch_link
from app.services.profile_store import load_chat_memory
from app.services.chat_summary import (
    FOLD_TRIGGER_TURNS,
    Turn,
    extract_source_turns_to_fetch,
    fetch_active_blocks,
    pair_turns,
    render_notes_for_answer,
    render_summary_for_answer,
    join_after_stop,
    rows_after_fold_point,
    should_fold_summary,
    unanswered_after_stop,
)
from app.services.chat_stop import TurnStop, TurnStopped, guarded, register as register_stop, \
    unregister as unregister_stop
from app.services.helpers.credits import (
    CHAT_MIN_BALANCE_CREDITS,
    MICRO_CREDITS_PER_CREDIT,
    consume_chat_credits,
    consume_chat_stop_tail_credits,
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
from app.services.knowledge_index import embed_queries, index_now


# =========================================================
# ⚙️ 設定
# =========================================================

ROUTER_MODEL = "gemini/gemini-2.5-flash-lite"
# 2026-10-02に3.1 Flash Lite(推論なし)から変更。同じ材料で比べると、最初の1文字までの時間は同じくらい
# (約0.6秒)で、「1文に出典は1つ」「同じ内容を言う出典は1つにまとめる」をよく守った(7回中まとめ付け0回)。
ANSWER_MODEL = "anthropic/claude-haiku-5-5"
# 2026-10-07にLunaから変更(ユーザー判断)。Lunaは長さの指示にほとんど従わず、「プログラミング言語の宿題」の
# スレッドで返答が短すぎた。同じ5ターン+LeetCodeの「できた！」をHaiku 5.5(effort low)で書き直すと、
# 中身は全部正確で、長さはLunaの約1.2〜1.4倍、口調はLunaよりはっきり温かかった(絵文字・受け止めてから説明)。
# 単価はLunaと同じ(入力$0.10/M・出力$0.50/M)で、最初の1文字までは0.4〜0.9秒。mediumは長くなる代わりに
# 書き始めが3〜6秒に遅れたのでlowにした。プロンプトが10万トークンを超えると単価が5倍になるので、
# 入力はANSWER_MAX_INPUT_ESTIMATEに収める(fit_answer_input)。推論が要るターンもHaiku 5.5(effort medium、
# chat_reasoning.REASONING_CONFIG)。LiteLLM 1.90.2はreasoning_effortを thinking: adaptive +
# output_config.effort に変換し、既定値以外のtemperatureは外して送る(2026-10-07に実際に送って確認)。
#
# 以下はLunaを選んだときの記録。2026-10-05にGemini 2.5 Flashから変更(ユーザー判断、数日試す)。2.5 Flashは、正しい確かめ役(Luna)のメモを
# 受け取っても生徒のコードを別物に書き換えて「君のコード」として示し、コードが依存している行を消すよう
# 勧めた(LeetCodeのスレッド「Best Time to Buy and Sell Stock」、作り直し3回中3回)。同じターンをLunaが
# 直接書くと3回とも正確で、1ターンの原価も安い(入力$0.10/M・出力$0.50/M)。口調はVOICEの節で補う
# (Lunaは素のままだと淡々とする。2026-10-03の比べ読み: results/tone_compare_20261003.md)。
# 推論が要るターンは、二段構えをやめてLunaが推論lowで一段で答える(chat_reasoning.REASONING_CONFIG)。
#
# 以下は2.5 Flashを選んだときの記録。2026-10-04に3.5 Flash-Liteから変更。3.5 Flash-Liteは日本語の相談の会話で単語が崩れる事故が
# 複数回出た(「コミカカ」「走り抜けたちから」、評価では韓国語の文字が混入する例も)。同じ会話を
# 5回ずつ作り直す比較で、2.5 Flash(推論none)は崩れ0/5、3.5 Flash-Liteは1/5で再現した。
# 単価は3.5 Flash-Liteと同じ($0.30/$2.50)で、最初の1文字までの時間も変わらない(約0.4〜0.5秒)。
# ユーザー判断: contents_generation/test_codes/answer_reasoning_test/results/counseling_compare_20261004.md
# 2026-10-02にlowからnoneへ変更。同じ質問をlow/noneそれぞれ2回ずつ比べたところ、
# 6問中5問はlowがnoneと同じか安く、「詳しく教えて」系の1問だけlowが約+1credit高かった。
# その1問で中身を読み比べても、低い方(low)が考えた分だけ良い回答になっている様子は無く
# (むしろnoneの方が短い出力トークンでより詳しい回答を書いていた)、厚くする理由が無いと判断した。
# (ここまでのnone/lowの比較はGeminiのとき。Haiku 5.5はlow、上のANSWER_MODELの説明を参照)
ANSWER_REASONING_EFFORT = "low"
# max_tokensには思考のトークンも含まれるので、その分を足しておく(回答の途中で切れないように)。
# 推論するとき(ふだんのeffort low・推論ターンのmedium)は考える量が多いので別に取る。推論ターンのHaiku medium は
# 計算の追い直しで出力(思考込み)が7,756トークンまで出た(2026-10-08)ので、回答の分と合わせて切れないよう広めに取る
ANSWER_THINKING_TOKENS = 1024
ANSWER_REASONING_THINKING_TOKENS = 16384
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
# 未要約の履歴全体の合計トークン上限。要約が遅延した場合でも文字数で切らず古い完全往復単位でドロップする
RAW_HISTORY_MAX_TOKENS = 30_000
HISTORY_MAX_CHARS_PER_MESSAGE = 2000
ROUTER_HISTORY_MAX_MESSAGES = 20
ROUTER_HISTORY_MAX_CHARS_PER_MESSAGE = 1200

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
        "user_goal": {
            "type": "string",
            "description": "Clear, self-contained statement in English capturing the student's true goal, resolving context anchors, handling multiple intents, and desired outcome.",
        },
        "retrieval_reason": {
            "type": "string",
            "description": "Brief explanation (1 sentence) of whether lecture retrieval is needed and why.",
        },
        "needs_retrieval": {"type": "boolean"},
        "needs_reasoning": {"type": "boolean"},
        "reply_language": {"type": "string"},
        "thread_title": {"type": ["string", "null"]},
    },
    "required": [
        "intent",
        "user_goal",
        "retrieval_reason",
        "needs_retrieval",
        "needs_reasoning",
        "reply_language",
        "thread_title",
    ],
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
    # 生徒の真の目的・文脈アンカー・複合要求・成功条件の言語化
    user_goal: Optional[str] = None
    # 資料取得の要否を判断した理由(自己回帰推論で探索要否を正確に判断するためのCoT)
    retrieval_reason: Optional[str] = None
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
            "user_goal": self.user_goal,
            "retrieval_reason": self.retrieval_reason,
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
        user_goal=None,
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
    user_goal = raw.get("user_goal") if isinstance(raw.get("user_goal"), str) and raw.get("user_goal").strip() else None
    retrieval_reason = raw.get("retrieval_reason") if isinstance(raw.get("retrieval_reason"), str) else None

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
        user_goal=user_goal,
        retrieval_reason=retrieval_reason,
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
    rows: list[dict],
    max_turns: int = RAW_MAX_TURNS,
    max_chars: Optional[int] = None,
    attachment_titles: Optional[dict[str, list[str]]] = None,
) -> list[Message]:
    """
    まだ要約に畳んでいない会話を回答役に渡す形に変換する。
    - 完了した往復(Turn)だけを使い、文の途中で機械的に文字数カットしない(文の途切れによる幻覚を防ぐ)。
    - 万が一、要約タスクの遅延等で未要約往復が膨大になった場合でも、文字数で切るのではなく
      「古い完全な往復(PairTurn)」単位でドロップし、最新の往復を安全にRAW_HISTORY_MAX_TOKENS以内に収める。
    """
    all_turns = pair_turns(rows)[-max_turns:]
    # トークン上限(30,000トークン)を超える場合、古い完全な往復から丸ごと除外する(最新1往復は必ず残す)
    cumulative_tokens = 0
    selected_turns: list[Turn] = []
    for t in reversed(all_turns):
        t_tokens = estimate_tokens(t.user_content or "") + estimate_tokens(t.assistant_content or "")
        if selected_turns and (cumulative_tokens + t_tokens > RAW_HISTORY_MAX_TOKENS):
            break
        selected_turns.append(t)
        cumulative_tokens += t_tokens
    selected_turns.reverse()

    messages = []
    for t in selected_turns:
        user_content = t.user_content
        if max_chars is not None and max_chars > 0:
            user_content = user_content[:max_chars]
        if t.user_selected_text:
            user_content = f"[Selected: {t.user_selected_text[:MAX_SELECTED_TEXT_CHARS_IN_HISTORY]}] {user_content}"
        titles = (attachment_titles or {}).get(t.user_message_id)
        if titles:
            user_content = f"{history_marker(titles)}{user_content}"

        asst_content = t.assistant_content
        if max_chars is not None and max_chars > 0:
            asst_content = asst_content[:max_chars]

        messages.append(Message(role="user", content=user_content))
        messages.append(Message(role="assistant", content=asst_content))
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
    reply_quote: Optional[str] = None,
) -> str:
    """
    画面の文脈。full_page=Trueは回答役用(見ているページの本文まで)、Falseは振り分け役用
    (ページの名前だけ。本文が回答役に見えていることが分かれば足りる)。
    選択テキストは本文の中で見つかれば<selected>で囲んであるので、別には添えない。
    reply_quote: 会話の中のAIの回答の一部を選んで返信したときの、その回答の抜粋(選択箇所は<selected>で囲んである)。
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
    if reply_quote:
        parts.append(
            "The student selected a passage of your earlier answer in this conversation and is replying to it. "
            f"Here is that answer around the passage (the passage itself is wrapped in {SELECTED_OPEN}…{SELECTED_CLOSE}):\n"
            f"<earlier_answer>\n{reply_quote}\n</earlier_answer>")
    elif selected_text and not (page and full_page and page.selection_marked):
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
    """
    この送信で添付された資料(審査の前)。titleは本人が付けた名前(無ければNone)。
    ファイル(chat_files.py)はattachment_idに、送る前に取り出し済みのdraftの行を指す(contentは空)。
    """
    title: Optional[str]
    content: str
    attachment_id: Optional[str] = None
    # テキスト: 本文の印(⟦att:ref⟧)で使う端末の仮のidと、保存する行のid(prepare_chat_turnが先に決める)
    ref: Optional[str] = None
    new_id: Optional[str] = None

    @property
    def is_file(self) -> bool:
        return self.attachment_id is not None

    @property
    def id(self) -> str:
        return self.attachment_id or self.new_id or ""


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
    # 会話の中のAIの回答の一部を選んで返信したとき、その回答の抜粋(本人の回答で、選択が本当にその中にあると
    # 確かめられたときだけ入る。確かめられなければ、ただの選択として扱う)
    reply_quote: Optional[str] = None
    # このスレッドの使える資料(審査を通ったもの、添付順)と、この送信で添付された資料の行(processing)
    attachments: list[Attachment] = field(default_factory=list)
    new_attachment_rows: list[dict] = field(default_factory=list)
    # 添付資料の裏処理タスク(画像やドキュメントのOCR・要約・インデックス化)。回答終了時に合流して確実に課金する
    attachment_tasks: list["asyncio.Task"] = field(default_factory=list)
    # 資料解析で拒絶(blocked)が発生したかのフラグ
    attachments_blocked: bool = False
    # 資料ごとの読み込み原価・使用量(chat_messages.usage.attachments.readに残す)
    attachments_read: list[dict] = field(default_factory=list)
    # 回答役に渡す画像(選択中の画像の資料、answer_image_attachmentsの順)。run_chat_turnが読み込む
    answer_images: list[bytes] = field(default_factory=list)
    # 本文が文中で指している資料のid(出てくる順)と、全文で読む枠に入れる資料のid(新しく添付したもの +
    # 「全文で添付」した既存の資料)。新しく添付した資料は、いつも全文で添付(2026-10-07にユーザーと合意)
    mentions: list[str] = field(default_factory=list)
    pin_requests: list[str] = field(default_factory=list)
    # 全文で読む枠を超えて外した資料など(返答の行のcontextに残し、画面に知らせる)
    attachment_notice: Optional[dict] = None
    # 直前に「返答の前に止めた」質問の本文(古い順)。打ちかけで送って止め、続きを今回送ったときなど。
    # 今回の質問の前につなげて読ませる(間に止めたことの一行を挟む。chat_summary.join_after_stop)
    carried_messages: list[str] = field(default_factory=list)
    # 途中停止の状態(run_chat_turnが入れる)。課金のある呼び出しの入口で確認する
    stop: Optional[TurnStop] = None
    # 今回完了した返答の本文(要約エンキュー判定で未要約往復に含めるため)
    assistant_content: Optional[str] = None

    @property
    def message_for_prompt(self) -> str:
        """LLMに渡す本文(資料の印は呼び名と名前に直す。資料だけ送ったときは、その旨の一文)。"""
        current = render_mentions(self.content, self.attachments).strip()
        if self.carried_messages:
            stopped = [render_mentions(c, self.attachments).strip() for c in self.carried_messages]
            return join_after_stop([t for t in stopped if t], current or ATTACHMENT_ONLY_MESSAGE)
        return current or ATTACHMENT_ONLY_MESSAGE

    def language_hint(self) -> str:
        """振り分け役を通る前に返答言語を推すための文(本文、無ければ添付した資料の冒頭)。"""
        text = plain_mentions("\n".join([*self.carried_messages, self.content])).replace("[attached material]", "").strip()
        return text or " ".join((r.get("content") or r.get("file_name") or "")[:200]
                                for r in self.new_attachment_rows)


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


def _fetch_edit_target(admin_client, message_id: str) -> Optional[dict]:
    r = admin_client.table("chat_messages") \
        .select("id, thread_id, user_id, role, created_at, deleted_at") \
        .eq("id", message_id).maybe_single().execute()
    return r.data if r else None


def _fetch_rows_between(admin_client, thread_id: str, after: Optional[str], before: str) -> list[dict]:
    """編集したとき: 残る要約ブロックの後ろから、編集点の手前までの履歴(新しい方からRAW_FETCH_MESSAGES件)。"""
    q = admin_client.table("chat_messages").select("id, role, content, status, created_at, context") \
        .eq("thread_id", thread_id).is_("deleted_at", "null").lt("created_at", before)
    if after:
        q = q.gt("created_at", after)
    h = q.order("created_at", desc=True).limit(RAW_FETCH_MESSAGES).execute()
    return list(reversed(h.data or []))


def _ts(value: Optional[str]) -> Optional[datetime]:
    """DBのtimestamptzの文字列を比べられる形に(小数秒の桁数が行ごとに違うので、文字列のまま比べない)。"""
    return datetime.fromisoformat(value) if value else None


def _fetch_reply_target(admin_client, message_id: str) -> Optional[dict]:
    r = admin_client.table("chat_messages") \
        .select("id, thread_id, user_id, role, status, content, created_at, deleted_at") \
        .eq("id", message_id).maybe_single().execute()
    return r.data if r else None


def _truncate_thread_from(admin_client, thread_id: str, user_id: str, message_id: str) -> dict:
    res = admin_client.rpc("truncate_chat_thread_from", {
        "p_thread_id": thread_id, "p_user_id": user_id, "p_message_id": message_id,
    }).execute()
    return res.data or {}


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


ATTACHMENT_COLUMNS = ("id, title, content, summary, sections, message_id, created_at, status, selected, token_count, "
                      "forbids_ai_code, kind, image_path, selected_at")
# 送る前に取り出したファイル(draft)。extractionは書き起こしに使う(送った後のターンで消す)
DRAFT_COLUMNS = ("id, user_id, kind, status, title, file_name, extraction, storage_prefix, deleted_at, "
                 "created_at, token_count")
# ファイルから書き起こした本文の上限(送る前の見積もりで10万字以内を確かめてあるが、書き起こしが
# 見積もりより長くなることがある。超えた分は切り、警告を残す)
MAX_FILE_CONTENT_CHARS = 150_000


def _fetch_drafts(admin_client, attachment_ids: list[str]) -> list[dict]:
    if not attachment_ids:
        return []
    res = admin_client.table("chat_attachments").select(DRAFT_COLUMNS).in_("id", attachment_ids).execute()
    return res.data or []


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
    attachment_modes: Optional[list[dict]] = None,
    reply_to_message_id: Optional[str] = None,
    adopt_attachments_from: Optional[str] = None,
) -> tuple[str, str, str, list[dict]]:
    """
    スレッド作成(新規のみ) → ファイルのdraftをこのスレッドに結び付ける → userメッセージ →
    添付された資料(processing) → 返答用の空行。どれも書き込みなので逐次。資料の行(審査前、添付順)も返す。
    """
    attachments = attachments or []
    if is_new_thread:
        t = admin_client.table("chat_threads").insert({
            "user_id": user_id,
            "mode": "learning",
            "context_lecture_id": context_lecture_id,
        }).execute()
        thread_id = t.data[0]["id"]

    # 同じ送信の資料は、添付した順に1msずつずらした時刻にする(同じ時刻だと呼び名A1…の順が決まらない。
    # 2026-10-04の通しテストで、後に添付した方を最後と判定しなかった)
    base = datetime.now(timezone.utc)
    created = {i: (base + timedelta(milliseconds=i)).isoformat() for i in range(len(attachments))}

    # ファイル: draftのうちに取る(同じdraftを2つの送信が同時に使わないよう、statusがdraftのものだけ)
    claimed: dict[int, dict] = {}
    for i, att in enumerate(attachments):
        if not att.is_file:
            continue
        r = admin_client.table("chat_attachments").update({
            "thread_id": thread_id, "status": "processing", "created_at": created[i],
            **({"title": att.title} if att.title else {}),
        }).eq("id", att.attachment_id).eq("status", "draft").execute()
        if not r.data:
            # 取れなかった: 取ったものをdraftに戻し、作ったばかりのスレッドは消す
            for row in claimed.values():
                admin_client.table("chat_attachments").update({"thread_id": None, "status": "draft"}) \
                    .eq("id", row["id"]).execute()
            if is_new_thread:
                try:
                    admin_client.table("chat_threads").delete().eq("id", thread_id).execute()
                except Exception:
                    pass
            raise ChatRequestError(409, "ATTACHMENT_NOT_READY", "An attached file is no longer available.")
        claimed[i] = r.data[0]

    message_context = {}
    if context_lecture_id:
        message_context["lecture_id"] = context_lecture_id
    if selected_text:
        message_context["selected_text"] = selected_text
    if reply_to_message_id:
        message_context["reply_to_message_id"] = reply_to_message_id
    if screen_ref:
        message_context["screen"] = {
            k: v for k, v in {"kind": screen_ref.kind, "id": screen_ref.id,
                              "topic_number": screen_ref.topic_number}.items() if v is not None
        }
    # このメッセージで添付・指した資料と、その渡し方(full: 全文で添付 / mention: 指しただけ)。画面のチップ用
    if attachment_modes:
        message_context["attachments"] = attachment_modes

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
        # 取ったファイルはdraftに戻す(スレッドを消すとON DELETE CASCADEで行ごと消えてしまう)
        for row in claimed.values():
            try:
                admin_client.table("chat_attachments").update({"thread_id": None, "status": "draft"}) \
                    .eq("id", row["id"]).execute()
            except Exception:
                pass
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
    # 編集して送ったとき: 編集したメッセージで添付した資料を、新しいメッセージの資料に付け替える
    # (資料は残す。本文の @資料 もそのまま使える。消えたのはメッセージの方)
    if adopt_attachments_from:
        admin_client.table("chat_attachments").update({"message_id": user_message_id}) \
            .eq("message_id", adopt_attachments_from).is_("deleted_at", "null").execute()

    attachment_rows: list[dict] = []
    if claimed:
        admin_client.table("chat_attachments").update({"message_id": user_message_id}) \
            .in_("id", [row["id"] for row in claimed.values()]).execute()
        for row in claimed.values():
            row["message_id"] = user_message_id
    texts = [(i, att) for i, att in enumerate(attachments) if not att.is_file]
    if texts:
        res = admin_client.table("chat_attachments").insert([{
            "id": att.new_id,
            "user_id": user_id,
            "thread_id": thread_id,
            "message_id": user_message_id,
            "kind": "text",
            "status": "processing",
            "title": att.title,
            "content": att.content,
            "char_count": len(att.content),
            "token_count": estimate_tokens(att.content),
            "created_at": created[i],
        } for i, att in texts]).execute()
        attachment_rows.extend(res.data or [])
    attachment_rows.extend(claimed.values())
    attachment_rows.sort(key=lambda r: r.get("created_at") or "")

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
    reply_to_message_id: Optional[str] = None,
    replace_from_message_id: Optional[str] = None,
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
    # 新しく添付する資料(text / file)と、このスレッドの既存の資料を指すもの(existing: 全文で添付 / メンション)
    existing_refs: list[tuple[str, str]] = [
        (a.attachment_id, "full" if getattr(a, "mode", None) == "full" else "mention")
        for a in attachments or [] if getattr(a, "kind", "text") == "existing" and getattr(a, "attachment_id", None)
    ]
    attachments = [
        NewAttachment(title=((getattr(a, "title", None) or "").strip()[:MAX_ATTACHMENT_TITLE_CHARS] or None),
                      content=(getattr(a, "content", None) or "").strip(),
                      attachment_id=getattr(a, "attachment_id", None) if getattr(a, "kind", "text") == "file" else None,
                      ref=getattr(a, "ref", None),
                      new_id=str(uuid.uuid4()) if getattr(a, "kind", "text") == "text" else None)
        for a in attachments or [] if getattr(a, "kind", "text") in ("text", "file")
    ]

    # --- 入力の上限(LLMはおろかDBも呼ぶ前に弾く) ---
    # 資料だけを送るのは許す(「これを一緒に読みたい」と書かずに貼ることもある)
    if not content and not attachments and not existing_refs:
        raise ChatRequestError(400, "EMPTY_MESSAGE", "Message is empty.")
    if len(existing_refs) > MAX_MENTIONS_PER_MESSAGE:
        raise ChatRequestError(413, "TOO_MANY_MENTIONS", f"At most {MAX_MENTIONS_PER_MESSAGE} materials per message.",
                               {"max_mentions": MAX_MENTIONS_PER_MESSAGE})
    if len(attachments) > MAX_ATTACHMENTS_PER_MESSAGE:
        raise ChatRequestError(413, "TOO_MANY_ATTACHMENTS",
                               f"At most {MAX_ATTACHMENTS_PER_MESSAGE} attachments per message.",
                               {"max_attachments": MAX_ATTACHMENTS_PER_MESSAGE})
    for att in attachments:
        if att.is_file:
            continue
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
    # 編集・作り直し: このユーザーメッセージ自身と、それより後ろを消してから、新しい往復を書く(一本道)
    if replace_from_message_id and is_new_thread:
        raise ChatRequestError(422, "INVALID_EDIT", "An edit needs the conversation it belongs to.")

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
        # 会話の中の回答を選んで返信するときの選択は、見ているページには無いので、ページ側では探さない
        selection = ScreenSelection(
            text=selected_text,
            before=(selection_before or "")[-MAX_SELECTION_CONTEXT_CHARS:],
            after=(selection_after or "")[:MAX_SELECTION_CONTEXT_CHARS],
        ) if selected_text and not (reply_to_message_id and thread_id) else None

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
        thread_row, is_busy, history_rows, summary_blocks, summary_level2, attachment_rows, draft_rows,
        reply_row, edit_target,
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
        to_thread(_fetch_drafts, admin_client, [a.attachment_id for a in attachments if a.is_file]),
        to_thread(_fetch_reply_target, admin_client, reply_to_message_id)
        if reply_to_message_id and selected_text and not is_new_thread else none(),
        to_thread(_fetch_edit_target, admin_client, replace_from_message_id) if replace_from_message_id else none(),
    )
    timer.mark("prep_checks")
    summary_blocks = summary_blocks or []
    history_rows = rows_after_fold_point(
        history_rows or [], summary_blocks[-1]["end_message_id"] if summary_blocks else None
    )

    # 編集・作り直し: 編集点より前だけで会話を組み直す(消すのは事前チェックが全部通った後)
    edit_from: Optional[datetime] = None
    if replace_from_message_id:
        if (not edit_target or edit_target.get("thread_id") != thread_id or edit_target.get("user_id") != user_id
                or edit_target.get("role") != "user" or edit_target.get("deleted_at")):
            raise ChatRequestError(404, "MESSAGE_NOT_FOUND", "The message to edit was not found.")
        edit_from = _ts(edit_target["created_at"])
        summary_blocks = [b for b in summary_blocks if _ts(b["end_message_created_at"]) < edit_from]
        summary_level2 = [b for b in summary_level2 or [] if _ts(b["end_message_created_at"]) < edit_from]
        history_rows = await to_thread(
            _fetch_rows_between, admin_client, thread_id,
            summary_blocks[-1]["end_message_created_at"] if summary_blocks else None, edit_target["created_at"])
        # 後ろのメッセージで添付した資料は消える(編集したメッセージ自身の資料は残る)
        attachment_rows = [r for r in attachment_rows or []
                           if r.get("message_id") == replace_from_message_id or _ts(r.get("created_at")) < edit_from]

    if context_lecture_id and lecture_label is None:
        context_lecture_id = None
    carried_messages = [r.get("content") or "" for r in unanswered_after_stop(history_rows)]

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

    # ファイル: 本人のdraftで、送る前の取り出しが済んでいること
    drafts_by_id = {r["id"]: r for r in draft_rows or []}
    for att in attachments:
        if not att.is_file:
            continue
        row = drafts_by_id.get(att.attachment_id)
        if not row or row.get("user_id") != user_id or row.get("deleted_at"):
            raise ChatRequestError(404, "ATTACHMENT_NOT_FOUND", "An attached file was not found.")
        if row.get("status") != "draft" or not row.get("extraction"):
            raise ChatRequestError(409, "ATTACHMENT_NOT_READY", "An attached file is not ready to send.")

    # 返信先: 本人のこのスレッドの、完了したAIの回答で、選択した文章が本当にその中にあるときだけ。
    # 1つでも合わなければ、ただの選択として扱う(回答でないものを「あなたの回答」と見せないため)
    reply_quote: Optional[str] = None
    if reply_row and selected_text:
        if (reply_row.get("thread_id") == thread_id and reply_row.get("user_id") == user_id
                and reply_row.get("role") == "assistant" and reply_row.get("status") in ("complete", "stopped")
                and not reply_row.get("deleted_at")
                and (edit_from is None or _ts(reply_row.get("created_at")) < edit_from)):
            reply_quote = build_reply_quote(reply_row.get("content") or "", ScreenSelection(
                text=selected_text,
                before=(selection_before or "")[-MAX_SELECTION_CONTEXT_CHARS:],
                after=(selection_after or "")[:MAX_SELECTION_CONTEXT_CHARS],
            ))
    validated_reply_to_id = reply_row["id"] if reply_quote and reply_row else None

    attachment_rows = attachment_rows or []
    # 既存の資料を指すのは、このスレッドの使える(ready)資料だけ
    ready_ids = {r["id"] for r in attachment_rows if r.get("status") == "ready"}
    for att_id, _mode in existing_refs:
        if att_id not in ready_ids:
            raise ChatRequestError(404, "ATTACHMENT_NOT_FOUND", "A referenced material was not found in this conversation.")
    # 本文の印: 仮のid(テキストのref)を本物のidに直し、このスレッドで指せないものは消す
    content = rewrite_mentions(
        content, {a.ref: a.new_id for a in attachments if a.ref and a.new_id},
        ready_ids | {a.id for a in attachments})
    mentions = mention_ids(content)
    if len(mentions) > MAX_MENTIONS_PER_MESSAGE:
        raise ChatRequestError(413, "TOO_MANY_MENTIONS", f"At most {MAX_MENTIONS_PER_MESSAGE} materials per message.",
                               {"max_mentions": MAX_MENTIONS_PER_MESSAGE})

    def _is_image_new_att(att: NewAttachment) -> bool:
        if att.is_file and att.attachment_id:
            return (drafts_by_id.get(att.attachment_id) or {}).get("kind") == "image"
        return False

    pin_requests = [att_id for att_id, mode in existing_refs if mode == "full"] + [
        a.id for a in attachments if not _is_image_new_att(a)
    ]
    attachment_modes = [{"id": att_id, "mode": mode} for att_id, mode in existing_refs] + \
                       [{"id": a.id, "mode": "full"} for a in attachments]

    if attachments and len(attachment_rows) + len(attachments) > MAX_ATTACHMENTS_PER_THREAD:
        raise ChatRequestError(409, "THREAD_ATTACHMENT_LIMIT",
                               f"A conversation can hold at most {MAX_ATTACHMENTS_PER_THREAD} attachments.",
                               {"max_attachments": MAX_ATTACHMENTS_PER_THREAD})

    timer.mark("prep_thread")

    if replace_from_message_id:
        # 削除・無効化は1つのトランザクションで(migration 20261018000000_chat_edit_truncate.sql)
        try:
            truncated = await to_thread(_truncate_thread_from, admin_client, thread_id, user_id, replace_from_message_id)
        except Exception as e:
            if "MESSAGE_NOT_FOUND" in str(e):
                raise ChatRequestError(404, "MESSAGE_NOT_FOUND", "The message to edit was not found.")
            raise
        timer.details["edit"] = truncated
        timer.mark("prep_truncated")

    thread_id, user_message_id, assistant_message_id, new_attachment_rows = await to_thread(
        _write_turn_rows, admin_client, is_new_thread, thread_id, user_id, content,
        client_message_id, context_lecture_id, selected_text, screen_ref, attachments, attachment_modes,
        validated_reply_to_id, replace_from_message_id,
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
        reply_quote=reply_quote,
        carried_messages=carried_messages,
        attachments=[Attachment.from_row(r) for r in attachment_rows if r.get("status") == "ready"],
        new_attachment_rows=new_attachment_rows,
        mentions=mentions,
        pin_requests=pin_requests,
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
    res = admin_client.table("user_profiles").select("username, bio, interests, future_goals") \
        .eq("id", user_id).maybe_single().execute()
    row = (res.data if res else None) or {}
    parts = []
    if (row.get("username") or "").strip():
        parts.append(f"Name: {row['username'].strip()}")
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
    referenced_sources: Optional[str] = None,
) -> RouterDecision:
    is_first_message = turn.is_new_thread or not turn.thread_has_title
    # 指示文は毎ターン同じsystemに置き、変わる入力はすべて後ろのuserに入れる
    # (先頭が一致する部分にだけプロンプトキャッシュが効くため)。
    input_template = _render_conditional_sections(_load_prompt("chat_router_input_prompt.txt"), {
        "HAS_REFERENCED_SOURCES": bool(referenced_sources),
    })
    tz = resolve_timezone(turn.timezone_name)
    current_time_str = datetime.now(tz).strftime("%Y-%m-%d (%a) %H:%M")
    user_input = fill_placeholders(input_template, {
        "EARLIER_CONVERSATION": memory.for_router(),
        "REFERENCED_SOURCES": referenced_sources or "",
        "RECENT_CONVERSATION": format_router_conversation(history),
        "SCREEN_CONTEXT": format_screen_context(
            turn.lecture_label, turn.selected_text, turn.screen_page, full_page=False,
            reply_quote=turn.reply_quote) or "(none)",
        "COURSES": courses_text,
        "ATTACHMENTS": attachments_text,
        "IS_FIRST_MESSAGE": "true" if is_first_message else "false",
        "CURRENT_TIME": current_time_str,
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
    stop: Optional[TurnStop] = None,
) -> list[dict]:
    """
    検索は必ずユーザー本人のJWTで作ったクライアント(user_client)で呼ぶ。
    search_knowledge_chunksはauth.uid()で本人の行だけに絞る設計なので、
    ここでサービスロールを使うと0件になる(=他人のデータが混ざる余地が無い)。
    見ている講義があれば、最初のクエリでその講義に絞った検索も1本足す。
    今のプランで使えない種類(blocked_source_types)は検索しない。
    """
    source_types = [t for t in [*LECTURE_SOURCE_TYPES, "chat_turn"] if t not in blocked_source_types]
    if stop is not None:
        await stop.check()
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
    must_check_attachments: bool = False,
    user_goal: Optional[str] = None,
    on_compressing: Optional[Callable[[], Awaitable[None]]] = None,
    referenced_sources: Optional[str] = None,
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
        tz = resolve_timezone(turn.timezone_name)
        now = datetime.now(tz)
        current_time_str = now.strftime("%Y-%m-%d (%a) %H:%M")
        nav_input = NavigatorInput(
            message=turn.message_for_prompt,
            selected_text=turn.selected_text,
            screen_lecture_id=turn.context_lecture_id,
            recent_conversation=history,
            today=now.date(),
            student_map=student_map or StudentMap(),
            current_time_str=current_time_str,
            chat_map=chat_map or ChatMap(),
            current_thread_id=turn.thread_id,
            previous_turn_refs=_previous_turn_refs(turn.history_rows),
            blocked_source_types=blocked_source_types,
            screen_topic_index=_screen_topic_index(turn),
            screen_page_title=turn.screen_page.title if turn.screen_page else None,
            screen_page_excerpt=turn.screen_page.excerpt() if turn.screen_page else None,
            attachments=turn.attachments,
            attachment_visibility=attachment_visibility,
            must_check_attachments=must_check_attachments,
            links=_turn_links(turn),
            user_goal=user_goal,
            referenced_sources=referenced_sources,
        )
        # 速度の計測: ベクトル化1回ごと・検索RPC1本ごとの所要時間(ユーザー用クライアントの
        # 1本目が接続の張り直しで遅いかどうかも、rpc_msの先頭で分かる)
        embed_ms: list[int] = turn.timer.details.setdefault("embed_ms", [])
        rpc_ms: list[int] = turn.timer.details.setdefault("rpc_ms", [])

        async def embed(qs: list[str]) -> list[list[float]]:
            if turn.stop is not None:
                await turn.stop.check()
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
            web_search=guarded(turn.stop, lambda q: brave_search(q, billing, timeout=WEB_SEARCH_TIMEOUT_SECONDS)),
            link_fetch=guarded(turn.stop, lambda url: fetch_link(url, billing)),
        )

        async def on_lap(lap: int) -> None:
            turn.timer.mark(f"navigator_lap{lap}")

        try:
            navigation = await navigate(llm, nav_input, tools, on_lap=on_lap, on_fetch=on_fetch)
            print(f"🧭 [chat] message={turn.assistant_message_id} {summarize_for_log(navigation)}")
            if not navigation.failed_before_any_fetch:
                return await select_materials_async(allowed(navigation.materials), billing=billing, on_compressing=on_compressing), navigation
        except Exception as e:
            print(f"⚠️ [chat] navigator failed, falling back to plain search: {e}")

    if not turn.content:
        return [], navigation  # 資料だけの送信: 本文で検索するものが無い
    if turn.stop is not None:
        turn.stop.raise_if_stopped()
    try:
        chunks = await _retrieve(user_client, billing, [plain_mentions(turn.content)[:200]], turn.context_lecture_id, blocked_source_types,
                                 turn.stop)
    except Exception as e:
        print(f"⚠️ [chat] retrieval failed, answering without sources: {e}")
    return await select_materials_async(allowed([material_from_chunk(c, student_map=student_map) for c in chunks]), billing=billing, on_compressing=on_compressing), navigation


def _answer_max_tokens(navigation: Optional[NavigationResult], materials: list[Material]) -> int:
    """コース全体の概観のような広い質問だけ長く書けるようにする(普段は短く速く)。"""
    wide = (navigation is not None and len(navigation.goal) >= WIDE_GOAL_ITEMS) or any(m.kind == "course" for m in materials)
    return ANSWER_MAX_OUTPUT_TOKENS_WIDE if wide else ANSWER_MAX_OUTPUT_TOKENS


def answer_options(model: str, effort: Optional[str], max_output_tokens: int) -> LLMOptions:
    """
    回答役の呼び出しのオプション。思考のトークンも上限に含まれるので、推論の量に応じて足す。
    GPT-6系はtemperatureの既定値(1)以外とmax_tokensを受け付けない(探索役・確かめ役と同じ)。
    """
    limit = max_output_tokens + (ANSWER_THINKING_TOKENS if effort in (None, "none") else ANSWER_REASONING_THINKING_TOKENS)
    if model.startswith("gpt-"):
        return LLMOptions(temperature=1.0, max_completion_tokens=limit, reasoning_effort=effort)
    if model.startswith("anthropic/"):
        # Claude 5系も既定値(1)以外のtemperatureを受け付けない(LiteLLMが外して送るが、明示しておく)
        return LLMOptions(temperature=1.0, max_tokens=limit, reasoning_effort=effort)
    return LLMOptions(max_tokens=limit, reasoning_effort=effort)


def _turn_links(turn: PreparedTurn) -> list:
    """
    探索役が開けるリンク(U1…)。大事な順に集める: 今のメッセージ → 選択テキスト → 画面のページ →
    添付資料 → それより前の生徒の発言(新しい順)。開けるのは会話に出てきたURLだけ(chat_links.py)。
    """
    sources: list[tuple[str, str]] = [("message", turn.content or ""), ("selection", turn.selected_text or "")]
    if turn.screen_page is not None:
        sources.append(("screen", turn.screen_page.text))
    sources += [(f"attachment:{a.handle}", a.content) for a in turn.attachments]
    sources += [("earlier", r.get("content") or "") for r in reversed(turn.history_rows) if r.get("role") == "user"]
    return collect_links(sources)


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

def format_student_message_for_answer(turn: PreparedTurn) -> str:
    """
    回答役に見せる生徒のメッセージ。
    テキスト選択(Ask AI)や返信引用がある場合、その対象を動的ラベル([Selected text from ...]:)で
    本文の直前に明示して、モデルの第一アテンションが確実に選択対象へ向くようにする。
    """
    raw_message = turn.message_for_prompt
    prefix_parts = []

    if turn.reply_quote:
        prefix_parts.append(
            f"[Quoted from your earlier reply]:\n\"\"\"\n{turn.reply_quote.strip()}\n\"\"\""
        )
    elif turn.selected_text:
        # 動的ラベルの決定
        label = "Selected text from screen"
        page = turn.screen_page
        if page:
            if page.kind == "deep_note":
                label = f"Selected text from Deep Note ({page.title})"
            elif page.kind == "review_card":
                label = f"Selected text from Review Cards ({page.title})"
            elif page.kind == "fun_fact":
                label = f"Selected text from Fun Fact ({page.title})"
            elif page.title:
                label = f"Selected text from {page.title}"
        prefix_parts.append(
            f"[{label}]:\n\"\"\"\n{turn.selected_text.strip()}\n\"\"\""
        )

    if prefix_parts:
        return "\n\n".join(prefix_parts) + "\n\n" + raw_message
    return raw_message


async def _fetch_referenced_source_turns(
    admin_client, thread_id: str, source_turns: list[int]
) -> str:
    """
    needs_source: True の source_turn の完全な生テキストを DB から取得して整形する。
    """
    if not source_turns:
        return ""
    def _q():
        return admin_client.table("chat_messages").select("id, role, content, status, router, created_at") \
            .eq("thread_id", thread_id).is_("deleted_at", "null") \
            .order("created_at").execute()
    res = await asyncio.to_thread(_q)
    all_turns = {t.number: t for t in pair_turns(res.data or [])}

    parts = []
    for num in sorted(source_turns):
        t = all_turns.get(num)
        if t:
            parts.append(f"[Turn {num}] Student: {t.user_content}\n[Turn {num}] Assistant: {t.assistant_content}")
        else:
            print(f"⚠️ [chat] referenced source turn {num} not found in thread {thread_id}")
    return "\n\n".join(parts)


def _build_answer_messages(
    turn: PreparedTurn,
    decision: RouterDecision,
    memory: ConversationMemory,
    history: list[Message],
    profile: str,
    materials: list[Material],
    student_memos: Optional[list[dict]] = None,
    open_questions: Optional[list[str]] = None,
    attachment_visibility: Optional[Visibility] = None,
    link_failures: Optional[list[tuple[str, str]]] = None,
    referenced_sources: Optional[str] = None,
    retrieval_reasoning: Optional[str] = None,
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
        "HAS_REFERENCED_SOURCES": bool(referenced_sources),
    })
    system = fill_placeholders(system_template, {
        "STUDENT_PROFILE": profile,
        "STUDENT_MEMOS": _format_student_memos(student_memos or []),
        "OPEN_QUESTIONS": "\n".join(f"- {q}" for q in open_questions or []),
        "CONVERSATION_SUMMARY": memory.summary,
        "CONVERSATION_NOTES": memory.notes,
        "REFERENCED_SOURCES": referenced_sources or "",
    })
    screen_context = format_screen_context(
        turn.lecture_label, turn.selected_text, turn.screen_page, reply_quote=turn.reply_quote)
    # 資料は毎ターン変わりうる(添付・外す・全文で渡す1本の入れ替わり)ので最後のメッセージに置く。
    # 確かめ役(chat_reasoning)はsystemだけ差し替えるので、同じ資料が見える
    attachments_text = render_for_answer(turn.attachments, attachment_visibility or plan_visibility(turn.attachments))
    ai_code_rule = render_ai_code_rule(turn.attachments)
    turn_template = _render_conditional_sections(_load_prompt("chat_answer_turn_prompt.txt"), {
        "HAS_SOURCES": bool(materials),
        "HAS_ATTACHMENTS": bool(attachments_text),
        "HAS_AI_CODE_RULE": bool(ai_code_rule),
        "HAS_SCREEN_CONTEXT": bool(screen_context),
        "HAS_LINK_NOTES": bool(link_failures),
        "HAS_USER_GOAL": bool(decision.user_goal),
        "HAS_RETRIEVAL_REASONING": bool(retrieval_reasoning),
    })
    tz = resolve_timezone(turn.timezone_name)
    current_time_str = datetime.now(tz).strftime("%Y-%m-%d (%a) %H:%M")
    turn_message = fill_placeholders(turn_template, {
        "SOURCES": format_sources_block(materials),
        "ATTACHMENTS": attachments_text,
        "AI_CODE_RULE": ai_code_rule,
        "SCREEN_CONTEXT": screen_context,
        "CURRENT_TIME": current_time_str,
        "USER_GOAL": decision.user_goal or "",
        "RETRIEVAL_REASONING": retrieval_reasoning or "",
        # 探索役が開こうとして読めなかったリンク(ログインが要る授業サイトなど)
        "LINK_NOTES": "\n".join(f"- {url}: {reason}" for url, reason in link_failures or []),
        "REPLY_LANGUAGE": decision.reply_language,
        "MESSAGE": format_student_message_for_answer(turn),
    })
    # 選択中の画像の資料(render_for_answerが「image N」と書いた順)。回答役は画像を読めるモデルであること
    return [Message(role="system", content=system), *history,
            Message(role="user", content=turn_message, images=turn.answer_images)]


# 回答役の入力の上限(estimate_tokensの概算で数える)。回答役のHaiku 5.5は、プロンプトが10万トークンを超えると
# そのターンの単価が入力も出力も5倍になる(1ターン約4→約24クレジット)。Claudeの数え方は概算の1.1〜1.2倍
# (日本語の会話)、英語だけの長文では1.4倍だった(2026-10-07にcount_tokensで実測)ので、英語の資料ばかりでも
# 10万に届かないよう65,000にしている。ふだんのターンは5,000〜10,000、資料を3万トークン分全文で読んでいても
# 4〜5万で、届くのは長い資料・長い履歴・長い教材が重なったときだけ。
ANSWER_MAX_INPUT_ESTIMATE = 65_000


def fit_answer_input(messages: list[Message], limit: int = ANSWER_MAX_INPUT_ESTIMATE) -> tuple[list[Message], int]:
    """
    回答役の入力が上限を超えるなら、古い履歴から1往復ずつ外す。外した往復の数も返す。
    system(指示・要約)と最後のメッセージ(資料・出典・画面・質問)はそのまま残す。全文で読む資料は
    生徒が選んだものなので、削るのは履歴を先にする(古い往復の中身は、畳まれれば要約にも残る)。
    """
    if len(messages) < 2:
        return messages, 0
    system, history, last = messages[0], list(messages[1:-1]), messages[-1]
    fixed = (estimate_tokens(system.content) + estimate_tokens(last.content)
             + sum(image_tokens(i) for i in last.images))
    history_tokens = [estimate_tokens(m.content) for m in history]
    dropped = 0
    # build_history_messagesは user → assistant の往復で並べるので、2つずつ外せば交互の並びが保たれる
    while history and fixed + sum(history_tokens) > limit:
        del history[:2], history_tokens[:2]
        dropped += 1
    if fixed + sum(history_tokens) > limit:
        print(f"⚠️ [chat] answer input is still over the limit without any history: ~{fixed} tokens")
    return [system, *history, last], dropped


async def _load_answer_images(turn: PreparedTurn, vis: Visibility) -> list[bytes]:
    """
    選択中の画像の資料の画像を読み込み、回答役に渡す大きさに縮める。読めなかった画像は、その資料を
    書き起こしだけで見せる(image_pathを外す。render_for_answerの「image N」の番号がずれないように)。
    """
    targets = answer_image_attachments(turn.attachments, vis)
    if not targets:
        return []
    from app.core.r2_storage import storage_service

    def load(path: str) -> bytes:
        return answer_image(storage_service.download_binary(path))

    results = await asyncio.gather(*[asyncio.to_thread(load, a.image_path) for a in targets], return_exceptions=True)
    images = []
    for a, r in zip(targets, results):
        if isinstance(r, BaseException):
            print(f"⚠️ [chat] failed to load the image of attachment {a.id}: {r}")
            a.image_path = None
        else:
            images.append(r)
    return images


def _chargeable_usd(records: list) -> float:
    """請求の元にする原価(トークン、Web検索の回数、およびプロンプト圧縮等のModal GPU時間)。Cloud Runの時間の概算は含めない。"""
    return sum(
        r.cost_usd for r in records
        if r.dimension == "tokens"
        or (r.dimension == "count" and r.resource in CHARGEABLE_COUNT_RESOURCES)
        or (r.dimension == "time" and r.resource == "modal/t4")
    )


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

    行はまだ生成中(streaming)のときだけ確定する。途中停止では、停止のエンドポイント(生成していた
    インスタンスが落ちたとき)と、このターンの締めが同じ行を確定しようとするので、先に確定した方だけが
    課金する(後の方は何もせず0を返す)。課金は確定の後(二重に課金しないため)。
    """
    cost_usd = billing.total_usd()
    chargeable_usd = _chargeable_usd(billing.records)
    breakdown = [vars(r) for r in billing.records]

    claimed = await asyncio.to_thread(
        lambda: admin_client.table("chat_messages").update({
            "content": content,
            "status": status,
            "citations": citations,
            "router": decision.to_json() if decision else None,
            "usage": {"records": breakdown, "chargeable_usd": chargeable_usd, **usage_extra},
            "cost_usd": cost_usd,
            "credits_charged_micro": 0,
            **({"context": message_context} if message_context else {}),
        }).eq("id", turn.assistant_message_id).eq("status", "streaming").execute()
    )
    if not claimed.data:
        print(f"⚠️ [chat] message {turn.assistant_message_id} was already finalized; skipping status={status}")
        return 0

    charged_micro = 0
    if charge and status in ("complete", "stopped") and chargeable_usd > 0:
        try:
            charged_micro = await asyncio.to_thread(
                consume_chat_credits, turn.user_id, turn.thread_id,
                turn.assistant_message_id, chargeable_usd, breakdown,
            )
        except Exception as e:
            # 課金の失敗で返答自体を失敗扱いにはしない(講義のFINALIZE_JOBと同じ方針)
            print(f"⚠️ [chat] failed to consume credits for message {turn.assistant_message_id}: {e}")
        if charged_micro:
            await asyncio.to_thread(
                lambda: admin_client.table("chat_messages").update({"credits_charged_micro": charged_micro})
                    .eq("id", turn.assistant_message_id).execute()
            )

    thread_update: dict[str, Any] = {"last_message_at": _now_iso()}
    if decision and decision.thread_title and not turn.thread_has_title:
        thread_update["title"] = decision.thread_title
    await asyncio.to_thread(
        lambda: admin_client.table("chat_threads").update(thread_update).eq("id", turn.thread_id).execute()
    )
    return charged_micro


async def _background_transcribe_image(
    llm: UnifiedLLM, admin_client, row: dict, limiter: asyncio.Semaphore, turn: Optional[PreparedTurn] = None
) -> None:
    """画像の文字起こしと要約を裏で非同期に行い、DBを更新する(回答の待ち時間に影響させない)。"""
    from app.core.r2_storage import storage_service
    extraction = row.get("extraction") or {}
    image_keys: dict[str, str] = extraction.get("images") or {}

    async def load(key: str) -> bytes:
        return await asyncio.to_thread(storage_service.download_binary, image_keys[key])

    try:
        tr = await transcribe_file(llm, "image", units_from_json(extraction), load, limiter)
        if tr.blocked:
            if turn is not None:
                turn.attachments_blocked = True
            admin_client.table("chat_attachments").update({
                "status": "blocked",
                "usage": tr.usage_json(),
                "forbids_ai_code": tr.forbids_ai_code,
            }).eq("id", row["id"]).execute()
            return

        content = tr.content[:MAX_FILE_CONTENT_CHARS]
        title = tr.title or (row.get("file_name") or "")[:60] or "Image"
        sections = [Section(index=1, start=0, end=len(content), title=title, description=tr.summary[:400])]
        tokens = estimate_tokens(content) + 1550

        admin_client.table("chat_attachments").update({
            "content": content,
            "char_count": len(content),
            "token_count": tokens,
            "image_path": image_keys.get("main"),
            "extraction": None,
            "status": "ready",
            "title": title,
            "summary": tr.summary,
            "sections": [sec.to_json() for sec in sections],
            "usage": tr.usage_json(),
            "forbids_ai_code": tr.forbids_ai_code,
        }).eq("id", row["id"]).execute()

        if turn is not None:
            turn.attachments_read.append(tr.usage_json())

        task = asyncio.create_task(index_now("chat_attachment", row["id"]))
        _BACKGROUND_TASKS.add(task)
        task.add_done_callback(_BACKGROUND_TASKS.discard)
        task.add_done_callback(_ignore_task_exception)

    except Exception as e:
        print(f"⚠️ [chat] background image transcribe failed for attachment {row.get('id')}: {e}")
        try:
            admin_client.table("chat_attachments").update({"status": "failed"}).eq("id", row["id"]).execute()
        except Exception:
            pass


async def _background_process_non_image(
    llm: UnifiedLLM,
    admin_client,
    row: dict,
    limiter: asyncio.Semaphore,
    turn: Optional[PreparedTurn] = None,
) -> None:
    """非画像ファイル(PDF, Word等)の文字起こし・要約・目次分割・インデックス化を裏で非同期に行う。"""
    from app.core.r2_storage import storage_service
    extraction = row.get("extraction") or {}
    image_keys: dict[str, str] = extraction.get("images") or {}
    images_seen: dict[str, bytes] = {}

    async def load(key: str) -> bytes:
        data = await asyncio.to_thread(storage_service.download_binary, image_keys[key])
        images_seen[image_keys[key]] = data
        return data

    try:
        if row.get("kind", "text") == "text":
            content = row.get("content") or ""
            file_usage = None
            read_res = await read_attachment(llm, content, limiter)
        else:
            tr = await transcribe_file(llm, row["kind"], units_from_json(extraction), load, limiter)
            file_usage = tr.usage_json()
            if tr.blocked:
                if turn is not None:
                    turn.attachments_blocked = True
                admin_client.table("chat_attachments").update({
                    "status": "blocked",
                    "usage": {"file": file_usage},
                }).eq("id", row["id"]).execute()
                return
            content = tr.content
            if len(content) > MAX_FILE_CONTENT_CHARS:
                content = content[:MAX_FILE_CONTENT_CHARS]
                file_usage["truncated"] = True
            if not content.strip():
                admin_client.table("chat_attachments").update({"status": "failed"}).eq("id", row["id"]).execute()
                return
            read_res = await read_attachment(llm, content, limiter)

        if read_res.blocked:
            if turn is not None:
                turn.attachments_blocked = True
            admin_client.table("chat_attachments").update({
                "status": "blocked",
                "usage": {**read_res.usage_json(), **({"file": file_usage} if file_usage else {})},
            }).eq("id", row["id"]).execute()
            return

        if read_res.error:
            admin_client.table("chat_attachments").update({"status": "failed"}).eq("id", row["id"]).execute()
            return

        tokens = estimate_tokens(content)
        # 30,000〜40,000 トークンの長文資料は、Modal LLMLingua-2 でソフト圧縮して 30,000 枠内に押し込む
        content, tokens, was_compressed = await compress_attachment_content_if_needed(content, tokens, billing=llm.billing)

        title = row.get("title") or read_res.title or (row.get("file_name") or "")[:60] or "Document"
        meta = dict(row.get("metadata") or {})
        if was_compressed:
            meta["compressed"] = True

        file_fields = {
            "content": content,
            "char_count": len(content),
            "token_count": tokens,
        } if (was_compressed or row.get("kind", "text") != "text") else {}
        if row.get("kind", "text") != "text":
            file_fields["extraction"] = None
        admin_client.table("chat_attachments").update({
            **file_fields,
            "status": "ready",
            "title": title,
            "summary": read_res.summary,
            "metadata": meta,
            "sections": [sec.to_json() for sec in read_res.sections],
            "usage": {**read_res.usage_json(), **({"file": file_usage} if file_usage else {})},
            "forbids_ai_code": read_res.forbids_ai_code,
        }).eq("id", row["id"]).execute()


        if turn is not None:
            turn.attachments_read.append({**read_res.usage_json(), **({"file": file_usage} if file_usage else {})})

        idx_task = asyncio.create_task(index_now("chat_attachment", row["id"]))
        _BACKGROUND_TASKS.add(idx_task)
        idx_task.add_done_callback(_BACKGROUND_TASKS.discard)
        idx_task.add_done_callback(_ignore_task_exception)

    except Exception as e:
        print(f"⚠️ [chat] background doc processing failed for attachment {row.get('id')}: {e}")
        try:
            admin_client.table("chat_attachments").update({"status": "failed"}).eq("id", row["id"]).execute()
        except Exception:
            pass


async def _read_new_attachments(
    llm: UnifiedLLM, admin_client, turn: PreparedTurn
) -> tuple[bool, list[dict]]:
    """
    新しく添付された資料を読む準備をする。
    画像もドキュメントも、回答役には即座に渡せる表現(画像バイナリ、抽出テキスト)を渡し、
    重い文字起こし・要約・インデックス化は裏タスクで並行実行する(回答の待ち時間をゼロにする)。
    裏タスクは turn.attachment_tasks に保持し、回答完了時に合流して確実に課金する。
    """
    rows = turn.new_attachment_rows
    limiter = asyncio.Semaphore(READ_MAX_CONCURRENT_CALLS)

    image_rows = [r for r in rows if r.get("kind") == "image"]
    non_image_rows = [r for r in rows if r.get("kind") != "image"]

    # 1. 画像資料
    new_images: list[Attachment] = []
    for r in image_rows:
        extraction = r.get("extraction") or {}
        image_keys = extraction.get("images") or {}
        image_path = image_keys.get("main")
        title = (r.get("file_name") or "")[:60] or "Image"
        att = Attachment(
            id=r["id"],
            title=title,
            content="",
            summary="",
            sections=[],
            message_id=r.get("message_id"),
            created_at=r.get("created_at") or "",
            token_count=1550,
            kind="image",
            image_path=image_path,
            selected=False,
        )
        new_images.append(att)
        bg_task = asyncio.create_task(_background_transcribe_image(llm, admin_client, r, limiter, turn))
        _BACKGROUND_TASKS.add(bg_task)
        bg_task.add_done_callback(_BACKGROUND_TASKS.discard)
        turn.attachment_tasks.append(bg_task)

    turn.attachments.extend(new_images)

    # 2. 非画像資料(PDF, docx, txt)
    new_docs: list[Attachment] = []
    for r in non_image_rows:
        kind = r.get("kind", "text")
        preview_text = ""
        if kind == "text":
            preview_text = r.get("content") or ""
        else:
            extraction = r.get("extraction") or {}
            units_raw = extraction.get("units") or []
            pieces = []
            for u in units_raw:
                t = (u.get("text") or "").strip()
                tail = (u.get("tail") or "").strip()
                label = u.get("label") or ""
                header = f"[{label}]\n" if label else ""
                body = "\n".join(p for p in [t, tail] if p)
                if body:
                    pieces.append(f"{header}{body}")
            preview_text = "\n\n".join(pieces)
            if not preview_text:
                preview_text = r.get("content") or ""

        if len(preview_text) > MAX_FILE_CONTENT_CHARS:
            preview_text = preview_text[:MAX_FILE_CONTENT_CHARS]

        title = (r.get("file_name") or "")[:60] or "Document"
        tokens = estimate_tokens(preview_text)
        att = Attachment(
            id=r["id"],
            title=title,
            content=preview_text,
            summary="",
            sections=[],
            message_id=r.get("message_id"),
            created_at=r.get("created_at") or "",
            token_count=tokens,
            kind=kind,
            selected=False,
        )
        new_docs.append(att)
        bg_task = asyncio.create_task(_background_process_non_image(llm, admin_client, r, limiter, turn))
        _BACKGROUND_TASKS.add(bg_task)
        bg_task.add_done_callback(_BACKGROUND_TASKS.discard)
        turn.attachment_tasks.append(bg_task)

    turn.attachments.extend(new_docs)
    return False, []


# 返答を待たせずに走らせる後片付け(資料のインデックス)。参照を持っておかないとGCで途中で消える
_BACKGROUND_TASKS: set = set()


async def _apply_pins(admin_client, turn: PreparedTurn) -> Optional[dict]:
    """
    全文で添付した資料を全文で読む枠に入れ、枠を超えた分は古いものから外す(chat_attachments.plan_pins)。
    文中で指した全文の資料は「使った」ので、外す順番を後ろにする(selected_atを今にする)。
    外した・長すぎて全文にできなかった資料があれば、画面に知らせる内容を返す。
    """
    if not turn.pin_requests and not turn.mentions:
        return None
    plan = plan_pins(turn.attachments, turn.pin_requests)
    pinned, unpinned = set(plan.pin), set(plan.unpin)
    used = [a.id for a in turn.attachments
            if a.selected and a.id in turn.mentions and a.id not in pinned and a.id not in unpinned]
    now = _now_iso()

    def save() -> None:
        if plan.pin:
            admin_client.table("chat_attachments").update({"selected": True, "selected_at": now}) \
                .in_("id", plan.pin).execute()
        if plan.unpin:
            admin_client.table("chat_attachments").update({"selected": False}).in_("id", plan.unpin).execute()
        if used:
            admin_client.table("chat_attachments").update({"selected_at": now}).in_("id", used).execute()
    await asyncio.to_thread(save)
    for a in turn.attachments:
        if a.id in pinned:
            a.selected, a.selected_at = True, now
        elif a.id in unpinned:
            a.selected = False
        elif a.id in used:
            a.selected_at = now
    if plan.unpin or plan.too_long:
        return {"unpinned": plan.unpin, "too_long": plan.too_long}
    return None


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
    今回の往復(AIの返答が完了したもの)を含めて、未要約が15往復以上または20,000トークン以上なら、
    畳む処理をCloud Tasksに積む。
    畳むのが遅れても次のターンは原文を少し多めに送るだけなので、ここで失敗しても
    返答自体には影響させない(次のターンでまた積まれる)。
    ※ 判定・折りたたみは常に完全な往復(Turn: user発言 + 完了した返答)の単位で行われ、
      AIの返答を抜いて生徒の発言だけを畳むことは絶対にない。
    """
    if enqueue_summary is None:
        return
    last_block = turn.summary_blocks[-1] if turn.summary_blocks else None
    first_num = (last_block["turn_end"] + 1) if last_block else 1
    turns = pair_turns(turn.history_rows, first_number=first_num)
    if turn.assistant_content and turn.assistant_content.strip():
        turns.append(Turn(
            number=first_num + len(turns),
            user_message_id=turn.user_message_id,
            assistant_message_id=turn.assistant_message_id,
            user_content=turn.content,
            assistant_content=turn.assistant_content,
            assistant_created_at=datetime.now(timezone.utc).isoformat(),
            reply_language=None,
        ))
    if not should_fold_summary(turns):
        return
    next_block_index = (last_block["block_index"] + 1) if last_block else 1
    try:
        await enqueue_summary(turn.thread_id, next_block_index)
    except Exception as e:
        print(f"⚠️ [chat] failed to enqueue summary for thread {turn.thread_id}: {e}")


async def _run_turn_steps(
    turn: PreparedTurn,
    user_client,
    admin_client,
    billing: BillingEngine,
    llm: UnifiedLLM,
    stop: TurnStop,
    progress: "TurnProgress",
    emit: Callable[[str, dict], Awaitable[None]],
    enqueue_summary: Optional[EnqueueSummary],
) -> None:
    """
    1ターンの本体(仕分け → 探索 → 回答 → 締め)。完了・断った・失敗はここで締める。
    止められたらTurnStoppedを投げ、締めはrun_chat_turnが行う(途中までの本文はprogressに残す)。
    """
    decision: Optional[RouterDecision] = None
    timer = turn.timer

    try:
        attachments_read = turn.attachments_read
        await emit("meta", {
            "thread_id": turn.thread_id,
            "user_message_id": turn.user_message_id,
            "assistant_message_id": turn.assistant_message_id,
        })
        # --- 1.5 添付された資料の並行読み込みを開始(回答を待たせない) ---
        if turn.new_attachment_rows:
            await _read_new_attachments(llm, admin_client, turn)
            timer.mark("attachments_started")
            stop.raise_if_stopped()

        await emit("status", {"stage": "thinking"})

        # 全文で添付した資料を全文で読む枠に入れる(超えたら古いものから外し、画面に知らせる)
        turn.attachment_notice = await _apply_pins(admin_client, turn)
        if turn.attachment_notice:
            await emit("attachments", turn.attachment_notice)

        # 資料の呼び名(A1…)と、このターンに全文で渡す資料(新着画像・メンションした画像は、このターンだけ画像も渡す)
        turn.attachments = assign_handles(turn.attachments)
        new_att_ids = {r["id"] for r in turn.new_attachment_rows}
        attachment_visibility = plan_visibility(turn.attachments, turn.mentions, new_att_ids)
        # 履歴の本文の資料の印も、このターンの呼び名に直す(外した資料は [removed material])
        turn.history_rows = [{**r, "content": render_mentions(r.get("content") or "", turn.attachments)}
                             if r.get("role") == "user" else r for r in turn.history_rows]
        # 選択中の画像の資料は、画像そのものも回答役に渡す。振り分け役・探索役と並行で読み込んでおく
        answer_images_task = asyncio.create_task(_load_answer_images(turn, attachment_visibility))
        answer_images_task.add_done_callback(_ignore_task_exception)
        # 会話ノートに needs_source: True があれば、該当ターンの生テキストをDBから取得
        active_header = turn.summary_blocks[-1].get("header") if turn.summary_blocks else None
        source_turns_needed = extract_source_turns_to_fetch(active_header)
        referenced_sources = ""
        if source_turns_needed:
            referenced_sources = await _fetch_referenced_source_turns(admin_client, turn.thread_id, source_turns_needed)

        history = build_history_messages(turn.history_rows, RAW_MAX_TURNS, None,
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
                                     render_for_router(turn.attachments, attachment_visibility),
                                     referenced_sources=referenced_sources)
        progress.decision = decision
        timer.mark("router_done")
        stop.raise_if_stopped()

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

        # 推論が要るターンで、言及された資料(または新規添付)のうち全文を渡していないものがあれば、
        # 振り分け役が探索不要と判断しても探しに行く(確かめ役が仕様書を見ずに一般論で答えるのを防ぐ)
        retrieval_forced = False
        has_relevant_unopened_attachment = any(
            (attachment_visibility.is_mentioned(a) or a.id in {r.get("id") for r in turn.new_attachment_rows})
            and not attachment_visibility.is_full(a)
            for a in turn.attachments
        )
        must_check_attachments = decision.needs_reasoning and has_relevant_unopened_attachment
        if must_check_attachments and not decision.needs_retrieval:
            decision.needs_retrieval = True
            retrieval_forced = True
        # 文中で指した資料が全文で見えていなければ、その中を探しに行く(探索役には<mention_note>で伝える)
        if not decision.needs_retrieval and any(
                attachment_visibility.is_mentioned(a) and not attachment_visibility.is_full(a) for a in turn.attachments):
            decision.needs_retrieval = True
            retrieval_forced = True

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

            async def on_compressing() -> None:
                await emit("status", {"stage": "searching", "detail": ["organizing"]})

            materials, navigation = await _gather_materials(
                llm, billing, user_client, turn, history, map_task, chat_map_task, await blocked_task, on_fetch,
                attachment_visibility, must_check_attachments, user_goal=decision.user_goal,
                on_compressing=on_compressing, referenced_sources=referenced_sources)
            timer.mark("retrieval_done")
            # 探索役の中で握りつぶされた停止を、ここで拾い直す
            stop.raise_if_stopped()
            progress.materials = materials
            await emit("sources", {"sources": sources_event(materials)})

        # --- 4. 回答 ---
        turn.answer_images = await answer_images_task
        # 探索役の最終思考(なぜ情報が足りているか、どう回答すべきと見立てたか)を取得
        retrieval_reasoning = ""
        if navigation and navigation.laps:
            last_lap = navigation.laps[-1]
            retrieval_reasoning = getattr(last_lap, "reasoning", "") if hasattr(last_lap, "reasoning") else (last_lap.get("reasoning", "") if isinstance(last_lap, dict) else "")

        messages = _build_answer_messages(
            turn, decision, memory, history, profile, materials,
            student_memos=student_memos, open_questions=open_questions,
            attachment_visibility=attachment_visibility,
            link_failures=navigation.link_failures if navigation else None,
            referenced_sources=referenced_sources,
            retrieval_reasoning=retrieval_reasoning,
        )
        messages, trimmed_turns = fit_answer_input(messages)
        answer_model, answer_effort = ANSWER_MODEL, ANSWER_REASONING_EFFORT
        # 「じっくり考えています…」を出すのは推論が要るターンだけ(Haiku 5.5はふだんからeffort lowで少し考えるが、
        # 最初の1文字まで1秒もかからないので、ふだんの「書いています」のままにする)
        thinking = False
        checked: Optional[CheckedWork] = None
        # 推論が要るターン: 二段構えなら確かめ役のメモを足し、一段ならそのモデルで直接答える(chat_reasoning.py)
        if decision.needs_reasoning:
            if REASONING_CONFIG.mode == "two_stage":
                await emit("status", {"stage": "reasoning"})
                checked = await check_work(llm, messages)
                timer.mark("reasoning_done")
                stop.raise_if_stopped()
                if checked.notes:
                    messages = with_checked_work(messages, checked.notes)
                else:
                    # メモが無くても答えは出す(ふだんの回答役だけで答える)
                    print(f"⚠️ [chat] checking step failed for message {turn.assistant_message_id}: {checked.error}")
            else:
                answer_model = REASONING_CONFIG.single_model or ANSWER_MODEL
                answer_effort = REASONING_CONFIG.single_effort
                # 一段で推論するときは、考えている間(最初の1文字まで)「じっくり考えています…」を出す
                thinking = answer_effort not in (None, "none")
        await emit("status", {"stage": "reasoning" if thinking else "writing"})
        state = StreamState()
        options = answer_options(answer_model, answer_effort, _answer_max_tokens(navigation, materials))
        timer.mark("answer_started")
        stop.raise_if_stopped()

        async def _on_thought(chunk: str) -> None:
            if not stop.stopped:
                await emit("thought", {"text": chunk})

        async for delta in llm.generate_stream(
            answer_model, messages, state, options, stop_event=stop.event, on_thought=_on_thought,
        ):
            if "answer_first_token" not in timer.marks:
                timer.mark("answer_first_token")
            progress.answer_parts.append(delta)
            await emit("delta", {"text": delta})
        timer.mark("answer_done")
        # 止められてストリームを閉じた: 途中までの本文で、run_chat_turnが締める
        progress.answer_usage = {"answer_input_tokens": state.input_tokens, "answer_output_tokens": state.output_tokens,
                                 "usage_estimated": state.usage_estimated}
        stop.raise_if_stopped()

        usage_extra = {
            "router_model": ROUTER_MODEL,
            "navigator": navigation.to_json() if navigation else None,
            "answer_model": answer_model,
            "reasoning": {
                "mode": REASONING_CONFIG.mode,
                "checked_work": checked.to_json() if checked else None,
                "thought": state.thought_text if state.thought_text else None,
            } if decision.needs_reasoning else ({"thought": state.thought_text} if state.thought_text else None),
            "answer_input_tokens": state.input_tokens,
            "answer_output_tokens": state.output_tokens,
            "answer_cache_read_tokens": state.cache_read_tokens,
            "answer_cache_write_tokens": state.cache_write_tokens,
            "answer_history_trimmed_turns": trimmed_turns or None,
            "usage_estimated": state.usage_estimated,
            "materials": [{"key": m.key, "handle": m.handle} for m in materials],
            "retrieval_forced_for_attachments": retrieval_forced or None,
            "attachments": {
                "count": len(turn.attachments),
                "full": [a.handle for a in turn.attachments if attachment_visibility.is_full(a)],
                "read": turn.attachments_read,
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

        # 裏で走っている資料解析タスクの完了を待つ(確実に課金するため)
        pending_att = [t for t in turn.attachment_tasks if not t.done()]
        if pending_att:
            await emit("status", {"stage": "indexing_attachments"})
            await asyncio.gather(*pending_att, return_exceptions=True)

        # 資料解析で有害判定(blocked)が出た場合は、安全のため回答を断り文に差し替える
        if turn.attachments_blocked:
            reply_lang = decision.reply_language if decision else guess_language(turn.language_hint())
            text = blocked_text(reply_lang)
            await emit("replace", {"text": text})
            await _finalize(
                admin_client, turn, content=text, status="blocked",
                decision=decision, citations=[], billing=billing,
                usage_extra={**usage_extra, "attachments_blocked": True}, charge=False,
            )
            await emit("done", {"status": "blocked", "credits_charged": 0})
            return

        charged_micro = await _finalize(
            admin_client, turn, content=answer_text, status="complete",
            decision=decision, citations=citations, billing=billing,
            usage_extra={**usage_extra, "finish_reason": state.finish_reason}, charge=True,
            message_context={
                **({"opened": opened_refs} if opened_refs else {}),
                **({"attachment_notice": turn.attachment_notice} if turn.attachment_notice else {}),
            } or None,
        )
        turn.assistant_content = answer_text
        await emit("done", {
            "status": "complete",
            "citations": citations,
            "credits_charged": charged_micro / MICRO_CREDITS_PER_CREDIT,
        })
        await _maybe_enqueue_summary(turn, enqueue_summary)

    except TurnStopped:
        raise
    except Exception as e:
        if stop.stopped:
            # 止めたことで起きた失敗(読み込みの途中で打ち切った等)。失敗ではなく停止として締める
            raise TurnStopped() from e
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


# 停止のとき、ストリームを閉じる・段階の境目に着くなど、すぐ終わる本体だけを待つ時間。これを過ぎたら
# 走っている呼び出し(非ストリームの呼び出しは止められない)を待たずに締め、その原価は終わってから請求する
STOP_SETTLE_SECONDS = 0.5


@dataclass
class TurnProgress:
    """止めたときの締めに使う、ここまでの進み具合。"""
    decision: Optional[RouterDecision] = None
    materials: list = field(default_factory=list)
    answer_parts: list[str] = field(default_factory=list)
    answer_usage: Optional[dict] = None

    @property
    def current_text(self) -> str:
        """ここまでに受信・生成された返答の全文。"""
        return "".join(self.answer_parts)


def _fail_unread_attachments(admin_client, turn: PreparedTurn) -> list[str]:
    """止めたとき、読み終わっていない(processingの)資料をfailedにし、そのidを返す(画面で知らせる)。"""
    ids = [r["id"] for r in turn.new_attachment_rows]
    if not ids:
        return []
    res = admin_client.table("chat_attachments").update({"status": "failed"}) \
        .in_("id", ids).eq("status", "processing").execute()
    return [r["id"] for r in res.data or []]


async def _finalize_stopped(
    admin_client, turn: PreparedTurn, billing: BillingEngine, progress: TurnProgress,
) -> int:
    """止めたところまでを返答として確定し、ここまでに発生した原価を請求する。消費したμクレジットを返す。"""
    text = progress.current_text
    citations: list[dict] = []
    if text.strip():
        text = normalize_citations(text, progress.materials)
        citations = extract_citations(text, progress.materials)
    try:
        failed_ids = await asyncio.to_thread(_fail_unread_attachments, admin_client, turn)
    except Exception as e:
        print(f"⚠️ [chat] failed to mark unread attachments as failed for message {turn.assistant_message_id}: {e}")
        failed_ids = []
    context = {
        **({"attachment_notice": turn.attachment_notice} if turn.attachment_notice else {}),
        **({"stopped_attachments": failed_ids} if failed_ids else {}),
    }
    return await _finalize(
        admin_client, turn, content=text, status="stopped", decision=progress.decision,
        citations=citations, billing=billing,
        usage_extra={"stopped": True, **(progress.answer_usage or {}), "timings": turn.timer.to_json()},
        charge=True, message_context=context or None,
    )


async def _charge_after_stop(
    work: "asyncio.Task", admin_client, turn: PreparedTurn, billing: BillingEngine, charged_records: int,
) -> None:
    """
    止めた後も走り切らせた呼び出しが終わるのを待ち、その原価を別の取引として請求する
    (CHAT_MESSAGEはmessage_idで二重課金を弾くので、同じメッセージに上乗せできない。要約と同じやり方)。
    本体はTurnStoppedで終わる(次の呼び出しの入口で止まる)ので、結果は捨てる。
    """
    try:
        await work
    except BaseException:
        pass
    tail = billing.records[charged_records:]
    tail_usd = _chargeable_usd(tail)
    if tail_usd <= 0:
        return
    try:
        tail_micro = await asyncio.to_thread(
            consume_chat_stop_tail_credits, turn.user_id, turn.thread_id, turn.assistant_message_id,
            tail_usd, [vars(r) for r in tail],
        )

        def add_to_row() -> None:
            row = admin_client.table("chat_messages").select("credits_charged_micro, usage") \
                .eq("id", turn.assistant_message_id).maybe_single().execute()
            data = (row.data if row else None) or {}
            usage = {**(data.get("usage") or {}), "after_stop": {"records": [vars(r) for r in tail],
                                                                  "chargeable_usd": tail_usd}}
            admin_client.table("chat_messages").update({
                "credits_charged_micro": (data.get("credits_charged_micro") or 0) + tail_micro,
                "cost_usd": billing.total_usd(),
                "usage": usage,
            }).eq("id", turn.assistant_message_id).execute()
        await asyncio.to_thread(add_to_row)
    except Exception as e:
        print(f"⚠️ [chat] failed to charge the calls that finished after the stop for message "
              f"{turn.assistant_message_id}: {e}")


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

    途中停止(chat_stop.py): 本体(_run_turn_steps)と停止の信号を競わせる。止められたら、走っている
    呼び出しを待たずに止めたところまでで締め(スレッドがすぐ空き、次の送信と履歴に使える)、
    走り切らせた呼び出しの原価は終わってから請求する。停止の後の課金のある呼び出しは、入口で止まる。
    """
    admin_client = get_supabase_client()
    billing = BillingEngine(task_type="CHAT_MESSAGE")
    stop = TurnStop(admin_client, turn.assistant_message_id)
    turn.stop = stop
    llm = UnifiedLLM(billing, guard=stop.check)
    progress = TurnProgress()
    timer = turn.timer

    async def emit(event: str, data: dict) -> None:
        # 止めた後は流さない(画面は停止のエンドポイントの返す行で確定する)
        if stop.stopped:
            return
        await queue.put(sse_event(event, data))

    register_stop(stop)
    watcher = asyncio.create_task(stop.watch())
    watcher.add_done_callback(_ignore_task_exception)
    work = asyncio.create_task(_run_turn_steps(
        turn, user_client, admin_client, billing, llm, stop, progress, emit, enqueue_summary))
    stop_wait = asyncio.create_task(stop.event.wait())
    try:
        await asyncio.wait({work, stop_wait}, return_when=asyncio.FIRST_COMPLETED)
        if not work.done():
            await asyncio.wait({work}, timeout=STOP_SETTLE_SECONDS)
        if work.done() and not (work.cancelled() or isinstance(work.exception(), TurnStopped)):
            return  # 完了・断った・失敗は本体の中で締めた
        if work.done() and work.cancelled():
            return

        timer.mark("stopped")
        charged_records = len(billing.records)
        try:
            charged_micro = await _finalize_stopped(admin_client, turn, billing, progress)
        except Exception as e:
            # ここで失敗したら、行はstreamingのまま残る。停止のエンドポイントが待ちきれずにstoppedにする
            print(f"❌ [chat] failed to finalize the stopped message {turn.assistant_message_id}: {e}")
            charged_micro = 0
        await queue.put(sse_event("done", {"status": "stopped", "credits_charged": charged_micro / MICRO_CREDITS_PER_CREDIT}))
        if not work.done():
            task = asyncio.create_task(_charge_after_stop(work, admin_client, turn, billing, charged_records))
            _BACKGROUND_TASKS.add(task)
            task.add_done_callback(_BACKGROUND_TASKS.discard)
            task.add_done_callback(_ignore_task_exception)
        turn.assistant_content = progress.current_text
        await _maybe_enqueue_summary(turn, enqueue_summary)
    finally:
        stop_wait.cancel()
        watcher.cancel()
        unregister_stop(stop)
        timer.mark("finalized")
        print(timer.log_line(turn.assistant_message_id))
        await queue.put(None)
