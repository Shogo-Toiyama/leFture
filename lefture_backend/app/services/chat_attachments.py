# app/services/chat_attachments.py
"""
チャットの資料添付。docs/chatbot_context_and_retrieval_roadmap.md 10章(2026-10-04に合意)。

    送信(本文 + 新しい資料) ──▶ prepare_chat_turn: 上限の確認・processingで保存
                                      ↓
                              run_chat_turn の最初: read_attachment(審査 + 要約 + 目次)
                                      ├─ どれか1つでも断った → そのターンごと blocked(課金なし・断られた回数に数える)
                                      ├─ 失敗 → そのターンは error(課金なし)
                                      └─ 全部通った → ready。処理の原価はそのターンの請求に含まれる
                                      ↓
                              新しい資料は、選択中の合計がMAX_SELECTED_TOKENSに収まれば自動で選ぶ(auto_select)
                                      ↓
                              毎ターン: 選択中の資料は全文、それ以外は一覧(名前と要約)+目次と検索

- 振り分け役は資料の本文を読まない。安全の確認は添付時に一度だけ(本文を必ず読む要約役が兼ねる)。
  節の束を前から波(READ_WAVE_BATCHES個ずつ並列)で読み、断った束が出た波で止める(最後まで読まされない)。
- 毎ターン渡すもの(10章「選んだ資料だけ全文で読む」、2026-10-04): 本人が選んだ資料(selected)は全文。
  選択の上限は合計MAX_SELECTED_TOKENS。選んでいない資料は一覧(名前と要約)だけで、中身は探索役が
  目次(A2)→ 節(A2/S3)と開くか、資料の中を検索する(attachment.search)。
  以前の「合計1万字以内なら全部・最後に添付した1本」のルールは、4万字の課題の仕様書で要約しか
  見えずに仕様書と逆のことを答えた失敗を受けて、本人が選ぶ形に置き換えた。
- 節の区切りはコードで決める(見出しらしい行・段落の切れ目で2〜3千字ずつ)。要約役は各節に名前と
  「何が書いてあるか」を付けるだけなので、区切りがずれて本文が欠けることは無い。
"""

import asyncio
import re
from dataclasses import dataclass, field
from typing import Any, Optional

from app.services.helpers.helpers import _load_prompt
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM


# =========================================================
# ⚙️ 設定
# =========================================================

# 要約・目次・審査のモデル。2026-10-04に実在の文書3本(日本語の設計書5.3万字・英語の利用規約2万字・
# 日本語のメモ9千字)で2.5 Flash-Liteと比べて決めた(contents_generation/test_codes/attachment_toc_test/)。
# 2.5 Flash-Liteは、9千字のメモで節の名前が実際の位置とずれ(「4. Soft Launch期間の…」で始まる節に
# 「3. CSU / Berkeley」と付けた)、日本語の資料2本の説明を英語で書いた。Lunaは位置が正確で説明も具体的。
# 原価はほぼ同じ(5.3万字でLuna $0.010 / Flash-Lite $0.007)。入力の上限はLunaが92.2万トークンで、
# 10万字を十分に超える。ユーザーの方針「Flash-Liteで足りなければLuna」でLunaにした。
ATTACHMENT_MODEL = "gpt-6-luna"

# 上限(コードで止める)。1本の上限は、悪意ある長文で運営が負担する額の上限にもなる
# (断ったときは課金しないので、1本10万字 × 1日の断られた回数の上限まで)。
MAX_ATTACHMENT_CHARS = 100_000
MAX_ATTACHMENTS_PER_THREAD = 30
MAX_ATTACHMENTS_PER_MESSAGE = 5
MAX_ATTACHMENT_TITLE_CHARS = 100

# 全文で渡す資料(選択中)の合計の上限(トークン、estimate_tokensの概算)。
# 30,000〜40,000トークンの長文資料は、添付時にModal LLMLingua-2でソフト圧縮(Rate 0.7〜0.6)して約25k〜30kトークンに押し込む。
# 圧縮による安全マージンを考慮し、選択枠の上限を36,000トークンまで許容する。
MAX_SELECTED_TOKENS = 36_000


# 節の区切り(文字数)。見出しらしい行があればそこで、無ければ段落の切れ目で区切る
SECTION_TARGET_CHARS = 2500
SECTION_MAX_CHARS = 3500
SECTION_MIN_CHARS = 600

