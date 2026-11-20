"""Turn complete reasoning-summary lines into transient chat progress labels."""

import asyncio
from typing import Awaitable, Callable


class ReasoningProgress:
    def __init__(
        self,
        summarize: Callable[[str], Awaitable[str]],
        publish: Callable[[str], Awaitable[None]],
    ) -> None:
        self._summarize = summarize
        self._publish = publish
        self._partial = ""
        self._lines: list[str] = []
        self._batch_size = 1
        self._pending: str | None = None
        self._task: asyncio.Task[None] | None = None
        self._closed = False

    def feed(self, chunk: str) -> None:
        if self._closed:
            return
        lines = (self._partial + chunk).split("\n")
        self._partial = lines.pop()
        for line in lines:
            line = line.strip()
            if not line:
                continue
            self._lines.append(line)
            if len(self._lines) != self._batch_size:
                continue
            excerpt = "\n\n".join(self._lines)
            self._lines.clear()
            self._batch_size = 3
            if self._task is None or self._task.done():
                self._task = asyncio.create_task(self._run(excerpt))
            else:
                self._pending = excerpt

    async def _run(self, excerpt: str) -> None:
        while not self._closed:
            try:
                async with asyncio.timeout(3):
                    label = (await self._summarize(excerpt)).strip()
                if (
                    not self._closed
                    and 0 < len(label) <= 60
                    and label.upper() != "NONE"
                    and len(label.splitlines()) == 1
                ):
                    await self._publish(label)
            except Exception:
                # A progress label is optional. The answer stream continues.
                pass
            if self._pending is None:
                return
            excerpt, self._pending = self._pending, None

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self._pending = None
        if self._task is not None:
            self._task.cancel()
