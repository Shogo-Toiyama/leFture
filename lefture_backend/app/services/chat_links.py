# app/services/chat_links.py
"""
チャットに出てきたリンクを開いて、ページの本文を取ってくる(探索役の open U1)。2026-10-16に方針を合意。

    リンクを集める(collect_links): 今のメッセージ・選択テキスト・画面のページ・添付資料・直近の生徒の発言
                                     ↓ 探索役が open U1
    取ってくる(fetch_link):  YouTube → 字幕(youtube-transcript-api)
                             それ以外 → 直接取る(httpx + trafilatura、PDFはpypdfium2)
                             ↓ どちらも、ボット対策で弾かれた・本文が取れなかったときだけ
                             Tavily Extract(basic)。無料枠を超えた(432/433)・キーが無いときは諦める

- 開けるのは会話に出てきたURLだけ(探索役はU1…の呼び名で選ぶ。モデルが作ったURLは開けない)。
- 直接取るときは、内部のアドレス(Cloud Runのメタデータサーバー 169.254.169.254 など)へ行かないよう、
  リダイレクトのたびに名前を引き直して公開のアドレスか確かめる。名前を引いてから接続するまでの間に
  向き先を変えられる(DNS rebinding)隙は残るが、届くのは公開のページと同じ扱いの文字列だけで、
  応答の大きさと時間にも上限がある。
- 比べた結果(2026-10-16、GCPのIPから): 静的なページ(Wikipedia・公式ドキュメント・RFC・PDF・GitHub)は
  直接取る方が本文だけきれいに取れる。Stack Overflow・LeetCode・Mediumはボット対策で403になり、
  ブラウザのTLSをまねても(curl_cffi)GCPのIPからは通らなかった。Tavilyはそれらと YouTube の字幕まで
  取れたが、MDNは失敗した。なので「自作 → 取れなければTavily」の順にする。よく失敗するサイトは、
  探索の記録(navigator.links)のドメインを見て、公式のAPIで取る専用の取り方を足していく。
- ログインが要るページ(Canvasなどの授業サイト・非公開のGoogleドキュメント)はどれでも取れない。
  そのときは回答役が「開けなかったので、中身を貼るか添付してほしい」と伝える(探索役のプロンプト)。
"""

import asyncio
import io
import ipaddress
import os
import re
import socket
import time
from dataclasses import dataclass, field
from typing import Optional
from urllib.parse import parse_qs, urljoin, urlparse

import httpx

from app.services.helpers.llm_unified import BillingEngine

# =========================================================
# ⚙️ 設定
# =========================================================

# 1ターンに集めるリンクの数(多すぎると地図が長くなる)
MAX_LINKS = 10
# 直接取るとき: 1回の通信の時間・リダイレクトの回数・応答の大きさの上限
FETCH_TIMEOUT_SECONDS = 12
MAX_REDIRECTS = 5
MAX_RESPONSE_BYTES = 8 * 1024 * 1024
PDF_MAX_PAGES = 60
# これより短い本文は「取れなかった」とみなす(ボット対策の画面・中身の無い外枠)
MIN_TEXT_CHARS = 200
# Tavily Extract(basic: 成功1件0.2クレジット、失敗は無料)
TAVILY_EXTRACT_URL = "https://api.tavily.com/extract"
TAVILY_TIMEOUT_SECONDS = 20
# 同じURLをすぐ後のターンでまた開くことが多い(続けて質問する)ので、しばらく覚えておく
CACHE_SECONDS = 15 * 60
CACHE_MAX_ENTRIES = 64

USER_AGENT = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/130.0 Safari/537.36")
# ボット対策の画面に出る文言(本文が取れたように見えても、これなら弾かれている)
_BLOCKED_MARKERS = ("Enable JavaScript and cookies to continue", "Just a moment...",
                    "This website is using a security service to protect itself")
# この状態なら、Tavilyに頼めば取れる見込みがある(ボット対策・混雑)。404や401は誰が行っても同じなので頼まない
_RETRY_ELSEWHERE_STATUSES = {403, 429, 503, 520, 521, 522, 523, 524}

_URL_RE = re.compile(r"https?://[^\s<>\"'`、。「」『』【】（）《》〈〉]+")
_TRAILING_PUNCT = ".,;:!?…"
_YOUTUBE_HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com"}
_YOUTUBE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")


# =========================================================
# 🧩 データの形
# =========================================================

