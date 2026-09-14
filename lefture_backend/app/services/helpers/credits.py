# app/services/helpers/credits.py
import logging
from dataclasses import dataclass
from typing import Any, Optional

from app.core.supabase import get_supabase_client

logger = logging.getLogger(__name__)

# 1クレジット = $1 / CREDITS_PER_USD。実際の消費・付与はこの値を
# 1_000_000倍したμクレジット単位(bigint)でDBに記録する。
# 表示単位を変えたい場合はここだけ調整すればよい。
CREDITS_PER_USD = 300
MICRO_CREDITS_PER_CREDIT = 1_000_000
MICRO_CREDITS_PER_USD = CREDITS_PER_USD * MICRO_CREDITS_PER_CREDIT


def usd_to_micro_credits(cost_usd: float) -> int:
    return round(cost_usd * MICRO_CREDITS_PER_USD)


def record_task_cost(
    user_id: str,
    task_id: Optional[str],
    task_type: Optional[str],
    cost_usd: float,
    cost_breakdown: list[dict[str, Any]],
    job_id: Optional[str] = None,
) -> None:
    """1タスク分のAI処理コストを`usage_records`に記録する(実コスト可視化のためだけの
    ログで、ユーザーのクレジット残高には一切影響しない)。

    以前はここで`consume_credits`も呼び、実コスト分をそのままその場で消費していたが、
    録音の長さに応じた固定額を`FINALIZE_JOB`で1回だけ消費する方式に変更したため、
    この関数はもう課金(残高操作)を行わない。原価とマージンを後から分析できるように
    `micro_credits_charged`列には「もし実コストどおり課金していたら」の参考値を
    引き続き書いておく(実際の消費額ではない)。

    分析用の記録が失敗してもパイプライン全体を止めたくないため、呼び出し側で
    例外を握りつぶせるように例外はそのまま送出する(ログ出力は呼び出し側に任せる)。
    """
    if cost_usd <= 0:
        return

    micro_credits = usd_to_micro_credits(cost_usd)
    if micro_credits <= 0:
        return

    supabase = get_supabase_client()

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


@dataclass(frozen=True)
class DurationTier:
    key: str  # Core Extractionプロンプトの<!--IF:key-->タグ名としてそのまま使う
    max_duration_seconds: float  # この値以下ならこのtierに該当
    credits: int
    min_topics: int
    max_topics: int


# 音声の長さ(秒)に応じた固定クレジット消費量とACADEMICトピック数の上限/下限。
# 録音自体の上限がMAX_RECORDING_SECONDS(3時間半)なので、それを超えるケースは
# 通常発生しない想定だが、resolve_duration_tierは防御的に最後のtierへクランプする。
# keyはcore_extraction_prompt.txt内の<!--IF:TOPIC_COUNT_xxx-->タグ名と1対1で対応しており、
# 両者はこのリストを唯一の情報源として揃える(値の重複定義を避ける)。
DURATION_TIERS: list[DurationTier] = [
    DurationTier(key="TOPIC_COUNT_TIER_1", max_duration_seconds=30 * 60, credits=60, min_topics=2, max_topics=4),
    DurationTier(key="TOPIC_COUNT_TIER_2", max_duration_seconds=90 * 60, credits=80, min_topics=3, max_topics=5),
    DurationTier(key="TOPIC_COUNT_TIER_3", max_duration_seconds=150 * 60, credits=100, min_topics=4, max_topics=6),
    DurationTier(key="TOPIC_COUNT_TIER_4", max_duration_seconds=210 * 60, credits=120, min_topics=5, max_topics=7),
]

MAX_RECORDING_SECONDS = DURATION_TIERS[-1].max_duration_seconds

# /start-analysisの新規ジョブ受付ゲート用。見積もりクレジットに対してこの割合以上の
# 残高があれば通す(既存の「進行中ジョブのオーバードラフトは許容する」設計と揃え、
# ゲート時点の見積もりも多少ブレる前提なので、100%は要求しない)。
MIN_BALANCE_RATIO_FOR_NEW_JOB = 0.5


def resolve_duration_tier(duration_seconds: float) -> DurationTier:
    for tier in DURATION_TIERS:
        if duration_seconds <= tier.max_duration_seconds:
            return tier
    return DURATION_TIERS[-1]


def consume_lecture_credits(
    user_id: str,
    job_id: str,
    lecture_id: str,
    duration_seconds: float,
) -> None:
    """講義1件分の全タスク完了後、音声の長さに応じた固定クレジットを1回だけ消費する。

    reasonは"LECTURE_ANALYSIS"で固定し、後から「どのLectureにいくら」を追える
    ようにlecture_id/音声長/tier情報はmetadata(jsonb)側に積む(reasonを構造化データの
    置き場にはしない — 集計・フィルタ用の安定した短いタグのまま残す)。

    Cloud Tasksのリトライ等でFINALIZE_JOBが2回動いても二重消費しないよう、
    同じjob_idに対する"LECTURE_ANALYSIS"消費が既に記録されていないか先にチェックする
    (行の作成自体はDBの一意性制約で守られていないので、ごく僅かな競合ウィンドウは
    残るが、そこまで厳密な排他が要る操作ではないと判断している)。
    """
    supabase = get_supabase_client()

    existing = (
        supabase.table("credit_transactions")
        .select("id")
        .eq("related_job_id", job_id)
        .eq("reason", "LECTURE_ANALYSIS")
        .limit(1)
        .execute()
    )
    if existing.data:
        logger.warning(f"consume_lecture_credits: job_id={job_id} already charged. Skipping duplicate charge.")
        return

    tier = resolve_duration_tier(duration_seconds)
    micro_credits = tier.credits * MICRO_CREDITS_PER_CREDIT

    supabase.rpc(
        "consume_credits",
        {
            "p_user_id": user_id,
            "p_amount": micro_credits,
            "p_reason": "LECTURE_ANALYSIS",
            "p_job_id": job_id,
            "p_metadata": {
                "lecture_id": lecture_id,
                "duration_seconds": duration_seconds,
                "credits": tier.credits,
                "topic_range": [tier.min_topics, tier.max_topics],
            },
        },
    ).execute()
