# app/services/chat_summary.py
"""
横断チャットボットのスレッド要約(ロードマップ ステップ2)。
設計の正本は docs/chatbot_context_and_retrieval_roadmap.md の 2-1〜2-14。

- 数える単位は往復(userの発言 + 完了した返答)。blocked/crisis/errorの往復は数えない
- 未要約の往復が15になったら、古い10往復を1つのブロックに畳む(原文は常に5〜14往復残る)
- 畳むのはCloud Tasks(/worker/chat-summary)から呼ばれるrun_fold()。要約役はGPT-6 Luna
- 回答役・振り分け役へは、節の呼び名やメッセージIDを含まない形でだけ渡す
- 2段目(1段目のブロック10個=100往復をさらに畳む)はまだ作っていない。テーブルはlevel列で対応済み
"""

import asyncio
from dataclasses import dataclass
from typing import Any, Optional

from app.core.supabase import get_supabase_client
from app.services.helpers.credits import consume_chat_summary_credits
from app.services.helpers.helpers import _load_prompt
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM

SUMMARY_MODEL = "gpt-6-luna"

FOLD_TRIGGER_TURNS = 15
FOLD_SIZE_TURNS = 10

# 履歴・要約に使う返答の状態。途中停止(stopped)を足すときはここに加える。
KEPT_ASSISTANT_STATUSES = ("complete",)

HEADER_CATEGORIES = ("style_preferences", "context", "purpose", "unresolved")
EMPTY_HEADER: dict[str, list] = {k: [] for k in HEADER_CATEGORIES}

_HEADER_LABELS = {
    "style_preferences": "Response style requested",
    "context": "Context for this conversation",
    "purpose": "Purpose of this conversation",
    "unresolved": "Unresolved items",
}

_LANGUAGE_NAMES = {
    "ja": "Japanese", "en": "English", "zh": "Chinese", "ko": "Korean",
    "es": "Spanish", "fr": "French", "de": "German", "pt": "Portuguese",
}

SUMMARY_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "sections": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "bullets": {"type": "array", "items": {"type": "string"}},
                    "rounds": {"type": "array", "items": {"type": "integer"}},
                },
                "required": ["title", "bullets", "rounds"],
            },
        },
        "header": {
            "type": "object",
            "properties": {
                k: {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "text": {"type": "string"},
                            "source_round": {"type": "integer"},
                        },
                        "required": ["text", "source_round"],
                    },
                }
                for k in HEADER_CATEGORIES
            },
            "required": list(HEADER_CATEGORIES),
        },
    },
    "required": ["sections", "header"],
}


class SummaryValidationError(Exception):
    pass


# =========================================================
# 🧩 純粋関数
# =========================================================

@dataclass
class Turn:
    number: int
    user_message_id: str
    assistant_message_id: str
    user_content: str
    assistant_content: str
    assistant_created_at: str
    reply_language: Optional[str]


def pair_turns(rows: list[dict], first_number: int = 1) -> list[Turn]:
    """
    古い順のメッセージ行を往復にまとめる。返答が完了していない往復
    (blocked/crisis/error/streaming)は、そのuserメッセージごと捨てる。
    番号は捨てなかった往復だけで数える(後ろの往復の状態は後から変わらないので、
    一度付いた番号はずれない)。
    """
    turns: list[Turn] = []
    pending_user: Optional[dict] = None
    for row in rows:
        if row.get("role") == "user":
            pending_user = row
            continue
        if row.get("role") == "assistant":
            if row.get("status") in KEPT_ASSISTANT_STATUSES and pending_user is not None:
                turns.append(Turn(
                    number=first_number + len(turns),
                    user_message_id=pending_user.get("id"),
                    assistant_message_id=row.get("id"),
                    user_content=pending_user.get("content") or "",
                    assistant_content=row.get("content") or "",
                    assistant_created_at=row.get("created_at"),
                    reply_language=(row.get("router") or {}).get("reply_language"),
                ))
            pending_user = None
    return turns


def rows_after_fold_point(rows: list[dict], fold_end_message_id: Optional[str]) -> list[dict]:
    """
    rows(古い順、スレッドの最新の一部)のうち、畳んだ最後のメッセージより後ろだけを返す。
    畳んだ最後のメッセージがrowsに無ければ、rowsは丸ごとそれより後ろにある。
    """
    if not fold_end_message_id:
        return rows
    for i, row in enumerate(rows):
        if row.get("id") == fold_end_message_id:
            return rows[i + 1:]
    return rows


def summary_language(turns: list[Turn]) -> str:
    """畳む往復の返答言語で一番多いもの(振り分け役がreply_languageを必ず入れている)。"""
    counts: dict[str, int] = {}
    for t in turns:
        if t.reply_language:
            counts[t.reply_language] = counts.get(t.reply_language, 0) + 1
    return max(counts, key=counts.get) if counts else "en"