@dataclass
class Link:
    handle: str  # U1, U2, …(そのターンで振る)
    url: str
    # どこに出てきたか(探索役に見せる): message / selection / screen / attachment:A2 / earlier
    origin: str

    @property
    def domain(self) -> str:
        return _domain(self.url)


@dataclass
class LinkPage:
    url: str
    title: str = ""
    text: str = ""
    # direct / youtube / tavily(どの取り方で取れたか。失敗したときは最後に試したもの)
    via: str = ""
    # 取れなかった理由(取れたらNone): login_required / not_found / blocked / no_text / unsafe_url / error
    error: Optional[str] = None
    # 試した取り方と結果(記録用。よく失敗するサイトを見つけて専用の取り方を足すため)
    attempts: list = field(default_factory=list)
    elapsed_ms: int = 0

    @property
    def ok(self) -> bool:
        return self.error is None and bool(self.text)

    def log(self) -> dict:
        return {"domain": _domain(self.url), "via": self.via, "ok": self.ok, "error": self.error,
                "chars": len(self.text), "attempts": self.attempts, "ms": self.elapsed_ms}


class _Unsafe(Exception):
    """公開のアドレスでない・http(s)でない(Tavilyにも頼まない)。"""


class _Failed(Exception):
    def __init__(self, reason: str, retry_elsewhere: bool):
        super().__init__(reason)
        self.reason = reason
        self.retry_elsewhere = retry_elsewhere


# =========================================================
# 🔗 リンクを集める
# =========================================================

def find_urls(text: str) -> list[str]:
    """本文の中のURL。文末の句読点と、対になっていない閉じかっこ(Markdownの [x](url) など)は外す。"""
    urls = []
    for m in _URL_RE.finditer(text or ""):
        url = m.group(0)
        while url and (url[-1] in _TRAILING_PUNCT or (url[-1] == ")" and url.count("(") < url.count(")"))
                       or (url[-1] == "]" and url.count("[") < url.count("]"))):
            url = url[:-1]
        if urlparse(url).netloc:
            urls.append(url)
    return urls


def collect_links(sources: list[tuple[str, str]], limit: int = MAX_LINKS) -> list[Link]:
    """
    (出どころ, 本文)の順にURLを集め、U1, U2, …を振る。同じURLは最初に出てきた方だけ。
    sourcesは大事な順に並べて渡す(今のメッセージ → 選択 → 画面 → 添付 → それより前の発言)。
    """
    links: list[Link] = []
    seen: set[str] = set()
    for origin, text in sources:
        for url in find_urls(text):
            key = url.rstrip("/")
            if key in seen:
                continue
            seen.add(key)
            links.append(Link(handle=f"U{len(links) + 1}", url=url, origin=origin))
            if len(links) >= limit:
                return links
    return links


_ORIGIN_LABELS = {
    "message": "in the student's message",
    "selection": "in the selected text",
    "screen": "on the page open on screen",
    "earlier": "earlier in this conversation",
}


def render_for_navigator(links: list[Link]) -> str:
    lines = ["Links in this conversation (open one to read that page now):"]
    for link in links:
        origin = _ORIGIN_LABELS.get(link.origin) or (
            f"in attached material {link.origin.split(':', 1)[1]}" if link.origin.startswith("attachment:") else link.origin)
        lines.append(f"{link.handle} {link.url} — {origin}")
    return "\n".join(lines)


# =========================================================
# 📥 取ってくる
# =========================================================

_cache: dict[str, tuple[float, LinkPage]] = {}


async def fetch_link(url: str, billing: Optional[BillingEngine] = None) -> LinkPage:
    """リンク先の本文を取る。例外は投げず、取れなかったときはerrorに理由を入れて返す。"""
    hit = _cache.get(url)
    if hit and time.monotonic() - hit[0] < CACHE_SECONDS:
        return hit[1]
    t0 = time.perf_counter()
    page = await _fetch(url, billing)
    page.elapsed_ms = round((time.perf_counter() - t0) * 1000)
    if page.ok:
        if len(_cache) >= CACHE_MAX_ENTRIES:
            _cache.pop(min(_cache, key=lambda k: _cache[k][0]))
        _cache[url] = (time.monotonic(), page)
    return page


