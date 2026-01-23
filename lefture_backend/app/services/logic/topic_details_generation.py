import json
import time
import asyncio
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial

from app.services.helpers.llm_unified import LLMOptions, CostCollector, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, _strip_code_fence, token_report_from_result

class TopicDetailGenerationService:
    def __init__(self, llm: UnifiedLLM, collector: CostCollector):
        self.llm = llm
        self.collector = collector
        self.model_alias = "2_5_flash"

    async def run(self, segments_path: Path, sentences_path: Path, work_dir: Path) -> list[Path]:
        print(f"   [Logic] Starting topic_detail_generation (JSON Mode)")
        
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
            print(f"⚠️ Topic Details Logic Error: {e}")
            # エラー時もログを出して続行（Pipeline側で検知させるならraiseしても良い）
            import traceback
            traceback.print_exc()

        # 成果物: JSONファイル1つ
        output_json = work_dir / "segments_with_details.json"
        
        if not output_json.exists():
            print(f"[WARN] Topic details generation failed. {output_json} not found.")
            return []

        print(f"   [Logic] Topic details finished: {output_json.name}")
        return [output_json]

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
        print("\n### Topic Detail Generation (JSON) ###")
        start_time = time.time()

        if not segments_path.exists() or not sentences_path.exists():
            raise FileNotFoundError("Input files not found")

        # データを読み込み
        segments_obj = json.loads(segments_path.read_text(encoding="utf-8"))
        sentences_data = json.loads(sentences_path.read_text(encoding="utf-8"))
        
        # "segments" キーの中にリストが入っている構造を想定
        # もし segments.json がリスト直下なら segments_list = segments_obj とする
        segments_list = segments_obj.get("segments", []) if isinstance(segments_obj, dict) else segments_obj
        
        print(f"Generating details for {len(segments_list)} topics...")

        tasks = []
        for i, seg in enumerate(segments_list):
            topic_title = seg.get("topic_title", f"Topic {i+1}")
            start_sid = seg.get("start_sid")
            end_sid = seg.get("end_sid")
            
            # テキスト抽出ロジック
            # (簡易的にインデックス検索。sentencesがソートされている前提)
            start_idx = next((k for k, s in enumerate(sentences_data) if s["sid"] == start_sid), 0)
            end_idx = next((k for k, s in enumerate(sentences_data) if s["sid"] == end_sid), len(sentences_data)-1)
            
            chunk_sentences = sentences_data[start_idx : end_idx + 1]
            source_text = "\n".join([s["text"] for s in chunk_sentences if s.get("text")])

            tasks.append({
                "index": i, # リストのインデックスを保持
                "title": topic_title,
                "source_text": source_text
            })

        # 並列実行用辞書: {future: task_index}
        results_map = {}

        max_workers = 5
        with ThreadPoolExecutor(max_workers=max_workers) as ex:
            fn = partial(
                self._generate_one_detail,
                llm, model_alias, options_text, prompt, self.collector
            )
            # submit
            futures = {ex.submit(fn, task): task["index"] for task in tasks}

            for fut in as_completed(futures):
                idx = futures[fut]
                try:
                    markdown_content = fut.result()
                    # 生成されたマークダウンを元のリストに追加！
                    segments_list[idx]["detail_content"] = markdown_content
                except Exception as e:
                    print(f"❌ Failed to generate detail for index {idx}: {e}")
                    segments_list[idx]["detail_content"] = "" # 失敗時は空文字などで埋める

        # 結果をJSONとして保存
        output_path = work_dir / "segments_with_details.json"
        
        # もとの構造を保ったまま保存
        final_obj = {"segments": segments_list}
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(final_obj, f, ensure_ascii=False, indent=2)

        elapsed = time.time() - start_time
        print(f"⏰Generated all topic details (JSON): {elapsed:.2f} seconds.")

    def _generate_one_detail(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options: LLMOptions,
        prompt_tmpl: str,
        collector: CostCollector,
        task: dict
    ) -> str:
        title = task["title"]
        source_text = task["source_text"]

        messages = [
            Message(role="system", content=prompt_tmpl),
            Message(role="user", content=f"## Topic Title: {title}\n\n## Transcript:\n{source_text}")
        ]

        print(f"   ... generating detail for: {title}")
        res = llm.generate(model_alias, messages, options)
        
        content = _strip_code_fence(res.output_text)
        # Markdown文字列を返すだけ
        return content