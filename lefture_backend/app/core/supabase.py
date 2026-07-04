import os
import threading
import httpx
from supabase import create_client, Client, ClientOptions

_client: Client | None = None
_client_lock = threading.Lock()

# 100人同時利用を見据え、httpxのデフォルト(max_connections=100前後)より
# 余裕を持たせたコネクションプールを明示指定する。将来100を超えるようなら
# ここの数値を上げるだけでよい（Supabase側のプラン上限は別途確認が必要）。
_HTTPX_LIMITS = httpx.Limits(max_connections=200, max_keepalive_connections=50)


def get_supabase_client() -> Client:
    """
    プロセス内で1つのSupabaseクライアント（＝1つのhttpxコネクションプール）を
    使い回す。以前は呼び出すたびにcreate_client()していたため、リクエストのたびに
    新規のTCP/TLSハンドシェイクが発生していた。
    httpx.Clientはスレッドセーフなので、asyncio.to_thread経由の並行呼び出しからも
    安全に共有できる。
    """
    global _client
    if _client is not None:
        return _client

    with _client_lock:
        if _client is None:
            url: str = os.environ.get("SUPABASE_URL")
            key: str = os.environ.get("SUPABASE_SECRET_KEY")

            if not url or not key:
                raise ValueError("Supabase credentials not found in env vars")

            _client = create_client(
                url,
                key,
                options=ClientOptions(httpx_client=httpx.Client(limits=_HTTPX_LIMITS)),
            )

        return _client
