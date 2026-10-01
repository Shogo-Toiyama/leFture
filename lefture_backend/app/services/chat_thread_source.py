# app/services/chat_thread_source.py
"""
探索役(chat_navigator.py)が過去のチャット・この会話の畳んだ部分を「開く」ときに読むデータ。
docs/chatbot_context_and_retrieval_roadmap.md の 3-14 ④。chat_lecture_source.pyのチャット版。

往復の番号(turn number)は要約(chat_summary.pair_turns)と全く同じ数え方。要約の節
(chat_summary_blocks.sections[].turns)が指す番号と一致するので、検索で当たった往復を
節の呼び名に結びつけたり、節を開いてその往復の原文を見せたりできる。

ここはDbから素のデータ(dict / list)を返すだけで、探索役に見せる文章にするのは
chat_navigator.pyの役目。評価ハーネスは同じ形のデータを台本の世界から返すものに差し替える。
"""

import asyncio
from typing import Optional, Protocol

from app.services.chat_summary import pair_turns


class ChatThreadSource(Protocol):
    async def thread_meta(self, thread_id: str) -> Optional[dict]:
        """{title, date}。スレッドが無い/本人のものでなければNone。"""
        ...

    async def thread_turns(self, thread_id: str) -> list[dict]:
        """[{number, user_content, assistant_content, created_at}] を番号順に(全往復)。"""
        ...

    async def thread_sections(self, thread_id: str) -> list[dict]:
        """そのスレッド自身が畳んだ1段目の節: [{handle(int), title, bullets, turns: [番号]}]。"""
        ...

    async def thread_groups(self, thread_id: str) -> list[dict]:
        """2段目の節: [{handle(int), title, bullets, children: [1段目の節の番号], turns}]。"""
        ...

    async def recent_threads_with_trail(self, exclude_thread_id: Optional[str], limit: int) -> list[dict]:
        """[{id, title, date, trail: [節のタイトル]}] last_message_at降順、exclude_thread_idを除く。
        trailは2段目の節 → 2段目に入っていない1段目の節の順(長いスレッドは2段目のタイトルが先に並ぶ)。"""
        ...


class DbChatThreadSource:
    """本番用。1ターンの間だけ使い、同じスレッドの読み直しを避けるため中身を覚えておく。"""

    def __init__(self, admin_client, user_id: str):
        self._client = admin_client
        self._user_id = user_id
        self._turns: dict[str, list[dict]] = {}

    async def thread_meta(self, thread_id: str) -> Optional[dict]:
        def _q():
            return self._client.table("chat_threads").select("title, last_message_at, deleted_at") \
                .eq("id", thread_id).eq("user_id", self._user_id).maybe_single().execute()
        res = await asyncio.to_thread(_q)
        row = res.data if res else None
        if not row or row.get("deleted_at"):
            return None
        return {"title": (row.get("title") or "Untitled conversation").strip(), "date": (row.get("last_message_at") or "")[:10]}

    async def thread_turns(self, thread_id: str) -> list[dict]:
        if thread_id not in self._turns:
            def _q():
                return self._client.table("chat_messages").select("id, role, content, status, router, created_at") \
                    .eq("thread_id", thread_id).eq("user_id", self._user_id).is_("deleted_at", "null") \
                    .order("created_at").execute()
            res = await asyncio.to_thread(_q)
            self._turns[thread_id] = [
                {"number": t.number, "user_content": t.user_content, "assistant_content": t.assistant_content,
                 "created_at": t.assistant_created_at}
                for t in pair_turns(res.data or [])
            ]
        return self._turns[thread_id]

    async def thread_sections(self, thread_id: str) -> list[dict]:
        def _q():
            return self._client.table("chat_summary_blocks").select("sections") \
                .eq("thread_id", thread_id).eq("level", 1).is_("invalidated_at", "null") \
                .order("block_index").execute()
        res = await asyncio.to_thread(_q)
        return [{"handle": sec["handle"], "title": sec["title"], "bullets": sec.get("bullets") or [], "turns": sec["turns"]}
                for b in (res.data or []) for sec in b.get("sections") or []]

    async def thread_groups(self, thread_id: str) -> list[dict]:
        def _q():
            return self._client.table("chat_summary_blocks").select("sections") \
                .eq("thread_id", thread_id).eq("level", 2).is_("invalidated_at", "null") \
                .order("block_index").execute()
        res = await asyncio.to_thread(_q)
        return [{"handle": g["handle"], "title": g["title"], "bullets": g.get("bullets") or [],
                 "children": g.get("children") or [], "turns": g.get("turns") or []}
                for b in (res.data or []) for g in b.get("sections") or []]

    async def recent_threads_with_trail(self, exclude_thread_id: Optional[str], limit: int) -> list[dict]:
        def _threads_q():
            return self._client.table("chat_threads").select("id, title, last_message_at") \
                .eq("user_id", self._user_id).is_("deleted_at", "null") \
                .order("last_message_at", desc=True).limit(limit + 1).execute()
        res = await asyncio.to_thread(_threads_q)
        rows = [r for r in (res.data or []) if r["id"] != exclude_thread_id][:limit]
        if not rows:
            return []

        thread_ids = [r["id"] for r in rows]

        def _blocks_q():
            return self._client.table("chat_summary_blocks").select("id, thread_id, level, block_index, sections, child_block_ids") \
                .in_("thread_id", thread_ids).is_("invalidated_at", "null") \
                .order("level", desc=True).order("block_index").execute()
        blocks_res = await asyncio.to_thread(_blocks_q)
        covered = {cid for b in blocks_res.data or [] if b["level"] == 2 for cid in b.get("child_block_ids") or []}
        trails: dict[str, list[str]] = {}
        for b in blocks_res.data or []:  # 2段目が先、1段目が後(並び順で)
            if b["id"] in covered:
                continue
            trails.setdefault(b["thread_id"], [])
            trails[b["thread_id"]] += [sec["title"] for sec in b.get("sections") or []]

        return [
            {"id": r["id"], "title": (r.get("title") or "Untitled conversation").strip(),
             "date": (r.get("last_message_at") or "")[:10], "trail": trails.get(r["id"], [])}
            for r in rows
        ]