# 節を小さな束(1回の呼び出しで読む量、ほぼ1節)に分け、READ_WAVE_BATCHES個ずつ並列に読む。待ち時間は
# 出力の長さで決まるので、1回で全部読むより速い(9千字のメモ: 1回で約13秒、4千字の束で約5秒、
# 2.5千字の束で約3.4秒。2026-10-04にLunaで計測)。断った束が出たら、次の波は読まない。
READ_BATCH_CHARS = 2500
READ_WAVE_BATCHES = 10
# 1回の送信で読む資料(最大5本)全体での、Lunaへの同時呼び出しの上限
READ_MAX_CONCURRENT_CALLS = 12
READ_MAX_TOKENS = 4096
# 名前と要約: 短い資料は全文から(束と並列に)、それより長い資料は冒頭と目次から(束の後に)
OVERVIEW_FULL_TEXT_CHARS = 10_000
OVERVIEW_HEAD_CHARS = 3000

SECTION_TITLE_CHARS = 60
SECTION_DESCRIPTION_CHARS = 400
SUMMARY_CHARS = 800

READER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "verdict": {"type": "string", "enum": ["ok", "blocked"]},
        "sections": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "n": {"type": "integer"},
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                },
                "required": ["n", "title", "description"],
            },
        },
    },
    "required": ["verdict", "sections"],
}


OVERVIEW_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {"title": {"type": "string"}, "summary": {"type": "string"}, "forbids_ai_code": {"type": "boolean"}},
    "required": ["title", "summary", "forbids_ai_code"],
}


# =========================================================
# 🧩 データの形
# =========================================================

@dataclass
class Section:
    index: int  # 1始まり(呼び名 A2/S3 の3)
    start: int
    end: int
    title: str = ""
    description: str = ""

    def to_json(self) -> dict:
        return {"index": self.index, "title": self.title, "description": self.description,
                "start": self.start, "end": self.end}


@dataclass
class Attachment:
    """スレッドの資料1本(DBの行)。handleはそのターンで振る呼び名(添付順にA1, A2, …)。"""
    id: str
    title: str
    content: str
    summary: str
    sections: list[Section]
    message_id: Optional[str] = None
    created_at: str = ""
    handle: str = ""
    # 本人が選んだ(全文で渡す)資料か。新しい資料は上限に収まれば自動で選ばれる
    selected: bool = False
    token_count: int = 0
    forbids_ai_code: bool = False
    # text / pdf / docx / pptx / image(chat_files.py)。画像の資料は、選択中なら画像そのものも回答役に渡す
    kind: str = "text"
    image_path: Optional[str] = None
    # 全文で読み始めた・最後にメンションされた時刻(全文で読む枠を超えたら、古いものから外す)
    selected_at: str = ""
    # LLMLingua-2 でソフト圧縮された資料か
    compressed: bool = False


    @property
    def char_count(self) -> int:
        return len(self.content)

    def section(self, index: int) -> Optional[Section]:
        return next((s for s in self.sections if s.index == index), None)

    def section_text(self, s: Section) -> str:
        return self.content[s.start:s.end].strip()

    @classmethod
    def from_row(cls, row: dict) -> "Attachment":
        content = row.get("content") or ""
        sections = []
        for raw in row.get("sections") or []:
            if not isinstance(raw, dict) or not isinstance(raw.get("index"), int):
                continue
            start, end = raw.get("start"), raw.get("end")
            if not isinstance(start, int) or not isinstance(end, int) or not 0 <= start < end <= len(content):
                continue
            sections.append(Section(index=raw["index"], start=start, end=end,
                                    title=str(raw.get("title") or ""), description=str(raw.get("description") or "")))
        token_count = row.get("token_count")
        return cls(id=row["id"], title=(row.get("title") or "").strip(), content=content,
                   summary=(row.get("summary") or "").strip(), sections=sections,
                   message_id=row.get("message_id"), created_at=row.get("created_at") or "",
                   selected=bool(row.get("selected")),
                   forbids_ai_code=bool(row.get("forbids_ai_code")),
                   kind=row.get("kind") or "text", image_path=row.get("image_path"),
                   selected_at=row.get("selected_at") or "",
                   compressed=bool(row.get("compressed") or (row.get("metadata") or {}).get("compressed")),
                   token_count=token_count if isinstance(token_count, int) else estimate_tokens(content))



@dataclass
class ReadResult:
    """read_attachmentの結果。blocked=Trueなら審査で断った。errorがあれば処理に失敗した。"""
    title: str = ""
    summary: str = ""
    sections: list[Section] = field(default_factory=list)
    # 課題の資料が、AIでコードを書くことを禁止しているか(回答役に毎ターン明示する、10章)
    forbids_ai_code: bool = False
    blocked: bool = False
    error: Optional[str] = None
    calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0

    def usage_json(self) -> dict:
        return {"model": ATTACHMENT_MODEL, "calls": self.calls,
                "input_tokens": self.input_tokens, "output_tokens": self.output_tokens}