async def _fetch(url: str, billing: Optional[BillingEngine]) -> LinkPage:
    attempts: list[dict] = []
    retry_elsewhere = True
    last_reason = "error"
    via, first = ("youtube", _youtube_fetch) if _youtube_id(url) else ("direct", _direct_fetch)
    try:
        title, text = await first(url)
        attempts.append({"via": via, "ok": True})
        return LinkPage(url=url, title=title, text=text, via=via, attempts=attempts)
    except _Unsafe as e:
        return LinkPage(url=url, via="direct", error="unsafe_url",
                        attempts=[{"via": "direct", "ok": False, "reason": str(e)[:120]}])
    except _Failed as e:
        retry_elsewhere, last_reason = e.retry_elsewhere, e.reason
        attempts.append({"via": via, "ok": False, "reason": e.reason})
    except Exception as e:
        last_reason = "error"
        attempts.append({"via": via, "ok": False, "reason": f"{type(e).__name__}: {e}"[:160]})

    if retry_elsewhere:
        try:
            title, text = await _tavily_fetch(url, billing)
            attempts.append({"via": "tavily", "ok": True})
            return LinkPage(url=url, title=title, text=text, via="tavily", attempts=attempts)
        except _Failed as e:
            last_reason = e.reason if e.reason != "tavily_unavailable" else last_reason
            attempts.append({"via": "tavily", "ok": False, "reason": e.reason})
        except Exception as e:
            attempts.append({"via": "tavily", "ok": False, "reason": f"{type(e).__name__}: {e}"[:160]})
    return LinkPage(url=url, via=attempts[-1]["via"], error=last_reason, attempts=attempts)


# ---------- 直接取る ----------

async def _check_public(url: str) -> None:
    """http(s)で、名前を引いた先が全部公開のアドレスか(内部のアドレス・メタデータサーバーへ行かない)。"""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise _Unsafe("not an http(s) URL")
    if parsed.port not in (None, 80, 443):
        raise _Unsafe("non-standard port")
    if parsed.username or parsed.password:
        raise _Unsafe("credentials in URL")
    try:
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        infos = await asyncio.get_running_loop().getaddrinfo(parsed.hostname, port, type=socket.SOCK_STREAM)
    except socket.gaierror:
        raise _Failed("not_found", retry_elsewhere=False)
    for info in infos:
        addr = ipaddress.ip_address(info[4][0])
        if not addr.is_global:
            raise _Unsafe(f"non-public address {addr}")


async def _direct_fetch(url: str) -> tuple[str, str]:
    headers = {"User-Agent": USER_AGENT, "Accept-Language": "ja,en;q=0.8",
               "Accept": "text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8"}
    async with httpx.AsyncClient(follow_redirects=False, timeout=FETCH_TIMEOUT_SECONDS, headers=headers) as client:
        current = url
        for _ in range(MAX_REDIRECTS + 1):
            await _check_public(current)
            async with client.stream("GET", current) as resp:
                if resp.is_redirect:
                    location = resp.headers.get("location")
                    if not location:
                        raise _Failed("error", retry_elsewhere=True)
                    current = urljoin(current, location)
                    continue
                if resp.status_code in (401, 407):
                    raise _Failed("login_required", retry_elsewhere=False)
                if resp.status_code in (404, 410):
                    raise _Failed("not_found", retry_elsewhere=False)
                if resp.status_code in _RETRY_ELSEWHERE_STATUSES:
                    raise _Failed("blocked", retry_elsewhere=True)
                if resp.status_code >= 400:
                    raise _Failed("error", retry_elsewhere=True)
                body = await _read_limited(resp)
                ctype = (resp.headers.get("content-type") or "").lower()
                final_url = str(resp.url)
                break
        else:
            raise _Failed("error", retry_elsewhere=True)

    if "pdf" in ctype or body[:5] == b"%PDF-":
        title, text = await asyncio.to_thread(_pdf_text, body)
    elif "html" in ctype or "xml" in ctype or not ctype:
        html = body.decode(_charset(ctype) or "utf-8", errors="replace")
        if any(marker in html for marker in _BLOCKED_MARKERS):
            raise _Failed("blocked", retry_elsewhere=True)
        title, text = await asyncio.to_thread(_html_text, html, final_url)
        if _looks_like_login(final_url, title, text):
            raise _Failed("login_required", retry_elsewhere=False)
    elif ctype.startswith("text/"):
        title, text = "", body.decode(_charset(ctype) or "utf-8", errors="replace")
    else:
        raise _Failed("unsupported_type", retry_elsewhere=False)
    if len(text.strip()) < MIN_TEXT_CHARS:
        # JavaScriptで中身を描くページ(外枠しか無い)など
        raise _Failed("no_text", retry_elsewhere=True)
    return title, text.strip()


