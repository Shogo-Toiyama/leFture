
import re
import json
from datetime import datetime
from pathlib import Path
from datetime import datetime
from typing import Optional
from app.services.helpers.llm_unified import CostCollector
from app.core.config import PROMPTS_DIR


def _strip_code_fence(text: str) -> str:
    if text.lstrip().startswith("```"):
        lines = [ln.rstrip("\n") for ln in text.splitlines()]
        # 先頭の```を落とす
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        # 末尾の```を落とす
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines)
    return text

def token_report_from_result(res, collector: CostCollector):
    u = res.usage
    collector.add("Lecture Audio to Text", res.estimated_cost_usd)
    return (
        "TOKEN USAGE REPORT\n"
        f"  ⬆️:{u.input_tokens}, 🧠: {u.reasoning_tokens}, ⬇️: {u.output_tokens}\n"
        f"  TOTAL: {u.total_tokens}\n"
        f"  Estimated cost: ${res.estimated_cost_usd:.6f}"
    )

def _load_prompt(filename: str) -> str:
    prompt_path = PROMPTS_DIR / filename
    if not prompt_path.exists():
        raise FileNotFoundError(f"Prompt file not found: {filename}")
        
    return prompt_path.read_text(encoding="utf-8")


def _sid_to_int(sid: Optional[str]) -> Optional[int]:
    SID_NUM = re.compile(r"s(\d+)")
    if not sid:
        return None
    m = SID_NUM.fullmatch(sid)
    return int(m.group(1)) if m else None

_LOG_FILE_PATH: Path | None = None

def init_logger(work_dir: Path):
    """
    ジョブの開始時にログファイルを初期化する
    """
    global _LOG_FILE_PATH
    _LOG_FILE_PATH = work_dir / "log.json"
    
    # ファイルを空で作成しておく
    with open(_LOG_FILE_PATH, "w", encoding="utf-8") as f:
        f.write("")

def print_log(message: str):
    """
    コンソールに出力しつつ、ログファイルにもJSON形式で追記する
    """
    # 1. コンソール出力 (Cloud Runのログ用)
    print(message)

    # 2. ファイル出力 (追記モード)
    if _LOG_FILE_PATH:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        entry = {
            "timestamp": timestamp,
            "message": str(message)
        }
        
        try:
            # 追記モード('a')で開く
            with open(_LOG_FILE_PATH, "a", encoding="utf-8") as f:
                # 後で読みやすいように、1行に1つのJSONを書く (JSON Lines形式)
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except Exception as e:
            # ログ出力自体がコケると本末転倒なので、エラーはコンソールに出してスルー
            print(f"⚠️ Failed to write log: {e}")

def finalize_log_and_get_path() -> Path | None:
    """
    JSON Lines形式で書かれたログを、正しいJSON配列形式に変換して保存し直す
    戻り値: 完成したファイルのパス
    """
    if not _LOG_FILE_PATH or not _LOG_FILE_PATH.exists():
        return None
    
    logs = []
    try:
        # 1行ずつ読み込んでリストにする
        with open(_LOG_FILE_PATH, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    logs.append(json.loads(line))
        
        final_data = {"logs": logs}
        
        with open(_LOG_FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(final_data, f, ensure_ascii=False, indent=2)
            
        return _LOG_FILE_PATH
    except Exception as e:
        print(f"⚠️ Failed to finalize log: {e}")
        return None
