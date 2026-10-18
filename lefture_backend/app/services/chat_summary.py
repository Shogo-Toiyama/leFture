# app/services/chat_summary.py
"""
横断チャットボットのスレッド要約(ロードマップ ステップ2)。
設計の正本は docs/chatbot_context_and_retrieval_roadmap.md の 2-1〜2-14。

- 数える単位は往復(userの発言 + 完了した返答)。blocked/crisis/errorの往復は数えない
- 未要約の往復が15になったら、古い10往復を1つのブロックに畳む(原文は常に5〜14往復残る)
- 畳むのはCloud Tasks(/worker/chat-summary)から呼ばれるrun_fold()。要約役はGPT-6 Luna
- 回答役・振り分け役へは、節の呼び名やメッセージIDを含まない形でだけ渡す
- 2段目: 2段目に入っていない1段目のブロックが15個になったら、古い10個(約100往復)を2段目の
  ブロック1つに畳む(1段目は常に5個以上残る)。入力は1段目の節だけで、原文は読まない。1段目は
  消さずに残すので、探索役は「2段目の節H* → 1段目の節S* → 往復 → 全文」とたどれる
"""

import asyncio
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Optional

from app.core.supabase import get_supabase_client
from app.services.chat_attachments import plain_mentions
from app.services.helpers.credits import consume_chat_summary_credits
from app.services.helpers.helpers import _load_prompt
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM

SUMMARY_MODEL = "gpt-6-luna"

FOLD_TRIGGER_TURNS = 15
FOLD_SIZE_TURNS = 10
# 2段目: 2段目に入っていない1段目のブロックがこの数になったら、古い方からこの数を畳む
LEVEL2_TRIGGER_BLOCKS = 15
LEVEL2_FOLD_BLOCKS = 10

# 履歴・要約に使う返答の状態。途中停止(stopped)を足すときはここに加える。
# 往復として残す返答の状態。stopped(生徒が途中で止めた)も、止めたところまでの本文を残す
# (返答の前に止めて本文が空のときは、往復にせず、その質問を次の質問の前につなげる。pair_turnsを参照)
KEPT_ASSISTANT_STATUSES = ("complete", "stopped")
# 返答の前に止めた質問と、次の質問の間に挟む一行。打ちかけで送って止め続きを送ったのか、取り下げて
# 聞き直したのかは、意図を決めつけずにモデルに次の質問の中身から判断させる(2026-10-17に合意)
STOPPED_BEFORE_REPLY_NOTE = "[Stopped before you replied. The next message may continue or replace this one.]"


def join_after_stop(stopped: list[str], current: str) -> str:
    """返答の前に止めた質問(古い順)を、今の質問の前につなげる(間に止めたことの一行を挟む)。"""
    return "\n\n".join([*(f"{text}\n\n{STOPPED_BEFORE_REPLY_NOTE}" for text in stopped), current])

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


LEVEL2_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "groups": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "bullets": {"type": "array", "items": {"type": "string"}},
                    "sections": {"type": "array", "items": {"type": "integer"}},
                },
                "required": ["title", "bullets", "sections"],
            },
        },
    },
    "required": ["groups"],
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
    # 質問時に選択していたテキスト(あれば)。要約・検索では使わず、chat_serviceの
    # build_history_messagesだけがMessageに織り込む(「これ」の対象を後の往復でも判断できるように)
    user_selected_text: Optional[str] = None


def _is_unanswered_stop(row: dict) -> bool:
    """返答の前に止めた(本文が空のstopped)返答。"""
    return row.get("status") == "stopped" and not (row.get("content") or "").strip()


