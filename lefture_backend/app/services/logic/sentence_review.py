import os
import re
from pathlib import Path
from collections import defaultdict
from groq import Groq
from nltk.tokenize import sent_tokenize

from app.services.helpers.helpers import print_log

class SentenceReviewService:
    def __init__(self):
        self.client = Groq()
        self.model = "openai/gpt-oss-120b"
        
        # プロンプトファイルのパス解決 (logicディレクトリの1つ上のpromptディレクトリ)
        self.prompt_path = Path(__file__).parent.parent / "prompt" / "sentence_review_prompt.txt"

    def _load_prompt_template(self) -> str:
        if not self.prompt_path.exists():
            raise FileNotFoundError(f"Prompt file not found at {self.prompt_path}")
        with open(self.prompt_path, "r", encoding="utf-8") as f:
            return f.read()

    def run(self, chunks_to_review: list, previous_chunk: dict = None, course_title: str = "", keywords_list: str = "") -> list:
        """
        4つ溜まったチャンク（未校正）を受け取り、LLMで文脈・句読点を修正して返す。
        """
        print_log(f"🧠 [Sentence Review] Starting review for {len(chunks_to_review)} chunks...")

        # ==========================================
        # 1. データの準備（LLMに投げるテキストの構築）
        # ==========================================
        orig_map = {}
        target_xml = ""
        
        # 前回のチャンクの最後の一部
        if previous_chunk and previous_chunk.get("segments"):
            last_segs = previous_chunk["segments"][-3:]
            for seg in last_segs:
                sid = seg["sid"]
                orig_map[sid] = seg
                target_xml += f"<{sid}>{seg['text']}</{sid}>"

        # 今回の修正対象チャンクを追加
        for chunk in chunks_to_review:
            for seg in chunk.get("segments", []):
                sid = seg["sid"]
                orig_map[sid] = seg
                target_xml += f"<{sid}>{seg['text']}</{sid}>"

        # ==========================================
        # 2. プロンプトの生成と LLM 呼び出し
        # ==========================================
        prompt_template = self._load_prompt_template()
        prompt = prompt_template.format(
            course_title=course_title,
            keywords_list=keywords_list,
            target_xml_text=target_xml
        )

        print_log(f"   [LLM] Calling Groq API ({self.model})...")
        response = self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "user", "content": prompt}
            ],
            temperature=0.1 # フォーマット遵守のため低めに設定
        )
        llm_output = response.choices[0].message.content

        # ==========================================
        # 3. LLM出力の堅牢なパース (フェイルセーフ設計)
        # ==========================================
        # おしゃべりやマークダウン(```xml)を無視し、純粋にタグの中身だけを抽出
        matches = re.findall(r'<s(\d{6})>(.*?)</s\1>', llm_output, re.DOTALL)
        parsed_dict = {f"s{sid}": text.strip() for sid, text in matches}

        merged_segments = []
        last_non_empty_seg = None

        # 元のSIDの順番通りに処理する（LLMがタグを消したり順番を狂わせても無視して安全に処理する）
        for sid in orig_map.keys():
            text = parsed_dict.get(sid, "")
            orig_seg = orig_map[sid]

            if text:
                # テキストが入っている場合、新しいセグメントとして追加
                new_seg = {
                    "text": text,
                    "start": orig_seg["start"],
                    "end": orig_seg["end"],
                    "chunk_index": orig_seg["chunk_index"],
                    "confidence": orig_seg["confidence"]
                }
                
                # もし最初のタグが空にされてしまっていた場合の救済措置
                if not merged_segments and orig_seg["start"] > orig_map[list(orig_map.keys())[0]]["start"]:
                    new_seg["start"] = orig_map[list(orig_map.keys())[0]]["start"]

                merged_segments.append(new_seg)
                last_non_empty_seg = new_seg
            else:
                # LLMが空にした（前のタグに吸収させた）場合、時間を前のタグに結合(マージ)する
                if last_non_empty_seg is not None:
                    last_non_empty_seg["end"] = max(last_non_empty_seg["end"], orig_seg["end"])

        # ==========================================
        # 4. NLTKによる複数文の分割とタイムスタンプ按分
        # ==========================================
        final_segments = []
        for seg in merged_segments:
            sentences = sent_tokenize(seg["text"])
            sentences = [s.strip() for s in sentences if s.strip()]

            if not sentences:
                continue

            if len(sentences) == 1:
                final_segments.append(seg)
            else:
                # 複数文入っていた場合、文字数ベースでタイムスタンプを計算（Proportional interpolation）
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

        # ==========================================
        # 5. SIDの再採番と、チャンクごとの再梱包
        # ==========================================
        updated_chunks_dict = defaultdict(lambda: {"segments": [], "text": ""})
        counters = defaultdict(int)

        for seg in final_segments:
            c_idx = seg["chunk_index"]
            counters[c_idx] += 1
            # SIDを綺麗に付け直す
            seg["sid"] = f"s{c_idx:03d}{counters[c_idx]:03d}"
            
            updated_chunks_dict[c_idx]["segments"].append(seg)
            # そのチャンクの全文(text)も結合して更新しておく
            updated_chunks_dict[c_idx]["text"] += seg["text"] + " "

        # リストの形に戻して返す
        result_chunks = []
        for c_idx in sorted(updated_chunks_dict.keys()):
            updated_chunks_dict[c_idx]["text"] = updated_chunks_dict[c_idx]["text"].strip()
            updated_chunks_dict[c_idx]["chunk_index"] = c_idx
            result_chunks.append(updated_chunks_dict[c_idx])

        print_log(f"✅ [Sentence Review] Review completed perfectly. Ready to update DB.")
        return result_chunks