"""
回答役に渡す出典の本文を「区切り」に分けて番号を振る(‹3.5› = 出典3の5番目の区切り)。

回答役は [3] ではなく [3.5] / [3.5-7](連続する範囲) で引用し、指された区切りがそのまま
根拠の箇所になる(後から原文を探して照合しない)。2026-10-02〜03の実験
(contents_generation/test_codes/citation_grounding_test)で、
  - 書式は182か所すべてで守られた(3.5 Flash-Lite・推論なし)
  - 根拠として正しい箇所を指せた割合は、埋め込みで後から探す方式より高く、
    「出典に根拠の無い所への番号付け」も減った
  - わざと雑に区切ると正しさが明確に落ちた(回答役が範囲で繋ぎ直すのは保険にとどまる)
ため、区切り方は「なるべくまとまりを保つ」方に寄せ、拾いきれない分だけ回答役の範囲指定に任せる。

区切りの単位は出典の種類ごとの自然な単位:
  - Deep Note・トピック・復習カード・キーワード・お知らせ等: Markdownのブロック(段落・見出しから
    始まる行・箇条書きの1行・キーワードの1項目)。300字を超えるブロックだけ、さらに文に分ける
  - トランスクリプト・講義の要約・Web・チャット・コース: 文
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

BLOCK_MAX_CHARS = 300
# これより短い断片(見出しだけの行・「OK.」等)は次の区切りにつなげる
MIN_UNIT_CHARS = 12
# 括弧の対応を待つのはこの長さまで(閉じ忘れの括弧で、残り全部が1つにならないように)
MAX_BRACKET_SPAN = 400

SENTENCE_SOURCE_TYPES = frozenset({"transcript_topic", "lecture_summary", "web", "chat_turn", "course", ""})

_OPENERS = "(（「『[【“‘〈《"
_CLOSERS = ")）」』]】”’〉》"
_CLOSER_CHARS = "」』）)\\]】\"'”’〉》"

# 文末の候補。「。」は数字の後でも文末(「答えは120。」)だが、!?は数字の直後なら文末にしない
# (ファクトリアルの 5! や「P(A)?」のような記法)。「.」は後ろが空白か終わりのときだけ(3.5 や e.g. で切らない)。
_SENT_END_RE = re.compile(
    rf"(?:[。؟।]|(?<![0-9０-９])[！？!?])[。！？!?؟।]*[{_CLOSER_CHARS}]*"
    rf"|\.(?=[{_CLOSER_CHARS}]*(?:\s|$))[{_CLOSER_CHARS}]*"
    r"|\n+"
)
# Markdownのブロックの境目: 空行 / 見出し・箇条書き・引用・「Keywords:」「Deep Note:」で始まる行 /
# キーワードの項目の境目「; 名前: 」
_BLOCK_SEP_RE = re.compile(
    r"\n\s*\n|\n(?=\s*(?:#|[-*+] |\d+\. |>|Keywords:|Deep Note:))|; (?=[^;\n]{1,60}: )"
)


# 本文の引用記号: Deep Note・復習カードの⟦s000143⟧ ⟦s000325-s000331, s000341⟧、FunFactの⟦1⟧と揺れ(〚1〛 [[1]])。
# 画面にも出ていないので、回答役にも利用者にも見せない
_CITATION_MARK_RE = re.compile(r"[ \t]*(?:⟦[^⟧]*⟧|〚[^〛]*〛|\[\[\s*[sS]?\d[\d\s,，sS\-–—−]*\]\])")
_FIGURE_RE = re.compile(r"<!--\s*FIGURE:[^>]*-->")


def strip_citations(text: str) -> str:
    """引用記号と図のプレースホルダーを剥がす(画面に出ていないもの)。"""
    text = _FIGURE_RE.sub("", text or "")
    text = _CITATION_MARK_RE.sub("", text)
    return re.sub(r"[ \t]+\n", "\n", text).strip()


@dataclass
class Unit:
    start: int
    end: int


def _visible_len(text: str) -> int:
    """空白と記号を除いた文字数(短すぎる断片の判定用)。"""
    return sum(1 for ch in text if not ch.isspace() and unicodedata.category(ch)[0] not in "PS")


def _bracket_depth(text: str) -> int:
    depth = 0
    for ch in text:
        if ch in _OPENERS:
            depth += 1
        elif ch in _CLOSERS and depth > 0:
            depth -= 1
    return depth


def _trim(text: str, a: int, b: int) -> tuple[int, int]:
    while a < b and text[a] in " \t\n;":
        a += 1
    while b > a and text[b - 1] in " \t\n":
        b -= 1
    return a, b


def _is_boundary(text: str, start: int, m: "re.Match[str]") -> bool:
    if m.group(0).startswith("\n"):
        return True
    end = m.end()
    # 閉じ括弧・引用符で終わり、その直後に空白なしで文が続く(「…だ！」と言った / （…キロメートル！）まで)
    # なら、括弧の中の文末なので切らない
    if m.group(0)[-1] in _CLOSER_CHARS and end < len(text) and not text[end].isspace() \
            and not _SENT_END_RE.match(text, end):
        return False
    # 括弧・鉤括弧の中(まだ閉じていない)なら切らない
    if end - start <= MAX_BRACKET_SPAN and _bracket_depth(text[start:end]) > 0:
        return False
    return True


def split_sentences(text: str) -> list[Unit]:
    """文に分ける(位置つき)。短すぎる断片は次の文につなげる。"""
    raw: list[tuple[int, int]] = []
    pos = 0
    for m in _SENT_END_RE.finditer(text):
        if not _is_boundary(text, pos, m):
            continue
        if text[pos:m.end()].strip():
            raw.append((pos, m.end()))
        pos = m.end()
    if text[pos:].strip():
        raw.append((pos, len(text)))
    return _merge_short(text, raw)


def _merge_short(text: str, spans: list[tuple[int, int]]) -> list[Unit]:
    out: list[Unit] = []
    carry = None
    for i, (a, b) in enumerate(spans):
        if carry is not None:
            a, carry = carry, None
        a, b = _trim(text, a, b)
        if b <= a:
            continue
        if _visible_len(text[a:b]) < MIN_UNIT_CHARS and i < len(spans) - 1:
            carry = a
            continue
        out.append(Unit(a, b))
    if carry is not None:
        a, b = _trim(text, carry, len(text))
        if b > a:
            if out:
                out[-1].end = b
            else:
                out.append(Unit(a, b))
    return out


def split_units(text: str, source_type: str = "") -> list[Unit]:
    """出典の種類ごとの自然な単位で区切る。"""
    if source_type in SENTENCE_SOURCE_TYPES:
        return split_sentences(text)
    spans, pos = [], 0
    for m in _BLOCK_SEP_RE.finditer(text):
        spans.append((pos, m.start()))
        pos = m.end()
    spans.append((pos, len(text)))
    units: list[Unit] = []
    for u in _merge_short(text, spans):
        if u.end - u.start > BLOCK_MAX_CHARS:
            units += [Unit(u.start + s.start, u.start + s.end) for s in split_sentences(text[u.start:u.end])]
        else:
            units.append(u)
    return units


def mark_units(text: str, units: list[Unit], ref: str) -> str:
    """各区切りの先頭に ‹ref.k› を入れた本文(回答役に渡す形)。"""
    out, pos = [], 0
    for k, u in enumerate(units, 1):
        out.append(text[pos:u.start])
        out.append(f"‹{ref}.{k}› ")
        pos = u.start
    out.append(text[pos:])
    return "".join(out)


# 前後の文脈として添える区切りの長さの上限(区切りそのものは切らない)
PASSAGE_CONTEXT_CHARS = 300


def passage(text: str, units: list[Unit], a: int, b: int) -> dict:
    """a〜b番目(1始まり)の区切りと、その前後1区切り(文脈)。"""
    before = text[units[a - 2].start:units[a - 2].end] if a >= 2 else ""
    after = text[units[b].start:units[b].end] if b < len(units) else ""
    return {
        "before": ("…" + before[-PASSAGE_CONTEXT_CHARS:]) if len(before) > PASSAGE_CONTEXT_CHARS else before,
        "text": text[units[a - 1].start:units[b - 1].end],
        "after": (after[:PASSAGE_CONTEXT_CHARS] + "…") if len(after) > PASSAGE_CONTEXT_CHARS else after,
    }
