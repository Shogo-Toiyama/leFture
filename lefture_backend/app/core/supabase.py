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


_auth_client: Client | None = None
_auth_client_lock = threading.Lock()


def get_supabase_auth_client() -> Client:
    """
    JWT検証(auth.get_user)専用の、プロセス内で使い回すクライアント。

    get_supabase_client()と分けてあるのは鍵が違うため — こちらは
    publishable key(＝クライアント相当の権限)で、検証したいトークンは
    get_user(token)の引数として1回ごとに渡す(supabase_authは呼び出しごとに
    Authorizationヘッダをそのトークンで上書きするので、クライアントを
    共有してもユーザーが混ざることはない)。

    以前は認証のたびにcreate_client()しており、認証付きリクエスト1本ごとに
    新規のTCP/TLSハンドシェイクが発生していた(get_supabase_client()が
    管理者クライアントについて解消したのと同じ問題が、認証側に残っていた)。
    """
    global _auth_client
    if _auth_client is not None:
        return _auth_client

    with _auth_client_lock:
        if _auth_client is None:
            url: str = os.environ.get("SUPABASE_URL")
            key: str = os.environ.get("SUPABASE_PUBLISHABLE_KEY")

            if not url or not key:
                raise ValueError("Supabase credentials not found in env vars")

            _auth_client = create_client(
                url,
                key,
                options=ClientOptions(httpx_client=httpx.Client(limits=_HTTPX_LIMITS)),
            )
        return _auth_client
