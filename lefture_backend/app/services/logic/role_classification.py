import json, re, time, math, asyncio, shutil
from pathlib import Path

from app.services.helpers.llm_unified import LLMOptions, CostCollector, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, _sid_to_int, _strip_code_fence, token_report_from_result


class RoleClassificationService:
    def __init__(self, llm: UnifiedLLM, collector: CostCollector):
        self.llm = llm
        self.collector = collector
        self.model_alias = "2_5_flash_lite" 

    async def run(self, sentences_path: Path, work_dir: Path) -> Path:
        print(f"   [Logic] Starting role_classification")

        prompt = _load_prompt("role_classification_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.2, google_search=False, reasoning_effort="low")

        try:
            await self._role_classification(
                llm=self.llm,
                model_alias=self.model_alias,
                options_json=options_json,
                work_dir=work_dir,
                sentences_path=sentences_path,
                prompt=prompt,
            )
        except Exception as e:
            print(f"⚠️ Role Classification Logic Error (Continuing to return artifacts): {e}")
        
        output_json = work_dir / "sentences_final.json"
        batches_dir = work_dir / "role_batches"

        results = []

        if output_json.exists():
            results.append(output_json)
        else:
            print(f"[WARN] Role classification finished but {output_json} was not found.")

        if batches_dir.exists():
            zip_file_str = shutil.make_archive(
                base_name=str(work_dir / "role_batches"),
                format="zip",
                root_dir=batches_dir
            )
            zip_path = Path(zip_file_str)
            results.append(zip_path)
            print(f"📦 Zipped batches to: {zip_path.name}")
            
        print(f"   [Logic] Role classification finished. Artifacts: {[p.name for p in results]}")
        return results

    async def _role_classification(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options_json: LLMOptions,
        work_dir: Path,
        sentences_path: Path,
        prompt: str,
        max_batch_size: int = 300,
        ctx: int = 10,
        concurrency: int = 6,
    ):
        print("\n### Role Classification ###")
        start_time = time.time()
        with open(sentences_path, "r", encoding="utf-8") as f:
          sentences = json.load(f)

        ALLOWED_CLASSIFY = ["sid", "text"]
        projected = [{k: s.get(k) for k in ALLOWED_CLASSIFY} for s in sentences]

        print("\n --> Separate Json to batches")
        n = len(projected)
        print(f"[INFO] sentences: {n}")
        ranges = self.split_balanced(n, max_batch_size)
        print(f"[INFO] {len(ranges)} batches: {ranges}")

        batches_dir = work_dir / "role_batches"
        batches_dir.mkdir(exist_ok=True)

        for i, (start, end) in enumerate(ranges):
            batch_num = i + 1
            batch_dir = batches_dir / f"batch_{batch_num:02d}"
            batch_dir.mkdir(exist_ok=True, parents=True)
            self.save_batches(projected, batch_num, start, end, ctx, batch_dir)

        await self._run_all_role_classification(llm, model_alias, options_json, batches_dir, prompt, concurrency=concurrency)

        self.merge_role_classifications(work_dir)

        out_role_classification = json.loads((work_dir / "role_classifications.json").read_text(encoding="utf-8"))
        labels = out_role_classification.get("labels", [])
        label_map = {lab["sid"]: lab for lab in labels}

        ALLOWED_FINAL = ["sid", "text", "start", "end"]
        minimum_sentences = [{k: s.get(k) for k in ALLOWED_FINAL} for s in sentences]

        merged = []
        missing = []
        for s in minimum_sentences:
            sid = s.get("sid")
            lab = label_map.get(sid)
            if lab is None:
                missing.append(sid)
                merged.append({**s, "role": None})
            else:
                merged.append({**s, "role": lab.get("role")})

        sentence_sids = {s["sid"] for s in sentences}
        extra = [sid for sid in label_map.keys() if sid not in sentence_sids]

        with open(work_dir / "sentences_final.json", "w", encoding="utf-8") as f:
            json.dump(merged, f, ensure_ascii=False, indent=2)

        print(f"merged {len(merged)} sentences -> sentences_final.json")
        if missing:
            print(f"[WARN] labels missing for {len(missing)} sid(s). e.g., {missing[:5]}")
        if extra:
            print(f"[WARN] labels contain {len(extra)} extra sid(s). e.g., {extra[:5]}")

        elapsed = time.time() - start_time
        print(f"⏰Classified roles: {elapsed:.2f} seconds.")



    async def _run_all_role_classification(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options_json: LLMOptions,
        batches_dir: Path,
        prompt: str,
        concurrency: int = 6,
    ):

        sem = asyncio.Semaphore(concurrency)
        batch_files = sorted(batches_dir.glob("batch_*/batch_*.json"))
        print(f"Found {len(batch_files)} batches under {batches_dir}")

        async def sem_task(batch_file: Path):
            async with sem:
                return await self.run_one_role_classification(llm, model_alias, options_json, prompt, batch_file)

        results = await asyncio.gather(*(sem_task(f) for f in batch_files))
        success = sum(1 for r in results if r)
        print(f"\n✅ Completed {success}/{len(batch_files)} batches")

    async def run_one_role_classification(
        self,
        llm: UnifiedLLM,
        model_alias: str,
        options_json: LLMOptions,
        prompt: str,
        batch_path: Path,
    ):
        start_time = time.time()
        batch_dir = batch_path.parent

        out_file = batch_dir / "role_classifications_batch.json"
        if out_file.exists():
            print(f"⏭️  Skip (exists) {out_file.relative_to(Path.cwd())}")
            return True

        batch_json = batch_path.read_text(encoding="utf-8")

        messages = [
            Message(role="system", content=prompt),
            Message(role="user", content=batch_json),
            Message(
                role="user",
                content="Using the JSON data provided above, follow the instructions and return the result in JSON format.",
            ),
        ]

        try:
            print(f"Waiting for response {batch_path.name} from {llm.provider} API...")
            # UnifiedLLM is sync; run it in a thread to keep asyncio structure
            res = await asyncio.to_thread(llm.generate, model_alias, messages, options_json)

            out_file.write_text(res.output_text, encoding="utf-8")
            print(f"✅ Saved {out_file.name}")

            elapsed = time.time() - start_time
            print(token_report_from_result(res, self.collector))
            if res.warnings:
                print("  [WARN]", "; ".join(res.warnings))
            print(f"⏰One Role Classification of {batch_path.name}: {elapsed:.2f} seconds.")
            return True
        except Exception as e:
            print(f"❌ Error in {batch_dir.name}: {e}")
            return False
        

    
    def split_balanced(self, n_items: int, max_batch: int):
        if n_items <= 0:
            return []
        if max_batch <= 0:
            raise ValueError("max_batch must be positive")
        n_batches = math.ceil(n_items / max_batch)
        base = n_items // n_batches
        rem = n_items % n_batches
        ranges = []
        start = 0
        for i in range(n_batches):
            size = base + (1 if i < rem else 0)
            end = start + size
            ranges.append((start, end))
            start = end
        return ranges

    def save_batches(self, data, batch_num: int, start: int, end: int, ctx: int, batch_dir: Path):
        n = len(data)
        main_text_chunk = data[start:end]
        ctx_bf_mt_chunk = data[max(0, start - ctx): start]
        ctx_af_mt_chunk = data[end: min(n, end + ctx)]
        obj = [
            {
                "context_before_main_text": ctx_bf_mt_chunk,
                "main_text": main_text_chunk,
                "context_after_main_text": ctx_af_mt_chunk,
            }
        ]
        with open(batch_dir / f"batch_{batch_num:02d}.json", "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
        return json.dumps(obj, ensure_ascii=False, indent=2)
    
    def merge_role_classifications(self, lecture_dir: Path, strict_continuity: bool = True):
        batches_dir = lecture_dir / "role_batches"
        files = sorted(batches_dir.glob("batch_*/role_classifications_batch.json"))
        if not files:
            raise FileNotFoundError(f"No role_classifications_batch.json found under {batches_dir}")

        merged_labels = []
        seen_sids = set()

        prev_sid_num = None
        prev_sid = None

        total_files = 0
        total_items = 0
        skipped_dups = 0

        for f in files:
            text = _strip_code_fence(f.read_text(encoding="utf-8"))
            try:
                obj = json.loads(text)
            except json.JSONDecodeError as e:
                raise ValueError(f"JSON parse failed in {f}: {e}") from e

            labels = obj.get("labels")
            if not isinstance(labels, list):
                raise ValueError(f"{f} does not contain a 'labels' array")

            total_files += 1
            total_items += len(labels)

            for item in labels:
                sid = item.get("sid")
                if sid in seen_sids:
                    skipped_dups += 1
                    continue

                if strict_continuity:
                    cur = _sid_to_int(sid)
                    if prev_sid_num is not None and cur is not None:
                        expected = prev_sid_num + 1
                        if cur != expected:
                            print(f"[WARN] SID continuity broken: expected s{expected:06d} after {prev_sid}, got {sid} in {f.name}")
                            # raise AssertionError(
                            #     f"SID continuity broken: expected s{expected:06d} after {prev_sid}, got {sid} in {f}"
                            # )
                    if cur is not None:
                        prev_sid_num = cur
                        prev_sid = sid

                merged_labels.append(item)
                seen_sids.add(sid)

        out_path = lecture_dir / "role_classifications.json"
        out_path.write_text(
            json.dumps({"labels": merged_labels}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        print(
            f"📦 Merged {total_files} files, {total_items} items → {len(merged_labels)} unique items "
            f"(skipped {skipped_dups} dups) -> {out_path.name}"
        )
        return out_path