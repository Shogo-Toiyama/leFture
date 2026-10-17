"""
チャットの返答の途中停止(docs/chatbot_context_and_retrieval_roadmap.md 2-12、2026-10-17に合意)。

方針: 走っているAPI呼び出しは止められない(非ストリームの呼び出しは、接続を切ってもプロバイダー側で
最後まで生成され、全額かかる)ので走り切らせる。その代わり、停止の後の課金のある呼び出しは確実に止める。
回答役のストリームだけは、接続を閉じれば生成が止まり出力の課金も止まるので、すぐ閉じる。

信号の置き場はDB(chat_messages.stop_requested_at)。停止のリクエストは、生成を走らせているのとは
別のCloud Runインスタンスに届くことがあるため。同じインスタンスに届いたときは、メモリ上のEventも立てて
すぐ効かせる(_ACTIVE)。

確実に止めるしくみは二重:
1. 課金のある呼び出しの入口(UnifiedLLMのguard、埋め込み、Web検索、リンクの取得)で、呼ぶ直前に
   check()する。DBも読むので、別のインスタンスに届いた停止も、呼び出しの前に必ず拾う。
2. 一度止まったら、ずっと止まる(sticky)。探索役のやり直しや検索の失敗の飲み込み(except Exception)で
   TurnStoppedが握りつぶされても、次の呼び出しの入口でまた投げるので、課金は発生しない。
   握りつぶされた停止は、run_chat_turnの段階の境目で拾い直す。
"""

from __future__ import annotations

import asyncio
import time
from typing import Optional

# 回答のストリーム中に、別のインスタンスに届いた停止を拾う間隔
STOP_POLL_SECONDS = 1.0
# 呼び出しの入口でDBを読み直すのは、直前に読んでからこれ以上たったときだけ(同時に並ぶ検索の入口で、
# 同じ読み取りを何本も投げないため)。これより短い間に届いた停止は、次の入口か見回りで拾う
CHECK_FRESH_SECONDS = 0.1


class TurnStopped(Exception):
    """停止が求められたので、課金のある呼び出しをしない。"""


class TurnStop:
    """1ターン分の停止の状態。run_chat_turnが作り、課金のある呼び出しの入口に渡す。"""

    def __init__(self, admin_client, message_id: str):
        self._admin = admin_client
        self.message_id = message_id
        self.event = asyncio.Event()
        self._last_refresh = 0.0

    @property
    def stopped(self) -> bool:
        return self.event.is_set()

    def _requested_in_db(self) -> bool:
        r = self._admin.table("chat_messages").select("stop_requested_at") \
            .eq("id", self.message_id).maybe_single().execute()
        return bool(r and r.data and r.data.get("stop_requested_at"))

    async def refresh(self) -> bool:
        """DBの停止の印を読み直す。読めなければ止めない(停止の信号の読み取りの失敗で、返答を壊さない)。"""
        if self.event.is_set():
            return True
        self._last_refresh = time.monotonic()
        try:
            requested = await asyncio.to_thread(self._requested_in_db)
        except Exception as e:
            print(f"⚠️ [chat] failed to read the stop flag for message {self.message_id}: {e}")
            return False
        if requested:
            self.event.set()
        return self.event.is_set()

    async def check(self) -> None:
        """課金のある呼び出しの直前に呼ぶ。止まっていればTurnStoppedを投げる。"""
        if self.event.is_set():
            raise TurnStopped()
        if time.monotonic() - self._last_refresh >= CHECK_FRESH_SECONDS:
            await self.refresh()
        if self.event.is_set():
            raise TurnStopped()

    def raise_if_stopped(self) -> None:
        """段階の境目で、握りつぶされた停止を拾い直す(DBは読まない)。"""
        if self.event.is_set():
            raise TurnStopped()

    async def watch(self) -> None:
        """生成の間、別のインスタンスに届いた停止を拾う。止まるか、呼び出し側にcancelされるまで。"""
        while not self.event.is_set():
            await asyncio.sleep(STOP_POLL_SECONDS)
            await self.refresh()


# このインスタンスで生成中のターン(返答のメッセージID → 停止の状態)。停止のリクエストが
# 同じインスタンスに届いたら、DBの見回りを待たずにすぐ効かせる
_ACTIVE: dict[str, TurnStop] = {}


def register(stop: TurnStop) -> None:
    _ACTIVE[stop.message_id] = stop


def unregister(stop: TurnStop) -> None:
    if _ACTIVE.get(stop.message_id) is stop:
        del _ACTIVE[stop.message_id]


def request_local_stop(message_id: str) -> bool:
    """このインスタンスで生成中なら、すぐ止める。生成中でなければFalse。"""
    stop = _ACTIVE.get(message_id)
    if stop is None:
        return False
    stop.event.set()
    return True


def guarded(stop: Optional[TurnStop], fn):
    """課金のある非同期関数の前に停止の確認を挟む(埋め込み・Web検索・リンクの取得用)。"""
    if stop is None:
        return fn

    async def wrapper(*args, **kwargs):
        await stop.check()
        return await fn(*args, **kwargs)

    return wrapper
