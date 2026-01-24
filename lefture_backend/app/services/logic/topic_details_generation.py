import json
import time
import asyncio
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial

from app.services.helpers.llm_unified import LLMOptions, CostCollector, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, _strip_code_fence, token_report_from_result, print_log

class TopicDetailGenerationService:
    def __init__(self, llm: UnifiedLLM, collector: CostCollector):
        self.llm = llm
        self.collector = collector
        self.model_alias = "2_5_flash"

    async def run(self, segments_path: Path, sentences_path: Path, work_dir: Path) -> list[Path]:
        print_log(f"   [Logic] Starting topic_detail_generation")
        
        # ユーザー指定のファイル名
        prompt = _load_prompt("topic_details_generation_prompt.txt")
        options_text = LLMOptions(output_type="text", temperature=0.2)

        try:
            await asyncio.to_thread(
                self._generate_all_details,
                llm=self.llm,
                model_alias=self.model_alias,
                options_text=options_text,
                work_dir=work_dir,
                segments_path=segments_path,
                sentences_path=sentences_path,
                prompt=prompt
            )
        except Exception as e:
            print_log(f"⚠️ Topic Details Logic Error: {e}")
            import traceback
            traceback.print_exc()

        output_json = work_dir / "segments_with_details.json"
        
        if not output_json.exists():
            print_log(f"[WARN] Topic details generation failed. {output_json} not found.")
            return []

        print_log(f"   [Logic] Topic details finished: {output_json.name}")
        return [output_json]

    def _slice_by_sid(self, sentences, start_sid=None, end_sid=None):
        if isinstance(sentences, dict):
            seq = sorted(sentences.values(), key=lambda s: s.get("sid", ""))
        else:
            seq = list(sentences)
        if not seq:
            return []

        sid_to_idx = {}
        for i, s in enumerate(seq):
            sid = s.get("sid")
            if sid is not None and sid not in sid_to_idx:
                sid_to_idx[sid] = i

        if start_sid is None:
            i0 = 0
        else:
            if start_sid not in sid_to_idx:
                print_log(f"[WARN] start_sid {start_sid} not found, using 0")
                i0 = 0
            else:
                i0 = sid_to_idx[start_sid]

        if end_sid is None:
            i1 = len(seq) - 1
        else:
            if end_sid not in sid_to_idx:
                print_log(f"[WARN] end_sid {end_sid} not found, using last")
                i1 = len(seq) - 1
            else:
                i1 = sid_to_idx[end_sid]

        if i0 > i1:
            i0, i1 = i1, i0

        # add context window (+/- 20 sentences) ※元のコードの仕様
        i0 = max(0, i0 - 20)
        i1 = min(len(seq) - 1, i1 + 20)

        return seq[i0 : i1 + 1]

    def _generate_all_details(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options_text: LLMOptions,
        work_dir: Path,
        segments_path: Path,
        sentences_path: Path,
        prompt: str
    ):
        print_log("\n### Topic Detail Generation (JSON) ###")
        start_time = time.time()

        if not segments_path.exists() or not sentences_path.exists():
            raise FileNotFoundError("Input files not found")

        try:
            segments_obj = json.loads(segments_path.read_text(encoding="utf-8"))
            sentences_data = json.loads(sentences_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            raise ValueError(f"Failed to load JSON inputs: {e}")

        # リスト探索ロジック
        segments_list = []
        if isinstance(segments_obj, list):
            segments_list = segments_obj
        elif isinstance(segments_obj, dict):
            for key in ["topics", "segments", "results", "items"]:
                if key in segments_obj and isinstance(segments_obj[key], list):
                    segments_list = segments_obj[key]
                    break
            if not segments_list:
                for k, v in segments_obj.items():
                    if isinstance(v, list) and len(v) > 0:
                        segments_list = v
                        break
        
        if not segments_list:
            print_log(f"[ERROR] Could not find any segment list.")
            return 
        
        print_log(f"Generating details for {len(segments_list)} topics...")

        tasks = []
        # 元のコードに合わせて必要なフィールドだけ抽出
        ALLOWED = ["sid", "text", "role"] 
        projected_sentences = [{k: s.get(k) for k in ALLOWED} for s in sentences_data]

        for i, seg in enumerate(segments_list):
            # idx, title, start_sid, end_sid を取得
            # 元のコードは seg["idx"] を使っていたが、なければ i+1
            idx = seg.get("idx", i + 1)
            title = seg.get("title") or seg.get("topic_title") or f"Topic {idx}"
            start_sid = seg.get("start_sid")
            end_sid = seg.get("end_sid")

            # スライシング実行 (リストのオブジェクトのまま取得)
            partial_sentences = self._slice_by_sid(projected_sentences, start_sid, end_sid)

            tasks.append({
                "index": i,
                "topic_segment": seg, # segment情報丸ごと
                "partial_sentences": partial_sentences # 抽出したリスト(dictの配列)
            })

        max_workers = 3 # 元のコードに合わせて 3
        with ThreadPoolExecutor(max_workers=max_workers) as ex:
            fn = partial(
                self._generate_one_detail,
                llm, model_alias, options_text, prompt,
            )
            futures = {ex.submit(fn, task): task["index"] for task in tasks}

            for fut in as_completed(futures):
                idx = futures[fut]
                try:
                    markdown_content = fut.result()
                    segments_list[idx]["detail_content"] = markdown_content
                except Exception as e:
                    print_log(f"❌ Failed to generate detail for index {idx}: {e}")
                    segments_list[idx]["detail_content"] = "" 

        output_path = work_dir / "segments_with_details.json"
        final_obj = {"segments": segments_list}
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(final_obj, f, ensure_ascii=False, indent=2)

        elapsed = time.time() - start_time
        print_log(f"⏰Generated all topic details: {elapsed:.2f} seconds.")

    def _generate_one_detail(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options: LLMOptions,
        prompt_tmpl: str,
        task: dict
    ) -> str:
        segment = task["topic_segment"]
        partial_transcript = task["partial_sentences"]

        payload = {
            "task": "Topic Detail Generation",
            "instruction": prompt_tmpl,
            "data": {
                "topic": segment,
                "partial-transcript": partial_transcript,
            },
        }

        # メッセージ構成
        messages = [
            Message(
                role="system",
                content="You are a careful lecture note generator. Follow the instructions strictly and keep the professor's nuance.",
            ),
            Message(
                role="user",
                content=json.dumps(payload, ensure_ascii=False),
            ),
        ]

        print_log(f"   ... generating detail for: {segment.get('title', 'Unknown')}")
        res = llm.generate(model_alias, messages, options)
        
        content = _strip_code_fence(res.output_text)
        print_log(token_report_from_result("Topic Details Generation", res, self.collector))
        return content