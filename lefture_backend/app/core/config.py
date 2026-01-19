from enum import Enum
from pathlib import Path

class JobStatus(str, Enum):
    PENDING = "PENDING"
    DOWNLOADING = "DOWNLOADING"
    TRANSCRIBING = "TRANSCRIBING"
    REVIEWING = "REVIEWING"
    SEGMENTING = "SEGMENTING"
    GENERATING_DETAILS = "GENERATING_DETAILS"
    COMPLETED = "COMPLETED"
    ERROR = "ERROR"

# Cloud Runなどのコンテナ環境では /tmp だけが書き込み可能
BASE_WORK_DIR = Path("/tmp/leFture_jobs")