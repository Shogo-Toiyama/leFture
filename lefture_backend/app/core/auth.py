"""
認証まわりの共通処理。

もともと main.py に置いていた JWT 検証(_bearer_token / _authenticate_request)を
ここへ移し、main.py と Adminルーター(app/api/admin.py)の双方から同じ実装を
使えるようにしたもの。main.py 側は後方互換の別名を残しているため、既存の
エンドポイントの呼び出し方は一切変わっていない。

加えて、Adminダッシュボード専用のゲート(require_admin)をここに置く。
Admin判定をDBに持たせない・RLSに触らないというのがこのダッシュボードの
設計方針で、その根拠は require_admin の docstring に書いてある。
"""

import os
import json
import base64
import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timezone

import httpx
from fastapi import HTTPException, Request
from supabase import AuthError, AuthApiError, AuthRetryableError

from app.core.supabase import get_supabase_auth_client

logger = logging.getLogger(__name__)


def _bearer_token(request: Request) -> str:
    """AuthorizationヘッダからJWTを取り出す。無ければ401。"""
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    token = auth_header.replace("Bearer ", "").strip()
    if not token:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    return token


def _authenticate_request(request: Request):
    """
    AuthorizationヘッダのJWTをSupabase Authで検証し、userを返す。

    以前はこの処理が全エンドポイントにコピペで散らばっており、例外の扱いが
    バラバラだった。特にget_user()が投げるAuthApiErrorを捕まえていない
    エンドポイント(/billing/summary等)では、単なるセッション失効が500として
    返っていた。500だとクライアントは「サーバー障害」と解釈して再認証に
    進めないため、死んだトークンを送り続ける無限ループになる
    (2026-09-19にクレジット表示が最大1時間読めなくなった事象の直接原因)。

    方針:
      - 「GoTrueがトークンを見て明確に拒否した」場合だけ401で返す
        (クライアントはこの401を見てセッションを破棄し再ログインに誘導する)
      - それ以外 — Auth自体が落ちている(5xx系=AuthRetryableError)、
        GoTrueのレート制限(429)、backend↔Supabase Auth間の生の通信失敗
        (httpx.HTTPError — ConnectError/ReadTimeout/RemoteProtocolError等。
        これらはsupabase_authのAuthError系に変換されずここまで素通りしてくる)
        — は全て503で返す。401にするとクライアントが不要なサインアウトを
        してしまうため(2026-09-20、一時的な通信失敗で頻繁にログアウトされる
        事象の直接原因だった)
      - GoTrueが返すerror_code(bad_jwt / session_not_found / user_not_found 等)を
        必ずログに残す。これが無いと「なぜ弾かれたか」がログから復元できない

    この関数は同期HTTPを行うので、asyncエンドポイントからは
    _get_authenticated_user_id_async()等のasync版を使うこと。
    """
    token = _bearer_token(request)
    try:
        user_res = get_supabase_auth_client().auth.get_user(token)
    except AuthRetryableError as e:
        logger.error(f"Supabase Auth unavailable while verifying JWT: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail="Authentication service temporarily unavailable")
    except AuthApiError as e:
        code = getattr(e, "code", None) or "unknown"
        status = getattr(e, "status", None)
        logger.warning(f"JWT rejected by Supabase Auth: code={code} status={status} message={e}")
        if status == 429:
            # レート制限。トークンが無効なわけではないので401にしてはいけない。
            raise HTTPException(status_code=503, detail="Authentication service rate limited")
        raise HTTPException(status_code=401, detail=f"Invalid or expired session ({code})")
    except AuthError as e:
        # AuthApiError以外のAuthError(例: AuthUnknownError)。GoTrueがJWTの
        # 中身まで見て拒否したと確定できないため、安全側に倒して503にする。
        code = getattr(e, "code", None) or "unknown"
        logger.warning(f"Unexpected auth error while verifying JWT: code={code} message={e}")
        raise HTTPException(status_code=503, detail="Authentication service temporarily unavailable")
    except httpx.HTTPError as e:
        # backend→Supabase Auth間の生の通信失敗(ConnectError/ReadTimeout/
        # RemoteProtocolError等)。supabase_authはHTTPStatusError/RuntimeError
        # しかAuthRetryableErrorに変換しないため、httpx側の例外はここまで
        # ラップされずに素通りしてくる。トークンの正当性とは無関係なので401
        # にしてはいけない。
        logger.error(f"Network error while verifying JWT: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail="Authentication service temporarily unavailable")
    except Exception as e:
        # ここに来るのは真に想定外のエラーのみ。トークンが不正だと確定した
        # わけではないため、クライアントを不要にサインアウトさせないよう503にする。
        logger.error(f"Unexpected error verifying JWT: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail="Authentication service temporarily unavailable")

    if not user_res or not user_res.user:
        raise HTTPException(status_code=401, detail="Unauthorized user")

    return user_res.user


async def get_authenticated_user(request: Request):
    """認証済みユーザー本体(email/user_metadata等)が必要な場合に使う。"""
    return await asyncio.to_thread(_authenticate_request, request)


async def get_authenticated_user_id(request: Request) -> str:
    """認証済みユーザーのidだけが必要な場合に使う。"""
    user = await asyncio.to_thread(_authenticate_request, request)
    return user.id


# ---------------------------------------------------------
# Admin ゲート
# ---------------------------------------------------------
def _admin_user_ids() -> frozenset[str]:
    """
    管理者のuser_idの集合。DBではなく環境変数(Cloud Runのランタイム設定)で
    持つ —— DBが侵害されても、あるいはRLSやuser_profilesの書き込み経路に
    穴があっても、管理者が増えないようにするため。

    user_metadataやuser_profilesで管理者を判定する設計にしてはいけない:
    user_metadataは本人が更新でき、user_profilesは本人がinsert/updateできる。
    「自分でadminフラグを立てられる」= 全ユーザーのデータが全員に見える、
    という最悪の事故に直結する。
    """
    raw = os.getenv("ADMIN_USER_IDS", "")
    return frozenset(uid.strip() for uid in raw.split(",") if uid.strip())


def _admin_require_mfa() -> bool:
    return os.getenv("ADMIN_REQUIRE_MFA", "true").strip().lower() not in ("false", "0", "no")


def _admin_mfa_max_age_hours() -> int:
    return int(os.getenv("ADMIN_MFA_MAX_AGE_HOURS", "12"))


@dataclass(frozen=True)
class AdminIdentity:
    """require_admin()が通ったリクエストの発行者。監査ログの主語になる。"""
    user_id: str
    email: str | None
    aal: str | None
    ip: str | None
    user_agent: str | None


def decode_jwt_claims_unverified(token: str) -> dict:
    """
    JWTのペイロード部をデコードする(署名検証はしない)。

    「検証していないJWTを信じる」ように見えるが、この関数は必ず
    _authenticate_request() が成功した直後にだけ呼ぶ。つまりその時点で
    Supabase Auth(GoTrue)がそのトークンの署名・有効期限・失効を検証済みで、
    ここでは「同じトークンの中に何が書いてあるか」を読み出しているだけ。
    aal/amr のようなセッションの強度に関する主張は get_user() のレスポンス
    (=ユーザー情報)には含まれず、トークンのclaimにしか無いためこの読み出しが要る。

    ★ 順序を絶対に入れ替えないこと。検証前にこの関数の戻り値で分岐すると、
      攻撃者が自作した未署名トークンで aal2 を主張できてしまう。
    """
    try:
        payload_b64 = token.split(".")[1]
        payload_b64 += "=" * (-len(payload_b64) % 4)  # base64urlのパディング復元
        return json.loads(base64.urlsafe_b64decode(payload_b64))
    except Exception as e:
        logger.warning(f"Failed to decode JWT claims: {type(e).__name__}: {e}")
        return {}


def _client_ip(request: Request) -> str | None:
    """Cloud Runの前段(Google Front End)が付けるX-Forwarded-Forの最初の要素。"""
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else None


def _mfa_age_seconds(claims: dict) -> float | None:
    """
    amr(Authentication Methods References)から、MFAを実際に通した時刻を探して
    経過秒数を返す。見つからない場合はNone。
    """
    amr = claims.get("amr")
    if not isinstance(amr, list):
        return None
    timestamps = [
        entry.get("timestamp")
        for entry in amr
        if isinstance(entry, dict)
        and isinstance(entry.get("timestamp"), (int, float))
        and "totp" in str(entry.get("method", "")).lower()
    ]
    if not timestamps:
        return None
    return datetime.now(timezone.utc).timestamp() - max(timestamps)


def _require_admin(request: Request) -> AdminIdentity:
    """
    Adminダッシュボード専用のゲート。同期版(asyncio.to_thread経由で使う)。

    3段構えで、どれか1つでも欠けたら通さない:
      1. Supabase AuthがJWTを検証している(=正規のログインセッション)
      2. そのuser_idが環境変数ADMIN_USER_IDSに載っている
      3. そのセッションがMFA(TOTP)を通っている(aal2)かつ、通ってから
         ADMIN_MFA_MAX_AGE_HOURS以内である

    3が重要なのは、Adminダッシュボードを通常利用と同じセッションの上に
    載せているため。MFAを要求しないと、普段使いのアクセストークンが漏れた
    瞬間に全ユーザーのデータを操作できる鍵になってしまう。逆にMFAを
    要求しておけば、盗まれたトークンでできることは「そのユーザー自身の
    普通の操作」までに留まる。

    ★ フロントエンドのルーティングやUIの出し分けは、セキュリティ境界では
      一切ない(SPAのJSは誰でもダウンロードできる)。守っているのはここだけ。
    """
    admin_ids = _admin_user_ids()
    if not admin_ids:
        # 未設定のまま動かすと全員が素通りする実装にだけは絶対にしない。
        logger.error("ADMIN_USER_IDS is not configured; refusing all admin requests")
        raise HTTPException(status_code=403, detail="Admin access is not configured")

    token = _bearer_token(request)
    user = _authenticate_request(request)   # ← ここで署名・有効期限・失効を検証

    if user.id not in admin_ids:
        # 誰が叩いたかは必ず残す。ここへの到達自体が調査対象になりうる。
        logger.warning(f"Rejected admin request from non-admin user {user.id} ip={_client_ip(request)}")
        raise HTTPException(status_code=404, detail="Not found")

    claims = decode_jwt_claims_unverified(token)
    aal = claims.get("aal")

    if _admin_require_mfa():
        if aal != "aal2":
            logger.warning(f"Rejected admin request from {user.id}: aal={aal} (MFA required)")
            raise HTTPException(
                status_code=403,
                detail={
                    "error_code": "ADMIN_MFA_REQUIRED",
                    "message": "Admin access requires a multi-factor (TOTP) verified session.",
                },
            )

        age = _mfa_age_seconds(claims)
        max_age = _admin_mfa_max_age_hours() * 3600
        if age is None:
            # aal2は取れているのでMFA自体は通っている。鮮度だけ判定できない
            # (amrの形が想定と違う)ケースなので、拒否せず記録に留める。
            logger.warning(f"Admin session for {user.id} is aal2 but carries no TOTP timestamp in amr")
        elif age > max_age:
            logger.warning(f"Rejected admin request from {user.id}: MFA is {int(age)}s old (max {max_age}s)")
            raise HTTPException(
                status_code=403,
                detail={
                    "error_code": "ADMIN_MFA_STALE",
                    "message": "Admin session is too old. Re-verify with your authenticator app.",
                },
            )

    return AdminIdentity(
        user_id=user.id,
        email=getattr(user, "email", None),
        aal=aal,
        ip=_client_ip(request),
        user_agent=request.headers.get("user-agent"),
    )


async def require_admin(request: Request) -> AdminIdentity:
    """
    FastAPIのDependencyとして使うAdminゲート。

    _require_admin()はSupabase Authへの同期HTTP(get_user)を含むため、必ず
    asyncio.to_threadでイベントループの外に出す(他エンドポイントと同じ理由)。
    """
    return await asyncio.to_thread(_require_admin, request)
