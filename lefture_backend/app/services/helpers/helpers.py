import re
import json
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any

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


# =========================================================
# 📝 新しいロギング・システム (TaskLogger)
# =========================================================

class TaskLogger:
    """
    タスクごとに独立してログを保持するクラス。
    グローバル変数の競合を防ぎ、Cloud Runでの並列処理を安全にします。
    """
    def __init__(self, uid: str, lecture_id: str, task_name: str):
        self.uid = uid
        self.lecture_id = lecture_id
        self.task_name = task_name
        self.logs: List[Dict[str, str]] = []
        
    def log(self, *args):
        """コンソールに出力しつつ、メモリ内のリストに保存"""
        message = " ".join(map(str, args))
        
        # コンソールではどのタスクのログか分かりやすいようにプレフィックスをつける
        print(f"[{self.task_name}] {message}") 
        
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self.logs.append({
            "timestamp": timestamp,
            "message": message
        })
        
    def save_to_r2(self, storage_service) -> str:
        """
        タスクの最後に呼び出し、R2にコンソールログJSONを保存する。
        """
        if not self.logs:
            return ""
        
        final_data = {
            "task_name": self.task_name, 
            "logs": self.logs
        }
        
        # 例: uid/lecture_id/pipeline_logs/core_extraction_console.json に保存
        r2_path = storage_service.save_json_log(
            self.uid, 
            self.lecture_id, 
            f"{self.task_name}_console", 
            final_data
        )
        return r2_path


# ---------------------------------------------------------
# 下位互換性用のヘルパー (※一部の職人クラスでまだ呼ばれている場合のため)
# ---------------------------------------------------------
def print_log(*args):
    """
    [非推奨] 
    今後は各タスク内で生成した logger.log() を使用してください。
    この関数は純粋なコンソール出力のみを行い、ファイルには保存されません。
    """
    print(" ".join(map(str, args)))