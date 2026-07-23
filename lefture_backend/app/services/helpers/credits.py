# app/services/helpers/credits.py
import logging
from typing import Any, Optional

from app.core.supabase import get_supabase_client

logger = logging.getLogger(__name__)

# 1クレジット = $1 / CREDITS_PER_USD。実際の消費・付与はこの値を
# 1_000_000倍したμクレジット単位(bigint)でDBに記録する。
# 表示単位を変えたい場合はここだけ調整すればよい。
CREDITS_PER_USD = 300
MICRO_CREDITS_PER_USD = CREDITS_PER_USD * 1_000_000


def usd_to_micro_credits(cost_usd: float) -> int:
    return round(cost_usd * MICRO_CREDITS_PER_USD)


def charge_credits_for_task(
    user_id: str,
    task_id: str,
    task_type: Optional[str],
    cost_usd: float,
    cost_breakdown: list[dict[str, Any]],
    job_id: Optional[str] = None,
) -> None:
    """1タスク分のAI処理コストをクレジットとして消費し、履歴を記録する。

    課金処理の失敗でパイプライン全体を止めたくないため、呼び出し側で
    例外を握りつぶせるように例外はそのまま送出する(ログ出力は呼び出し側に任せる)。
    """
    if cost_usd <= 0:
        return

    micro_credits = usd_to_micro_credits(cost_usd)
    if micro_credits <= 0:
        return

    supabase = get_supabase_client()

    supabase.rpc(
        "consume_credits",
        {
            "p_user_id": user_id,
            "p_amount": micro_credits,
            "p_reason": task_type or "unknown_task",
            "p_job_id": job_id,
        },
    ).execute()

    supabase.table("usage_records").insert(
        {
            "user_id": user_id,
            "job_id": job_id,
            "task_id": task_id,
            "cost_usd": cost_usd,
            "cost_breakdown": cost_breakdown,
            "micro_credits_charged": micro_credits,
        }
    ).execute()
