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


# ---------------------------------------------------------
# 💬 横断チャットボットの課金
# ---------------------------------------------------------
# 講義は録音の長さに応じた固定額だが、チャットは「実際にかかった原価 ×
# CHAT_CREDIT_MARKUP」を1メッセージごとに消費する(CREDITS_PER_USD=300なので
# 実質450クレジット/$1)。原価はBillingEngine(PRICE_MATRIX)から計算するため、
# PRICE_MATRIXの単価がそのまま請求額に効く点に注意。
# 2026-10-03に2から1.5へ下げた(ユーザー決定)。手取りが一番少ないMax($19.99、Appleの手数料15%を
# 引いて1クレジット$0.0042)でも、チャットの1クレジットの原価は$0.0022で、授業分析の重いケース
# (2時間=100クレジットで約$0.33、1クレジット$0.0033)より安い。つまりプランの最悪ケースは授業分析で
# 決まり、チャットはそれより利益率が高い。1.2倍まで下げない理由は、請求していない原価(Cloud Run・
# 断ったターンの振り分け役など)、固定費、Free/Welcome Bonusの無償クレジットの分を残すため。
CHAT_CREDIT_MARKUP = 1.5
# 送信を受け付ける最低残高。1メッセージの原価は通常1〜3クレジット程度なので、
# これだけあれば少なくとも1回分は賄える。
CHAT_MIN_BALANCE_CREDITS = 5


def chat_cost_to_micro_credits(cost_usd: float) -> int:
    return round(cost_usd * CHAT_CREDIT_MARKUP * MICRO_CREDITS_PER_USD)


def _consume_chat_cost(
    user_id: str,
    thread_id: str,
    reason: str,
    dedup_key: str,
    dedup_value: str,
    cost_usd: float,
    cost_breakdown: list[dict[str, Any]],
) -> int:
    """
    チャット関連の原価×CHAT_CREDIT_MARKUPを消費し、実際に消費したμクレジットを返す。

    講義(consume_lecture_credits)と同じくconsume_creditsのRPCを使う。
    同じ(reason, dedup_key=dedup_value)への二重課金はここで弾く。
    原価の記録(usage_records)もここで一緒に行う。講義と違い「参考値」
    ではなく、micro_credits_chargedは実際の消費額そのもの。
    """
    micro_credits = chat_cost_to_micro_credits(cost_usd)
    if micro_credits <= 0:
        return 0

    supabase = get_supabase_client()

    existing = (
        supabase.table("credit_transactions")
        .select("id")
        .eq("reason", reason)
        .eq(f"metadata->>{dedup_key}", dedup_value)
        .limit(1)
        .execute()
    )
    if existing.data:
        logger.warning(f"{reason}: {dedup_key}={dedup_value} already charged. Skipping duplicate charge.")
        return 0

    supabase.rpc(
        "consume_credits",
        {
            "p_user_id": user_id,
            "p_amount": micro_credits,
            "p_reason": reason,
            "p_job_id": None,
            "p_metadata": {
                "thread_id": thread_id,
                dedup_key: dedup_value,
                "cost_usd": cost_usd,
                "markup": CHAT_CREDIT_MARKUP,
            },
        },
    ).execute()

    supabase.table("usage_records").insert(
        {
            "user_id": user_id,
            "job_id": None,
            "task_id": None,
            "cost_usd": cost_usd,
            "cost_breakdown": cost_breakdown,
            "micro_credits_charged": micro_credits,
            "metadata": {"kind": reason, "thread_id": thread_id, dedup_key: dedup_value},
        }
    ).execute()

    return micro_credits


def consume_chat_credits(
    user_id: str,
    thread_id: str,
    message_id: str,
    cost_usd: float,
    cost_breakdown: list[dict[str, Any]],
) -> int:
    """チャット1メッセージ分。二重課金の判定はmessage_idごと。"""
    return _consume_chat_cost(
        user_id, thread_id, "CHAT_MESSAGE", "message_id", message_id, cost_usd, cost_breakdown,
    )


def consume_chat_summary_credits(
    user_id: str,
    thread_id: str,
    summary_block_id: str,
    cost_usd: float,
    cost_breakdown: list[dict[str, Any]],
) -> int:
    """
    スレッド要約1ブロック分。メッセージの課金とは別の行にする
    (CHAT_MESSAGEはmessage_idで二重課金を弾くため、同じメッセージに
    要約分を上乗せできない)。二重課金の判定はsummary_block_idごと。
    """
    return _consume_chat_cost(
        user_id, thread_id, "CHAT_SUMMARY", "summary_block_id", summary_block_id, cost_usd, cost_breakdown,
    )


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

    # 講義レコード自体にも消費クレジット(マイクロクレジット)を記録
    try:
        supabase.table("lectures").update({"credits_used": micro_credits}).eq("id", lecture_id).execute()
    except Exception as e:
        logger.warning(f"consume_lecture_credits: failed to update lectures.credits_used for {lecture_id}: {e}")

