"""
Adminダッシュボードの監査ログ書き込み。

方針:
  - 変更を伴う操作(クレジット付与・停止・削除…)は「やる前に」記録し、
    結果が出てから result を確定させる… ということはしない。代わりに
    「操作が終わってから1行だけ書く」。理由: 途中経過の行を後から更新する
    設計にすると admin_audit_log を追記専用(UPDATE禁止)にできなくなるため。
    失敗した操作も result='error' として1行残るので、抜けは生じない。
  - PIIの開示(メールアドレスのマスク解除)も記録対象。覗いたこと自体が
    残らないと「見ていない」を後から示せない。
  - params に講義本文・トランスクリプト・生成コンテンツを入れてはいけない。
    入れてよいのはID・件数・理由・金額といったメタデータだけ。

書き込みに失敗しても操作自体は止めない(ログには残す)。監査のためにユーザー
対応が止まる方が実害が大きいため。ただし失敗はerrorログに出るので気付ける。
"""

import asyncio
import logging
from typing import Any, Optional

from app.core.auth import AdminIdentity
from app.core.supabase import get_supabase_client

logger = logging.getLogger(__name__)


async def record_admin_action(
    admin: AdminIdentity,
    action: str,
    *,
    target_type: Optional[str] = None,
    target_id: Optional[str] = None,
    params: Optional[dict[str, Any]] = None,
    result: str = "ok",
    error_message: Optional[str] = None,
) -> None:
    row = {
        "admin_user_id": admin.user_id,
        "admin_email": admin.email,
        "action": action,
        "target_type": target_type,
        "target_id": str(target_id) if target_id is not None else None,
        "params": params or {},
        "result": result,
        "error_message": error_message[:2000] if error_message else None,
        "ip": admin.ip,
        "user_agent": (admin.user_agent or "")[:500] or None,
    }

    try:
        admin_client = get_supabase_client()
        await asyncio.to_thread(
            lambda: admin_client.table("admin_audit_log").insert(row).execute()
        )
    except Exception as e:
        logger.error(
            f"❌ Failed to write admin audit log (action={action} target={target_type}:{target_id}): {e}",
            exc_info=True,
        )