def build_summary_messages(
    prior_section_titles: list[str],
    header: dict,
    turns: list[Turn],
    language: str,
) -> list[Message]:
    system = _load_prompt("chat_summary_prompt.txt").replace(
        "${SUMMARY_LANGUAGE}", _LANGUAGE_NAMES.get(language, language)
    )
    titles_text = "\n".join(f"- {t}" for t in prior_section_titles) if prior_section_titles else "(none yet)"

    header_lines = []
    for key in HEADER_CATEGORIES:
        items = header.get(key) or []
        if items:
            header_lines.append(f"[{key}]")
            header_lines.extend(f"- {it['text']} (source_round={it['source_turn']})" for it in items)
    header_text = "\n".join(header_lines) if header_lines else "(none yet)"

    rounds_text = "\n\n".join(
        f"[round {t.number}] Student: {t.user_content}\n[round {t.number}] Assistant: {t.assistant_content}"
        for t in turns
    )
    user_content = (
        f"<previous_section_titles>\n{titles_text}\n</previous_section_titles>\n\n"
        f"<current_header>\n{header_text}\n</current_header>\n\n"
        f"<rounds_to_fold>\n{rounds_text}\n</rounds_to_fold>"
    )
    return [Message(role="system", content=system), Message(role="user", content=user_content)]


def validate_summary_output(raw: Any, turns: list[Turn], next_handle: int) -> tuple[list[dict], dict]:
    """
    要約役の出力を検証し、保存する形(sections, header)に変換する。
    節が指す往復は今回畳む範囲に、ヘッダーの根拠の往復はそれ以前の範囲に収まっていること。
    """
    if not isinstance(raw, dict) or not isinstance(raw.get("sections"), list) or not isinstance(raw.get("header"), dict):
        raise SummaryValidationError("output is not the expected object")

    batch_numbers = {t.number for t in turns}
    last_number = turns[-1].number

    sections = []
    for sec in raw["sections"]:
        title = (sec.get("title") or "").strip()
        bullets = [b.strip() for b in sec.get("bullets") or [] if isinstance(b, str) and b.strip()]
        rounds = sorted({r for r in sec.get("rounds") or [] if isinstance(r, int)})
        if not title or not bullets:
            raise SummaryValidationError(f"section without title or bullets: {sec!r}")
        if not rounds or not set(rounds) <= batch_numbers:
            raise SummaryValidationError(f"section rounds {rounds} outside this batch {sorted(batch_numbers)}")
        sections.append({"handle": next_handle + len(sections), "title": title, "bullets": bullets, "turns": rounds})
    if not sections:
        raise SummaryValidationError("no sections")

    header: dict[str, list] = {}
    for key in HEADER_CATEGORIES:
        items = []
        for it in raw["header"].get(key) or []:
            text = (it.get("text") or "").strip()
            source = it.get("source_round")
            if not text:
                continue
            if not isinstance(source, int) or not 1 <= source <= last_number:
                raise SummaryValidationError(f"header item {text!r} has source_round {source!r} outside 1..{last_number}")
            items.append({"text": text, "source_turn": source})
        header[key] = items

    return sections, header


def render_summary_for_answer(blocks: list[dict]) -> str:
    """回答役・振り分け役向け。節のタイトルと箇条書きだけで、呼び名やIDは入れない。"""
    parts = []
    for block in blocks:
        for sec in block.get("sections") or []:
            parts.append(f"## {sec['title']}")
            parts.extend(f"- {b}" for b in sec["bullets"])
            parts.append("")
    return "\n".join(parts).strip()


def render_notes_for_answer(header: Optional[dict]) -> str:
    if not header:
        return ""
    lines = []
    for key in HEADER_CATEGORIES:
        items = header.get(key) or []
        if items:
            lines.append(f"{_HEADER_LABELS[key]}: " + "; ".join(it["text"] for it in items))
    return "\n".join(lines)


# =========================================================
# 🗄️ DB
# =========================================================

_BLOCK_COLUMNS = "id, block_index, turn_start, turn_end, end_message_id, end_message_created_at, sections, header"


def fetch_active_blocks(admin_client, thread_id: str) -> list[dict]:
    res = admin_client.table("chat_summary_blocks").select(_BLOCK_COLUMNS) \
        .eq("thread_id", thread_id).eq("level", 1).is_("invalidated_at", "null") \
        .order("block_index").execute()
    return res.data or []


def _fetch_rows_after(admin_client, thread_id: str, after_created_at: Optional[str]) -> list[dict]:
    q = admin_client.table("chat_messages").select("id, role, content, status, router, created_at") \
        .eq("thread_id", thread_id).is_("deleted_at", "null")
    if after_created_at:
        q = q.gt("created_at", after_created_at)
    return q.order("created_at").execute().data or []


