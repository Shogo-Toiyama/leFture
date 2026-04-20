import json
from typing import Any, Dict, List
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, TaskLogger

class TopicDetailGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "gemini/gemini-2.5-flash"

    async def run_from_memory(self, role_classified_data: List[Dict[str, Any]], core_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        self.logger.log(f"   [Logic] Starting Topic Detail Generation")
        
        prompt_template = _load_prompt("topic_details_generation_prompt.txt")
        options_text = LLMOptions(output_type="text", temperature=0.2)
        
        all_details = []

        # ACADEMIC なトピックだけを抽出
        academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]

        for topic in academic_topics:
            topic_idx = topic.get("idx")
            topic_title = topic.get("title")
            start_sid = topic.get("start_sid")
            end_sid = topic.get("end_sid")

            try:
                start_num = int(start_sid[1:])
                end_num = int(end_sid[1:])
            except: continue

            # このトピック範囲の文を抽出
            segment_sentences = [
                s for s in role_classified_data 
                if start_num <= int(s["sid"][1:]) <= end_num
            ]

            if not segment_sentences: continue

            # 💡 確率ベースでフィルタリング (CONTENTS 10%以上 OR INTERACTION 50%以上)
            trimmed_lines = []
            for s in segment_sentences:
                probs = s.get("all_probabilities", {})
                
                if not probs:
                    if s.get("role") in ["CONTENT", "INTERACTION"]:
                        trimmed_lines.append(f"{s['sid']}: {s['text']}")
                    continue
                
                content_prob = probs.get("CONTENT", 0.0)
                interaction_prob = probs.get("INTERACTION", 0.0)
                
                if content_prob >= 0.10 or interaction_prob >= 0.50:
                    trimmed_lines.append(f"{s['sid']}: {s['text']}")

            if not trimmed_lines:
                self.logger.log(f"   [Logic] Skipping Topic Detail {topic_idx} (No valid sentences)")
                continue

            trimmed_transcript = "\n".join(trimmed_lines)
            self.logger.log(f"   [Logic] Generating detail contents for Topic {topic_idx}: {topic_title}")

            messages = [
                Message(role="system", content=prompt_template),
                Message(role="user", content=(
                    f"Topic segment:\n{json.dumps(topic, ensure_ascii=False)}\n\n"
                    f"Partial transcript:\n{trimmed_transcript}"
                ))
            ]

            res = await self.llm.generate(model=self.model_alias, messages=messages, options=options_text)
            
            # Markdownのテキスト結果をリストに保存
            if res.output_text:
                all_details.append({
                    "topic_idx": topic_idx,
                    "content": res.output_text
                })

        return all_details