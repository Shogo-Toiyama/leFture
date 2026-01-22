import json
import time
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

    def run(self, transcript_path: Path, work_dir: Path) -> Path:
        print(f"   [Logic] Starting sentence_reviewing")
        
        prompt = self._load_prompt("sentence_review_prompt.txt")
        try:
            self._sentence_review(
                llm=self.llm,
                model_alias=self.model_alias,
                work_dir=work_dir,
                transcript_path=transcript_path,
                prompt=prompt,
            )
        except Exception as e:
            print(f"⚠️ Sentence Review Logic Error (Continuing to return artifacts): {e}")

        reviewed_sentences_raw = work_dir / "reviewed_sentences_raw.json"
        reviewed_sentences_raw_text = work_dir / "reviewed_sentences_raw_text.json"
        reviewed_sentences = work_dir / "reviewed_sentences.json"

        results = []

        if reviewed_sentences_raw.exists():
            results.append(reviewed_sentences_raw)

        if reviewed_sentences.exists():
            results.append(reviewed_sentences)

        if not reviewed_sentences_raw.exists() and reviewed_sentences_raw_text.exists():
            results.append(reviewed_sentences_raw_text)
        
        if not results:
             raise FileNotFoundError("Sentence Review failed and no artifacts were generated.")
        print(f"   [Logic] Sentence Review finished! Artifacts: {[p.name for p in results]}")

        return results
    
    def _sentence_review(self, llm: UnifiedLLM, model_alias: str, work_dir: Path, transcript_path: Path, prompt: str, options_json: LLMOptions | None = None):
        print("\n### Sentence Review ###")
        start_time = time.time()

        if not transcript_path.exists():
            raise FileNotFoundError(f"Input file not found: {transcript_path}")

        with open(transcript_path, "r", encoding="utf-8") as f:
            sentences = json.load(f)

        ALLOWED = ["sid", "text", "confidence"]
        projected_sentences = [{k: s.get(k) for k in ALLOWED} for s in sentences]
        
        low_confidence_sentences = [
            s for s in projected_sentences 
            if s.get("confidence") is not None and s.get("confidence", 1.0) < 0.9
        ]
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
            print(f"⚠️ JSON Decode Error: {e}")
            (work_dir / "reviewed_sentences_raw_text.txt").write_text(raw_text, encoding="utf-8")

        with open(work_dir / "reviewed_sentences_raw.json", "w", encoding="utf-8") as f:
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

        elapsed_time = time.time() - start_time
        print(token_report_from_result(res, self.collector))
        
        if res.warnings:
            print("  [WARN]", "; ".join(res.warnings))
        print(f"⏰Sentence Review: {elapsed_time:.2f} seconds.")