"""TODO #2: 音声なし・発話なしの失敗を「やり直さない失敗」にする変更の確認。

確かめること(本番コードの関数をそのまま呼ぶ。DB・R2・文字起こし・LLMはフェイク):
  A. CORE_EXTRACTION: 本番で実際に落ちていた講義(ユーザーX・講義1、allowlist外)の
     transcript_assembled.json(R2から読み取りのみ)を入力にすると、LLMを呼ばずに
     PermanentTaskError(NO_SPEECH_DETECTED) になる。
  B. TRANSCRIBE_MASTER: 文字起こし結果が空 → FAILED("NO_SPEECH_DETECTED: ..."、トレースバック無し)、
     文字起こしの原価はusage_recordsに記録される。audio_pathが空 → AUDIO_NOT_UPLOADED。
     発話がある場合は従来どおりCOMPLETED。
  C. CHECK_AND_ASSEMBLE: 全チャンクREVIEWEDだが発話ゼロ → NO_SPEECH_DETECTED。
  D. /worker/* 共通部(_run_worker_task): PermanentTaskErrorなら200相当の戻り値+ジョブ即FAILED。
     通常の例外は従来どおり再送出(=500でCloud Tasksがリトライ)、最終試行のみジョブFAILED。
  E. /start-analysis: プレレコでaudio_pathが空・チャンク0件 → 409 AUDIO_NOT_UPLOADED。
     チャンクがある / audio_pathがある場合は通過する。

本番への書き込み: 0件。外部API: 0回(Aのみ R2 GET 1回、--dry-run では0回)。費用: $0。
実行: .venv/bin/python contents_generation/test_codes/permanent_task_failure/run_test.py [--dry-run] [--r2-lecture UID/LECTURE_ID]
  --r2-lecture: Aで読む講義(公開リポジトリなのでIDは書かず、実行時に渡す)。省略時は空配列で代用。
"""
import asyncio
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402
load_dotenv(ROOT / "lefture_backend" / ".env")

DRY_RUN = "--dry-run" in sys.argv

from fastapi import HTTPException  # noqa: E402
from app.services import task_runners as tr  # noqa: E402
from app.services.helpers.task_errors import PermanentTaskError, NO_SPEECH_DETECTED, AUDIO_NOT_UPLOADED  # noqa: E402
from app.services.logic.core_extraction import CoreExtractionService  # noqa: E402
from app.services.helpers.helpers import TaskLogger  # noqa: E402
import app.main as main  # noqa: E402

# 本番で落ちていた講義(allowlist外。IDはコードにも結果ファイルにも書かない)
R2_LECTURE = sys.argv[sys.argv.index("--r2-lecture") + 1] if "--r2-lecture" in sys.argv else None

RESULTS = []


def record(case, ok, detail):
    RESULTS.append({"case": case, "pass": bool(ok), "detail": detail})
    print(f"{'✅' if ok else '❌'} {case}: {detail}")


# ------------------------------------------------------------------ フェイク
class Res:
    def __init__(self, data, count=None):
        self.data = data
        self.count = count


class FakeQuery:
    def __init__(self, db, table):
        self.db, self.table, self.op, self.filters, self.payload = db, table, "select", [], None

    def select(self, *a, **k):
        self.op = "select"
        return self

    def update(self, payload):
        self.op, self.payload = "update", payload
        return self

    def insert(self, payload):
        self.op, self.payload = "insert", payload
        return self

    def upsert(self, payload, **k):
        self.op, self.payload = "upsert", payload
        return self

    def delete(self):
        self.op = "delete"
        return self

    def __getattr__(self, name):
        # eq / neq / in_ / order / limit / single / maybe_single / lt ... は条件として記録だけする
        def f(*a, **k):
            self.filters.append((name, a))
            return self
        return f

    @property
    def not_(self):
        return self

    def execute(self):
        self.db.calls.append({"table": self.table, "op": self.op, "payload": self.payload, "filters": self.filters})
        handler = self.db.handlers.get((self.table, self.op))
        if handler:
            return handler(self)
        return Res([{"id": "x"}] if self.op in ("update", "insert", "upsert") else [], count=0)


