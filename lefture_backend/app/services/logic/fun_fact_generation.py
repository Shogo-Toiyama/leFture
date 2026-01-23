import json
import time
import asyncio
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial

from app.services.helpers.llm_unified import LLMOptions, CostCollector, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, _strip_code_fence, token_report_from_result

class FunFactGenerationService:
    def __init__(self, llm: UnifiedLLM, collector: CostCollector):
        self.llm = llm
        self.collector = collector
        self.model_alias = "2_5_flash"

    async def run(self, work_dir: Path, segments_with_details_path: Path) -> list[Path]:
        print(f"   [Logic] Starting fun_fact_generation (JSON Mode)")
        
        prompt = _load_prompt("fun_facts_generation_prompt.txt")
        options_text = LLMOptions(output_type="text", temperature=0.7)

        try:
            await asyncio.to_thread(
                self._generate_all_fun_facts,
                llm=self.llm,
                model_alias=self.model_alias,
                options_text=options_text,
                work_dir=work_dir,
                segments_with_details_path=segments_with_details_path,
                prompt=prompt
            )
        except Exception as e:
            print(f"⚠️ Fun Facts Logic Error: {e}")
            import traceback
            traceback.print_exc()

        # 成果物: 完全版JSON
        output_json = work_dir / "lecture_complete_data.json"
        
        if not output_json.exists():
            print(f"[WARN] Fun facts generation failed. {output_json} not found.")
            return []

        print(f"   [Logic] Fun facts finished: {output_json.name}")
        return [output_json]

    def _generate_all_fun_facts(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options_text: LLMOptions,
        work_dir: Path,
        segments_with_details_path: Path,
        prompt: str
    ):
        print("\n### Fun Fact Generation (JSON) ###")
        start_time = time.time()

        # 前のステップのJSON (segments_with_details.json) を探す
        input_json_path = segments_with_details_path
        if not input_json_path.exists():
            raise FileNotFoundError(f"segments_with_details.json not found at {segments_with_details_path}")
        
        data_obj = json.loads(input_json_path.read_text(encoding="utf-8"))
        segments_list = data_obj.get("segments", []) if isinstance(data_obj, dict) else data_obj

        print(f"Generating fun facts for {len(segments_list)} topics...")

        tasks = []
        for i, seg in enumerate(segments_list):
            # 詳細解説のMarkdownがあればそれを使う、なければタイトルだけ
            detail_content = seg.get("detail_content", "")
            title = seg.get("topic_title", "")
            
            if not detail_content:
                print(f"   [Skip] No detail content for topic {i}")
                continue

            tasks.append({
                "index": i,
                "title": title,
                "detail_content": detail_content
            })

        max_workers = 5
        with ThreadPoolExecutor(max_workers=max_workers) as ex:
            fn = partial(
                self._generate_one_fun_fact,
                llm, model_alias, options_text, prompt, self.collector
            )
            futures = {ex.submit(fn, task): task["index"] for task in tasks}

            for fut in as_completed(futures):
                idx = futures[fut]
                try:
                    fun_fact_text = fut.result()
                    # 豆知識をリストに追加！
                    segments_list[idx]["fun_fact"] = fun_fact_text
                except Exception as e:
                    print(f"❌ Failed to generate fun fact for index {idx}: {e}")
                    segments_list[idx]["fun_fact"] = ""

        # 最終保存
        output_path = work_dir / "lecture_complete_data.json"
        final_obj = {"segments": segments_list}
        
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(final_obj, f, ensure_ascii=False, indent=2)

        elapsed = time.time() - start_time
        print(f"⏰Generated all fun facts (JSON): {elapsed:.2f} seconds.")

    def _generate_one_fun_fact(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options: LLMOptions,
        prompt_tmpl: str,
        collector: CostCollector,
        task: dict
    ) -> str:
        content = task["detail_content"]
        
        messages = [
            Message(role="system", content=prompt_tmpl),
            Message(role="user", content=f"Here is the topic detail:\n{content}")
        ]

        # print(f"   ... fun fact for: {task['title']}")
        res = llm.generate(model_alias, messages, options)
        
        return _strip_code_fence(res.output_text)