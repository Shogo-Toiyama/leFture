import re
from collections import defaultdict
from nltk.tokenize import sent_tokenize

from app.services.helpers.helpers import _load_prompt, TaskLogger
from app.services.helpers.llm_unified import UnifiedLLM, Message, LLMOptions

class SentenceReviewService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        # LiteLLM 経由で呼び出すモデル
        self.model_alias = "groq/openai/gpt-oss-120b" 

    async def run_from_memory(self, chunks_to_review: list, previous_chunk: dict = None, course_title: str = "", keywords_list: str = "") -> list:
        self.logger.log(f"🧠 [Sentence Review] Starting review for {len(chunks_to_review)} chunks...")

        orig_map = {}
        target_xml = ""
        
        # 前回のチャンク
        if previous_chunk and previous_chunk.get("segments"):
            prev_start_time = previous_chunk.get("start_time")
            if prev_start_time is None:
                raise ValueError(f"CRITICAL: prev_chunk (index={previous_chunk.get('chunk_index')}) is missing start_time. Cannot calculate absolute timestamps.")
            last_segs = previous_chunk["segments"][-3:]
            for seg in last_segs:
                sid = seg["sid"]
                orig_map[sid] = {
                    "text": seg["text"],
                    "start": seg["start"] + prev_start_time,
                    "end": seg["end"] + prev_start_time,
                    "chunk_index": previous_chunk.get("chunk_index"),
                    "confidence": seg.get("confidence", 0.99)
                }
                target_xml += f"<{sid}>{seg['text']}</{sid}>"

        # 今回のチャンク
        for chunk in chunks_to_review:
            chunk_start_time = chunk.get("start_time")
            if chunk_start_time is None:
                raise ValueError(f"CRITICAL: chunk (index={chunk.get('chunk_index')}) is missing start_time. Cannot calculate absolute timestamps.")
            for seg in chunk.get("segments", []):
                sid = seg["sid"]
                orig_map[sid] = {
                    "text": seg["text"],
                    "start": seg["start"] + chunk_start_time,
                    "end": seg["end"] + chunk_start_time,
                    "chunk_index": chunk.get("chunk_index"),
                    "confidence": seg.get("confidence", 0.99)
                }
                target_xml += f"<{sid}>{seg['text']}</{sid}>"

        # プロンプト生成
        prompt_template = _load_prompt("sentence_review_prompt.txt")
        prompt = prompt_template.format(
            course_title=course_title,
            keywords_list=keywords_list,
            target_xml_text=target_xml
        )

        self.logger.log(f"   [LLM] Calling LiteLLM API ({self.model_alias})...")
        
        messages = [Message(role="user", content=prompt)]
        options = LLMOptions(temperature=0.2)
        
        # 💡 UnifiedLLM を使って非同期実行！
        res = await self.llm.generate(model=self.model_alias, messages=messages, options=options)
        llm_output = res.output_text

        # パース処理 (元のロジックのまま)
        matches = re.findall(r'<s(\d{6})>(.*?)</s\1>', llm_output, re.DOTALL)
        parsed_dict = {f"s{sid}": text.strip() for sid, text in matches}

        merged_segments = []
        last_non_empty_seg = None

        for sid in orig_map.keys():
            text = parsed_dict.get(sid, "")
            orig_seg = orig_map[sid]

            if text:
                new_seg = {
                    "text": text,
                    "start": orig_seg["start"],
                    "end": orig_seg["end"],
                    "chunk_index": orig_seg["chunk_index"],
                    "confidence": orig_seg["confidence"]
                }
                
                if not merged_segments and orig_seg["start"] > orig_map[list(orig_map.keys())[0]]["start"]:
                    new_seg["start"] = orig_map[list(orig_map.keys())[0]]["start"]

                merged_segments.append(new_seg)
                last_non_empty_seg = new_seg
            else:
                if last_non_empty_seg is not None:
                    last_non_empty_seg["end"] = max(last_non_empty_seg["end"], orig_seg["end"])

        # NLTK分割
        final_segments = []
        for seg in merged_segments:
            sentences = sent_tokenize(seg["text"])
            sentences = [s.strip() for s in sentences if s.strip()]

            if not sentences:
                continue

            if len(sentences) == 1:
                final_segments.append(seg)
            else:
                total_chars = sum(len(s) for s in sentences)
                total_duration = seg["end"] - seg["start"]
                
                curr_start = seg["start"]
                for s in sentences:
                    ratio = len(s) / total_chars if total_chars > 0 else 0
                    dur = total_duration * ratio
                    
                    final_segments.append({
                        "text": s,
                        "start": round(curr_start, 3),
                        "end": round(curr_start + dur, 3),
                        "chunk_index": seg["chunk_index"],
                        "confidence": seg["confidence"]
                    })
                    curr_start += dur

        updated_chunks_dict = defaultdict(lambda: {"segments": [], "text": ""})
        counters = defaultdict(int)

        for chunk in chunks_to_review:
            c_idx = chunk["chunk_index"]
            updated_chunks_dict[c_idx] = {"segments": [], "text": "", "chunk_index": c_idx}

        for seg in final_segments:
            c_idx = seg["chunk_index"]
            counters[c_idx] += 1
            seg["sid"] = f"s{c_idx:03d}{counters[c_idx]:03d}"
            
            updated_chunks_dict[c_idx]["segments"].append(seg)
            updated_chunks_dict[c_idx]["text"] += seg["text"] + " "

        result_chunks = []
        for c_idx in sorted(updated_chunks_dict.keys()):
            updated_chunks_dict[c_idx]["text"] = updated_chunks_dict[c_idx]["text"].strip()
            updated_chunks_dict[c_idx]["chunk_index"] = c_idx
            result_chunks.append(updated_chunks_dict[c_idx])

        self.logger.log(f"✅ [Sentence Review] Review completed perfectly.")
        return result_chunks