class FakeDB:
    def __init__(self, handlers=None):
        self.handlers = handlers or {}
        self.calls = []

    def table(self, name):
        return FakeQuery(self, name)

    def rpc(self, name, params):
        db = self

        class R:
            def execute(self_inner):
                db.calls.append({"rpc": name})
                return db.handlers[("rpc", name)]()
        return R()


class FakeStorage:
    def __init__(self):
        self.saved = []

    def save_json_log(self, uid, lecture_id, name, data):
        self.saved.append(name)
        return f"{uid}/{lecture_id}/pipeline_logs/{name}.json"

    def download_file(self, src, dst):
        Path(dst).write_bytes(b"fake")

    def download_binary(self, src):
        return b"fake"


def patch_runner_env(db, status_log, lecture_row, transcribe_result, chunks=None):
    """task_runners のI/Oをフェイクに差し替える。"""
    tr.get_supabase_client = lambda: db
    storage = FakeStorage()
    tr.storage_service = storage

    async def job_ctx(job_id):
        return {"user_id": "uid-test", "lecture_id": "lec-test", "expected_chunks": 2 if chunks is not None else 0}
    tr._get_job_context = job_ctx

    async def claim(task_id):
        return True
    tr._claim_task = claim

    async def upd(task_id, status, payload=None, error_msg=None, user_id=None, job_id=None):
        status_log.append({"status": status, "payload": payload, "error_msg": error_msg, "user_id": user_id})
    tr._update_task_status = upd

    class FakeModal:
        def __init__(self, logger, billing):
            self.billing = billing

        async def transcribe_file(self, **k):
            from app.services.helpers.llm_unified import CostRecord
            self.billing.records.append(CostRecord(task_type="TRANSCRIBE_MASTER", resource="modal/t4", dimension="time",
                                                   usage={"seconds": 5.0, "multiplier": 1.0}, cost_usd=0.001, note=None))
            return transcribe_result
    tr.ModalTranscriptionService = FakeModal
    db.handlers[("lectures", "select")] = lambda q: Res(lecture_row)
    if chunks is not None:
        db.handlers[("lecture_transcripts", "select")] = lambda q: Res(chunks)
    return storage


# ------------------------------------------------------------------ A. CORE_EXTRACTION
async def case_a():
    if DRY_RUN or not R2_LECTURE:
        transcript = []
        source = "literal [] (dry-run or no --r2-lecture)"
    else:
        from app.core.r2_storage import storage_service as real_storage
        obj = real_storage.s3.get_object(Bucket=real_storage.bucket_name,
                                         Key=f"{R2_LECTURE}/pipeline_logs/transcript_assembled.json")
        transcript = json.loads(obj["Body"].read())
        source = f"production R2 (user X, lecture 1): {len(transcript)} sentences"

    class NoLLM:
        def __getattr__(self, name):
            raise AssertionError(f"LLM must not be called (attr {name})")

    svc = CoreExtractionService(NoLLM(), TaskLogger("uid-test", "lec-test", "CORE_EXTRACTION"))
    try:
        await svc.run_from_memory(transcript, duration_tier=tr.resolve_duration_tier(73.0), plan_tier=1,
                                  user_id="uid-test", content_language="en", transcript_language="en", is_bilingual=False)
        record("A core_extraction empty", False, "no exception")
    except PermanentTaskError as e:
        record("A core_extraction empty", e.code == NO_SPEECH_DETECTED, f"{source} -> PermanentTaskError({e.code})")
    except Exception as e:  # noqa: BLE001
        record("A core_extraction empty", False, f"{type(e).__name__}: {e}")


