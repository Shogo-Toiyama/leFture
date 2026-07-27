import json
from typing import Any, Dict, List
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, TaskLogger, _build_language_instruction

class FunFactGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "gemini/gemini-2.5-flash"

    async def run_from_memory(
        self,
        core_data: Dict[str, Any],
        seed_data: Dict[str, Any],
        search_results: List[Dict[str, Any]],
        student_profile: str,
        content_language: str = "English",
    ) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Fun Fact Generation")

        prompt_template = _load_prompt("fun_fact_generation_prompt.txt")
        prompt_template = prompt_template.replace(
            "${LANGUAGE_INSTRUCTIONS}", _build_language_instruction(content_language)
        )
        options_json = LLMOptions(output_type="json", temperature=0.7)

        fun_fact_selection = core_data.get("fun_fact_selection") or {}
        concept_focus = fun_fact_selection.get("concept_focus", "")
        concept_intro_line = fun_fact_selection.get("concept_intro_line", "")

        if not seed_data:
            self.logger.log("   [Logic] ⚠️ No fun fact seed found from brainstorming. Continuing with empty seed.")

        seed_for_prompt = {
            "seed_fun_fact_idea": seed_data.get("seed_fun_fact_idea", ""),
            "named_instance": seed_data.get("named_instance", ""),
            "concrete_detail": seed_data.get("concrete_detail", ""),
            "domain": seed_data.get("domain", ""),
        }

        search_text = ""
        if search_results:
            search_text = json.dumps(search_results, ensure_ascii=False)
        else:
            search_text = "No web search results available."

        messages = [
            Message(role="system", content=prompt_template),
            Message(role="user", content=(
                f"<STUDENT_PROFILE>\n{student_profile}\n</STUDENT_PROFILE>\n\n"
                f"<CONCEPT_FOCUS>\n{concept_focus}\n</CONCEPT_FOCUS>\n\n"
                f"<CONCEPT_INTRO_LINE>\n{concept_intro_line}\n</CONCEPT_INTRO_LINE>\n\n"
                f"<SEED_FUN_FACT_IDEA>\n{json.dumps(seed_for_prompt, ensure_ascii=False)}\n</SEED_FUN_FACT_IDEA>\n\n"
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
