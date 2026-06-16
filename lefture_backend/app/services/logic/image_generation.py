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

    async def run_from_memory(self, review_cards_results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        self.logger.log(f"   [Logic] Starting Image Prompt Generation")
        
        if not review_cards_results:
            self.logger.log("   [Logic] No review cards results found. Skipping Image Generation LLM call.")
            return []
            
        prompt_template = _load_prompt("image_generation_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=1.0, reasoning_effort="medium")

        # LLMに渡すインプットを最小化 (タイトルとHookのみ)
        minimized_topics = []
        for res in review_cards_results:
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
                "topic_idx": res.get("topic_idx"),
                "title": res.get("topic_evaluation", {}).get("core_concept_identified", "Unknown Topic"),
                "hook_text": hook_text,
                "summary": summary
            })

        prompt_text = prompt_template # 変数置換がないタイプなのでそのまま
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

        image_prompts = res.output_json.get("image_prompts")
        if not isinstance(image_prompts, list):
            raise ValueError("Image prompt output must contain an image_prompts list.")

        for idx, item in enumerate(image_prompts, start=1):
            if not isinstance(item, dict):
                raise ValueError(f"image_prompts[{idx}] must be an object.")
            if "topic_idx" not in item:
                raise ValueError(f"image_prompts[{idx}] is missing topic_idx.")
            if not isinstance(item.get("flux_prompt"), str) or not item["flux_prompt"].strip():
                raise ValueError(f"image_prompts[{idx}] is missing a valid flux_prompt.")

        self.logger.log(f"   [Logic] Generated {len(image_prompts)} image prompt(s).")
        return image_prompts