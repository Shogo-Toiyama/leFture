# app/services/helpers/plan_features.py
"""プランごとの機能開放を判定する一元窓口。

tier_level (0=Free, 1=Lite, 2=Core, 3=Max) とプランが解禁する機能の対応表を
ここだけに持たせ、DAGの各タスクやAPIエンドポイントはこのモジュール経由でしか
判定しない形にする。get_credit_summaryと違い、機能ゲートはtier_levelさえ
分かればよいので専用のクエリで完結させる(クレジット残高RPCとは責務を分ける)。
"""
import logging
import os

from app.core.supabase import get_supabase_client

logger = logging.getLogger(__name__)

# サブスクをまだTestFlightに出しておらず、既存のテストユーザー(Free/旧Welcome
# Bonus)には全機能を使い続けてもらいたい期間だけTrueにしておくグローバルkill-switch。
# Trueの間はhas_feature()がtier_levelを見ずに常にTrueを返す — subscription_plans側
# のtier_levelは一切書き換えない(Free=0のまま)ので、Flutter側のtier_levelベースの
# 表示ロジック(PlanOption.isPremiumTier等)には影響しない。
# サブスクUIをTestFlightに出し、テストユーザーに1年間有効のMaxプロモコードを
# 配布し終えたらFalseに戻す。
GATING_DISABLED_FOR_ALL_USERS = True

# GATING_DISABLED_FOR_ALL_USERS中でも、開発者自身の実機テスト用アカウントだけは
# 本番同様にtier_levelベースの実際のgatingを受けられるようにする許可リスト。
# 環境変数 REAL_GATING_TEST_USER_IDS にカンマ区切りのuser_id(uuid)を設定する
# (Cloud Runの環境変数 or ローカルの.env、デバイス側ではなくサーバー側の設定)。
# 重要: JWTで認証済みのuser_id(サーバー側でSupabaseから解決した値)とだけ突き合わせる
# — クライアント(Flutter)から送られてくるどんな値も信用しない。クライアントに
# gating on/offを決めさせる設計は、その値を偽装するだけで誰でも課金機能を回避できて
# しまうため、意図的に避けている。
_REAL_GATING_TEST_USER_IDS = {
    uid.strip()
    for uid in os.environ.get("REAL_GATING_TEST_USER_IDS", "").split(",")
    if uid.strip()
}

TIER_FREE = 0
TIER_LITE = 1
TIER_CORE = 2
TIER_MAX = 3

# --- Feature keys ---------------------------------------------------------
# 全プラン共通で使える機能(ReviewCards生成, Fun Fact生成, DeepNotesの
# 1トピック目プレビュー)にはキーを割り当てない。ここに列挙するのは
# 「ゲートが必要な機能」だけ。
FEATURE_KEYWORD_EXTRACTION_SUBSCRIBER = "keyword_extraction_subscriber"
FEATURE_ANNOUNCEMENT_GENERATION = "announcement_generation"
FEATURE_SOURCE_TRANSCRIPT_VIEW = "source_transcript_view"
FEATURE_TOPIC_MAP = "topic_map"
FEATURE_DEEP_NOTES_FULL = "deep_notes_full"  # Lite以上: 全トピック生成(Freeは1トピック目のみ)
FEATURE_FUN_FACT_SEARCH = "fun_fact_search"
FEATURE_REALTIME_TRANSCRIBE = "realtime_transcribe"

# feature_key -> 必要な最小tier_level。
# 今は要件が細かく(機能の一部だけ別プラン、など)、DBでの管理には向かないため
# 意図的にハードコードしている。将来Maxから段階的に降ろす場合はここを直接編集する。
_FEATURE_MIN_TIER: dict[str, int] = {
    FEATURE_KEYWORD_EXTRACTION_SUBSCRIBER: TIER_CORE,
    FEATURE_ANNOUNCEMENT_GENERATION: TIER_CORE,
    FEATURE_SOURCE_TRANSCRIPT_VIEW: TIER_CORE,
    FEATURE_TOPIC_MAP: TIER_LITE,
    FEATURE_DEEP_NOTES_FULL: TIER_LITE,
    FEATURE_FUN_FACT_SEARCH: TIER_CORE,
    FEATURE_REALTIME_TRANSCRIBE: TIER_MAX,
}


def is_gating_disabled_for_user(user_id: str | None) -> bool:
    """このユーザーについてkill-switchによる全機能開放が効いているか。

    /billing/summaryがそのままFlutter側に返す値でもある(Flutter側のUIロック
    表示は本来このサーバー側の判定と一致させたいが、実際の生成・保存の可否は
    常にこのモジュール自身が最終判断するため、この値がクライアントに渡っても
    改ざんされて悪用される心配は無い — あくまで表示用のヒント)。
    """
    return GATING_DISABLED_FOR_ALL_USERS and user_id not in _REAL_GATING_TEST_USER_IDS


def has_feature(tier_level: int, feature_key: str, *, user_id: str | None = None) -> bool:
    """tier_levelがfeature_keyを使える権利を持つか判定する。

    user_idを渡した場合、それが_REAL_GATING_TEST_USER_IDSに含まれていれば
    GATING_DISABLED_FOR_ALL_USERSが立っていても無視し、本来のtier_level判定を行う
    (開発者自身の実機テスト用。呼び出し側は必ずサーバー側で解決済みのuser_idを渡すこと)。
    """
    if feature_key not in _FEATURE_MIN_TIER:
        raise KeyError(f"Unknown feature_key: {feature_key!r}")
    if is_gating_disabled_for_user(user_id):
        return True
    return tier_level >= _FEATURE_MIN_TIER[feature_key]


def get_user_tier_level(user_id: str) -> int:
    """ユーザーが現在有効なプランのtier_levelを返す。

    有効なプラン割当が無い場合(has_active_plan=falseに相当する状態)は
    TIER_FREEとして扱う — 機能ゲート的には最も制限された側に倒すのが安全なため。
    """
    supabase = get_supabase_client()
    # user_subscription_mappingsはsubscription_plansへのFKを2本持つ
    # (plan_id, pending_plan_id 2026-09-12追加)ため、"subscription_plans(...)"
    # だけだとPostgREST側でどちらのFK経由か曖昧になりPGRST201で失敗する。
    # 現在有効なプランを見たいのでplan_id経由だと明示する。
    res = (
        supabase.table("user_subscription_mappings")
        .select("subscription_plans!plan_id(tier_level)")
        .eq("user_id", user_id)
        .eq("status", "active")
        .limit(1)
        .execute()
    )
    rows = res.data or []
    if not rows:
        return TIER_FREE

    plan = rows[0].get("subscription_plans") or {}
    tier_level = plan.get("tier_level")
    return tier_level if isinstance(tier_level, int) else TIER_FREE