def _pair(rows: list[dict], first_number: int) -> tuple[list[Turn], list[dict]]:
    turns: list[Turn] = []
    pending_user: Optional[dict] = None
    # 返答の前に止めた質問(打ちかけで送って慌てて止めた、など)。往復にはせず、次の質問の前につなげる
    # (間にSTOPPED_BEFORE_REPLY_NOTEを挟む。続きか置き換えかは、モデルが次の質問の中身から判断する)
    carried: list[dict] = []
    for row in rows:
        if row.get("role") == "user":
            pending_user = row
            continue
        if row.get("role") == "assistant":
            if pending_user is not None and _is_unanswered_stop(row):
                carried.append(pending_user)
            elif row.get("status") in KEPT_ASSISTANT_STATUSES and pending_user is not None:
                carried_now, carried = carried, []
                users = [*carried_now, pending_user]
                turns.append(Turn(
                    number=first_number + len(turns),
                    user_message_id=pending_user.get("id"),
                    assistant_message_id=row.get("id"),
                    # 資料の印(⟦att:id⟧)は、資料の一覧が無いところ(要約・過去のチャットの検索・索引・プロフィール)
                    # では [attached material] にする。回答役の履歴はrun_chat_turnが呼び名つきに直してから渡す
                    user_content=join_after_stop([plain_mentions(u.get("content") or "") for u in carried_now],
                                                 plain_mentions(pending_user.get("content") or "")),
                    assistant_content=row.get("content") or "",
                    assistant_created_at=row.get("created_at"),
                    reply_language=(row.get("router") or {}).get("reply_language"),
                    user_selected_text=next(
                        (sel for u in reversed(users) if (sel := (u.get("context") or {}).get("selected_text"))),
                        None),
                ))
            pending_user = None
    return turns, carried


def pair_turns(rows: list[dict], first_number: int = 1) -> list[Turn]:
    """
    古い順のメッセージ行を往復にまとめる。返答が完了していない往復
    (blocked/crisis/error/streaming)は、そのuserメッセージごと捨てる。
    返答の前に止めた往復(本文が空のstopped)は、その質問を次の往復の質問の前につなげる。
    番号は捨てなかった往復だけで数える(後ろの往復の状態は後から変わらないので、
    一度付いた番号はずれない)。
    """
    return _pair(rows, first_number)[0]


def unanswered_after_stop(rows: list[dict]) -> list[dict]:
    """
    最後の往復の後ろに残った、返答の前に止めた質問の行(古い順)。次に送る質問の前につなげて読ませる
    (pair_turnsでは、つなげる先の質問がまだ無いので往復に入らない)。
    """
    return _pair(rows, 1)[1]


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


def uncovered_level1(level1: list[dict], level2: list[dict]) -> list[dict]:
    """2段目にまだ入っていない1段目のブロック(古い順)。"""
    covered = {cid for b in level2 for cid in b.get("child_block_ids") or []}
    return [b for b in level1 if b["id"] not in covered]


def build_level2_messages(prior_group_titles: list[str], sections: list[dict], language: str) -> list[Message]:
    system = _load_prompt("chat_summary_level2_prompt.txt").replace(
        "${SUMMARY_LANGUAGE}", _LANGUAGE_NAMES.get(language, language)
    )
    titles_text = "\n".join(f"- {t}" for t in prior_group_titles) if prior_group_titles else "(none yet)"
    sections_text = "\n\n".join(
        f"S{sec['handle']} {sec['title']}\n" + "\n".join(f"- {b}" for b in sec["bullets"]) for sec in sections
    )
    user_content = (
        f"<previous_group_titles>\n{titles_text}\n</previous_group_titles>\n\n"
        f"<sections_to_condense>\n{sections_text}\n</sections_to_condense>"
    )
    return [Message(role="system", content=system), Message(role="user", content=user_content)]


def validate_level2_output(raw: Any, sections: list[dict], next_handle: int) -> list[dict]:
    """
    2段目の出力を検証し、保存する形に。1段目の節はちょうど1回ずつ、元の順番のまま
    どこかのグループに入っていること(抜け・重複・順番の入れ替わりがあればやり直させる)。
    """
    if not isinstance(raw, dict) or not isinstance(raw.get("groups"), list):
        raise SummaryValidationError("output is not the expected object")
    order = [sec["handle"] for sec in sections]
    turns_of = {sec["handle"]: sec["turns"] for sec in sections}
    groups, used = [], []
    for g in raw["groups"]:
        title = (g.get("title") or "").strip()
        bullets = [b.strip() for b in g.get("bullets") or [] if isinstance(b, str) and b.strip()]
        children = [c for c in g.get("sections") or [] if isinstance(c, int)]
        if not title or not bullets or not children:
            raise SummaryValidationError(f"group without title, bullets, or sections: {g!r}")
        used += children
        groups.append({
            "handle": next_handle + len(groups), "title": title, "bullets": bullets, "children": children,
            "turns": sorted({t for c in children for t in turns_of.get(c, [])}),
        })
    if used != order:
        raise SummaryValidationError(f"groups must cover sections {order} exactly once in order, got {used}")
    return groups


