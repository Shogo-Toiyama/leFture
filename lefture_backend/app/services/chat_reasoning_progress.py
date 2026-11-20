"""Turn complete reasoning-summary lines into transient chat progress labels."""

import asyncio
import re
from typing import Awaitable, Callable


_SENTENCE_END = re.compile(r"(?<=[.!?])(?:[ \t]+|$)|(?<=[。！？])")


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
        if self._batch_size == 1 and not any(line.strip() for line in lines):
            sentence_end = _SENTENCE_END.search(self._partial)
            if sentence_end:
                end = sentence_end.end()
                lines.append(self._partial[:end])
                self._partial = self._partial[end:]
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
                    text = await self._summarize(excerpt)
                label = " ".join(line.strip() for line in text.splitlines() if line.strip())
                if not self._closed and label and label.upper() != "NONE":
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
