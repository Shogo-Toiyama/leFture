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

        selected_topic = next(
            (t for t in core_data.get("topics", []) if t.get("is_fun_fact_topic") is True),
            {},
        )
        concept_focus = selected_topic.get("concept_focus", "")
        concept_intro_line = selected_topic.get("concept_intro_line", "")

        if not seed_data:
            self.logger.log("   [Logic] ⚠️ No fun fact seed found from brainstorming. Continuing with empty seed.")

        seed_for_prompt = {
            "seed_fun_fact_idea": seed_data.get("seed_fun_fact_idea", ""),
            "named_instance": seed_data.get("named_instance", ""),
            "concrete_detail": seed_data.get("concrete_detail", ""),
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

        return self._validate_and_normalize_output(res.output_json)

    def _validate_and_normalize_output(self, output: Any) -> Dict[str, Any]:
        if not isinstance(output, dict):
            raise ValueError("Fun Fact output must be a JSON object.")

        required_keys = ["title", "hook", "body", "sources"]
        missing_keys = [key for key in required_keys if key not in output]
        if missing_keys:
            raise ValueError(f"Fun Fact output is missing keys: {missing_keys}")

        for key in ("title", "hook", "body"):
            value = output.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"Fun Fact field '{key}' must be a non-empty string.")

        sources = output.get("sources")
        if not isinstance(sources, list) or not all(isinstance(s, str) for s in sources):
            raise ValueError("Fun Fact field 'sources' must be a list of strings.")

        return output