def render_summary_for_answer(blocks: list[dict], level2: Optional[list[dict]] = None) -> str:
    """
    回答役・振り分け役向け。古い部分は2段目、残りは1段目(blocksのうち2段目に入っていないもの)。
    節のタイトルと箇条書きだけで、呼び名やIDは入れない。
    """
    parts = []
    for block in [*(level2 or []), *uncovered_level1(blocks, level2 or [])]:
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

_BLOCK_COLUMNS = ("id, block_index, turn_start, turn_end, start_message_id, end_message_id, end_message_created_at, "
                  "sections, header, child_block_ids, summary_language")


def fetch_active_blocks(admin_client, thread_id: str, level: int = 1) -> list[dict]:
    res = admin_client.table("chat_summary_blocks").select(_BLOCK_COLUMNS) \
        .eq("thread_id", thread_id).eq("level", level).is_("invalidated_at", "null") \
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
    未要約の往復が15以上ある間、古い10往復ずつ1段目のブロックに畳み、続けて2段目も
    条件を満たす間だけ畳む。作ったブロック数(両方の段の合計)を返す。
    同じスレッドで2つ同時に走っても、(thread_id, level, block_index)の一意制約で
    後から来た方の保存が失敗するだけで、二重に畳まれることはない。
    """
    admin_client = get_supabase_client()
    user_id = await asyncio.to_thread(_thread_owner, admin_client, thread_id)
    if not user_id:
        return 0
    created = await _fold_level1(admin_client, thread_id, user_id)
    created += await _fold_level2(admin_client, thread_id, user_id)
    return created


async def _fold_level1(admin_client, thread_id: str, user_id: str) -> int:
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

        saved = await _save_block(admin_client, billing, {
            "thread_id": thread_id,
            "user_id": user_id,
            "level": 1,
            "block_index": (last["block_index"] + 1) if last else 1,
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
        })
        if not saved:
            return created
        created += 1


async def _fold_level2(admin_client, thread_id: str, user_id: str) -> int:
    created = 0
    while True:
        level1 = await asyncio.to_thread(fetch_active_blocks, admin_client, thread_id, 1)
        level2 = await asyncio.to_thread(fetch_active_blocks, admin_client, thread_id, 2)
        uncovered = uncovered_level1(level1, level2)
        if len(uncovered) < LEVEL2_TRIGGER_BLOCKS:
            return created

        batch = uncovered[:LEVEL2_FOLD_BLOCKS]
        sections = [sec for b in batch for sec in b.get("sections") or []]
        prior_titles = [sec["title"] for b in level2 for sec in b.get("sections") or []]
        next_handle = 1 + max((sec["handle"] for b in level2 for sec in b.get("sections") or []), default=0)
        langs = [b.get("summary_language") for b in batch if b.get("summary_language")]
        language = max(set(langs), key=langs.count) if langs else "en"

        billing = BillingEngine(task_type="CHAT_SUMMARY")
        llm = UnifiedLLM(billing)
        messages = build_level2_messages(prior_titles, sections, language)
        options = LLMOptions(output_type="json", json_schema=LEVEL2_SCHEMA, temperature=1.0, max_completion_tokens=4000)
        groups = None
        last_error: Optional[Exception] = None
        for _attempt in range(2):
            result = await llm.generate(SUMMARY_MODEL, messages, options)
            try:
                groups = validate_level2_output(result.output_json, sections, next_handle)
                break
            except SummaryValidationError as e:
                print(f"⚠️ [chat-summary] invalid level-2 output (attempt {_attempt + 1}): {e}")
                last_error = e
        if groups is None:
            raise last_error

        saved = await _save_block(admin_client, billing, {
            "thread_id": thread_id,
            "user_id": user_id,
            "level": 2,
            "block_index": (level2[-1]["block_index"] + 1) if level2 else 1,
            "turn_start": batch[0]["turn_start"],
            "turn_end": batch[-1]["turn_end"],
            "start_message_id": batch[0]["start_message_id"],
            "end_message_id": batch[-1]["end_message_id"],
            "end_message_created_at": batch[-1]["end_message_created_at"],
            "sections": groups,
            # 2段目は会話の前提を作り直さない(常に最新の1段目のものを使う)。列が必須なので写しを入れる
            "header": batch[-1]["header"],
            "child_block_ids": [b["id"] for b in batch],
            "summary_language": language,
        })
        if not saved:
            return created
        created += 1


def _covers_deleted_range(admin_client, row: dict) -> bool:
    """ブロックの範囲が編集で消えたか(1段目: 最後のメッセージが消えた / 2段目: 元のブロックが無効になった)。"""
    if row["level"] == 1:
        r = admin_client.table("chat_messages").select("deleted_at").eq("id", row["end_message_id"]) \
            .maybe_single().execute()
        return not r or not r.data or bool(r.data.get("deleted_at"))
    children = row.get("child_block_ids") or []
    if not children:
        return False
    r = admin_client.table("chat_summary_blocks").select("id").in_("id", children) \
        .not_.is_("invalidated_at", "null").limit(1).execute()
    return bool(r.data)


async def _save_block(admin_client, billing: BillingEngine, row: dict) -> bool:
    """ブロックを保存して課金する。別の実行が先に同じ番号を作っていたらFalse。"""
    cost_usd = billing.total_usd()
    chargeable_usd = sum(r.cost_usd for r in billing.records if r.dimension == "tokens")
    breakdown = [vars(r) for r in billing.records]
    thread_id, level, block_index = row["thread_id"], row["level"], row["block_index"]
    try:
        inserted = await asyncio.to_thread(
            lambda: admin_client.table("chat_summary_blocks").insert({
                **row,
                "model": SUMMARY_MODEL,
                "usage": {"records": breakdown, "chargeable_usd": chargeable_usd},
                "cost_usd": cost_usd,
            }).execute()
        )
    except Exception as e:
        if "uq_chat_summary_blocks_active_index" in str(e) or "duplicate key" in str(e):
            print(f"⏭️ [chat-summary] level-{level} block {block_index} of thread {thread_id} was already created by another run.")
            return False
        raise

    block_id = inserted.data[0]["id"]
    # 畳んでいる間に編集で範囲が消えた(truncate_chat_thread_fromは、そのとき既にあったブロックしか
    # 無効にできない)。書いた後に確かめ、消えていればこのブロックも無効にする(課金もしない)
    if await asyncio.to_thread(_covers_deleted_range, admin_client, row):
        await asyncio.to_thread(
            lambda: admin_client.table("chat_summary_blocks").update({"invalidated_at": datetime.now(timezone.utc).isoformat()})
                .eq("id", block_id).execute()
        )
        print(f"⏭️ [chat-summary] level-{level} block {block_index} of thread {thread_id} covers an edited range; invalidated.")
        return False
    print(f"🗂️ [chat-summary] thread={thread_id} level={level} block={block_index} "
          f"turns={row['turn_start']}-{row['turn_end']} sections={len(row['sections'])} cost=${chargeable_usd:.6f}")
    try:
        charged = await asyncio.to_thread(
            consume_chat_summary_credits, row["user_id"], thread_id, block_id, chargeable_usd, breakdown,
        )
        await asyncio.to_thread(
            lambda: admin_client.table("chat_summary_blocks")
                .update({"credits_charged_micro": charged}).eq("id", block_id).execute()
        )
    except Exception as e:
        # 課金の失敗で要約自体を失敗扱いにはしない(メッセージの課金と同じ方針)
        print(f"⚠️ [chat-summary] failed to charge credits for block {block_id}: {e}")
    return True
