import json
import time
import asyncio
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial

from app.services.helpers.llm_unified import LLMOptions, CostCollector, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, _strip_code_fence, token_report_from_result, print_log

class FunFactGenerationService:
    def __init__(self, llm: UnifiedLLM, collector: CostCollector):
        self.llm = llm
        self.collector = collector
        self.model_alias = "2_5_flash"

    async def run(self, work_dir: Path, segments_with_details_path: Path) -> list[Path]:
        print_log(f"   [Logic] Starting fun_fact_generation")
        
        # ユーザー指定のファイル名
        prompt = _load_prompt("fun_fact_generation_prompt.txt")
        options_text = LLMOptions(output_type="text", temperature=0.2) # 元コードの設定

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
            print_log(f"⚠️ Fun Facts Logic Error: {e}")
            import traceback
            traceback.print_log_exc()

        output_json = work_dir / "lecture_complete_data.json"
        
        if not output_json.exists():
            print_log(f"[WARN] Fun facts generation failed. {output_json} not found.")
            return []

        print_log(f"   [Logic] Fun facts finished: {output_json.name}")
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
        print_log("\n### Fun Fact Generation (JSON) ###")
        start_time = time.time()

        if not segments_with_details_path.exists():
            raise FileNotFoundError(f"segments_with_details.json not found")
        
        data_obj = json.loads(segments_with_details_path.read_text(encoding="utf-8"))
        segments_list = data_obj.get("segments", []) if isinstance(data_obj, dict) else data_obj

        print_log(f"Generating fun facts for {len(segments_list)} topics...")

        tasks = []
        for i, seg in enumerate(segments_list):
            detail_content = seg.get("detail_content", "")
            title = seg.get("title") or seg.get("topic_title") or ""
            
            if not detail_content:
                print_log(f"   [Skip] No detail content for topic {i}")
                continue

            tasks.append({
                "index": i,
                "title": title,
                "detail_content": detail_content
            })

        max_workers = 3
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
                    segments_list[idx]["fun_fact"] = fun_fact_text
                except Exception as e:
                    print_log(f"❌ Failed to generate fun fact for index {idx}: {e}")
                    segments_list[idx]["fun_fact"] = ""

        output_path = work_dir / "lecture_complete_data.json"
        final_obj = {"segments": segments_list}
        
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(final_obj, f, ensure_ascii=False, indent=2)

        elapsed = time.time() - start_time
        print_log(f"⏰Generated all fun facts: {elapsed:.2f} seconds.")

    def _generate_one_fun_fact(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options: LLMOptions,
        prompt_tmpl: str,
        task: dict
    ) -> str:
        # 元のコードでは system に prompt、user に markdown を渡していた
        topic_details_markdown = task["detail_content"]
        
        messages = [
            Message(role="system", content=prompt_tmpl),
            Message(role="user", content=topic_details_markdown),
            Message(
                role="user",
                content="Using the text provided above, follow the instructions and return the result in markdown text.",
            ),
        ]

        print_log(f"   ... fun fact for: {task['title']}")
        res = llm.generate(model_alias, messages, options)
        print_log(token_report_from_result("Fun Facts Generation", res, self.collector))
        return _strip_code_fence(res.output_text)