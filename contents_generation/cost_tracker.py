# cost_tracker.py
from dataclasses import dataclass, field
from typing import Dict, Any

# llm_unified.py から価格設定を移植 ($ / 1M tokens)
PRICING_PER_1M = {
    "gemini-2.5-flash": {"input": 0.30, "output": 2.50},
    "gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40},
}

@dataclass
class CostCollector:
    items: list[tuple[str, float]] = field(default_factory=list)

    def add(self, label: str, cost_usd: float):
        self.items.append((label, float(cost_usd)))

    def total(self) -> float:
        return sum(c for _, c in self.items)

    def report(self) -> str:
        lines = ["\n--- 💰 Cost Report (Legacy Branch) ---"]
        for label, c in self.items:
            lines.append(f"{label}: ${c:.6f}")
        lines.append(f"TOTAL: ${self.total():.6f}")
        lines.append("------------------------------------\n")
        return "\n".join(lines)

def calculate_and_track(collector: CostCollector, task_name: str, model_name: str, response: Any):
    """
    Geminiのレスポンスからトークン情報を抜き出し、コスト計算してCollectorに追加、
    さらにコンソールにトークン使用量を表示します。
    """
    # 1. Usage Metadataの取得 (google.genai のレスポンス構造に対応)
    um = getattr(response, "usage_metadata", None)
    if not um:
        print(f"⚠️ No usage metadata for {task_name}")
        return

    prompt_tokens = int(getattr(um, "prompt_token_count", 0) or 0)
    out_tokens = int(getattr(um, "candidates_token_count", 0) or 0)
    total_tokens = int(getattr(um, "total_token_count", prompt_tokens + out_tokens) or 0)
    
    # Reasoning tokens (もしメタデータに含まれていれば計算、なければ0)
    # ※ llm_unified.py のロジックを踏襲
    reasoning_tokens = max(0, total_tokens - prompt_tokens - out_tokens)

    # 2. コスト計算
    price = PRICING_PER_1M.get(model_name)
    cost_usd = 0.0
    if price:
        # OutputにReasoningを含めて計算（llm_unified.pyのロジック）
        cost_usd = (prompt_tokens / 1_000_000.0) * price.get("input", 0.0) + \
                   ((reasoning_tokens + out_tokens) / 1_000_000.0) * price.get("output", 0.0)
    
    # 3. 集計に追加
    collector.add(task_name, cost_usd)

    # 4. その場でログ表示 (helpers.py の token_report_from_result 相当)
    print(f"\n[Token Usage: {task_name}]")
    print(f"  ⬆️ Input : {prompt_tokens}")
    print(f"  🧠 Reason: {reasoning_tokens}")
    print(f"  ⬇️ Output: {out_tokens}")
    print(f"  💵 Cost  : ${cost_usd:.6f}")