def _thread_owner(admin_client, thread_id: str) -> Optional[str]:
    res = admin_client.table("chat_threads").select("user_id, deleted_at").eq("id", thread_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return None
    return row["user_id"]


# =========================================================
# 🧠 畳む(Cloud Tasksから呼ばれる)
# =========================================================

async def summarize_turns(
    llm: UnifiedLLM,
    prior_titles: list[str],
    header: dict,
    turns: list[Turn],
    language: str,
    next_handle: int,
) -> tuple[list[dict], dict]:
    messages = build_summary_messages(prior_titles, header, turns, language)
    # gpt-6-lunaはtemperatureの既定値(1)以外を受け付けない
    options = LLMOptions(output_type="json", json_schema=SUMMARY_SCHEMA, temperature=1.0, max_completion_tokens=4000)
    last_error: Optional[Exception] = None
    for _attempt in range(2):
        result = await llm.generate(SUMMARY_MODEL, messages, options)
        try:
            return validate_summary_output(result.output_json, turns, next_handle)
        except SummaryValidationError as e:
            print(f"⚠️ [chat-summary] invalid summarizer output (attempt {_attempt + 1}): {e}")
            last_error = e
    raise last_error


async def run_fold(thread_id: str) -> int:
    """
    未要約の往復が15以上ある間、古い10往復ずつブロックに畳む。作ったブロック数を返す。
    同じスレッドで2つ同時に走っても、(thread_id, level, block_index)の一意制約で
    後から来た方の保存が失敗するだけで、二重に畳まれることはない。
    """
    admin_client = get_supabase_client()
    user_id = await asyncio.to_thread(_thread_owner, admin_client, thread_id)
    if not user_id:
        return 0

    created = 0
    while True:
        blocks = await asyncio.to_thread(fetch_active_blocks, admin_client, thread_id)
        last = blocks[-1] if blocks else None
        rows = await asyncio.to_thread(
            _fetch_rows_after, admin_client, thread_id, last["end_message_created_at"] if last else None
        )
        turns = pair_turns(rows, first_number=(last["turn_end"] + 1) if last else 1)
        if len(turns) < FOLD_TRIGGER_TURNS:
            return created

        batch = turns[:FOLD_SIZE_TURNS]
        prior_titles = [sec["title"] for b in blocks for sec in b.get("sections") or []]
        next_handle = 1 + max((sec["handle"] for b in blocks for sec in b.get("sections") or []), default=0)
        header = last["header"] if last else dict(EMPTY_HEADER)
        language = summary_language(batch)

        billing = BillingEngine(task_type="CHAT_SUMMARY")
        llm = UnifiedLLM(billing)
        sections, new_header = await summarize_turns(llm, prior_titles, header, batch, language, next_handle)

        cost_usd = billing.total_usd()
        chargeable_usd = sum(r.cost_usd for r in billing.records if r.dimension == "tokens")
        breakdown = [vars(r) for r in billing.records]
        block_index = (last["block_index"] + 1) if last else 1

        try:
            inserted = await asyncio.to_thread(
                lambda: admin_client.table("chat_summary_blocks").insert({
                    "thread_id": thread_id,
                    "user_id": user_id,
                    "level": 1,
                    "block_index": block_index,
                    "turn_start": batch[0].number,
                    "turn_end": batch[-1].number,
                    "start_message_id": batch[0].user_message_id,
                    "end_message_id": batch[-1].assistant_message_id,
                    "end_message_created_at": batch[-1].assistant_created_at,
                    "turn_map": [
                        {"turn": t.number, "user_message_id": t.user_message_id, "assistant_message_id": t.assistant_message_id}
                        for t in batch
                    ],
                    "sections": sections,
                    "header": new_header,
                    "summary_language": language,
                    "model": SUMMARY_MODEL,
                    "usage": {"records": breakdown, "chargeable_usd": chargeable_usd},
                    "cost_usd": cost_usd,
                }).execute()
            )
        except Exception as e:
            if "uq_chat_summary_blocks_active_index" in str(e) or "duplicate key" in str(e):
                print(f"⏭️ [chat-summary] block {block_index} of thread {thread_id} was already created by another run.")
                return created
            raise

        block_id = inserted.data[0]["id"]
        created += 1
        print(f"🗂️ [chat-summary] thread={thread_id} block={block_index} turns={batch[0].number}-{batch[-1].number} "
              f"sections={len(sections)} cost=${chargeable_usd:.6f}")

        try:
            charged = await asyncio.to_thread(
                consume_chat_summary_credits, user_id, thread_id, block_id, chargeable_usd, breakdown,
            )
            await asyncio.to_thread(
                lambda: admin_client.table("chat_summary_blocks")
                    .update({"credits_charged_micro": charged}).eq("id", block_id).execute()
            )
        except Exception as e:
            # 課金の失敗で要約自体を失敗扱いにはしない(メッセージの課金と同じ方針)
            print(f"⚠️ [chat-summary] failed to charge credits for block {block_id}: {e}")
