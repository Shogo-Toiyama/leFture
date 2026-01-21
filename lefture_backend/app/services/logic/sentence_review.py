import json, os, time
import assemblyai as aai
from pathlib import Path

from app.services.helpers.llm_unified import UnifiedLLM, CostCollector, Message, LLMOptions
from app.services.helpers.helpers import _strip_code_fence, token_report_from_result
from app.core.config import PROMPTS_DIR

class SentenceReviewService:
    def __init__(self, llm: UnifiedLLM, collector: CostCollector):
        self.llm = llm
        self.collector = collector
        self.model_alias = "2_5_flash" 

    def _load_prompt(self, filename: str) -> str:
        prompt_path = PROMPTS_DIR / filename
        if not prompt_path.exists():
            raise FileNotFoundError(f"Prompt file not found: {filename}")
            
        return prompt_path.read_text(encoding="utf-8")

    def run(self, work_dir: Path) -> Path:
        print(f"   [Logic] Starting sentence_reviewing")
        prompt = self._load_prompt("sentence_review_prompt.txt")

        self._sentence_review(
            llm=self.llm,
            model_alias=self.model_alias,
            work_dir=work_dir,
            prompt = prompt,
            collector=self.collector,
        )

        output_json = work_dir / "reviewed_sentences.json"
        
        if not output_json.exists():
            raise FileNotFoundError(f"Sentence-Reviewing logic finished but {output_json} was not found.")
            
        print(f"   [Logic] Sentence Reveiw finished: {output_json.name}")
        return output_json
    
    def _sentence_review(llm: UnifiedLLM, model_alias: str, work_dir: Path, prompt, collector: CostCollector, options_json: LLMOptions | None = None):
        print("\n### Sentence Review ###")
        start_time_sentence_review = time.time()

        REVIEWED_DIR = work_dir / "reviewed"
        REVIEWED_DIR.mkdir(exist_ok=True)

        with open(work_dir / "transcript_sentences.json", "r", encoding="utf-8") as f:
            sentences = json.load(f)

        ALLOWED = ["sid", "text", "confidence"]
        projected_sentences = [{k: s.get(k) for k in ALLOWED} for s in sentences]
        low_confidence_sentences = [s for s in projected_sentences if (s.get("confidence") is not None and s.get("confidence", 1.0) < 0.9)]
        print("Low Confident Sentences: ", len(low_confidence_sentences))

        payload = {
            "task": "Sentence Review",
            "instruction": prompt,
            "data": {
                "low_confidence_sentences": low_confidence_sentences
            }
        }

        messages = [
            Message(
                role="system",
                content="You are a careful transcript editor. Follow the instruction and return JSON only.",
            ),
            Message(role="user", content=json.dumps(payload, ensure_ascii=False)),
        ]

        options_json = options_json or LLMOptions(output_type="json", temperature=0.2, google_search=False, reasoning_effort="low")

        print(f"Waiting for response from {llm.provider} API...")
        res = llm.generate(model=model_alias, messages=messages, options=options_json)

        print("saving response...")
        raw_text = res.output_text
        clean_text = _strip_code_fence(raw_text).strip()

        try:
            out_review_sentence = json.loads(clean_text)
        except json.JSONDecodeError as e:
            # keep raw for debug
            (work_dir / "reviewed/reviewed_sentences_raw_text.txt").write_text(raw_text, encoding="utf-8")
            raise ValueError(f"Sentence Review JSON parse failed: {e}") from e

        with open(work_dir / "reviewed/reviewed_sentences_raw.json", "w", encoding="utf-8") as f:
            json.dump(out_review_sentence, f, ensure_ascii=False, indent=2)

        sentence_reviewed_list = out_review_sentence.get("results") or []

        mods = {}
        for r in sentence_reviewed_list:
            sid = r.get("sid")
            modified = r.get("modified")
            if sid and isinstance(modified, str) and modified.strip():
                mods[sid] = modified.strip()

        reviewed_sentences = []
        for s in sentences:
            sid = s.get("sid")
            if sid in mods:
                new_s = dict(s)
                new_s["text"] = mods[sid]
                reviewed_sentences.append(new_s)
            else:
                reviewed_sentences.append(s)

        with open(work_dir / "reviewed_sentences.json", "w", encoding="utf-8") as f:
            json.dump(reviewed_sentences, f, ensure_ascii=False, indent=2)

        elapsed_time_sentence_review = time.time() - start_time_sentence_review
        print(token_report_from_result(res, collector))
        if res.warnings:
            print("  [WARN]", "; ".join(res.warnings))
        print(f"⏰Sentence Review: {elapsed_time_sentence_review:.2f} seconds.")