import json
from typing import Any, Dict, List
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, TaskLogger

class FunFactGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "gemini/gemini-2.5-flash"

    async def run_from_memory(
        self, 
        role_classified_data: List[Dict[str, Any]], 
        core_data: Dict[str, Any],
        search_results: List[Dict[str, Any]],
        student_profile: str
    ) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Fun Fact Generation")
        
        prompt_template = _load_prompt("fun_fact_generation_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.7)

        # 💡 全トランスクリプトから確率ベースでノイズを除去
        trimmed_lines = []
        for s in role_classified_data:
            probs = s.get("all_probabilities")
            
            # Role Classification で確率データが無い場合のフォールバック
            if not probs:
                if s.get("role") in ["CONTENT", "INTERACTION"]:
                    trimmed_lines.append(f"{s['sid']}: {s['text']}")
                continue
                
            content_prob = probs.get("CONTENT", 0.0)
            interaction_prob = probs.get("INTERACTION", 0.0)
            
            if content_prob >= 0.10 or interaction_prob >= 0.50:
                trimmed_lines.append(f"{s['sid']}: {s['text']}")

        transcript_segment = "\n".join(trimmed_lines)
        seed_idea = core_data.get("fun_fact_idea") or {}
        if not seed_idea:
            self.logger.log("   [Logic] ⚠️ No fun_fact_idea found in core_data. Continuing with empty seed.")

        # student_profile is passed dynamically as a parameter

        search_text = ""
        if search_results:
            search_text = json.dumps(search_results, ensure_ascii=False)
        else:
            search_text = "No web search results available."

        messages = [
            Message(role="system", content=prompt_template),
            Message(role="user", content=(
                f"<STUDENT_PROFILE>\n{student_profile}\n</STUDENT_PROFILE>\n\n"
                f"<TRANSCRIPT_SEGMENT>\n{transcript_segment}\n</TRANSCRIPT_SEGMENT>\n\n"
                f"<SEED_FUN_FACT_IDEA>\n{json.dumps(seed_idea, ensure_ascii=False)}\n</SEED_FUN_FACT_IDEA>\n\n"
                f"<WEB_SEARCH_RESULTS>\n{search_text}\n</WEB_SEARCH_RESULTS>"
            ))
        ]

        res = await self.llm.generate(model=self.model_alias, messages=messages, options=options_json)

        if res.json_parse_error:
            self.logger.log(f"❌ Fun Fact JSON parse failed. Raw output:\n{res.output_text}")
            raise ValueError(f"Fun Fact JSON parse failed: {res.json_parse_error}")

        if not isinstance(res.output_json, dict):
            raise ValueError("Fun Fact output must be a JSON object.")

        return res.output_json