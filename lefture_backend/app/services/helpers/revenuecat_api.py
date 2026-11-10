"""RevenueCat REST API v2 の読み取り専用クライアント。

使う権限(v2 secret key):
  - customer_information:subscriptions:read  … GET /customers/{id}/subscriptions
  - project_configuration:products:read      … GET /products/{id}
書き込み系のエンドポイントは一切呼ばない。

実機確認(2026-11-10, contents_generation/test_codes/revenuecat_reconcile):
  - alias の app user id(Supabase uuid)でも顧客を引ける
  - 存在しないIDは 404 resource_missing(顧客は作られない。v1のGETは作ってしまう)
  - subscriptions は1ページ最大 limit 件、続きは next_page(絶対URL)
  - subscription.product_id は RevenueCat 内部ID(prod61c65a81de 等)で、
    ストアの商品ID(com.lefture.app.sub.premium 等)ではない → /products で変換する
"""

import logging
import os
import time
from typing import Optional
from urllib.parse import quote

import httpx

logger = logging.getLogger(__name__)

API_BASE = "https://api.revenuecat.com/v2"
SECRET_KEY = os.getenv("REVENUECAT_SECRET_API_KEY", "")
PROJECT_ID = os.getenv("REVENUECAT_PROJECT_ID", "")

PAGE_LIMIT = 100
MAX_PAGES = 10
REQUEST_TIMEOUT_SECONDS = 8.0

# RevenueCat内部の商品ID -> ストアの商品ID。商品定義はほぼ変わらないので
# プロセス内で長めにキャッシュする(見つからなかったIDは短めに)。
_PRODUCT_CACHE: dict[str, tuple[float, Optional[str]]] = {}
_PRODUCT_TTL_SECONDS = 6 * 3600
_PRODUCT_NEGATIVE_TTL_SECONDS = 600


class RevenueCatAPIError(Exception):
    pass


def is_configured() -> bool:
    return bool(SECRET_KEY and PROJECT_ID)


def _headers() -> dict:
    return {"Authorization": f"Bearer {SECRET_KEY}", "Accept": "application/json"}


async def _get(client: httpx.AsyncClient, url: str) -> tuple[int, dict]:
    res = await client.get(url, headers=_headers(), timeout=REQUEST_TIMEOUT_SECONDS)
    try:
        body = res.json()
    except ValueError:
        body = {"raw": res.text[:500]}
    return res.status_code, body


async def fetch_customer_subscriptions(app_user_id: str) -> Optional[list]:
    """顧客の全サブスク(期限切れ含む)を返す。顧客が存在しなければ []。

    全ページを取り切れなかった場合(ページ上限超え)は None を返す。呼び出し側は
    None を「判断材料が不完全」として扱い、DBを変更してはならない。
    API/ネットワークエラーは RevenueCatAPIError。
    """
    url = f"{API_BASE}/projects/{PROJECT_ID}/customers/{quote(app_user_id, safe='')}/subscriptions?limit={PAGE_LIMIT}"
    items: list = []
    async with httpx.AsyncClient() as client:
        for _ in range(MAX_PAGES):
            try:
                status, body = await _get(client, url)
            except httpx.HTTPError as e:
                raise RevenueCatAPIError(f"network error: {e}") from e
            if status == 404:
                return []
            if status != 200:
                raise RevenueCatAPIError(f"GET subscriptions -> {status}: {str(body)[:300]}")
            items.extend(body.get("items") or [])
            url = body.get("next_page")
            if not url:
                return items
    logger.warning(f"RevenueCat subscriptions for {app_user_id}: more than {MAX_PAGES} pages; treating as incomplete")
    return None


async def get_store_identifier(rc_product_id: str) -> Optional[str]:
    """RevenueCat内部の商品ID -> ストアの商品ID(Appleならcom.lefture...、Stripeならprod_xxx)。"""
    now = time.monotonic()
    cached = _PRODUCT_CACHE.get(rc_product_id)
    if cached and cached[0] > now:
        return cached[1]
    url = f"{API_BASE}/projects/{PROJECT_ID}/products/{quote(rc_product_id, safe='')}"
    async with httpx.AsyncClient() as client:
        try:
            status, body = await _get(client, url)
        except httpx.HTTPError as e:
            raise RevenueCatAPIError(f"network error: {e}") from e
    if status == 404:
        _PRODUCT_CACHE[rc_product_id] = (now + _PRODUCT_NEGATIVE_TTL_SECONDS, None)
        return None
    if status != 200:
        raise RevenueCatAPIError(f"GET product {rc_product_id} -> {status}: {str(body)[:300]}")
    store_identifier = body.get("store_identifier")
    _PRODUCT_CACHE[rc_product_id] = (now + _PRODUCT_TTL_SECONDS, store_identifier)
    return store_identifier
