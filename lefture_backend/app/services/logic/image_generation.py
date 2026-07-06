# app/services/logic/image_generation.py
import json
from typing import Any, Dict, List
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import TaskLogger, _load_prompt

class ImageGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "together_ai/openai/gpt-oss-20b"

    async def run_from_memory(self, review_cards_results: List[Dict[str, Any]], core_data: Dict[str, Any]) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Image Prompt Generation")
        
        if not review_cards_results:
            self.logger.log("   [Logic] No review cards results found. Skipping Image Generation LLM call.")
            return {}
            
        prompt_template = _load_prompt("image_generation_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.5, reasoning_effort="medium")

        # Core Extractionのトピック情報から学術名(title)をマッピングする辞書を作成
        academic_titles = {}
        for topic in core_data.get("topics", []):
            t_idx = topic.get("idx")
            t_title = topic.get("title")
            if t_idx is not None and t_title:
                academic_titles[t_idx] = t_title

        # LLMに渡すインプットを組み立て
        minimized_topics = []
        for res in review_cards_results:
            topic_idx = res.get("topic_idx")
            academic_title = academic_titles.get(topic_idx, "Unknown Topic")

            # hookカードを探す
            hook_card = next((c for c in res.get("review_cards", []) if c.get("card_type") == "hook"), {})
            hook_text = ""
            for block in hook_card.get("content_blocks", []):
                if isinstance(block, dict) and block.get("type") in ["quote", "paragraph", "callout"] and block.get("text"):
                    hook_text = block["text"]
                    break

            summary = ""
            for mt in res.get("topic_evaluation", {}).get("micro_topics", []):
                if isinstance(mt, dict) and mt.get("summary"):
                    summary = mt["summary"]
                    break

            minimized_topics.append({
                "topic_idx": topic_idx,
                "title": academic_title,
                "hook_text": hook_text.strip(),
                "summary": summary.strip()
            })

        prompt_text = prompt_template
        messages = [
            Message(role="system", content=prompt_text),
            Message(role="user", content=f"Generate visual prompts for these topics:\n{json.dumps(minimized_topics, ensure_ascii=False)}")
        ]

        res = await self.llm.generate(model=self.model_alias, messages=messages, options=options_json)

        if res.json_parse_error:
            self.logger.log(f"❌ Image prompt JSON parse failed. Raw output:\n{res.output_text}")
            raise ValueError(f"Image prompt JSON parse failed: {res.json_parse_error}")

        if not isinstance(res.output_json, dict):
            raise ValueError("Image prompt output must be a JSON object.")

        global_art_direction = res.output_json.get("global_art_direction")
        if not isinstance(global_art_direction, dict):
            raise ValueError("Image prompt output must contain a global_art_direction object.")
        
        if not isinstance(global_art_direction.get("flux_style_suffix"), str) or not global_art_direction["flux_style_suffix"].strip():
            raise ValueError("global_art_direction object must contain a non-empty flux_style_suffix.")

        image_prompts = res.output_json.get("image_prompts")
        if not isinstance(image_prompts, list):
            raise ValueError("Image prompt output must contain an image_prompts list.")

        for idx, item in enumerate(image_prompts, start=1):
            if not isinstance(item, dict):
                raise ValueError(f"image_prompts[{idx}] must be an object.")
            if "topic_idx" not in item:
                raise ValueError(f"image_prompts[{idx}] is missing topic_idx.")
            if not isinstance(item.get("flux_scene_description"), str) or not item["flux_scene_description"].strip():
                raise ValueError(f"image_prompts[{idx}] is missing a valid flux_scene_description.")

        self.logger.log(f"   [Logic] Generated {len(image_prompts)} image prompt(s).")
        return res.output_json