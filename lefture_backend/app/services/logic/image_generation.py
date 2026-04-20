# app/services/logic/image_generation.py
import json
from typing import Any, Dict, List
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import TaskLogger, _load_prompt

class ImageGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "groq/openai/gpt-oss-120b"

    async def run_from_memory(self, review_cards_results: List[Dict[str, Any]]) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Image Prompt Generation")
        
        prompt_template = _load_prompt("image_generation_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.5) # クリエイティブな表現のため少し上げる

        # LLMに渡すインプットを最小化 (タイトルとHookのみ)
        minimized_topics = []
        for res in review_cards_results:
            # hookカードを探す
            hook_card = next((c for c in res.get("review_cards", []) if c.get("card_type") == "hook"), {})
            minimized_topics.append({
                "topic_idx": res.get("topic_idx"),
                "title": res.get("topic_evaluation", {}).get("core_concept_identified", "Unknown Topic"),
                "hook_text": hook_card.get("content_blocks", [{}])[0].get("text", ""),
                "summary": res.get("topic_evaluation", {}).get("micro_topics", [{}])[0].get("summary", "")
            })

        prompt_text = prompt_template # 変数置換がないタイプなのでそのまま
        messages = [
            Message(role="system", content=prompt_text),
            Message(role="user", content=f"Generate visual prompts for these topics:\n{json.dumps(minimized_topics, ensure_ascii=False)}")
        ]

        res = await self.llm.generate(model=self.model_alias, messages=messages, options=options_json)
        return res.output_json