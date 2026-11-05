"""
Review Cards のプロンプトキャッシュ版 (v4) — 本番に入れる前の実験用。

本番 ReviewCardGenerationService との違いはプロンプトの組み立てだけ:
  - system: 固定の指示 (講義ごとに決まる言語指示を含む) + cache_control (5分 ephemeral)
  - user:   毎回変わる入力 (次トピック・キーワード・文字起こし・前回講義) と、最初/最後のトピック専用の指示
トピックの抽出・文のフィルタ・モデル/オプション・カード枚数チェックは本番のまま。
"""
import asyncio
from pathlib import Path
from typing import Any, Dict, List

from app.core.r2_storage import storage_service
from app.services.helpers.helpers import (
    _build_bilingual_gloss_instruction,
    _get_previous_lecture_topics,
    _render_conditional_sections,
    _sid_to_int,
)
from app.services.helpers.llm_unified import LLMOptions, Message
from app.services.logic import review_card_generation as rc

PROMPT_DIR = Path(__file__).resolve().parent / "prompts" / "v4"


class CachedReviewCardGenerationService(rc.ReviewCardGenerationService):
    async def run_from_memory(self, role_classified_data, core_data, uid, lecture_id,
                              content_language="English", transcript_language="English",
                              is_bilingual=False) -> List[Dict[str, Any]]:
        system_template = (PROMPT_DIR / "review_cards_generation_prompt.txt").read_text(encoding="utf-8")
        user_template = (PROMPT_DIR / "review_cards_generation_user_prompt.txt").read_text(encoding="utf-8")
        # 講義内の全トピックで同じ文字列になる → 2トピック目以降はキャッシュから読まれる
        system_text = system_template.replace(
            "${LANGUAGE_INSTRUCTIONS}",
            _build_bilingual_gloss_instruction(content_language, transcript_language, is_bilingual),
        )
        options_json = LLMOptions(output_type="json", reasoning_effort="low",
                                  max_tokens=rc.REVIEW_CARD_MAX_TOKENS, json_schema=rc.REVIEW_CARD_SCHEMA)

        results, failed = [], []
        academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]
        last_position = len(academic_topics) - 1
        for position, topic in enumerate(academic_topics):
            topic_idx, topic_title = topic.get("idx"), topic.get("title")
            is_final_topic, is_first_topic = position == last_position, position == 0
            cache_path = f"{uid}/{lecture_id}/pipeline_cache/review_cards_topic_{topic_idx}.json"
            cached = await asyncio.to_thread(storage_service.load_json_cache, cache_path)
            if cached is not None:
                results.append(cached)
                continue
            start_num = _sid_to_int(topic.get("start_sid")) if isinstance(topic.get("start_sid"), str) else None
            end_num = _sid_to_int(topic.get("end_sid")) if isinstance(topic.get("end_sid"), str) else None
            if start_num is None or end_num is None:
                continue
            lines = []
            for s in role_classified_data:
                n = _sid_to_int(s.get("sid"))
                if n is None or not (start_num <= n <= end_num):
                    continue
                probs = s.get("all_probabilities")
                if not probs:
                    if s.get("role") in ["CONTENT", "INTERACTION"]:
                        lines.append(f"{s['sid']}: {s['text']}")
                    continue
                if probs.get("CONTENT", 0.0) >= 0.10 or probs.get("INTERACTION", 0.0) >= 0.50:
                    lines.append(f"{s['sid']}: {s['text']}")
            if not lines:
                results.append({"topic_idx": topic_idx, "review_cards": []})
                continue

            if is_final_topic:
                next_ctx = "This is the final topic of today's lecture. There is no next topic."
                lecture_topics_text = rc._format_lecture_topics(academic_topics)
            else:
                next_ctx = rc._format_topic_context(academic_topics[position + 1])
                lecture_topics_text = ""
            prev = await asyncio.to_thread(_get_previous_lecture_topics, lecture_id) if is_first_topic else []
            show_prev = bool(prev)
            kws = rc._keyword_strings(topic)

            user_text = _render_conditional_sections(user_template, {"FINAL_TOPIC": is_final_topic,
                                                                    "FIRST_TOPIC": show_prev})
            user_text = (
                user_text
                .replace("${CURRENT_TOPIC_KEYWORDS}", "\n".join(f"- {k}" for k in kws) if kws else "N/A")
                .replace("${NEXT_TOPIC_CONTEXT}", next_ctx)
                .replace("${LECTURE_TOPICS}", lecture_topics_text)
                .replace("${PREVIOUS_LECTURE_CONTEXT}", rc._format_previous_lecture_topics(prev) if show_prev else "")
                .replace("${TRANSCRIPT_SEGMENT}", "\n".join(lines))
                .replace("${TOPIC_TITLE}", topic_title or "")
                .replace("${CONTENT_LANGUAGE}", content_language)
            )
            messages = [
                Message(role="system", content=system_text, cache_control={"type": "ephemeral"}),
                Message(role="user", content=user_text),
            ]
            res = await self.llm.generate(model=self.model_alias, messages=messages, options=options_json)
            if not res.json_parse_error and res.output_json and rc._has_expected_cards(res.output_json):
                out = res.output_json
                out["topic_idx"] = topic_idx
                await asyncio.to_thread(storage_service.save_json_cache, cache_path, out)
                results.append(out)
            else:
                failed.append(topic_idx)
        if failed:
            raise ValueError(f"Review Card generation failed for topics {failed}")
        return results
