"""Supabase REST(service role)の読み取り用ヘルパー。標準ライブラリのみ。"""
import json, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
env = {}
for line in open(ROOT / "lefture_backend" / ".env"):
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
URL, KEY = env["SUPABASE_URL"], env["SUPABASE_SECRET_KEY"]
H = {"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"}


def req(method, path, body=None):
    r = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body is not None else None, headers=H, method=method)
    try:
        return json.loads(urllib.request.urlopen(r).read() or "null")
    except urllib.error.HTTPError as e:
        return {"HTTPError": e.code, "body": e.read().decode()}


def get(t, q):
    return req("GET", f"/rest/v1/{t}?{q}")


def rpc(f, a):
    return req("POST", f"/rest/v1/rpc/{f}", a)
