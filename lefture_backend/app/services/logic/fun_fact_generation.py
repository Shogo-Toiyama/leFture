import re
import json
from typing import Any, Dict, List, Tuple
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, TaskLogger, _build_language_instruction

def _format_search_results_for_prompt(
    search_results: List[Dict[str, Any]]
) -> Tuple[str, Dict[int, str]]:
    """
    検索結果をインデックス番号付きのテキストに成形し、
    番号 -> URL のマッピング辞書を作成する。URL自体はプロンプトには含めない。
    """
    if not search_results:
        return "No web search results available.", {}

    formatted_blocks = []
    url_by_index: Dict[int, str] = {}
    valid_idx = 1
    for item in search_results:
        url = item.get("url")
        title = (item.get("title") or "").strip()
        content = (item.get("content") or "").strip()
        if not url or not content:
            continue
        url_by_index[valid_idx] = url
        block = f"⟦{valid_idx}⟧ Title: {title}\nContent: {content}"
        formatted_blocks.append(block)
        valid_idx += 1

    if not formatted_blocks:
        return "No web search results available.", {}

    return "\n\n".join(formatted_blocks), url_by_index


def _renumber_citations_and_extract_sources(
    body: str,
    url_by_index: Dict[int, str]
) -> Tuple[str, List[str]]:
    """
    body内の ⟦1⟧ や ⟦2, 5⟧ などの引用番号を登場順に ⟦1⟧, ⟦2⟧... と振り直し、
    本文を更新するとともに、対応するURLのリスト [url_1, url_2, ...] を返す。
    存在しない番号は無視/除去する。
    """
    if not url_by_index or not body:
        return body, []

    old_to_new: Dict[int, int] = {}
    sources: List[str] = []

    bracket_pattern = re.compile(r"(?:⟦|〚|\[\[)(.*?)(?:⟧|〛|\]\])")

    # 1. 登場順に有効な元のインデックスを特定し、連番を割り当てる
    for match in bracket_pattern.finditer(body):
        inner = match.group(1)
        for num_str in re.findall(r"\d+", inner):
            try:
                old_idx = int(num_str)
                if old_idx in url_by_index and old_idx not in old_to_new:
                    new_idx = len(sources) + 1
                    old_to_new[old_idx] = new_idx
                    sources.append(url_by_index[old_idx])
            except ValueError:
                continue

    if not old_to_new:
        return body, []

    # 2. 本文内のカッコ表記を新しい連番に置換する
    def _replace_bracket(m: re.Match) -> str:
        inner = m.group(1)
        valid_news = []
        for num_str in re.findall(r"\d+", inner):
            try:
                old_idx = int(num_str)
                if old_idx in old_to_new:
                    new_idx = old_to_new[old_idx]
                    if new_idx not in valid_news:
                        valid_news.append(new_idx)
            except ValueError:
                continue

        if not valid_news:
            return ""

        valid_news.sort()
        return f"⟦{', '.join(str(n) for n in valid_news)}⟧"

    renumbered_body = bracket_pattern.sub(_replace_bracket, body)
    return renumbered_body, sources


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

        search_text, url_by_index = _format_search_results_for_prompt(search_results)

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

        output_json = res.output_json
        raw_body = output_json.get("body", "") if isinstance(output_json, dict) else ""
        renumbered_body, sources = _renumber_citations_and_extract_sources(raw_body, url_by_index)
        if isinstance(output_json, dict):
            output_json["body"] = renumbered_body
        self.logger.log(f"   [Logic] Extracted {len(sources)} cited source URL(s) from body.")

        return self._validate_and_normalize_output(output_json, sources)

    def _validate_and_normalize_output(self, output: Any, sources: List[str]) -> Dict[str, Any]:
        if not isinstance(output, dict):
            raise ValueError("Fun Fact output must be a JSON object.")

        required_keys = ["title", "hook", "body"]
        missing_keys = [key for key in required_keys if key not in output]
        if missing_keys:
            raise ValueError(f"Fun Fact output is missing keys: {missing_keys}")

        for key in required_keys:
            value = output.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"Fun Fact field '{key}' must be a non-empty string.")

        # パースされた安全なURLリストを sources に設定
        output["sources"] = sources
        return output