async def _read_limited(resp: httpx.Response) -> bytes:
    chunks, size = [], 0
    async for chunk in resp.aiter_bytes():
        size += len(chunk)
        if size > MAX_RESPONSE_BYTES:
            raise _Failed("too_large", retry_elsewhere=False)
        chunks.append(chunk)
    return b"".join(chunks)


def _charset(ctype: str) -> Optional[str]:
    m = re.search(r"charset=([\w-]+)", ctype)
    return m.group(1) if m else None


def _html_text(html: str, url: str) -> tuple[str, str]:
    import trafilatura

    text = trafilatura.extract(html, url=url, output_format="markdown", include_tables=True,
                               include_links=False, include_comments=False) or ""
    meta = trafilatura.extract_metadata(html)
    return (meta.title if meta and meta.title else ""), text


def _pdf_text(data: bytes) -> tuple[str, str]:
    import pypdfium2 as pdfium

    try:
        pdf = pdfium.PdfDocument(io.BytesIO(data))
    except pdfium.PdfiumError:
        raise _Failed("unreadable_pdf", retry_elsewhere=False)
    pages = [pdf[i].get_textpage().get_text_range().strip() for i in range(min(len(pdf), PDF_MAX_PAGES))]
    title = (pdf.get_metadata_dict() or {}).get("Title") or ""
    return title, "\n\n".join(p for p in pages if p)


def _looks_like_login(url: str, title: str, text: str) -> bool:
    """ログイン画面に飛ばされた(本文はログインの案内だけ)。本文が長いページは、題名に「Login」が入っていても記事とみなす。"""
    if len(text) > 1500:
        return False
    path = urlparse(url).path.lower()
    return any(w in path for w in ("/login", "/signin", "/sign_in", "/sso")) or bool(
        re.search(r"\b(log ?in|sign ?in)\b|ログイン|サインイン", title or "", re.IGNORECASE))


# ---------- YouTube ----------

def _youtube_id(url: str) -> Optional[str]:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if host not in _YOUTUBE_HOSTS:
        return None
    if host == "youtu.be":
        vid = parsed.path.strip("/").split("/")[0]
    elif parsed.path == "/watch":
        vid = (parse_qs(parsed.query).get("v") or [""])[0]
    else:
        parts = parsed.path.strip("/").split("/")
        vid = parts[1] if len(parts) >= 2 and parts[0] in ("shorts", "embed", "live", "v") else ""
    return vid if _YOUTUBE_ID_RE.match(vid or "") else None


async def _youtube_fetch(url: str) -> tuple[str, str]:
    """動画の字幕(手で付けた日本語・英語 → 自動の日本語・英語 → ほかの言語の順)。30秒ごとに時刻を付ける。"""
    vid = _youtube_id(url)
    title = await _youtube_title(url)

    def load() -> list:
        from youtube_transcript_api import YouTubeTranscriptApi

        transcripts = YouTubeTranscriptApi().list(vid)
        langs = ["ja", "en", "en-US", "en-GB"]
        for finder in (transcripts.find_manually_created_transcript, transcripts.find_generated_transcript):
            try:
                return list(finder(langs).fetch())
            except Exception:
                continue
        return list(next(iter(transcripts)).fetch())

    try:
        snippets = await asyncio.to_thread(load)
    except Exception as e:
        # 字幕が無い・YouTubeにクラウドのIPを止められた: Tavilyなら取れることがある
        raise _Failed(f"no_transcript:{type(e).__name__}", retry_elsewhere=True)
    lines, block, block_start = [], [], None
    for s in snippets:
        if block_start is None:
            block_start = s.start
        block.append(s.text.replace("\n", " ").strip())
        if s.start - block_start >= 30:
            lines.append(f"[{_clock(block_start)}] " + " ".join(block))
            block, block_start = [], None
    if block:
        lines.append(f"[{_clock(block_start or 0)}] " + " ".join(block))
    text = "\n".join(lines)
    if len(text) < MIN_TEXT_CHARS:
        raise _Failed("no_text", retry_elsewhere=True)
    return title, f"(Transcript of the video)\n{text}"


async def _youtube_title(url: str) -> str:
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            r = await client.get("https://www.youtube.com/oembed", params={"url": url, "format": "json"})
            return (r.json().get("title") or "") if r.status_code == 200 else ""
    except Exception:
        return ""


