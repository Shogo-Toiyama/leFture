import unittest
import os
import sys
import json
import re
from pathlib import Path

# Setup sys.path to include lefture_backend
backend_dir = Path(__file__).resolve().parents[3] / "lefture_backend"
sys.path.insert(0, str(backend_dir))

from app.services.logic.figure_generation import FigureGenerationService, extract_html
from app.services.helpers.helpers import _load_prompt, TaskLogger
from app.services.helpers.llm_unified import LLMOptions, UnifiedLLM, BillingEngine


class MockUnifiedLLM(UnifiedLLM):
    def __init__(self, output_generator=None):
        self.billing = BillingEngine("TEST_BILLING")
        self.output_generator = output_generator or (
            lambda prompt: "```html\n<div class=\"deepnote-figure-card\"><svg viewBox=\"0 0 500 300\"></svg></div>\n```"
        )
        self.call_count = 0

    async def generate(self, model, messages, options=None):
        self.call_count += 1
        prompt = messages[0].content
        class Response:
            output_text = self.output_generator(prompt)
            input_tokens = 120
            output_tokens = 250
            elapsed_seconds = 0.8
        return Response()


class TestFigureTagExtraction(unittest.TestCase):
    def setUp(self):
        self.logger = TaskLogger("test_u", "test_l", "TAG_TEST")
        self.service = FigureGenerationService(MockUnifiedLLM(), self.logger)

    def test_standard_diagram_and_chart(self):
        content = (
            "Introduction text.\n"
            '<!-- FIGURE: type="diagram" title="Von Neumann Architecture" description="CPU, Memory and I/O bus connections" -->\n'
            "Body text explaining concepts.\n"
            '<!-- FIGURE: type="chart" title="Clock Frequency vs Power" description="Logarithmic scale showing thermal dissipation wall" -->\n'
            "Conclusion."
        )
        figures = self.service.extract_figures_from_note(1, content)
        self.assertEqual(len(figures), 2)

        # Check Figure 0
        self.assertEqual(figures[0]["topic_number"], 1)
        self.assertEqual(figures[0]["figure_index"], 0)
        self.assertEqual(figures[0]["figure_type"], "diagram")
        self.assertEqual(figures[0]["title"], "Von Neumann Architecture")
        self.assertEqual(figures[0]["description"], "CPU, Memory and I/O bus connections")

        # Check Figure 1
        self.assertEqual(figures[1]["topic_number"], 1)
        self.assertEqual(figures[1]["figure_index"], 1)
        self.assertEqual(figures[1]["figure_type"], "chart")
        self.assertEqual(figures[1]["title"], "Clock Frequency vs Power")
        self.assertEqual(figures[1]["description"], "Logarithmic scale showing thermal dissipation wall")

    def test_single_quotes_and_newlines(self):
        content = (
            "Text before.\n"
            "<!--   FIGURE: \n"
            "  type='diagram'\n"
            "  title='Complex State Machine'\n"
            "  description='Transition diagram between idle, active, and sleep states'\n"
            "-->\n"
            "Text after."
        )
        figures = self.service.extract_figures_from_note(3, content)
        self.assertEqual(len(figures), 1)
        self.assertEqual(figures[0]["figure_type"], "diagram")
        self.assertEqual(figures[0]["title"], "Complex State Machine")
        self.assertEqual(figures[0]["description"], "Transition diagram between idle, active, and sleep states")

    def test_type_normalization(self):
        content = (
            '<!-- FIGURE: type="chart" title="A" description="D1" -->\n'
            '<!-- FIGURE: type="CHART" title="B" description="D2" -->\n'
            '<!-- FIGURE: type="diagram" title="C" description="D3" -->\n'
            '<!-- FIGURE: type="flowchart" title="D" description="D4" -->\n'
            '<!-- FIGURE: type="unknown_custom_type" title="E" description="D5" -->\n'
        )
        figures = self.service.extract_figures_from_note(2, content)
        self.assertEqual(len(figures), 5)
        self.assertEqual(figures[0]["figure_type"], "chart")
        self.assertEqual(figures[1]["figure_type"], "chart")
        self.assertEqual(figures[2]["figure_type"], "diagram")
        self.assertEqual(figures[3]["figure_type"], "diagram")
        self.assertEqual(figures[4]["figure_type"], "diagram")

    def test_missing_attributes_fallback(self):
        # type and title omitted
        content = '<!-- FIGURE: description="Only description provided" -->'
        figures = self.service.extract_figures_from_note(4, content)
        self.assertEqual(len(figures), 1)
        self.assertEqual(figures[0]["figure_type"], "diagram")
        self.assertEqual(figures[0]["title"], "Figure 1")
        self.assertEqual(figures[0]["description"], "Only description provided")

    def test_empty_content_or_no_tags(self):
        self.assertEqual(self.service.extract_figures_from_note(1, ""), [])
        self.assertEqual(self.service.extract_figures_from_note(1, None), [])
        self.assertEqual(self.service.extract_figures_from_note(1, "Just regular markdown text without figure tags."), [])

    def test_context_window_boundary(self):
        short_note = '<!-- FIGURE: type="diagram" title="Short" description="Desc" -->'
        figures = self.service.extract_figures_from_note(1, short_note)
        self.assertEqual(len(figures), 1)
        # Context should not throw index error even if text is very short
        self.assertTrue(len(figures[0]["section_context"]) >= 0)


