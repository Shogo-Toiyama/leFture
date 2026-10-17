"""
チャットの「今見ているページ」。

画面からはページの種類と行のID(と選択テキスト・その前後)だけが届き、本文はここで
DBから読む。クライアントから本文を受け取らないのは、(1)リクエストが小さく済む、
(2)プランの制限(plan_features)をチャットの検索と同じ基準でかけられる、の2つのため。

送るのは選択の有無にかかわらず毎ターン(内容は最新のメッセージにだけ載るので、
会話が長くなっても積み上がらない)。ページの種類ごとの範囲:
  - deep_note:   そのトピックのページ全体
  - review_card: 同じトピックのカード全部(1トピック4枚前後。表紙のイラストは除く)。
                 今表示しているカードに印を付ける。表紙(id無し)ならトピック番号で読む
  - fun_fact:    その1件(選択→Askのときだけ届く)
トランスクリプトはページ全体が長すぎるので対象外(選択できるようになったら、
選択部分だけを送る方針)。

本文の引用記号(⟦s000143⟧ / FunFactの⟦1⟧)は剥がす。画面に出ていないものなので、
回答役にも見せない。見ているページは出典番号を付けずに使う(プロンプト側で指示)。
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional

from app.services.helpers.plan_features import DEEP_NOTES_SKIPPED_PLAN_LIMIT
from app.services.chat_units import strip_citations
from app.services.knowledge_index import _render_card_content

# 回答役に渡すページ本文の上限。Deep Noteは中央値3,300字・上位10%で7,000字だが、
# 12万字を超える外れ値もあるので切る。超えたら選択箇所(無ければ今のカード/先頭)の周りだけ
MAX_SCREEN_CHARS = 8000
# 探索役・振り分け役に見せる抜粋の長さ(全文は回答役だけ。探索役は「何のページか」が分かれば足りる)
NAVIGATOR_EXCERPT_CHARS = 1500
# 選択の前後として受け取る文字数の上限(位置の特定に使うだけ)
MAX_SELECTION_CONTEXT_CHARS = 300

SELECTED_OPEN = "<selected>"
SELECTED_CLOSE = "</selected>"
CURRENT_CARD_MARK = "(currently shown)"

SCREEN_KINDS = ("deep_note", "review_card", "fun_fact")
# 画面の種類 → plan_featuresで制限される材料の種類(blocked_knowledge_source_typesの値)
_KIND_SOURCE_TYPE = {"deep_note": "deep_note", "review_card": "review_card", "fun_fact": "fun_fact"}


_REVIEW_CARD_TYPE_ORDER = ["hook", "core_why", "gotcha", "next_action"]
_REVIEW_CARD_TYPE_LABEL = {
    "hook": "Hook", "core_why": "Core why", "gotcha": "Gotcha", "next_action": "Next action",
}


@dataclass
class ScreenRef:
    kind: str
    id: Optional[str] = None
    topic_number: Optional[int] = None


@dataclass
class ScreenSelection:
    text: str
    before: str = ""
    after: str = ""


@dataclass
class ScreenPage:
    kind: str
    lecture_id: Optional[str]
    topic_number: Optional[int]
    # 例: 'Deep Note "Heaps"' / 'Review Cards for topic "Heaps"' / 'Fun Fact "…"'
    title: str
    # 引用記号を剥がし、選択箇所を<selected>…</selected>で囲み、上限で切った本文
    text: str
    # 選択テキストを本文の中で見つけられたか(見つからなければ選択は別に添える)
    selection_marked: bool = False
    truncated: bool = False

    def excerpt(self, max_chars: int = NAVIGATOR_EXCERPT_CHARS) -> str:
        """探索役用の抜粋。選択箇所があればその周り、無ければ先頭。"""
        start = self.text.find(SELECTED_OPEN)
        if start < 0:
            return _clip(self.text, 0, 0, max_chars)
        end = self.text.find(SELECTED_CLOSE, start) + len(SELECTED_CLOSE)
        return _clip(self.text, start, end, max_chars)


# =========================================================
# 選択箇所の特定
# =========================================================

# 画面のtextContentには出ないMarkdownの記号と空白は、比べるときに無視する
_IGNORED_CHARS = set("*_`#>|~")


def _normalized_with_map(text: str, ignore_digits: bool = False) -> tuple[str, list[int]]:
    """
    比較用に、空白とMarkdownの記号を除いた文字列と、その各文字の元の位置。
    ignore_digits: 数字も除く(AIの回答の選択用。画面の出典番号のボタン「1」が選択テキストに混ざるため)。
    """
    chars: list[str] = []
    positions: list[int] = []
    for i, ch in enumerate(text):
        if ch.isspace() or ch in _IGNORED_CHARS or (ignore_digits and ch.isdigit()):
            continue
        chars.append(ch.lower())
        positions.append(i)
    return "".join(chars), positions


def _normalized(text: str, ignore_digits: bool = False) -> str:
    return _normalized_with_map(text, ignore_digits)[0]


def _common_suffix_len(a: str, b: str) -> int:
    n = 0
    while n < len(a) and n < len(b) and a[-1 - n] == b[-1 - n]:
        n += 1
    return n


def _common_prefix_len(a: str, b: str) -> int:
    n = 0
    while n < len(a) and n < len(b) and a[n] == b[n]:
        n += 1
    return n


def locate_selection(text: str, selection: ScreenSelection, ignore_digits: bool = False) -> Optional[tuple[int, int]]:
    """
    選択テキストが本文のどこか(元の文字位置の[start, end))。画面の文字列(Markdownの記号や
    改行が消えたtextContent)とDBの本文は一致しないので、空白とMarkdownの記号を除いて比べる。
    同じ文言が何度も出てくるときは、選択の前後の文字がより長く一致する方を選ぶ。
    """
    needle = _normalized(selection.text, ignore_digits)
    if not needle:
        return None
    hay, positions = _normalized_with_map(text, ignore_digits)
    before = _normalized(selection.before, ignore_digits)
    after = _normalized(selection.after, ignore_digits)

    best: Optional[tuple[int, int]] = None
    best_score = -1
    i = hay.find(needle)
    while i >= 0:
        j = i + len(needle)
        score = _common_suffix_len(hay[:i], before) + _common_prefix_len(hay[j:], after)
        if score > best_score:
            best, best_score = (i, j), score
        i = hay.find(needle, i + 1)
    if best is None:
        return None
    start, end = positions[best[0]], positions[best[1] - 1] + 1
    # 選択の端に接した強調・コードの記号(**太字** の ** など)は、印の内側に含める
    while start > 0 and text[start - 1] in "*_`":
        start -= 1
    while end < len(text) and text[end] in "*_`":
        end += 1
    return start, end


# AIの回答に入っている出典の印(⟦3⟧ ⟦3.5⟧ ⟦W1⟧)。画面ではボタンになるので、選択の文字とは別物
_ANSWER_CITATION_RE = re.compile(r"⟦[^⟦⟧\n]{1,60}⟧")
# 返信の引用で、選択箇所の前後に付ける文字数
REPLY_QUOTE_CONTEXT_CHARS = 300


def build_reply_quote(answer_text: str, selection: ScreenSelection) -> Optional[str]:
    """
    チャットの回答の一部を選んで返信するとき、その回答のどこかを示す抜粋(選択箇所を<selected>で囲み、
    前後に少し文脈を付ける)。選択テキストが回答の中に見つからなければNone
    (そのときは、ただの選択として扱う。回答でないものを「あなたの回答」と見せないための確認を兼ねる)。
    """
    text = _ANSWER_CITATION_RE.sub("", answer_text or "")
    span = locate_selection(text, selection, ignore_digits=True)
    if not span:
        return None
    a, b = span
    lo = max(0, a - REPLY_QUOTE_CONTEXT_CHARS)
    hi = min(len(text), b + REPLY_QUOTE_CONTEXT_CHARS)
    return (
        ("… " if lo > 0 else "")
        + text[lo:a] + SELECTED_OPEN + text[a:b] + SELECTED_CLOSE + text[b:hi]
        + (" …" if hi < len(text) else "")
    )


def _mark(text: str, span: tuple[int, int]) -> str:
    a, b = span
    return f"{text[:a]}{SELECTED_OPEN}{text[a:b]}{SELECTED_CLOSE}{text[b:]}"


def _clip(text: str, focus_start: int, focus_end: int, max_chars: int) -> str:
    """max_charsに収まるよう、focus(選択箇所や今のカード)を中心に切り出す。"""
    if len(text) <= max_chars:
        return text
    focus_len = max(0, focus_end - focus_start)
    if focus_len >= max_chars:
        start = focus_start
    else:
        start = max(0, focus_start - (max_chars - focus_len) // 2)
    start = min(start, len(text) - max_chars)
    end = start + max_chars
    return ("… " if start > 0 else "") + text[start:end] + (" …" if end < len(text) else "")


def _finish(page: ScreenPage, focus: Optional[tuple[int, int]], selection: Optional[ScreenSelection]) -> ScreenPage:
    """選択箇所に印を付け、上限で切る。focus: 選択が無いときに中心にする範囲(今のカード)。"""
    text = page.text
    span = locate_selection(text, selection) if selection else None
    if span:
        text = _mark(text, span)
        focus = (span[0], span[1] + len(SELECTED_OPEN) + len(SELECTED_CLOSE))
        page.selection_marked = True
    fs, fe = focus or (0, 0)
    clipped = _clip(text, fs, fe, MAX_SCREEN_CHARS)
    page.truncated = clipped != text
    page.text = clipped
    return page


# =========================================================
# DBから読む
# =========================================================

def _topic_title(admin_client, lecture_id: Optional[str], topic_number: Optional[int]) -> Optional[str]:
    if lecture_id is None or topic_number is None:
        return None
    res = admin_client.table("lecture_topics").select("topic_title") \
        .eq("lecture_id", lecture_id).eq("index", topic_number).maybe_single().execute()
    return (res.data or {}).get("topic_title") if res else None


def _owned(row: Optional[dict], user_id: str) -> bool:
    return bool(row) and row.get("user_id") == user_id and not row.get("deleted_at")


def _load_deep_note(admin_client, user_id: str, ref: ScreenRef) -> Optional[ScreenPage]:
    res = admin_client.table("deep_notes").select(
        "id, user_id, lecture_id, topic_number, note_contents, deleted_at"
    ).eq("id", ref.id).maybe_single().execute()
    row = res.data if res else None
    if not _owned(row, user_id):
        return None
    contents = row.get("note_contents") or ""
    if not contents.strip() or contents == DEEP_NOTES_SKIPPED_PLAN_LIMIT:
        return None
    title = _topic_title(admin_client, row.get("lecture_id"), row.get("topic_number"))
    return ScreenPage(
        kind="deep_note",
        lecture_id=row.get("lecture_id"),
        topic_number=row.get("topic_number"),
        title=f'Deep Note "{title}"' if title else "Deep Note",
        text=strip_citations(contents),
    )


def _load_review_cards(
    admin_client, user_id: str, ref: ScreenRef, lecture_id: Optional[str],
) -> tuple[Optional[ScreenPage], Optional[tuple[int, int]]]:
    """同じトピックのカード全部。返り値の2つ目は今表示しているカードの範囲(切り出しの中心)。"""
    current_id = None
    topic_number = ref.topic_number
    if ref.id:
        res = admin_client.table("review_cards").select(
            "id, user_id, lecture_id, topic_number, deleted_at"
        ).eq("id", ref.id).maybe_single().execute()
        row = res.data if res else None
        if not _owned(row, user_id):
            return None, None
        current_id, lecture_id, topic_number = row["id"], row.get("lecture_id"), row.get("topic_number")
    if lecture_id is None or topic_number is None:
        return None, None

    rows = admin_client.table("review_cards").select(
        "id, user_id, title, card_type, card_content"
    ).eq("user_id", user_id).eq("lecture_id", lecture_id).eq("topic_number", topic_number) \
        .is_("deleted_at", "null").execute().data or []
    if not rows:
        return None, None
    rows.sort(key=lambda r: _REVIEW_CARD_TYPE_ORDER.index(r.get("card_type"))
              if r.get("card_type") in _REVIEW_CARD_TYPE_ORDER else len(_REVIEW_CARD_TYPE_ORDER))

    parts: list[str] = []
    focus: Optional[tuple[int, int]] = None
    offset = 0
    for r in rows:
        label = _REVIEW_CARD_TYPE_LABEL.get(r.get("card_type"), r.get("card_type") or "Card")
        mark = f" {CURRENT_CARD_MARK}" if r["id"] == current_id else ""
        block = f"[{label} card{mark}] {r.get('title') or ''}".rstrip() + "\n" \
            + strip_citations(_render_card_content(r.get("card_content")))
        if r["id"] == current_id:
            focus = (offset, offset + len(block))
        parts.append(block)
        offset += len(block) + 2
    title = _topic_title(admin_client, lecture_id, topic_number)
    page = ScreenPage(
        kind="review_card",
        lecture_id=lecture_id,
        topic_number=topic_number,
        title=f'Review Cards for topic "{title}" (all of its cards)' if title else "Review Cards (all of the topic's cards)",
        text=("" if current_id else "(They are on the topic's cover; these are the cards that follow it.)\n\n")
        + "\n\n".join(parts),
    )
    return page, focus


def _load_fun_fact(admin_client, user_id: str, ref: ScreenRef) -> Optional[ScreenPage]:
    res = admin_client.table("fun_facts").select(
        "id, user_id, lecture_id, title, hook, body, deleted_at"
    ).eq("id", ref.id).maybe_single().execute()
    row = res.data if res else None
    if not _owned(row, user_id):
        return None
    body = "\n\n".join(strip_citations(row.get(k) or "") for k in ("hook", "body")).strip()
    if not body:
        return None
    title = (row.get("title") or "").strip()
    return ScreenPage(
        kind="fun_fact",
        lecture_id=row.get("lecture_id"),
        topic_number=None,
        title=f'Fun Fact "{title}"' if title else "Fun Fact",
        text=body,
    )


def load_screen_page(
    admin_client,
    user_id: str,
    ref: ScreenRef,
    lecture_id: Optional[str],
    selection: Optional[ScreenSelection],
    blocked_source_types: frozenset[str],
) -> Optional[ScreenPage]:
    """
    見ているページの本文。本人の行でない・消えている・今のプランでチャットに使えない
    種類(FreeのDeep Note等)ならNone(そのときは今まで通り講義名と選択テキストだけ)。
    lecture_id: 画面の講義(表紙を見ているときの復習カードの特定に使う)。
    """
    if ref.kind not in SCREEN_KINDS or _KIND_SOURCE_TYPE[ref.kind] in blocked_source_types:
        return None
    if ref.kind == "deep_note" and ref.id:
        page, focus = _load_deep_note(admin_client, user_id, ref), None
    elif ref.kind == "review_card":
        page, focus = _load_review_cards(admin_client, user_id, ref, lecture_id)
    elif ref.kind == "fun_fact" and ref.id:
        page, focus = _load_fun_fact(admin_client, user_id, ref), None
    else:
        return None
    if page is None or not page.text.strip():
        return None
    return _finish(page, focus, selection)