# ------------------------------------------------------------------ B. TRANSCRIBE_MASTER
async def case_b():
    # B1: 発話ゼロ
    db, log = FakeDB(), []
    patch_runner_env(db, log, {"audio_path": "u/l/master_audio.m4a", "recording_language": "en"},
                     {"segments": [], "text": "", "audio_duration": 73.0})
    try:
        await tr.run_transcribe_master_task("job-test", "task-b1")
        record("B1 transcribe_master no speech", False, "no exception")
    except PermanentTaskError as e:
        failed = [x for x in log if x["status"] == "FAILED"]
        with_cost = [x for x in failed if x["payload"] and x["user_id"]]
        msgs = {x["error_msg"] for x in failed}
        ok = (e.code == NO_SPEECH_DETECTED and failed and with_cost
              and all(m.startswith("NO_SPEECH_DETECTED:") and "Traceback" not in m for m in msgs)
              and not any(x["status"] == "COMPLETED" for x in log))
        record("B1 transcribe_master no speech", ok,
               f"code={e.code}, FAILED writes={len(failed)}, cost recorded={len(with_cost)}, messages={sorted(msgs)}")

    # B2: audio_path が空
    db, log = FakeDB(), []
    patch_runner_env(db, log, {"audio_path": None, "recording_language": "en"}, {})
    try:
        await tr.run_transcribe_master_task("job-test", "task-b2")
        record("B2 transcribe_master no audio", False, "no exception")
    except PermanentTaskError as e:
        msgs = [x["error_msg"] for x in log if x["status"] == "FAILED"]
        ok = e.code == AUDIO_NOT_UPLOADED and msgs and msgs[0].startswith("AUDIO_NOT_UPLOADED:") and "Traceback" not in msgs[0]
        record("B2 transcribe_master no audio", ok, f"code={e.code}, error_message={msgs}")

    # B3: 発話あり(回帰確認)
    db, log = FakeDB(), []
    seg = {"start": 0.0, "end": 2.0, "text": "Hello class.", "confidence": 0.9}
    patch_runner_env(db, log, {"audio_path": "u/l/master_audio.m4a", "recording_language": "en"},
                     {"segments": [seg], "text": "Hello class.", "audio_duration": 2.0})
    try:
        await tr.run_transcribe_master_task("job-test", "task-b3")
        ok = log and log[-1]["status"] == "COMPLETED"
        record("B3 transcribe_master with speech", ok, f"statuses={[x['status'] for x in log]}")
    except Exception as e:  # noqa: BLE001
        record("B3 transcribe_master with speech", False, f"{type(e).__name__}: {e}")


# ------------------------------------------------------------------ C. CHECK_AND_ASSEMBLE
async def case_c():
    db, log = FakeDB(), []
    chunks = [
        {"id": f"c{i}", "lecture_id": "lec-test", "chunk_index": i, "status": "REVIEWED", "start_time": 30.0 * i,
         "audio_duration": 30.0, "text_reviewed": "", "segments_reviewed": [], "text_stt": "", "segments_stt": [],
         "billing_records": []}
        for i in range(2)
    ]
    patch_runner_env(db, log, {}, {}, chunks=chunks)
    try:
        await tr.run_check_and_assemble_transcript_task("job-test", "task-c")
        record("C check_and_assemble no speech", False, f"no exception, statuses={[x['status'] for x in log]}")
    except PermanentTaskError as e:
        msgs = [x["error_msg"] for x in log if x["status"] == "FAILED"]
        ok = e.code == NO_SPEECH_DETECTED and msgs and msgs[0].startswith("NO_SPEECH_DETECTED:")
        record("C check_and_assemble no speech", ok, f"code={e.code}, error_message={msgs}")
    except Exception as e:  # noqa: BLE001
        record("C check_and_assemble no speech", False, f"{type(e).__name__}: {e}")


# ------------------------------------------------------------------ D. _run_worker_task
class FakeRequest:
    def __init__(self, retry):
        self.headers = {"X-CloudTasks-TaskRetryCount": str(retry)}


