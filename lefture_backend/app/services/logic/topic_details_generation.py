import json
import asyncio
from typing import Any, Dict, List
from app.core.r2_storage import storage_service
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, TaskLogger, _sid_to_int

class TopicDetailGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "gemini/gemini-2.5-flash"

    async def run_from_memory(
        self, 
        role_classified_data: List[Dict[str, Any]], 
        core_data: Dict[str, Any],
        uid: str,
        lecture_id: str
    ) -> List[Dict[str, Any]]:
        self.logger.log(f"   [Logic] Starting Topic Detail Generation")
        
        prompt_template = _load_prompt("topic_details_generation_prompt.txt")
        options_text = LLMOptions(output_type="text", temperature=0.2)
        
        all_details = []

        # ACADEMIC なトピックだけを抽出
        academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]

        failed_topic_indices = []

        for topic in academic_topics:
            topic_idx = topic.get("idx")
            topic_title = topic.get("title")

            # ① R2キャッシュ確認 (リトライ時はここでスキップ)
            cache_path = f"{uid}/{lecture_id}/pipeline_cache/detail_contents_topic_{topic_idx}.json"
            cached = await asyncio.to_thread(storage_service.load_json_cache, cache_path)
            if cached is not None:
                self.logger.log(f"   [Cache] Topic {topic_idx}: loaded from R2 cache, skipping LLM.")
                all_details.append(cached)
                continue

            start_sid = topic.get("start_sid")
            end_sid = topic.get("end_sid")

            start_num = _sid_to_int(start_sid) if isinstance(start_sid, str) else None
            end_num = _sid_to_int(end_sid) if isinstance(end_sid, str) else None
            if start_num is None or end_num is None:
                continue

            # BUFFER = 20 の文脈付きで抽出する
            BUFFER = 20
            context_start_num = max(1, start_num - BUFFER)
            context_end_num = end_num + BUFFER

            segment_sentences = []
            for s in role_classified_data:
                sid = s.get("sid", "")
                sid_num = _sid_to_int(sid)
                if sid_num is None:
                    self.logger.log(f"⚠️ Invalid SID in role_classified_data: {sid}")
                    continue

                if context_start_num <= sid_num <= context_end_num:
                    segment_sentences.append({
                        **s,
                        "_sid_num": sid_num,
                        "_scope": "topic" if start_num <= sid_num <= end_num else "context"
                    })

            if not segment_sentences:
                empty_res = {"topic_idx": topic_idx, "content": ""}
                await asyncio.to_thread(storage_service.save_json_cache, cache_path, empty_res)
                all_details.append(empty_res)
                continue

            # 💡 確率ベースでフィルタリング (CONTENTS 10%以上 OR INTERACTION 50%以上)
            trimmed_lines = []
            for s in segment_sentences:
                probs = s.get("all_probabilities")
                
                if not probs:
                    if s.get("role") in ["CONTENT", "INTERACTION"]:
                        trimmed_lines.append(f"{s['sid']} [{s['_scope']}]: {s['text']}")
                    continue
                
                content_prob = probs.get("CONTENT", 0.0)
                interaction_prob = probs.get("INTERACTION", 0.0)
                
                if content_prob >= 0.10 or interaction_prob >= 0.50:
                    trimmed_lines.append(f"{s['sid']} [{s['_scope']}]: {s['text']}")

            if not trimmed_lines:
                self.logger.log(f"   [Logic] Skipping Topic Detail {topic_idx} (No valid sentences)")
                empty_res = {"topic_idx": topic_idx, "content": ""}
                await asyncio.to_thread(storage_service.save_json_cache, cache_path, empty_res)
                all_details.append(empty_res)
                continue

            trimmed_transcript = "\n".join(trimmed_lines)
            self.logger.log(f"   [Logic] Generating detail contents for Topic {topic_idx}: {topic_title}")

            messages = [
                Message(role="system", content=prompt_template),
                Message(role="user", content=(
                    f"Topic segment:\n{json.dumps(topic, ensure_ascii=False)}\n\n"
                    f"Partial transcript with scope markers:\n{trimmed_transcript}\n\n"
                    "Use [topic] lines as the primary content. "
                    "Use [context] lines only when they clarify the topic."
                ))
            ]

            res = await self.llm.generate(model=self.model_alias, messages=messages, options=options_text)
            
            # Markdownのテキスト結果をリストに保存
            if res.output_text:
                detail = {
                    "topic_idx": topic_idx,
                    "content": res.output_text
                }
                # ③ 成功したらR2にキャッシュ保存
                await asyncio.to_thread(storage_service.save_json_cache, cache_path, detail)
                all_details.append(detail)
            else:
                self.logger.log(
                    f"❌ Failed to generate detail contents for Topic {topic_idx}: {topic_title}. "
                    f"Output text was empty or failed."
                )
                failed_topic_indices.append(topic_idx)

        # ④ 失敗があれば例外を送出する
        if failed_topic_indices:
            raise ValueError(
                f"Detail Contents generation failed for {len(failed_topic_indices)} topic(s): "
                f"indices={failed_topic_indices}. "
                f"Successfully cached {len(all_details)} topic(s). "
                f"Retry will skip cached topics."
            )

        return all_details