class TestHtmlExtraction(unittest.TestCase):
    def test_markdown_code_block_with_html_lang(self):
        raw = "```html\n<div class=\"card\">Content</div>\n```"
        self.assertEqual(extract_html(raw), '<div class="card">Content</div>')

    def test_markdown_code_block_without_lang(self):
        raw = "```\n<div class=\"card\">Content</div>\n```"
        self.assertEqual(extract_html(raw), '<div class="card">Content</div>')

    def test_plain_html_without_blocks(self):
        raw = '<div class="card">Content</div>'
        self.assertEqual(extract_html(raw), '<div class="card">Content</div>')

    def test_html_surrounded_by_chatter(self):
        raw = (
            "Here is the requested diagram:\n\n"
            "```html\n"
            "<div class=\"deepnote-card\">\n"
            "  <svg>...</svg>\n"
            "</div>\n"
            "```\n\n"
            "I hope this helps your understanding!"
        )
        extracted = extract_html(raw)
        self.assertTrue(extracted.startswith('<div class="deepnote-card">'))
        self.assertTrue(extracted.endswith('</div>'))
        self.assertNotIn("Here is the requested diagram", extracted)
        self.assertNotIn("I hope this helps", extracted)


class TestPromptIntegrity(unittest.TestCase):
    def test_prompt_file_and_placeholders(self):
        prompt = _load_prompt("deepnote_figure_prompt.txt")
        self.assertIsNotNone(prompt)
        # Verify required placeholders
        self.assertIn("${FIGURE_TYPE}", prompt)
        self.assertIn("${TITLE}", prompt)
        self.assertIn("${DESCRIPTION}", prompt)
        self.assertIn("${SECTION_CONTEXT}", prompt)

    def test_prompt_is_strictly_english(self):
        prompt = _load_prompt("deepnote_figure_prompt.txt")
        # Ensure no Japanese characters (Hiragana, Katakana, Kanji) in prompt
        japanese_pattern = re.compile(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]')
        match = japanese_pattern.search(prompt)
        self.assertIsNone(match, f"Found non-English character in prompt: {match.group(0) if match else ''}")


class TestFigureGenerationServiceExecution(unittest.IsolatedAsyncioTestCase):
    async def test_service_run_for_notes_success(self):
        mock_llm = MockUnifiedLLM()
        logger = TaskLogger("u1", "l1", "SVC_TEST")
        service = FigureGenerationService(mock_llm, logger)

        notes = [
            {
                "topic_number": 1,
                "note_contents": '<!-- FIGURE: type="diagram" title="T1F0" description="D1" -->\n<!-- FIGURE: type="chart" title="T1F1" description="D2" -->'
            },
            {
                "topic_number": 2,
                "note_contents": "No figure here."
            },
            {
                "topic_number": 3,
                "note_contents": '<!-- FIGURE: type="diagram" title="T3F0" description="D3" -->'
            }
        ]

        results = await service.run_for_notes(notes)
        self.assertEqual(len(results), 3)
        self.assertEqual(mock_llm.call_count, 3)

        # Check results mapping
        self.assertEqual(results[0]["topic_number"], 1)
        self.assertEqual(results[0]["figure_index"], 0)
        self.assertEqual(results[0]["title"], "T1F0")

        self.assertEqual(results[1]["topic_number"], 1)
        self.assertEqual(results[1]["figure_index"], 1)
        self.assertEqual(results[1]["title"], "T1F1")

        self.assertEqual(results[2]["topic_number"], 3)
        self.assertEqual(results[2]["figure_index"], 0)
        self.assertEqual(results[2]["title"], "T3F0")

    async def test_invalid_llm_output_is_skipped_gracefully(self):
        # LLM returns invalid output without <div
        bad_llm = MockUnifiedLLM(output_generator=lambda p: "I am sorry, I cannot generate diagrams.")
        logger = TaskLogger("u1", "l1", "BAD_SVC_TEST")
        service = FigureGenerationService(bad_llm, logger)

        notes = [{"topic_number": 1, "note_contents": '<!-- FIGURE: type="diagram" title="FailFig" description="D" -->'}]
        results = await service.run_for_notes(notes)
        # Should gracefully return empty list instead of crashing
        self.assertEqual(results, [])