@dataclass
class Visibility:
    """
    そのターンに各資料をどう見せるか。full: 回答役に全文を渡す資料のid。
    mentioned: 生徒がこのメッセージの文中で指した資料のid(全文でなければ、探索役がその中を探す)。
    """
    full: set[str]
    mentioned: set[str] = field(default_factory=set)

    def is_full(self, a: Attachment) -> bool:
        return a.id in self.full

    def is_mentioned(self, a: Attachment) -> bool:
        return a.id in self.mentioned


# =========================================================
# @ 本文の中で資料を指す(メンション)
# =========================================================

# 生徒の本文の中の資料の印(webappが入れる)。保存する本文もこの形: ⟦att:<資料のid>⟧
# 送るときの新しい資料(まだidが無いテキスト)は端末の仮のid(ref)で届き、prepare_chat_turnが本物のidに直す
MENTION_RE = re.compile(r"⟦att:([0-9A-Za-z-]{1,64})⟧")
MAX_MENTIONS_PER_MESSAGE = 10


def mention_ids(text: str) -> list[str]:
    """本文が指している資料のid(出てくる順、重複なし)。"""
    out: list[str] = []
    for m in MENTION_RE.finditer(text or ""):
        if m.group(1) not in out:
            out.append(m.group(1))
    return out


def rewrite_mentions(text: str, mapping: dict[str, str], allowed: set[str]) -> str:
    """仮のid(ref)を本物のidに直し、このスレッドで指せない印は消す。"""
    def sub(m: re.Match) -> str:
        target = mapping.get(m.group(1), m.group(1))
        return f"⟦att:{target}⟧" if target in allowed else ""
    return MENTION_RE.sub(sub, text or "")


def render_mentions(text: str, attachments: list[Attachment]) -> str:
    """LLMに渡す形: 印を資料の呼び名と名前に直す(例: [A2 "Project #1 spec"])。外した資料は [removed material]。"""
    by_id = {a.id: a for a in attachments}

    def sub(m: re.Match) -> str:
        a = by_id.get(m.group(1))
        if a is None:
            return "[removed material]"
        return f'[{a.handle} "{a.title or "untitled"}"]' if a.handle else f'["{a.title or "attached material"}"]'
    return MENTION_RE.sub(sub, text or "")


def answer_mentions(text: str, attachments: list[Attachment]) -> str:
    """
    回答役に渡す形: 印を資料の名前だけにする(例: [Attached material: "Project #1 spec"])。外した資料は [removed material]。
    A1などの呼び名は探索役が開くための目印。回答役は資料を引用しないので使わず、生徒にも見えない
    (2026-11-06、[A1 "…"] を見た回答役が「A1の範囲は」「範囲マップ（A1の番号順）」と書いた)。
    """
    by_id = {a.id: a for a in attachments}

    def sub(m: re.Match) -> str:
        a = by_id.get(m.group(1))
        return "[removed material]" if a is None else f'[Attached material: "{a.title or "untitled"}"]'
    return MENTION_RE.sub(sub, text or "")


# 探索役・振り分け役が書いた文の中の資料の呼び名(A1 / A1/S2)
_NOTE_ATTACHMENT_HANDLE_RE = re.compile(r"(?<![A-Za-z0-9])A(\d+)(?:/S(\d+))?(?![A-Za-z0-9])")


def attachment_handles_to_titles(text: str, attachments: list[Attachment]) -> str:
    """
    探索役の考え・振り分け役のuser_goal(どちらもLLMが書いた、回答役へのメモ)の中の資料の呼び名を名前に直す。
    回答役には呼び名を渡さないので、このままだと「A1」がどの資料かわからない。このターンに実在する呼び名だけを直す
    (講義の資料の本文は触らない。そこには「A1」が別の意味で出てきうる)。
    """
    by_handle = {a.handle: a for a in attachments if a.handle}

    def sub(m: re.Match) -> str:
        a = by_handle.get(f"A{m.group(1)}")
        if a is None:
            return m.group(0)
        name = f'"{a.title or "untitled"}"'
        sec = a.section(int(m.group(2))) if m.group(2) else None
        return f'{name} (section "{sec.title}")' if sec else name
    return _NOTE_ATTACHMENT_HANDLE_RE.sub(sub, text or "")