async def case_d():
    payload = main.WorkerPayload(job_id="job-test", task_id="task-test")

    async def permanent(job_id, task_id):
        raise PermanentTaskError(NO_SPEECH_DETECTED, "x")

    async def transient(job_id, task_id):
        raise ValueError("temporary")

    for name, fn, retry, expect_raise in [
        ("D1 permanent, first attempt", permanent, 0, False),
        ("D2 transient, first attempt", transient, 0, True),
        ("D3 transient, last attempt", transient, main.CLOUD_TASKS_MAX_ATTEMPTS - 1, True),
    ]:
        db = FakeDB()
        main.get_supabase_client = lambda db=db: db
        raised, ret = False, None
        try:
            ret = await main._run_worker_task(FakeRequest(retry), payload, fn)
        except ValueError:
            raised = True
        job_fails = [c for c in db.calls if c.get("table") == "processing_jobs" and c["op"] == "update"
                     and c["payload"].get("status") == "FAILED"]
        expect_job_fail = (not expect_raise) or retry >= main.CLOUD_TASKS_MAX_ATTEMPTS - 1
        ok = raised == expect_raise and bool(job_fails) == expect_job_fail
        record(name, ok, f"raised={raised}, return={ret}, job set FAILED={bool(job_fails)}")


# ------------------------------------------------------------------ E. /start-analysis
class StopHere(Exception):
    pass


async def case_e():
    async def uid(request):
        return "uid-test"

    async def not_suspended(client, user_id):
        return None
    main._get_authenticated_user_id = uid
    main._reject_if_suspended = not_suspended

    def make_db(audio_path, chunk_count):
        db = FakeDB()
        db.handlers[("rpc", "get_credit_summary")] = lambda: Res([{"has_active_plan": True, "credit_balance": 10**12}])
        db.handlers[("lectures", "select")] = lambda q: Res({"user_id": "uid-test", "course_id": "course-1", "audio_path": audio_path})
        db.handlers[("lecture_transcripts", "select")] = lambda q: Res([], count=chunk_count)

        def stop(q):
            raise StopHere()
        db.handlers[("processing_jobs", "select")] = stop  # ここまで来たら「通過」
        return db

    for name, audio_path, chunks, expected_chunks, expect_409 in [
        ("E1 pre-recorded, no audio, no chunks", None, 0, 0, True),
        ("E2 no audio_path but chunks on server (realtime from other device)", None, 3, 0, False),
        ("E3 realtime request (expected_chunks>0)", None, 0, 5, False),
        ("E4 pre-recorded with audio", "u/l/master_audio.m4a", 0, 0, False),
    ]:
        db = make_db(audio_path, chunks)
        main.get_supabase_client = lambda db=db: db
        req = main.StartAnalysisRequest(lecture_id="lec-test", expected_chunks=expected_chunks)
        outcome = None
        try:
            await main.start_analysis(req, None)
            outcome = "returned"
        except HTTPException as e:
            outcome = f"HTTP {e.status_code} {json.dumps(e.detail)[:80]}"
        except StopHere:
            outcome = "passed the audio check"
        got_409 = outcome.startswith("HTTP 409") and AUDIO_NOT_UPLOADED in outcome
        ok = got_409 if expect_409 else outcome == "passed the audio check"
        record(name, ok, outcome)


async def main_async():
    t0 = time.perf_counter()
    await case_a()
    await case_b()
    await case_c()
    await case_d()
    await case_e()
    elapsed = time.perf_counter() - t0
    passed = sum(r["pass"] for r in RESULTS)
    print(f"\n{passed}/{len(RESULTS)} passed in {elapsed:.2f}s")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = HERE / "results" / f"{stamp}_permanent_task_failure{'_dryrun' if DRY_RUN else ''}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps({"dry_run": DRY_RUN, "elapsed_seconds": round(elapsed, 3), "passed": passed,
                               "total": len(RESULTS), "cost_usd": 0.0, "results": RESULTS}, indent=2, ensure_ascii=False))
    print(f"saved {out.relative_to(ROOT)}")
    return passed == len(RESULTS)


if __name__ == "__main__":
    sys.exit(0 if asyncio.run(main_async()) else 1)
