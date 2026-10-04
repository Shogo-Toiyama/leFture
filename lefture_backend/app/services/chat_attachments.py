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
                              毎ターン: plan_visibility で「全文で渡す資料」と「一覧だけの資料」を決める

- 振り分け役は資料の本文を読まない。安全の確認は添付時に一度だけ(本文を必ず読む要約役が兼ねる)。
  節の束を前から波(READ_WAVE_BATCHES個ずつ並列)で読み、断った束が出た波で止める(最後まで読まされない)。
- 毎ターン渡すもの: スレッドの資料の合計がFULL_TEXT_BUDGET_CHARS以内なら全部を全文、超えたら
  最後に添付した1本だけ全文(それ自体が予算以内のとき)、残りは一覧(名前と要約)。中身は探索役が
  目次(A2)→ 節(A2/S3)と開く。「最後の1本」を外す条件は付けない(10章、ユーザーと合意)。
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

# 毎ターン全文で渡す量の上限(スレッドの資料の合計、または最後に添付した1本)
FULL_TEXT_BUDGET_CHARS = 10_000

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
# 名前と要約: 全文で渡す長さの資料は全文から(束と並列に)、それより長い資料は冒頭と目次から(束の後に)
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
    "properties": {"title": {"type": "string"}, "summary": {"type": "string"}},
    "required": ["title", "summary"],
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
        return cls(id=row["id"], title=(row.get("title") or "").strip(), content=content,
                   summary=(row.get("summary") or "").strip(), sections=sections,
                   message_id=row.get("message_id"), created_at=row.get("created_at") or "")


@dataclass
class ReadResult:
    """read_attachmentの結果。blocked=Trueなら審査で断った。errorがあれば処理に失敗した。"""
    title: str = ""
    summary: str = ""
    sections: list[Section] = field(default_factory=list)
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
    """そのターンに各資料をどう見せるか。full: 回答役に全文を渡す資料のid。"""
    full: set[str]

    def is_full(self, a: Attachment) -> bool:
        return a.id in self.full


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


async def _overview(llm: UnifiedLLM, text: str, sections: Optional[list[Section]], result: ReadResult) -> tuple[str, str]:
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
        return "", ""
    result.calls += 1
    result.input_tokens += res.input_tokens
    result.output_tokens += res.output_tokens
    out = res.output_json if isinstance(res.output_json, dict) else {}
    return str(out.get("title") or "").strip(), str(out.get("summary") or "").strip()


async def read_attachment(llm: UnifiedLLM, text: str, limiter: Optional[asyncio.Semaphore] = None) -> ReadResult:
    """
    資料を読んで、審査・節ごとの名前と説明・全体の名前と要約を作る。
    節の束をREAD_WAVE_BATCHES個ずつ並列に読み、断った束が出た波で止める(最後まで読まされない)。
    全文で渡す長さの資料は、名前と要約も全文から最初の波と並列に作る(待ち時間を増やさない)。
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
    if len(text) <= FULL_TEXT_BUDGET_CHARS:
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
        title, summary = await overview_task
    else:
        title, summary = await _overview(llm, text, result.sections, result)
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


def plan_visibility(attachments: list[Attachment], budget: int = FULL_TEXT_BUDGET_CHARS) -> Visibility:
    """合計が予算以内なら全部を全文、超えたら最後に添付した1本だけ(それ自体が予算以内のとき)。"""
    if not attachments:
        return Visibility(full=set())
    if sum(a.char_count for a in attachments) <= budget:
        return Visibility(full={a.id for a in attachments})
    last = max(attachments, key=lambda a: a.created_at)
    return Visibility(full={last.id} if last.char_count <= budget else set())


def _line(a: Attachment) -> str:
    parts = [f"{a.char_count:,} characters"]
    if len(a.sections) > 1:
        parts.append(f"{len(a.sections)} sections")
    return f"{a.handle}: {a.title or '(untitled)'} ({', '.join(parts)})"


def render_for_answer(attachments: list[Attachment], vis: Visibility) -> str:
    """回答役(と確かめ役)に渡す資料の枠。全文の資料は本文ごと、残りは名前と要約だけ。"""
    blocks = []
    for a in attachments:
        if vis.is_full(a):
            blocks.append(f'<material handle="{a.handle}" title="{a.title}">\n{a.content.strip()}\n</material>')
    listed = [a for a in attachments if not vis.is_full(a)]
    if listed:
        lines = [f"- {_line(a)}: {a.summary or '(no summary)'}" for a in listed]
        blocks.append("Also attached, but not shown in full here (only the parts in <sources>, if any, were read for "
                      "this message):\n" + "\n".join(lines))
    return "\n\n".join(blocks)


def render_for_router(attachments: list[Attachment], vis: Visibility) -> str:
    if not attachments:
        return "(none)"
    lines = []
    for a in attachments:
        seen = ("FULL TEXT visible to the answerer (questions about it never need a fetch)" if vis.is_full(a)
                else "only this summary is visible to the answerer (questions about its contents need a fetch)")
        lines.append(f"- {_line(a)} — {seen}. Summary: {a.summary or '(none)'}")
    return "\n".join(lines)


def render_for_navigator(attachments: list[Attachment], vis: Visibility) -> str:
    lines = ["Attached materials (pasted by the student into this conversation):"]
    for a in attachments:
        if vis.is_full(a):
            lines.append(f"{_line(a)} — the answerer already sees its full text; never open it.")
        else:
            lines.append(f"{_line(a)} — {a.summary or '(no summary)'}")
    return "\n".join(lines)


def history_marker(titles: list[str]) -> str:
    """会話の履歴に残す「ここで資料を添付した」印(本文は資料の枠で渡るので、履歴には入れない)。"""
    return "".join(f"[Attached material: {t or '(untitled)'}] " for t in titles)
