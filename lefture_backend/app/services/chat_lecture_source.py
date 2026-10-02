# app/services/chat_lecture_source.py
"""
探索役(chat_navigator.py)が講義の目次を「開く」ときに読むデータ。
docs/chatbot_context_and_retrieval_roadmap.md の 3-14 ③。

ここはDBから素のデータ(dict / list)を返すだけで、探索役・回答役に見せる文章に
するのはchat_navigator.pyの役目。評価ハーネス(contents_generation/test_codes/
navigator_test)は同じ形のデータを台本の世界から返すものに差し替えて、本番と同じ
組み立て方で評価する。

どのメソッドも、呼び出し側が本人の地図(chat_map.StudentMap)から取り出したIDだけを
渡す前提。念のためuser_idでも絞る(サービスロールで読むため)。

今のプランで使えない材料(plan_features.blocked_knowledge_source_types)は、ここで
読まない。探索役のプロンプトや選択肢で外していても、開く操作の最後の砦はここにする。
"""

import asyncio
import re
from typing import Optional, Protocol

from app.services.helpers.helpers import _sid_to_int
from app.services.helpers.plan_features import DEEP_NOTES_SKIPPED_PLAN_LIMIT
from app.services.knowledge_index import assemble_lecture_transcript


def first_sentence(text: Optional[str], max_chars: int) -> str:
    """要約の最初の1文(一覧の1行に使う)。"""
    text = re.sub(r"\s+", " ", (text or "").strip())
    if not text:
        return ""
    m = re.search(r"(.+?[.!?。！？])(\s|$)", text)
    sentence = m.group(1) if m else text
    return sentence if len(sentence) <= max_chars else sentence[:max_chars].rstrip() + "…"


class LectureSource(Protocol):
    async def lecture_summaries(self, lecture_ids: list[str]) -> dict[str, str]:
        """講義ID → 講義の要約(全文)。"""
        ...

    async def lecture_topics(self, lecture_id: str) -> list[dict]:
        """[{id, index, title, summary, topic_type}] をindex順に。"""
        ...

    async def topic_detail(self, lecture_id: str, index: int) -> Optional[dict]:
        """{id, index, title, summary, keywords: [(keyword, definition)], deep_note: str | None}"""
        ...

    async def transcript(self, lecture_id: str) -> list[dict]:
        """[{sid: int, text}] を文の順に。"""
        ...

    async def topic_indexes(self, topic_ids: list[str]) -> dict[str, tuple[str, int]]:
        """lecture_topics.id → (lecture_id, index)。検索で当たったトピックを呼び名に直すため。"""
        ...


class DbLectureSource:
    """本番用。1ターンの間だけ使い、同じ講義の読み直しを避けるため中身を覚えておく。"""

    def __init__(self, admin_client, user_id: str, blocked_source_types: frozenset[str] = frozenset()):
        self._client = admin_client
        self._user_id = user_id
        self._blocked = blocked_source_types
        self._topics: dict[str, list[dict]] = {}
        self._transcripts: dict[str, list[dict]] = {}

    async def lecture_summaries(self, lecture_ids: list[str]) -> dict[str, str]:
        if not lecture_ids:
            return {}

        def _q():
            return self._client.table("lectures").select("id, summary") \
                .eq("user_id", self._user_id).in_("id", lecture_ids).execute()
        res = await asyncio.to_thread(_q)
        return {r["id"]: (r.get("summary") or "").strip() for r in (res.data or [])}

    async def lecture_topics(self, lecture_id: str) -> list[dict]:
        if lecture_id not in self._topics:
            def _q():
                return self._client.table("lecture_topics").select(
                    "id, index, topic_title, summary, topic_type"
                ).eq("user_id", self._user_id).eq("lecture_id", lecture_id) \
                    .is_("deleted_at", "null").order("index").execute()
            res = await asyncio.to_thread(_q)
            self._topics[lecture_id] = [
                {"id": r["id"], "index": r.get("index"), "title": (r.get("topic_title") or "").strip(),
                 "summary": (r.get("summary") or "").strip(), "topic_type": r.get("topic_type")}
                for r in (res.data or []) if r.get("index") is not None
            ]
        return self._topics[lecture_id]

    async def topic_detail(self, lecture_id: str, index: int) -> Optional[dict]:
        topic = next((t for t in await self.lecture_topics(lecture_id) if t["index"] == index), None)
        if topic is None:
            return None

        def _keywords():
            return self._client.table("keywords").select("keyword, definition") \
                .eq("user_id", self._user_id).eq("lecture_id", lecture_id).eq("topic_number", index) \
                .is_("deleted_at", "null").execute()

        def _note():
            return self._client.table("deep_notes").select("note_contents") \
                .eq("user_id", self._user_id).eq("lecture_id", lecture_id).eq("topic_number", index) \
                .is_("deleted_at", "null").limit(1).execute()

        async def none():
            return None

        kw_res, note_res = await asyncio.gather(
            asyncio.to_thread(_keywords) if "keyword" not in self._blocked else none(),
            asyncio.to_thread(_note) if "deep_note" not in self._blocked else none(),
        )
        note = ((note_res.data or [{}])[0].get("note_contents") or "").strip() if note_res and note_res.data else ""
        if note == DEEP_NOTES_SKIPPED_PLAN_LIMIT:
            note = ""
        keywords = (kw_res.data or []) if kw_res else []
        return {
            **topic,
            "keywords": [(k.get("keyword") or "", k.get("definition") or "") for k in keywords if k.get("keyword")],
            "deep_note": note or None,
        }

    async def transcript(self, lecture_id: str) -> list[dict]:
        if "transcript_topic" in self._blocked:
            return []
        if lecture_id not in self._transcripts:
            sentences = await asyncio.to_thread(assemble_lecture_transcript, self._client, lecture_id, self._user_id)
            self._transcripts[lecture_id] = [
                {"sid": _sid_to_int(s.get("sid")), "text": (s.get("text") or "").strip()}
                for s in sentences if _sid_to_int(s.get("sid")) is not None
            ]
        return self._transcripts[lecture_id]

    async def topic_indexes(self, topic_ids: list[str]) -> dict[str, tuple[str, int]]:
        if not topic_ids:
            return {}

        def _q():
            return self._client.table("lecture_topics").select("id, lecture_id, index") \
                .eq("user_id", self._user_id).in_("id", topic_ids).execute()
        res = await asyncio.to_thread(_q)
        return {r["id"]: (r["lecture_id"], r["index"]) for r in (res.data or []) if r.get("index") is not None}
