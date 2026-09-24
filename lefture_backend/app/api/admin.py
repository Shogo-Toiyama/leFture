"""
Adminダッシュボードのバックエンド。

このルーターの全エンドポイントは require_admin を通る(ルーター単位の
dependenciesにも入れてあるので、個別のルートで書き忘れても素通りしない)。

このダッシュボードが「できてはいけないこと」——実装を足すときは必ずここを読むこと:

  A. 講義の中身を見ない
     トランスクリプト・Deep Notes・Review Card・Fun Fact・要約・タイトル、
     そして音声そのもの。講義の録音には教授やクラスメイトという
     「ユーザー本人ですらない第三者」の声が入っている。運営に見る権利は無い。
     返してよいのは件数・長さ・ステータス・消費クレジット・エラーだけ。

  B. なりすまさない
     impersonation(このユーザーとしてログイン)、パスワードの閲覧・設定、
     セッショントークンの取得、メールアドレスの変更。本人確認フローを
     迂回する手段を作らない。

  C. 台帳とプロバイダを迂回しない
     クレジットは必ず grant_credits() 経由(=credit_grantsに台帳が残る)。
     プラン状態の直接書き換えや返金はやらない —— Stripe/App Store側が
     正であり、こちらはリンクを出すだけ。

  D. 汎用のテーブルエディタにしない
     任意SQL・任意テーブルのCRUD・一括操作(全員への送信、一括削除)・
     ユーザー一覧のエクスポートは作らない。ここにあるのは「名前の付いた
     限定的な操作」の集合であって、Supabase Dashboardの代替ではない。

  E. 監査ログを消せない
     admin_audit_log はDBトリガでUPDATE/DELETEを拒否している。
"""

import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.core.admin_audit import record_admin_action
from app.core.auth import AdminIdentity, require_admin
from app.core.supabase import get_supabase_client
from app.services.helpers.credits import MICRO_CREDITS_PER_CREDIT

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])

# 1回の手動付与の上限(表示単位のクレジット)。運用上これを超える付与が
# 必要になることは無いはずで、桁を間違えた入力を止めるための安全装置。
MAX_MANUAL_GRANT_CREDITS = 10_000


def _to_micro_credits(credits: float) -> int:
    return int(round(credits * MICRO_CREDITS_PER_CREDIT))


async def _rpc(fn: str, params: Optional[dict] = None):
    """service_role権限でSQL関数を呼ぶ。admin_* 関数はservice_roleにしか
    EXECUTE権限が無い(migration 20260930010000)。"""
    admin_client = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: admin_client.rpc(fn, params or {}).execute()
    )
    return res.data


# ===========================================================================
# 1. 自分自身 / ヘルスチェック
# ===========================================================================
@router.get("/me")
async def admin_me(admin: AdminIdentity = Depends(require_admin)):
    """
    フロントエンドはこのエンドポイントが200を返すかどうかだけで
    Adminメニューを出すか決める。判定ロジックをフロントに持たせない
    (SPAのJSは誰でも読めるので、フロントの分岐はセキュリティ境界ではない)。
    """
    return {"user_id": admin.user_id, "email": admin.email, "aal": admin.aal}


# ===========================================================================
# 2. 統計(集計のみ。個人を跨ぐ生データはSQL側で閉じている)
# ===========================================================================
@router.get("/overview")
async def admin_overview():
    return await _rpc("admin_overview_stats")


@router.get("/series")
async def admin_series(days: int = Query(30, ge=1, le=365)):
    return await _rpc("admin_daily_series", {"p_days": days})


@router.get("/pipeline")
async def admin_pipeline(days: int = Query(7, ge=1, le=90)):
    return await _rpc("admin_pipeline_health", {"p_days": days})


@router.get("/hourly")
async def admin_hourly(days: int = Query(30, ge=1, le=365)):
    """
    時間帯・曜日・プラットフォーム・タイムゾーンごとの利用分布。

    `local` がユーザーのローカル時刻ベース、`utc` がUTCベース。見るべきは
    ほぼ常に `local` —— UTCで集計すると利用者の住む地域が混ざって分布が潰れる。
    """
    return await _rpc("admin_hourly_distribution", {"p_days": days})


@router.get("/plans")
async def admin_plans():
    return await _rpc("admin_plan_distribution")