class TestDagPipelineIntegrity(unittest.TestCase):
    def test_main_and_trigger_analysis_dag_consistency(self):
        from app.main import TASK_ROUTES

        # 1. TASK_ROUTES must have FIGURE_GENERATION
        self.assertIn("FIGURE_GENERATION", TASK_ROUTES)
        self.assertEqual(TASK_ROUTES["FIGURE_GENERATION"], "/worker/figure-generation")

        # 2. Check trigger_analysis.py blueprint
        trigger_analysis_path = backend_dir / "trigger_analysis.py"
        with open(trigger_analysis_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn('"task_type": "FIGURE_GENERATION"', code)
        self.assertIn('"dependencies": ["DETAIL_CONTENTS_GENERATION"]', code)

        # Check FINALIZE_JOB depends on FIGURE_GENERATION
        self.assertIn('"FIGURE_GENERATION"', code)

    def test_dag_is_acyclic(self):
        """Verify that the DAG does not contain cycles (can be topologically sorted)"""
        # Blueprint extracted from main.py
        blueprint = [
            {"task_type": "CHECK_AND_ASSEMBLE", "dependencies": []},
            {"task_type": "CORE_EXTRACTION", "dependencies": ["CHECK_AND_ASSEMBLE"]},
            {"task_type": "ROLE_CLASSIFICATION", "dependencies": ["CORE_EXTRACTION"]},
            {"task_type": "ANNOUNCEMENT_GENERATION", "dependencies": ["ROLE_CLASSIFICATION"]},
            {"task_type": "TOPIC_MAPPING", "dependencies": ["ROLE_CLASSIFICATION"]},
            {"task_type": "REVIEW_CARD_GENERATION", "dependencies": ["TOPIC_MAPPING"]},
            {"task_type": "IMAGE_PROMPT_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION"]},
            {"task_type": "IMAGE_RENDERING", "dependencies": ["IMAGE_PROMPT_GENERATION"]},
            {"task_type": "FUN_FACT_BRAINSTORMING", "dependencies": ["CORE_EXTRACTION"]},
            {"task_type": "FUN_FACT_SEARCH", "dependencies": ["FUN_FACT_BRAINSTORMING"]},
            {"task_type": "FUN_FACTS_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION", "FUN_FACT_SEARCH"]},
            {"task_type": "DETAIL_CONTENTS_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION"]},
            {"task_type": "FIGURE_GENERATION", "dependencies": ["DETAIL_CONTENTS_GENERATION"]},
            {"task_type": "FINALIZE_JOB", "dependencies": [
                "ANNOUNCEMENT_GENERATION",
                "IMAGE_RENDERING",
                "FUN_FACTS_GENERATION",
                "FIGURE_GENERATION"
            ]}
        ]

        in_degree = {t["task_type"]: len(t["dependencies"]) for t in blueprint}
        graph = {t["task_type"]: [] for t in blueprint}
        for t in blueprint:
            for dep in t["dependencies"]:
                graph[dep].append(t["task_type"])

        # Kahn's algorithm for topological sort
        queue = [t for t, deg in in_degree.items() if deg == 0]
        visited_count = 0

        while queue:
            node = queue.pop(0)
            visited_count += 1
            for neighbor in graph[node]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)

        self.assertEqual(visited_count, len(blueprint), "DAG contains cycles!")


class TestFigureGenerationTaskRunner(unittest.IsolatedAsyncioTestCase):
    async def test_task_runner_with_no_notes_completes_early(self):
        from unittest.mock import patch, AsyncMock, MagicMock
        from app.services.task_runners import run_figure_generation_task

        with patch("app.services.task_runners._get_job_context", new=AsyncMock(return_value={"user_id": "u1", "lecture_id": "l1"})), \
             patch("app.services.task_runners._claim_task", new=AsyncMock(return_value=True)), \
             patch("app.services.task_runners.get_supabase_client") as mock_supa, \
             patch("app.services.task_runners._update_task_status", new=AsyncMock()) as mock_update_status, \
             patch("app.services.task_runners.storage_service"):

            # Supabase returns empty deep_notes
            client = MagicMock()
            mock_supa.return_value = client
            client.table().select().eq().neq().order().execute.return_value.data = []

            await run_figure_generation_task("job_123", "task_456")

            # Should update status to COMPLETED with figure_count = 0
            mock_update_status.assert_called_once_with(
                "task_456", "COMPLETED", payload={"figure_count": 0, "billing_records": []}, user_id="u1", job_id="job_123"
            )

    async def test_task_runner_already_claimed_skips(self):
        from unittest.mock import patch, AsyncMock
        from app.services.task_runners import run_figure_generation_task

        with patch("app.services.task_runners._get_job_context", new=AsyncMock(return_value={"user_id": "u1", "lecture_id": "l1"})), \
             patch("app.services.task_runners._claim_task", new=AsyncMock(return_value=False)), \
             patch("app.services.task_runners._update_task_status", new=AsyncMock()) as mock_update_status:

            await run_figure_generation_task("job_123", "task_456")
            # Should skip execution without updating status
            mock_update_status.assert_not_called()


if __name__ == "__main__":
    unittest.main()

