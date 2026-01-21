# app/core/config.py
from enum import Enum
from pathlib import Path

# 全体のステータス (DBのstatusカラム用)
class JobStatus(str, Enum):
    DO_NOT_PROCESS = "DO_NOT_PROCESS"
    PENDING = "PENDING"
    PROCESSING = "PROCESSING"
    DONE = "DONE"
    ERROR = "ERROR"

# ステップの定義 (DBのcurrent_step, step_number用)
# ここで順番を管理します

class PipelineSteps(str, Enum):
    PENDING = "PENDING"
    READY = "READY"
    DOWNLOADING = "DOWNLOADING"
    TRANSCRIBING = "TRANSCRIBING"
    SENTENCE_REVIEWING = "SENTENCE_REVIEWING"
    ROLE_CLASSIFYING = "ROLE_CLASSIFYING"
    SEGMENTING = "SEGMENTING"
    GENERATING_DETAILS = "GENERATING_DETAILS"
    GENERATING_FUN_FACTS = "GENERATING_FUN_FACTS"
    COMPLETED = "COMPLETED"

PIPELINE_STEPS_NUM = {
    PipelineSteps.PENDING: -1,
    PipelineSteps.READY: 0,
    PipelineSteps.DOWNLOADING: 1,
    PipelineSteps.TRANSCRIBING: 2,
    PipelineSteps.SENTENCE_REVIEWING: 3,
    PipelineSteps.ROLE_CLASSIFYING: 4,
    PipelineSteps.SEGMENTING: 5,
    PipelineSteps.GENERATING_DETAILS: 6,
    PipelineSteps.GENERATING_FUN_FACTS: 7,
    PipelineSteps.COMPLETED: 100,
}

# 作業用の一時ディレクトリ (Cloud Runでは /tmp のみ書き込み可)
BASE_WORK_DIR = Path("/tmp/leFture_jobs")

APP_DIR = Path(__file__).resolve().parent.parent
PROMPTS_DIR = APP_DIR / "services" / "prompts"