def plain_mentions(text: str) -> str:
    """資料の一覧が無いところ(要約・検索の索引・プロフィール)で読む形。印を [attached material] にする。"""
    return MENTION_RE.sub("[attached material]", text or "")


# =========================================================
# ✂️ 節に区切る(純粋関数)
# =========================================================

# 見出しらしい行: Markdownの#、英語の決まった見出し語、日本語の「第N章」「問1」、記号の見出し(■【)。
# 番号付きの行(1. / 1.2 / A) / IV.)は箇条書きと区別がつかないので、直前が空行のときだけ見出しとみなす
# (リストの途中で節が切れないように)。どちらも短い行(HEADING_MAX_CHARS以下)だけ。
_HEADING_RE = re.compile(
    r"^\s{0,3}(?:"
    r"#{1,6}\s+\S"
    r"|(?:Part|Section|Chapter|Problem|Question|Task|Step|Exercise|Appendix|Requirements?|Overview|"
    r"Introduction|Background|Submission|Grading|Rubric|Deliverables?|Abstract|Conclusions?|References)\b"
    r"|第\s*[0-9０-９一二三四五六七八九十百]+\s*[章節部条問回]"
    r"|問\s*[0-9０-９一二三四五六七八九十]+"
    r"|[■□●◆◇▼▶【]"
    # ファイルから取り出した本文のページ・スライドの印(chat_files.assemble)。節がページをまたがないように
    r"|\[(?:p\.\d+|slide \d+)\]\s*$"
    r")",
    re.IGNORECASE,
)
_NUMBERED_HEADING_RE = re.compile(r"^\s{0,3}(?:\d+(?:\.\d+)*|[A-Z]|[IVX]+)[.)]\s+\S")
HEADING_MAX_CHARS = 100
_SENTENCE_END_RE = re.compile(r"(?<=[.!?。！？])\s+|(?<=[。！？])")


def _is_heading(line: str, after_blank: bool) -> bool:
    s = line.strip()
    if not 0 < len(s) <= HEADING_MAX_CHARS:
        return False
    return bool(_HEADING_RE.match(line)) or (after_blank and bool(_NUMBERED_HEADING_RE.match(line)))


def _split_long_line(start: int, line: str) -> list[tuple[int, int]]:
    """改行の無い長い行(PDFから貼った段落など)を、文の切れ目でSECTION_TARGET_CHARS前後に分ける。"""
    pieces, a = [], 0
    while len(line) - a > SECTION_MAX_CHARS:
        window = line[a + SECTION_MIN_CHARS: a + SECTION_MAX_CHARS]
        cut = None
        for m in _SENTENCE_END_RE.finditer(window):
            pos = a + SECTION_MIN_CHARS + m.end()
            if pos - a <= SECTION_TARGET_CHARS or cut is None:
                cut = pos
        if cut is None:
            cut = a + SECTION_TARGET_CHARS
        pieces.append((start + a, start + cut))
        a = cut
    pieces.append((start + a, start + len(line)))
    return pieces


