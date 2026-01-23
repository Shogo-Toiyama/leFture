
import re
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