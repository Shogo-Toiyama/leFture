import asyncio
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "chat_reasoning_progress",
    ROOT / "lefture_backend/app/services/chat_reasoning_progress.py",
)
progress_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(progress_module)
ReasoningProgress = progress_module.ReasoningProgress


class ReasoningProgressTests(unittest.IsolatedAsyncioTestCase):
    async def test_first_complete_line_then_groups_of_three(self):
        chunks = []
        labels = []

        async def summarize(excerpt):
            chunks.append(excerpt)
            return "Checking scope"

        async def publish(label):
            labels.append(label)

        progress = ReasoningProgress(summarize, publish)
        progress.feed("First")
        await asyncio.sleep(0)
        self.assertEqual(chunks, [])
        progress.feed(" line\n\nSecond\nThird\n")
        await asyncio.sleep(0)
        self.assertEqual(chunks, ["First line"])
        progress.feed("Fourth\nFifth")
        await asyncio.sleep(0)
        self.assertEqual(chunks, ["First line", "Second\n\nThird\n\nFourth"])
        self.assertEqual(labels, ["Checking scope", "Checking scope"])
        progress.close()

    async def test_slow_summary_keeps_only_the_latest_pending_group(self):
        entered = asyncio.Event()
        release = asyncio.Event()
        published = asyncio.Event()
        chunks = []
        labels = []

        async def summarize(excerpt):
            chunks.append(excerpt)
            entered.set()
            await release.wait()
            return "NONE" if len(chunks) == 1 else "Reviewing the problem"

        async def publish(label):
            labels.append(label)
            published.set()

        progress = ReasoningProgress(summarize, publish)
        progress.feed("First\na\nb\nc\n")
        await asyncio.wait_for(entered.wait(), 1)
        progress.feed("d\ne\nf\n")
        release.set()
        await asyncio.wait_for(published.wait(), 1)
        self.assertEqual(chunks, ["First", "d\n\ne\n\nf"])
        self.assertEqual(labels, ["Reviewing the problem"])
        progress.close()

    async def test_long_labels_are_published_in_full(self):
        long_label = "Checking how each variable is scoped across the nested functions " * 2
        outputs = iter(["First sentence.\n\nSecond sentence.", long_label, " ", "NONE"])
        labels = []

        async def summarize(_):
            return next(outputs)

        async def publish(label):
            labels.append(label)

        progress = ReasoningProgress(summarize, publish)
        for chunk in ("First\n", "a\nb\nc\n", "d\ne\nf\n", "g\nh\ni\n"):
            progress.feed(chunk)
            await asyncio.sleep(0)
        self.assertEqual(labels, ["First sentence. Second sentence.", long_label.strip()])
        progress.close()

    async def test_close_cancels_and_discards_pending_updates(self):
        entered = asyncio.Event()
        cancelled = asyncio.Event()

        async def summarize(_):
            entered.set()
            try:
                await asyncio.Future()
            finally:
                cancelled.set()

        async def publish(_):
            self.fail("An update arrived after close")

        progress = ReasoningProgress(summarize, publish)
        progress.feed("First\na\nb\nc\n")
        await asyncio.wait_for(entered.wait(), 1)
        progress.close()
        progress.feed("d\ne\nf\n")
        await asyncio.wait_for(cancelled.wait(), 1)


if __name__ == "__main__":
    unittest.main()