def _clock(seconds: float) -> str:
    s = int(seconds)
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60}:{s % 60:02d}"


# ---------- Tavily ----------

async def _tavily_fetch(url: str, billing: Optional[BillingEngine]) -> tuple[str, str]:
    api_key = os.getenv("TAVILY_API_KEY")
    if not api_key:
        raise _Failed("tavily_unavailable", retry_elsewhere=False)
    async with httpx.AsyncClient(timeout=TAVILY_TIMEOUT_SECONDS) as client:
        r = await client.post(TAVILY_EXTRACT_URL, headers={"Authorization": f"Bearer {api_key}"},
                              json={"urls": [url], "extract_depth": "basic", "format": "markdown"})
    if r.status_code in (432, 433):
        # 無料枠・従量課金の上限に届いた(支払い方法は登録していないので、月の無料枠を使い切ると432)
        print(f"⚠️ [chat] Tavily limit reached (HTTP {r.status_code}); links fall back to direct fetch only")
        raise _Failed("tavily_unavailable", retry_elsewhere=False)
    if r.status_code != 200:
        raise _Failed(f"tavily_http_{r.status_code}", retry_elsewhere=False)
    results = r.json().get("results") or []
    raw = (results[0].get("raw_content") or "") if results else ""
    if billing is not None and results:
        billing.add_count_cost("tavily/extract_basic", 1, note=f"Extract: {_domain(url)}")
    text = _skip_page_chrome(_clean_markdown(raw))
    if len(text) < MIN_TEXT_CHARS or any(marker in text[:500] for marker in _BLOCKED_MARKERS):
        # Tavilyは存在しないページでも「成功」で外枠を返すことがある
        raise _Failed("no_text", retry_elsewhere=False)
    title = next((ln.lstrip("# ").strip() for ln in text.splitlines() if ln.startswith("# ")), "")
    return title, text


_MD_IMAGE_RE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
_MD_LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")


def _clean_markdown(md: str) -> str:
    """Tavilyの出力に残るメニュー・画像・リンクの書式を落とす(回答役に渡す量を減らす)。"""
    md = _MD_IMAGE_RE.sub("", md)
    md = _MD_LINK_RE.sub(r"\1", md)
    lines = [ln.rstrip() for ln in md.splitlines()]
    # 中身の無い行(記号だけ・空のリスト項目)を落とし、空行の連続を1つにする
    out: list[str] = []
    for ln in lines:
        if re.fullmatch(r"[\s*\-|#>·•]*", ln):
            if out and out[-1] != "":
                out.append("")
            continue
        out.append(ln)
    return "\n".join(out).strip()


_LIST_LINE_RE = re.compile(r"^\s*(?:[*\-+•]|\d+\.)\s")
# 本文の始まりとみなす行の長さ(メニュー・ボタン・登録の案内は短い行か箇条書きになる)
PROSE_LINE_CHARS = 120
# 本文の始まりの前に残す行(空行を除く)。題名・問題番号・最初の短い文は長い行の少し前にあるので、
# 切り口をここまで戻す(途中に見出しがあれば、そこから残す)
KEEP_BEFORE_PROSE_LINES = 12
# 頭を落とすのは全体のこの割合まで(落としすぎて本文を欠かないように)
MAX_CHROME_SHARE = 0.4


def _skip_page_chrome(text: str) -> str:
    """
    Tavilyの出力の頭に付くメニュー・登録の案内を落とす(Stack Overflowでは本文の前に約6千字あった)。
    箇条書きでない長い行を本文の始まりとみなし、そこから少し戻ったところ(見出しがあればそこ)から残す。
    少し余分に残すのは、題名や最初の短い文(LeetCodeの問題文の1文目など)を欠かないため。
    """
    lines = text.splitlines()
    prose = next((i for i, ln in enumerate(lines)
                  if len(ln.strip()) >= PROSE_LINE_CHARS and not _LIST_LINE_RE.match(ln)), None)
    if not prose:
        return text
    start, kept = prose, 0
    while start > 0 and kept < KEEP_BEFORE_PROSE_LINES:
        start -= 1
        if lines[start].strip():
            kept += 1
            if lines[start].startswith("#"):
                break
    head_chars = sum(len(ln) + 1 for ln in lines[:start])
    return "\n".join(lines[start:]).strip() if head_chars <= len(text) * MAX_CHROME_SHARE else text


def _domain(url: str) -> str:
    host = urlparse(url).netloc
    return host[4:] if host.startswith("www.") else host
