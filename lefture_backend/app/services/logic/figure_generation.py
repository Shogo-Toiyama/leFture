import re
import json
import asyncio
from typing import Any, Dict, List, Optional
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, TaskLogger

FIGURE_TAG_REGEX = re.compile(r'<!--\s*FIGURE:\s*(.*?)\s*-->', re.IGNORECASE | re.DOTALL)
ATTR_REGEX = re.compile(r'(\w+)=["\'](.*?)["\']', re.DOTALL)

def extract_html(raw_response: str) -> str:
    """Robustly extract HTML code block from Markdown response"""
    cleaned = raw_response.strip()
    if "```" in cleaned:
        match = re.search(r'```(?:html)?\s*\n(.*?)(?:\n```|$)', cleaned, re.DOTALL | re.IGNORECASE)
        if match:
            return match.group(1).strip()
    return cleaned

class FigureGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model = "anthropic/claude-haiku-5-5"
        self.options = LLMOptions(
            temperature=0.2,
            reasoning_effort="low",
            max_completion_tokens=8000,
        )

    def extract_figures_from_note(self, topic_number: int, note_contents: str) -> List[Dict[str, Any]]:
        """
        Scan note_contents for <!-- FIGURE: ... --> tags in document order.
        Assign sequential figure_index (0, 1, ...).
        """
        if not note_contents:
            return []

        figures = []
        for match_idx, m in enumerate(FIGURE_TAG_REGEX.finditer(note_contents)):
            tag_content = m.group(1).strip()
            attrs = dict(ATTR_REGEX.findall(tag_content))
            
            raw_type = attrs.get("type", "diagram").lower().strip()
            # Explicit binary classification: 'chart' if explicitly specified, otherwise default to 'diagram'
            fig_type = "chart" if raw_type == "chart" else "diagram"

            title = attrs.get("title", f"Figure {match_idx + 1}").strip()
            desc = attrs.get("description", "").strip()

            # Context window around the tag (+-600 characters)
            start_pos = max(0, m.start() - 600)
            end_pos = min(len(note_contents), m.end() + 600)
            context = note_contents[start_pos:end_pos].strip()

            figures.append({
                "topic_number": topic_number,
                "figure_index": match_idx,
                "figure_type": fig_type,
                "title": title,
                "description": desc,
                "section_context": context,
                "raw_tag": m.group(0),
            })

        return figures

    async def generate_single_figure(self, fig: Dict[str, Any], prompt_template: str) -> Optional[Dict[str, Any]]:
        """
        Call Claude Haiku 5.5 to generate the standalone HTML/SVG component.
        """
        title = fig["title"]
        fig_type = fig["figure_type"]
        desc = fig["description"]
        context = fig["section_context"]
        topic_num = fig["topic_number"]
        fig_idx = fig["figure_index"]

        prompt = prompt_template
        prompt = prompt.replace("${FIGURE_TYPE}", fig_type)
        prompt = prompt.replace("${TITLE}", title)
        prompt = prompt.replace("${DESCRIPTION}", desc)
        prompt = prompt.replace("${SECTION_CONTEXT}", context)

        messages = [Message(role="user", content=prompt)]

        self.logger.log(f"   [Figure] Generating Topic {topic_num} Fig {fig_idx} ({title}) [{fig_type}]...")
        try:
            res = await self.llm.generate(model=self.model, messages=messages, options=self.options)
            html_code = extract_html(res.output_text or "")
            
            if not html_code or "<div" not in html_code:
                self.logger.log(f"⚠️ [Figure] Invalid or empty HTML for Topic {topic_num} Fig {fig_idx}: {title}")
                return None

            return {
                "topic_number": topic_num,
                "figure_index": fig_idx,
                "figure_type": fig_type,
                "title": title,
                "description": desc,
                "html_content": html_code,
                "tokens": {
                    "input": res.input_tokens,
                    "output": res.output_tokens,
                },
                "elapsed_seconds": res.elapsed_seconds,
            }
        except Exception as e:
            self.logger.log(f"❌ [Figure] Failed generation for Topic {topic_num} Fig {fig_idx} ({title}): {e}")
            raise e

    async def run_for_notes(
        self,
        notes: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """
        Process all figures found in notes list in parallel.
        notes: list of dict with 'topic_number' and 'note_contents'
        """
        prompt_template = _load_prompt("deepnote_figure_prompt.txt")
        all_targets = []

        for note in notes:
            topic_num = note.get("topic_number")
            contents = note.get("note_contents") or ""
            if topic_num is not None and contents:
                figs = self.extract_figures_from_note(topic_num, contents)
                all_targets.extend(figs)

        if not all_targets:
            self.logger.log("   [Figure] No figure placeholders found across all notes. Skipping.")
            return []

        self.logger.log(f"   [Figure] Found {len(all_targets)} figure placeholder(s). Starting parallel generation...")

        tasks = [self.generate_single_figure(fig, prompt_template) for fig in all_targets]
        results = await asyncio.gather(*tasks)

        successful_figures = [r for r in results if r is not None]
        self.logger.log(f"   [Figure] Completed generation: {len(successful_figures)}/{len(all_targets)} succeeded.")

        return successful_figures