# ===========================================================================
# 3. ユーザー(閲覧)
# ===========================================================================
@router.get("/users")
async def admin_users(
    q: Optional[str] = Query(None, max_length=200),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """メールは必ずマスク済みで返る(admin_user_search内でマスクしている)。"""
    return await _rpc("admin_user_search", {"p_query": q, "p_limit": limit, "p_offset": offset})


@router.get("/users/{user_id}")
async def admin_user_detail(user_id: str):
    data = await _rpc("admin_user_detail", {"p_user_id": user_id})
    if not data:
        raise HTTPException(status_code=404, detail="User not found")
    return data


@router.get("/users/{user_id}/lectures")
async def admin_user_lectures(user_id: str, limit: int = Query(100, ge=1, le=500)):
    """
    メタデータのみ。タイトルも要約も返らない(admin_user_lectures関数の
    コメント参照)。ここに「タイトルくらいは」と足したくなったら、
    その前にこのファイル冒頭のAを読み直すこと。
    """
    return await _rpc("admin_user_lectures", {"p_user_id": user_id, "p_limit": limit})


@router.get("/users/{user_id}/credits")
async def admin_user_credits(user_id: str, limit: int = Query(100, ge=1, le=500)):
    """クレジットの台帳(grants)と増減履歴(transactions)。金額とタグのみ。"""
    admin_client = get_supabase_client()

    grants_res = await asyncio.to_thread(
        lambda: admin_client.table("credit_grants")
            .select("id, created_at, amount, remaining_amount, source, plan_id, expires_at, metadata")
            .eq("user_id", user_id).order("created_at", desc=True).limit(limit).execute()
    )
    tx_res = await asyncio.to_thread(
        lambda: admin_client.table("credit_transactions")
            .select("id, created_at, delta, balance_after, reason, related_job_id, related_grant_id, metadata")
            .eq("user_id", user_id).order("created_at", desc=True).limit(limit).execute()
    )
    return {"grants": grants_res.data or [], "transactions": tx_res.data or []}


@router.post("/users/{user_id}/reveal-email")
async def admin_reveal_email(user_id: str, admin: AdminIdentity = Depends(require_admin)):
    """
    マスクを外した本物のメールアドレスを返す。

    GETではなくPOSTなのは「これは副作用のある操作である」と明示するため
    —— 開示は必ず監査ログに1行残る。誤ってリンクのプリフェッチや
    ブラウザの履歴再訪で開示ログが増えないようにする意図もある。
    """
    email = await _rpc("admin_user_email", {"p_user_id": user_id})
    if not email:
        raise HTTPException(status_code=404, detail="User not found")

    await record_admin_action(
        admin, "user.email.reveal", target_type="user", target_id=user_id
    )
    return {"user_id": user_id, "email": email}


# ===========================================================================
# 4. ユーザー(操作)
# ===========================================================================
class GrantCreditsRequest(BaseModel):
    credits: float = Field(..., gt=0, description="表示単位のクレジット(μクレジットではない)")
    reason: str = Field(..., min_length=3, max_length=500)
    expires_in_days: Optional[int] = Field(None, ge=1, le=3650)


@router.post("/users/{user_id}/credits/grant")
async def admin_grant_credits(
    user_id: str,
    payload: GrantCreditsRequest,
    admin: AdminIdentity = Depends(require_admin),
):
    """
    クレジットを手動で付与する。

    必ず grant_credits() SQL関数を通す —— 残高は credit_grants から毎回
    導出する設計で、台帳を経由しない加算は存在してはいけないため
    (credit_grantsに行を直接INSERTするのも不可: credit_transactionsへの
    記録と失効の実体化が飛ばされる)。
    """
    if payload.credits > MAX_MANUAL_GRANT_CREDITS:
        raise HTTPException(
            status_code=400,
            detail=f"Refusing to grant more than {MAX_MANUAL_GRANT_CREDITS} credits at once",
        )

    micro = _to_micro_credits(payload.credits)
    if micro <= 0:
        raise HTTPException(status_code=400, detail="Amount rounds to zero credits")

    admin_client = get_supabase_client()

    expires_at = None
    if payload.expires_in_days:
        from datetime import datetime, timedelta, timezone
        expires_at = (datetime.now(timezone.utc) + timedelta(days=payload.expires_in_days)).isoformat()

    try:
        res = await asyncio.to_thread(
            lambda: admin_client.rpc("grant_credits", {
                "p_user_id": user_id,
                "p_amount": micro,
                "p_source": "admin_manual",
                "p_plan_id": None,
                "p_expires_at": expires_at,
            }).execute()
        )
    except Exception as e:
        await record_admin_action(
            admin, "credits.grant", target_type="user", target_id=user_id,
            params={"credits": payload.credits, "reason": payload.reason},
            result="error", error_message=str(e),
        )
        raise HTTPException(status_code=500, detail=f"Failed to grant credits: {e}")

    grant = res.data if isinstance(res.data, dict) else (res.data or [None])[0]
    grant_id = grant.get("id") if isinstance(grant, dict) else None

    # 付与の理由と実行者を台帳側にも残す。監査ログが主で、こちらは
    # credit_grantsだけを見ている人にも由来が分かるようにするための控え。
    if grant_id:
        await asyncio.to_thread(
            lambda: admin_client.table("credit_grants").update({
                "metadata": {
                    "granted_by_admin": admin.user_id,
                    "reason": payload.reason,
                }
            }).eq("id", grant_id).execute()
        )

    await record_admin_action(
        admin, "credits.grant", target_type="user", target_id=user_id,
        params={
            "credits": payload.credits,
            "micro_credits": micro,
            "reason": payload.reason,
            "grant_id": grant_id,
            "expires_at": expires_at,
        },
    )
    return {"success": True, "grant_id": grant_id, "credits": payload.credits}


class SuspendRequest(BaseModel):
    reason: str = Field(..., min_length=3, max_length=500)


@router.post("/users/{user_id}/suspend")
async def admin_suspend_user(
    user_id: str,
    payload: SuspendRequest,
    admin: AdminIdentity = Depends(require_admin),
):
    """
    アカウントを停止する(account_suspensionsに行を追加)。

    停止中でも閲覧・サブスク解約・サポート問い合わせ・アカウント削除は
    通る(main.pyの_reject_if_suspendedを参照)。制限したまま課金だけ続く
    状態や、異議申立ての手段を奪う状態を作らないため。
    """
    admin_client = get_supabase_client()
    await asyncio.to_thread(
        lambda: admin_client.table("account_suspensions").upsert({
            "user_id": user_id,
            "reason": payload.reason,
            "suspended_by": admin.user_id,
        }).execute()
    )
    await record_admin_action(
        admin, "user.suspend", target_type="user", target_id=user_id,
        params={"reason": payload.reason},
    )
    return {"success": True, "user_id": user_id, "suspended": True}


@router.post("/users/{user_id}/unsuspend")
async def admin_unsuspend_user(user_id: str, admin: AdminIdentity = Depends(require_admin)):
    admin_client = get_supabase_client()
    await asyncio.to_thread(
        lambda: admin_client.table("account_suspensions").delete().eq("user_id", user_id).execute()
    )
    await record_admin_action(admin, "user.unsuspend", target_type="user", target_id=user_id)
    return {"success": True, "user_id": user_id, "suspended": False}


class DeleteUserRequest(BaseModel):
    # 二段階確認。フロントで対象のuser_idを打ち直させ、ここで突き合わせる。
    confirm_user_id: str
    reason: str = Field(..., min_length=3, max_length=500)


@router.post("/users/{user_id}/delete")
async def admin_delete_user(
    user_id: str,
    payload: DeleteUserRequest,
    admin: AdminIdentity = Depends(require_admin),
):
    """
    ユーザーのデータとアカウントを完全に削除する(取り消し不可)。

    ユーザー自身の /auth/delete-account と完全に同じ処理を呼ぶ。admin用に
    別経路の削除ロジックを持つと、片方だけ消し漏れが出る。
    """
    if payload.confirm_user_id != user_id:
        raise HTTPException(status_code=400, detail="confirm_user_id does not match the target user")

    # 遅延import: app.mainがこのルーターをimportするため、モジュール先頭では
    # 循環import になる。呼び出し時点ではapp.mainは読み込み済み。
    from app.main import _hard_delete_user_data

    admin_client = get_supabase_client()
    try:
        await _hard_delete_user_data(admin_client, user_id)
        await asyncio.to_thread(lambda: admin_client.auth.admin.delete_user(user_id))
    except Exception as e:
        await record_admin_action(
            admin, "user.delete", target_type="user", target_id=user_id,
            params={"reason": payload.reason}, result="error", error_message=str(e),
        )
        logger.error(f"❌ Admin failed to delete user {user_id}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to delete user: {e}")

    await record_admin_action(
        admin, "user.delete", target_type="user", target_id=user_id,
        params={"reason": payload.reason},
    )
    return {"success": True, "user_id": user_id}


# ===========================================================================
# 5. パイプラインの復旧操作
# ===========================================================================
@router.post("/lectures/{lecture_id}/cancel-jobs")
async def admin_cancel_lecture_jobs(lecture_id: str, admin: AdminIdentity = Depends(require_admin)):
    """止まっている/暴走しているジョブを打ち切る。行そのものは消さない。"""
    from app.main import _cancel_jobs_for_lecture

    admin_client = get_supabase_client()
    cancelled = await _cancel_jobs_for_lecture(admin_client, lecture_id)

    await record_admin_action(
        admin, "lecture.cancel_jobs", target_type="lecture", target_id=lecture_id,
        params={"cancelled_jobs": cancelled},
    )
    return {"success": True, "cancelled_jobs": cancelled}


@router.post("/tasks/{task_id}/retry")
async def admin_retry_task(task_id: str, admin: AdminIdentity = Depends(require_admin)):
    """
    失敗したタスクを(依存する後続タスクごと)やり直す。ユーザー向けの
    /retry-task と同じ実装を共有している(所有者チェックだけが無い)。
    """
    from app.main import _perform_task_retry, _load_task_and_job

    admin_client = get_supabase_client()
    task, job = await _load_task_and_job(admin_client, task_id)
    result = await _perform_task_retry(admin_client, task, job)

    await record_admin_action(
        admin, "task.retry", target_type="task", target_id=task_id,
        params={"job_id": task["job_id"], "task_type": task["task_type"], "owner_user_id": job["user_id"]},
    )
    return result


# ===========================================================================
# 6. サポートチケット
# ===========================================================================
@router.get("/support/tickets")
async def admin_support_tickets(
    status: Optional[str] = Query(None, max_length=50),
    limit: int = Query(50, ge=1, le=200),
):
    """
    一覧ではメールをマスクして返す。本文(message)はユーザーが運営宛てに
    自分で書いて送ったものなので、読むことに問題は無い。
    """
    admin_client = get_supabase_client()

    def _query():
        q = (admin_client.table("support_tickets")
             .select("id, ticket_code, user_id, user_email, category, message, status, created_at, updated_at")
             .order("created_at", desc=True).limit(limit))
        if status:
            q = q.eq("status", status)
        return q.execute()

    res = await asyncio.to_thread(_query)
    tickets = res.data or []
    for t in tickets:
        email = t.pop("user_email", None) or ""
        local, _, domain = email.partition("@")
        t["user_email_masked"] = f"{local[:2]}***@{domain}" if domain else None
    return tickets


@router.post("/support/tickets/{ticket_id}/reveal-email")
async def admin_reveal_ticket_email(ticket_id: str, admin: AdminIdentity = Depends(require_admin)):
    """返信のために本物のメールアドレスを取り出す。開示は監査ログに残る。"""
    admin_client = get_supabase_client()
    res = await asyncio.to_thread(
        lambda: admin_client.table("support_tickets")
            .select("id, user_id, user_email, attachment_urls, device_info")
            .eq("id", ticket_id).maybe_single().execute()
    )
    ticket = res.data if res else None
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")

    await record_admin_action(
        admin, "support.email.reveal", target_type="support_ticket", target_id=ticket_id,
        params={"user_id": ticket.get("user_id")},
    )
    return ticket


class TicketStatusRequest(BaseModel):
    status: str = Field(..., pattern="^(open|in_progress|resolved|closed)$")


@router.post("/support/tickets/{ticket_id}/status")
async def admin_set_ticket_status(
    ticket_id: str,
    payload: TicketStatusRequest,
    admin: AdminIdentity = Depends(require_admin),
):
    admin_client = get_supabase_client()
    await asyncio.to_thread(
        lambda: admin_client.table("support_tickets")
            .update({"status": payload.status}).eq("id", ticket_id).execute()
    )
    await record_admin_action(
        admin, "support.status", target_type="support_ticket", target_id=ticket_id,
        params={"status": payload.status},
    )
    return {"success": True, "ticket_id": ticket_id, "status": payload.status}


# ===========================================================================
# 7. 監査ログ(閲覧のみ。消す手段はどこにも無い)
# ===========================================================================
@router.get("/audit-log")
async def admin_audit_log(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    action: Optional[str] = Query(None, max_length=100),
    target_id: Optional[str] = Query(None, max_length=100),
):
    admin_client = get_supabase_client()

    def _query():
        q = (admin_client.table("admin_audit_log").select("*")
             .order("created_at", desc=True).range(offset, offset + limit - 1))
        if action:
            q = q.eq("action", action)
        if target_id:
            q = q.eq("target_id", target_id)
        return q.execute()

    res = await asyncio.to_thread(_query)
    return res.data or []
