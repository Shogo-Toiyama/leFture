import asyncio
import os
import sys
from pathlib import Path

# Add lefture_backend to sys.path
backend_dir = Path(__file__).resolve().parents[3] / "lefture_backend"
sys.path.insert(0, str(backend_dir))

from app.services.logic.figure_generation import FigureGenerationService, extract_html
from app.services.helpers.helpers import _load_prompt, TaskLogger
from app.services.helpers.llm_unified import LLMOptions, UnifiedLLM, BillingEngine

class MockLLM(UnifiedLLM):
    def __init__(self):
        self.billing = BillingEngine("TEST")
    
    async def generate(self, model, messages, options=None):
        class MockResponse:
            output_text = "```html\n<div class=\"deepnote-diagram-wrapper\">Mock SVG Diagram Content</div>\n```"
            input_tokens = 150
            output_tokens = 200
            elapsed_seconds = 0.5
        return MockResponse()

async def run_dry_run_test():
    print("=== Testing FigureGenerationService ===")
    
    # 1. Test prompt loading
    prompt = _load_prompt("deepnote_figure_prompt.txt")
    assert "${FIGURE_TYPE}" in prompt, "Missing ${FIGURE_TYPE} in prompt template"
    assert "${TITLE}" in prompt, "Missing ${TITLE} in prompt template"
    assert "${DESCRIPTION}" in prompt, "Missing ${DESCRIPTION} in prompt template"
    assert "${SECTION_CONTEXT}" in prompt, "Missing ${SECTION_CONTEXT} in prompt template"
    print("✅ Prompt template loaded and verified.")

    # 2. Test tag parsing
    sample_note = """
# Topic 1: Jomon Pottery

This is introduction.

<!-- FIGURE: type="diagram" title="Jomon Pottery Firing Stages" description="Cross-section showing open pit firing with oxidation layer" -->

Here is the body text explaining open pit firing.

<!-- FIGURE: type="chart" title="Temperature vs Time Curve" description="Firing temperature curve reaching 800 degrees Celsius over 6 hours" -->

Conclusion of topic 1.
"""
    logger = TaskLogger("test_user", "test_lecture", "FIGURE_TEST")
    mock_llm = MockLLM()
    service = FigureGenerationService(mock_llm, logger)

    figures = service.extract_figures_from_note(1, sample_note)
    print(f"✅ Extracted {len(figures)} figures:")
    for f in figures:
        print(f"   - Index {f['figure_index']}: [{f['figure_type']}] {f['title']} (context len: {len(f['section_context'])})")

    assert len(figures) == 2, f"Expected 2 figures, got {len(figures)}"
    assert figures[0]["figure_index"] == 0
    assert figures[0]["figure_type"] == "diagram"
    assert figures[1]["figure_index"] == 1
    assert figures[1]["figure_type"] == "chart"

    # 3. Test generation pipeline with mock LLM
    notes = [
        {"topic_number": 1, "note_contents": sample_note},
        {"topic_number": 2, "note_contents": "No figures in this topic."},
    ]
    results = await service.run_for_notes(notes)
    print(f"✅ Pipeline run completed with {len(results)} figures generated:")
    for r in results:
        print(f"   - Topic {r['topic_number']} Fig {r['figure_index']} ({r['title']}): HTML length {len(r['html_content'])}")
        assert "<div class=\"deepnote-diagram-wrapper\">" in r["html_content"]

    print("🎉 All FigureGenerationService tests PASSED!")

if __name__ == "__main__":
    asyncio.run(run_dry_run_test())
