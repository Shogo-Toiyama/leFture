import json
import time
import re
import asyncio
from pathlib import Path

from app.services.helpers.llm_unified import LLMOptions, CostCollector, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, _strip_code_fence, token_report_from_result

class LectureSegmentationService:
    def __init__(self, llm: UnifiedLLM, collector: CostCollector):
        self.llm = llm
        self.collector = collector
        self.model_alias = "2_5_flash"

    async def run(self, sentences_final_path: Path, work_dir: Path) -> list[Path]:
        print(f"   [Logic] Starting lecture_segmentation")
        
        prompt = _load_prompt("lecture_segmentation_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.2)

        try:
            # LLM呼び出し（同期関数をスレッドで実行）
            await asyncio.to_thread(
                self._lecture_segmentation,
                llm=self.llm,
                model_alias=self.model_alias,
                options_json=options_json,
                work_dir=work_dir,
                sentences_path=sentences_final_path,
                prompt=prompt
            )
        except Exception as e:
            print(f"⚠️ Segmentation Logic Error: {e}")
            import traceback
            traceback.print_exc()

        # 成果物チェック
        segments_json = work_dir / "segments.json"
        
        if not segments_json.exists():
            print(f"[WARN] Segmentation finished but {segments_json} was not found.")
            # 失敗しても空リストを返してPipeline側で判断させる
            return []

        print(f"   [Logic] Segmentation finished: {segments_json.name}")
        return [segments_json]

    def _lecture_segmentation(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options_json: LLMOptions,
        work_dir: Path,
        sentences_path: Path,
        prompt: str
    ):
        print("\n### Topic Segmentation ###")
        start_time = time.time()

        if not sentences_path.exists():
            raise FileNotFoundError(f"sentences_final.json not found at {sentences_path}")

        sentences_data = json.loads(sentences_path.read_text(encoding="utf-8"))

        # プロンプトにデータを埋め込む（f-string等はプロンプトファイル側で処理できないため、ここで結合）
        # ※元コードのロジックを踏襲
        input_text = json.dumps(sentences_data, ensure_ascii=False, indent=2)
        
        messages = [
            Message(role="system", content=prompt),
            Message(role="user", content=f"Here is the transcript data:\n{input_text}"),
            Message(role="user", content="Please segment this transcript into topics according to the system instruction.")
        ]

        print(f"Waiting for response from {llm.provider} API...")
        res = llm.generate(model_alias, messages, options_json)

        clean_text = _strip_code_fence(res.output_text)
        try:
            out_obj = json.loads(clean_text)
        except json.JSONDecodeError as e:
            # エラー時はテキストを残す
            (work_dir / "segments_error.txt").write_text(clean_text, encoding="utf-8")
            raise ValueError(f"JSON parse failed for segmentation: {e}")

        # 保存
        out_path = work_dir / "segments.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(out_obj, f, ensure_ascii=False, indent=2)

        elapsed = time.time() - start_time
        print(token_report_from_result(res, self.collector))
        print(f"⏰Segmented topics: {elapsed:.2f} seconds.")