def split_sections(text: str) -> list[tuple[int, int]]:
    """
    本文を節に区切り、各節の(開始, 終了)の文字位置を返す(text[start:end]をつなげると元に戻る)。
    - 見出しらしい行の前で区切る(今の節がSECTION_MIN_CHARS以上あれば)。
    - 見出しが無くても、SECTION_TARGET_CHARSを超えたら次の段落の切れ目(空行)で区切り、
      SECTION_MAX_CHARSを超えそうなら行の切れ目で区切る。
    - 最後の節が短すぎれば前の節にまとめる。
    """
    if not text:
        return []
    # 行(と、長すぎる行を分けた断片)の (開始, 終了, 見出しか, 直前が空行か)
    units: list[tuple[int, int, bool, bool]] = []
    pos, prev_blank = 0, True
    for raw in text.splitlines(keepends=True):
        line = raw.rstrip("\r\n")
        if len(line) > SECTION_MAX_CHARS:
            for i, (a, b) in enumerate(_split_long_line(pos, line)):
                end = b if b < pos + len(line) else pos + len(raw)
                units.append((a, end, False, prev_blank if i == 0 else True))
        else:
            units.append((pos, pos + len(raw), _is_heading(line, prev_blank), prev_blank))
        prev_blank = not line.strip()
        pos += len(raw)

    bounds: list[tuple[int, int]] = []
    cur_start = 0
    for a, b, heading, after_blank in units:
        cur_len = a - cur_start
        if cur_len > 0 and (
            (heading and cur_len >= SECTION_MIN_CHARS)
            or (cur_len >= SECTION_TARGET_CHARS and (after_blank or heading))
            or (cur_len + (b - a) > SECTION_MAX_CHARS and cur_len >= SECTION_MIN_CHARS)
        ):
            bounds.append((cur_start, a))
            cur_start = a
    bounds.append((cur_start, len(text)))

    # 空白だけの節を前の節にまとめ、最後の短すぎる節も前にまとめる
    merged: list[tuple[int, int]] = []
    for a, b in bounds:
        if merged and (not text[a:b].strip() or (b == len(text) and b - a < SECTION_MIN_CHARS // 2)):
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    return merged


def batch_sections(bounds: list[tuple[int, int]], max_chars: int = READ_BATCH_CHARS) -> list[list[int]]:
    """節を、1回の呼び出しで読む束(節の番号の一覧、0始まり)に分ける。"""
    batches: list[list[int]] = []
    cur: list[int] = []
    size = 0
    for i, (a, b) in enumerate(bounds):
        if cur and size + (b - a) > max_chars:
            batches.append(cur)
            cur, size = [], 0
        cur.append(i)
        size += b - a
    if cur:
        batches.append(cur)
    return batches


# =========================================================
# 📖 読む(審査 + 目次 + 要約)
# =========================================================

def _options(schema: dict[str, Any], max_tokens: Optional[int] = None) -> LLMOptions:
    """モデルに合わせたオプション。GPT-6系はtemperatureの既定値(1)以外とmax_tokensを受け付けない。"""
    if ATTACHMENT_MODEL.startswith("gpt-"):
        return LLMOptions(output_type="json", json_schema=schema, temperature=1.0,
                          max_completion_tokens=max_tokens, reasoning_effort="none")
    return LLMOptions(output_type="json", json_schema=schema, temperature=0.0, max_tokens=max_tokens)


def _looks_like_safety_block(error: Exception) -> bool:
    """入力そのものが安全フィルタで止められた(例外で返るもの)。断った扱いにして、断られた回数に数える。"""
    text = str(error).lower()
    return any(k in text for k in ("prohibited_content", "blockreason", "block_reason", "safety", "content_filter"))


def _sections_input(text: str, bounds: list[tuple[int, int]], indexes: list[int]) -> str:
    return "\n\n".join(f'<section n="{i + 1}">\n{text[bounds[i][0]:bounds[i][1]].strip()}\n</section>' for i in indexes)


def _apply_sections(out: dict, indexes: list[int], bounds: list[tuple[int, int]], sections: dict[int, Section]) -> None:
    wanted = {i + 1 for i in indexes}
    for raw in out.get("sections") or []:
        if not isinstance(raw, dict) or raw.get("n") not in wanted:
            continue
        n = raw["n"]
        a, b = bounds[n - 1]
        sections[n] = Section(index=n, start=a, end=b,
                              title=str(raw.get("title") or "").strip()[:SECTION_TITLE_CHARS],
                              description=str(raw.get("description") or "").strip()[:SECTION_DESCRIPTION_CHARS])


async def _read_batch(llm: UnifiedLLM, text: str, bounds: list[tuple[int, int]], indexes: list[int],
                      result: ReadResult, limiter: Optional[asyncio.Semaphore] = None) -> Optional[dict]:
    """
    節の束を1回読む。断ったらresult.blocked、失敗したら例外。読めない出力は1回だけやり直す。
    返り値は出力のJSON(断ったときはNone)。
    """
    messages = [Message(role="system", content=_load_prompt("chat_attachment_reader_prompt.txt")),
                Message(role="user", content=_sections_input(text, bounds, indexes))]
    options = _options(READER_SCHEMA, READ_MAX_TOKENS)
    last_error = ""
    for _attempt in range(2):
        if result.blocked:
            return None  # 同じ資料のほかの束で断った: これ以上読まない
        try:
            if limiter is None:
                res = await llm.generate(ATTACHMENT_MODEL, messages, options)
            else:
                async with limiter:
                    res = await llm.generate(ATTACHMENT_MODEL, messages, options)
        except Exception as e:
            if _looks_like_safety_block(e):
                result.blocked = True
                return None
            last_error = f"{type(e).__name__}: {e}"[:300]
            continue
        result.calls += 1
        result.input_tokens += res.input_tokens
        result.output_tokens += res.output_tokens
        if res.finish_reason == "content_filter":
            result.blocked = True
            return None
        out = res.output_json
        if isinstance(out, dict) and out.get("verdict") in ("ok", "blocked"):
            if out["verdict"] == "blocked":
                result.blocked = True
                return None
            return out
        last_error = res.json_parse_error or f"unreadable output (finish_reason={res.finish_reason})"
    raise RuntimeError(f"attachment reader failed: {last_error}")


async def _overview(llm: UnifiedLLM, text: str, sections: Optional[list[Section]], result: ReadResult) -> tuple[str, str, bool]:
    """
    資料の名前と要約。sectionsがNoneなら全文から、あれば冒頭と目次から作る。
    失敗しても資料は使える(名前は本人が付けたもの・節の名前で代わりがきく)ので、空で返す。
    """
    if sections is None:
        body = f"<document>\n{text}\n</document>"
    else:
        toc = "\n".join(f"{s.index}. {s.title} — {s.description}" for s in sections)
        body = (f"<beginning>\n{text[:OVERVIEW_HEAD_CHARS]}\n</beginning>\n\n"
                f"<table_of_contents>\n{toc}\n</table_of_contents>")
    messages = [Message(role="system", content=_load_prompt("chat_attachment_overview_prompt.txt")),
                Message(role="user", content=body)]
    try:
        res = await llm.generate(ATTACHMENT_MODEL, messages, _options(OVERVIEW_SCHEMA))
    except Exception as e:
        print(f"⚠️ [chat] attachment overview failed: {e}")
        return "", "", False
    result.calls += 1
    result.input_tokens += res.input_tokens
    result.output_tokens += res.output_tokens
    out = res.output_json if isinstance(res.output_json, dict) else {}
    return str(out.get("title") or "").strip(), str(out.get("summary") or "").strip(), out.get("forbids_ai_code") is True


async def read_attachment(llm: UnifiedLLM, text: str, limiter: Optional[asyncio.Semaphore] = None) -> ReadResult:
    """
    資料を読んで、審査・節ごとの名前と説明・全体の名前と要約を作る。
    節の束をREAD_WAVE_BATCHES個ずつ並列に読み、断った束が出た波で止める(最後まで読まされない)。
    短い資料は、名前と要約も全文から最初の波と並列に作る(待ち時間を増やさない)。
    要約役が節を返し損ねたら、その節は本文の最初の行を名前にする(本文は欠けない)。
    """
    result = ReadResult()
    bounds = split_sections(text)
    if not bounds:
        result.error = "empty"
        return result
    batches = batch_sections(bounds)
    sections: dict[int, Section] = {}
    overview_task: Optional[asyncio.Task] = None
    if len(text) <= OVERVIEW_FULL_TEXT_CHARS:
        overview_task = asyncio.create_task(_overview(llm, text, None, result))
    try:
        for w in range(0, len(batches), READ_WAVE_BATCHES):
            wave = batches[w:w + READ_WAVE_BATCHES]
            outs = await asyncio.gather(*[_read_batch(llm, text, bounds, b, result, limiter) for b in wave])
            if result.blocked:
                break
            for b, out in zip(wave, outs):
                _apply_sections(out or {}, b, bounds, sections)
    except Exception as e:
        result.error = str(e)[:500]
    if result.blocked or result.error:
        if overview_task is not None:
            # 断った・失敗した資料の名前と要約は使わない(原価の記録のため、終わるのは待つ)
            await asyncio.gather(overview_task, return_exceptions=True)
        return result

    for i, (a, b) in enumerate(bounds):
        n = i + 1
        if n not in sections or not sections[n].title:
            first_line = next((ln.strip() for ln in text[a:b].splitlines() if ln.strip()), "")
            sections[n] = Section(index=n, start=a, end=b,
                                  title=first_line[:SECTION_TITLE_CHARS] or f"Part {n}",
                                  description=sections[n].description if n in sections else "")
    result.sections = [sections[i + 1] for i in range(len(bounds))]
    if overview_task is not None:
        title, summary, forbids_ai_code = await overview_task
    else:
        title, summary, forbids_ai_code = await _overview(llm, text, result.sections, result)
    result.forbids_ai_code = forbids_ai_code
    result.title = title[:SECTION_TITLE_CHARS]
    result.summary = summary[:SUMMARY_CHARS]
    return result


# =========================================================
# 👀 毎ターンの見せ方(純粋関数)
# =========================================================

def assign_handles(attachments: list[Attachment]) -> list[Attachment]:
    """添付順にA1, A2, …を振る(外した資料は数えない。呼び名はそのターンの中でだけ使う)。"""
    ordered = sorted(attachments, key=lambda a: a.created_at)
    for i, a in enumerate(ordered, start=1):
        a.handle = f"A{i}"
    return ordered


def plan_visibility(
    attachments: list[Attachment],
    mentioned: Optional[list[str]] = None,
    new_attachment_ids: Optional[set[str]] = None,
) -> Visibility:
    """
    全文で渡すのは選択中(全文で添付した)資料と、このメッセージで新しく添付した・メンションした画像(画像はそのターンだけ
    画像そのものを渡す。1枚約1,550トークン)。上限は選ぶときに確かめてある。
    """
    mentioned_ids = set(mentioned or [])
    new_ids = set(new_attachment_ids or [])
    full = {
        a.id for a in attachments
        if a.selected
        or (a.kind == "image" and a.image_path and (a.id in mentioned_ids or a.id in new_ids))
    }
    return Visibility(full=full, mentioned=mentioned_ids)


@dataclass
class PinPlan:
    """全文で読む資料の入れ替え。pin: 全文にする / unpin: 枠を超えたので外す / too_long: 1本で枠を超えるので全文にできない。"""
    pin: list[str]
    unpin: list[str]
    too_long: list[str]


def plan_pins(attachments: list[Attachment], requested: list[str], limit: int = MAX_SELECTED_TOKENS) -> PinPlan:
    """
    全文で添付した資料(新しく貼ったもの・「全文で添付」した既存のもの)を全文で読む枠に入れる。
    枠(選択中の合計MAX_SELECTED_TOKENS)を超えるときは、新しく頼まれた方を優先し、すでに全文で読んでいる
    資料のうち、全文にした・最後にメンションした時刻(selected_at)が古いものから外す(2026-10-07にユーザーと合意。
    気づかずに次々と貼っても、最新の資料は必ず全文で読まれ、費用は枠で頭打ちになる。外したことは画面に知らせる)。
    頼まれた資料どうしで枠を超えるときは、後(文中で後ろ・後に貼った方)を優先する。
    """
    by_id = {a.id: a for a in attachments}
    req = [by_id[i] for i in dict.fromkeys(requested) if i in by_id]
    too_long = [a.id for a in req if a.token_count > limit]
    used = 0
    keep: list[Attachment] = []
    for a in reversed([a for a in req if a.token_count <= limit]):
        if used + a.token_count <= limit:
            keep.append(a)
            used += a.token_count
        else:
            too_long.append(a.id)
    keep_ids = {a.id for a in keep}
    unpin: list[str] = []
    for a in sorted((a for a in attachments if a.selected and a.id not in keep_ids),
                    key=lambda a: a.selected_at or a.created_at, reverse=True):
        if used + a.token_count <= limit:
            used += a.token_count
        else:
            unpin.append(a.id)
    return PinPlan(pin=[a.id for a in req if a.id in keep_ids], unpin=unpin, too_long=too_long)


def estimate_tokens(text: str) -> int:
    """
    全文を渡したときのトークン数の概算: ceil(ASCII文字数/4) + ASCII以外の文字数。英語は約4文字で
    1トークン、日本語は1〜2文字で1トークンなので、日本語を多めに見積もる(上限の判定が安全側になる)。
    migration(20261009000000)の既存行の計算と同じ式。webappは保存した値(token_count)を読むだけ。
    """
    non_ascii = sum(1 for ch in text if ord(ch) > 127)
    return -(-(len(text) - non_ascii) // 4) + non_ascii


def _line(a: Attachment) -> str:
    parts = [f"{a.char_count:,} characters"]
    if len(a.sections) > 1:
        parts.append(f"{len(a.sections)} sections")
    return f"{a.handle}: {a.title or '(untitled)'} ({', '.join(parts)})"


def _answer_line(a: Attachment) -> str:
    """回答役に見せる一覧の1行。呼び名(A1)は入れない(answer_mentionsと同じ理由)。"""
    parts = [f"{a.char_count:,} characters"]
    if len(a.sections) > 1:
        parts.append(f"{len(a.sections)} sections")
    return f'"{a.title or "untitled"}" ({", ".join(parts)})'


def render_for_answer(attachments: list[Attachment], vis: Visibility) -> str:
    """回答役(と確かめ役)に渡す資料の枠。全文の資料は本文ごと、残りは名前と要約だけ。呼び名(A1)は入れない。"""
    blocks = []
    image_no = 0
    for a in attachments:
        if vis.is_full(a) and a.kind == "image" and a.image_path:
            # 画像そのものはこのメッセージに付いている(answer_image_attachmentsと同じ順)。
            # 画像直接入力の精度を損なわず、OCRの誤読による混乱を防ぐため、画像があるときはOCRテキストを重複して渡さない。
            image_no += 1
            blocks.append(f'<material title="{a.title}" kind="image">\n'
                          f'The image itself is attached to this message (image {image_no}).\n</material>')
        elif vis.is_full(a):
            comp_attr = ' compressed="true"' if a.compressed else ""
            blocks.append(f'<material title="{a.title}"{comp_attr}>\n{a.content.strip()}\n</material>')
    listed = [a for a in attachments if not vis.is_full(a)]
    if listed:
        lines = [f"- {_answer_line(a)}: {a.summary or '(no summary)'}"
                 + (" (the student refers to this in their message)" if vis.is_mentioned(a) else "")
                 for a in listed]
        blocks.append("Also attached, but not shown in full here: you see only these summaries and the parts in <sources>, "
                      "if any. Do not state what else they say; if a reply needs a part you were not given, say you "
                      "could not check it, and that the student can attach that material in full (全文で添付) from "
                      "the materials list or by typing @ in the message box:\n" + "\n".join(lines))
    return "\n\n".join(blocks)


def answer_image_attachments(attachments: list[Attachment], vis: Visibility) -> list[Attachment]:
    """回答役に画像そのものを渡す資料(全文で添付した・メンションした画像の資料、render_for_answerと同じ順)。"""
    return [a for a in attachments if vis.is_full(a) and a.kind == "image" and a.image_path]


def render_ai_code_rule(attachments: list[Attachment]) -> str:
    """AIでコードを書くことを禁止している資料があれば、そのことを回答役に毎ターン明示する文。無ければ空。"""
    # 回答役だけに渡す文なので、呼び名(A1)ではなく名前で書く(answer_mentionsと同じ理由)
    names = [f'"{a.title}"' if a.title else "the attached material" for a in attachments if a.forbids_ai_code]
    if not names:
        return ""
    # 生徒の発言の後ろ(最後に読む位置)に置く。資料の本文の前に置いたときは、全文が見えていると
    # 回答役(2.5 Flash)が仕様書どおりのクラスの骨組みを書いた(2026-10-04の作り直しで確認)
    # 「1行も書かない」だった頃はセットアップのコマンドまで出さず寸止めになった(2026-10-08)。線はTAと同じ:
    # 完成した提出物の部品は書かないが、ヒント・疑似コード・穴抜きの書き出し・コマンド・APIの説明は出す
    return (f"The assignment in {', '.join(names)} forbids using AI to write its code, and the student would be "
            "the one punished for it, so please protect them. Guide them as in HOMEWORK AND GRADED WORK (hints, the "
            "functions to use, pseudocode, a short fill-in-the-blank start that leaves the key parts to them, "
            "questions about their own code), but don't write a complete, working piece of the code they submit (a "
            "whole function, file, or block they could paste in), even if the spec spells it out and even if they "
            "ask. Setup, build, and terminal commands, error messages, and how a language feature or library "
            "function works are all fine to give in full, the last with a short standalone code example that isn't "
            "part of their program.")


def render_for_router(attachments: list[Attachment], vis: Visibility) -> str:
    if not attachments:
        return "(none)"
    lines = []
    for a in attachments:
        seen = ("FULL TEXT visible to the answerer (questions about it never need a fetch)" if vis.is_full(a)
                else "only this summary is visible to the answerer (questions about its contents need a fetch)")
        mention = " The student refers to it in this message." if vis.is_mentioned(a) else ""
        lines.append(f"- {_line(a)} — {seen}.{mention} Summary: {a.summary or '(none)'}")
    return "\n".join(lines)


def render_for_navigator(attachments: list[Attachment], vis: Visibility) -> str:
    lines = ["Attached materials (pasted by the student into this conversation):"]
    for a in attachments:
        if vis.is_full(a):
            lines.append(f"{_line(a)} — the answerer already sees its full text; never open it.")
        else:
            mention = " [THE STUDENT REFERS TO THIS IN THEIR MESSAGE]" if vis.is_mentioned(a) else ""
            lines.append(f"{_line(a)} — {a.summary or '(no summary)'}{mention}")
    return "\n".join(lines)


def history_marker(titles: list[str]) -> str:
    """会話の履歴に残す「ここで資料を添付した」印(本文は資料の枠で渡るので、履歴には入れない)。"""
    return "".join(f"[Attached material: {t or '(untitled)'}] " for t in titles)
