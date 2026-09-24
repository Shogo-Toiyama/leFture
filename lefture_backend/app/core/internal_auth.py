"""
内部呼び出し専用エンドポイント(/worker/*, /enqueue-task, /maintenance/*)の認証。

これらは Cloud Tasks / Cloud Scheduler / バックエンド自身からしか呼ばれない
にもかかわらず、これまで認証チェックが一切無かった。Cloud Runが
allow-unauthenticatedで公開されている以上、URLさえ知っていれば誰でも
パイプラインのタスクを起動したり、任意のjob_id/user_idで処理を走らせたり、
メンテナンス処理(R2の一括削除を含む)を叩けてしまう状態だった。

受け入れる資格情報は2種類。どちらか一方が通ればよい:

  1. X-Internal-Secret ヘッダ (INTERNAL_API_SECRET と定数時間比較)
     バックエンドがCloud Tasksにタスクを積むときに自分で付ける。GCP側の
     設定に依存しないので、デプロイした瞬間から確実に効く。

  2. Google署名のOIDC IDトークン (Authorization: Bearer ...)
     Cloud Tasksは既に oidc_token(service_account_email, audience=CLOUD_RUN_URL)
     付きでリクエストしているので、こちらは追加設定なしで成立する。
     Cloud Schedulerからのpatrol呼び出しも、コンソールでOIDCトークンを
     設定してあればこの経路で通る。

2つ用意しているのは移行の安全のため —— デプロイ時点でキューに残っている
古いタスクにはヘッダが付いていないが、OIDC側で通るので落ちない。

設定を促すためのフェイルセーフ: INTERNAL_API_SECRET と SERVICE_ACCOUNT_EMAIL の
両方が未設定だと、内部エンドポイントは何も受け付けられなくなる(=全拒否)。
「未設定なら素通し」にはしない。
"""

import os
import hmac
import asyncio
import logging
import threading
import time

import httpx
from fastapi import HTTPException, Request

logger = logging.getLogger(__name__)

INTERNAL_SECRET_HEADER = "X-Internal-Secret"

_GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v1/certs"
_GOOGLE_ISSUERS = ("https://accounts.google.com", "accounts.google.com")

# Googleの公開鍵は数時間〜1日単位でしか変わらない。google-authの
# verify_oauth2_token()は毎回証明書を取りに行くので、/worker/* のような
# ホットパスに1リクエスト1往復のHTTPが増える。ここで自前にキャッシュする。
_CERTS_TTL_SECONDS = 3600
_certs_cache: dict | None = None
_certs_fetched_at: float = 0.0
_certs_lock = threading.Lock()


def _internal_secret() -> str:
    return os.getenv("INTERNAL_API_SECRET", "")


def _service_account_email() -> str:
    return os.getenv("SERVICE_ACCOUNT_EMAIL", "")


def _enforced() -> bool:
    """
    段階的な切り替え用の逃がし弁。既定は有効(=検証する)。

    GCP側の設定(Cloud SchedulerへのOIDC付与など)が間に合わない場合に限り
    INTERNAL_AUTH_ENFORCED=false で一時的に外せるが、外している間は
    起動時とリクエストごとに警告を出し続ける。恒久的に false のまま
    運用してはいけない。
    """
    return os.getenv("INTERNAL_AUTH_ENFORCED", "true").strip().lower() not in ("false", "0", "no")


def internal_task_headers() -> dict[str, str]:
    """
    Cloud Tasksに積むタスクのHTTPヘッダに載せる内部認証情報。
    INTERNAL_API_SECRETが未設定なら空(その場合はOIDC側で通る)。
    """
    secret = _internal_secret()
    return {INTERNAL_SECRET_HEADER: secret} if secret else {}


def _fetch_google_certs() -> dict:
    global _certs_cache, _certs_fetched_at
    now = time.monotonic()
    if _certs_cache is not None and (now - _certs_fetched_at) < _CERTS_TTL_SECONDS:
        return _certs_cache

    with _certs_lock:
        now = time.monotonic()
        if _certs_cache is not None and (now - _certs_fetched_at) < _CERTS_TTL_SECONDS:
            return _certs_cache
        resp = httpx.get(_GOOGLE_CERTS_URL, timeout=10.0)
        resp.raise_for_status()
        _certs_cache = resp.json()
        _certs_fetched_at = now
        return _certs_cache


def _verify_google_oidc(token: str) -> bool:
    """
    Cloud Tasks / Cloud Scheduler が付けるGoogle署名のIDトークンを検証する。
    署名・有効期限・audience は google.auth.jwt が見る。発行者とサービス
    アカウントのメールはここで突き合わせる(署名が正しくても、別プロジェクトの
    サービスアカウントが発行したトークンを受け入れてはいけないため)。
    """
    expected_email = _service_account_email()
    if not expected_email:
        return False

    try:
        from google.auth import jwt as google_jwt
    except ImportError:
        logger.error("google-auth is not installed; cannot verify OIDC tokens")
        return False

    audience = os.getenv("CLOUD_RUN_URL") or None

    try:
        claims = google_jwt.decode(token, certs=_fetch_google_certs(), audience=audience)
    except Exception as e:
        logger.warning(f"OIDC token rejected: {type(e).__name__}: {e}")
        return False

    if claims.get("iss") not in _GOOGLE_ISSUERS:
        logger.warning(f"OIDC token rejected: unexpected issuer {claims.get('iss')}")
        return False
    if claims.get("email") != expected_email:
        logger.warning(f"OIDC token rejected: email {claims.get('email')} != {expected_email}")
        return False
    if claims.get("email_verified") not in (True, "true"):
        logger.warning("OIDC token rejected: email_verified is not true")
        return False

    return True


def _require_internal_caller_sync(request: Request) -> None:
    if not _enforced():
        logger.warning(
            "⚠️ INTERNAL_AUTH_ENFORCED=false — internal endpoint %s is reachable by anyone",
            request.url.path,
        )
        return

    secret = _internal_secret()
    provided = request.headers.get(INTERNAL_SECRET_HEADER, "")
    if secret and provided and hmac.compare_digest(secret, provided):
        return

    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):].strip()
        if token and _verify_google_oidc(token):
            return

    if not secret and not _service_account_email():
        logger.error(
            "Neither INTERNAL_API_SECRET nor SERVICE_ACCOUNT_EMAIL is configured; "
            "internal endpoints cannot authenticate any caller"
        )

    logger.warning(f"🔒 Blocked unauthenticated internal request to {request.url.path}")
    raise HTTPException(status_code=401, detail="Unauthorized internal request")


async def require_internal_caller(request: Request) -> None:
    """
    FastAPIのDependency。OIDC検証は初回のみ証明書取得のHTTPを伴うため
    (以降はキャッシュ)、同期処理をイベントループの外に出しておく。
    """
    await asyncio.to_thread(_require_internal_caller_sync, request)
