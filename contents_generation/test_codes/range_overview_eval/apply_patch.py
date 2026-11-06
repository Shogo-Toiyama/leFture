"""
本番の chat_navigator.py のコピー(patched/chat_navigator.py)に、範囲の講義をまとめて開く変更を入れる。
コピーし直してから何度でも当て直せるように、置き換え前の文字列が1回だけあることを確かめる。

  cp lefture_backend/app/services/chat_navigator.py contents_generation/test_codes/range_overview_eval/patched/
  .venv/bin/python contents_generation/test_codes/range_overview_eval/apply_patch.py

本番に入れるときは、patched/chat_navigator.py と本番の差分(diff)をそのまま当てる。
"""

from pathlib import Path

P = Path(__file__).resolve().parent / "patched" / "chat_navigator.py"
s = P.read_text(encoding="utf-8")


def rep(old: str, new: str) -> None:
    global s
    n = s.count(old)
    assert n == 1, (n, old[:80])
    s = s.replace(old, new)


# 1. 予算の定数
rep("BY_DATE_MAX_DAYS = 400\n", '''BY_DATE_MAX_DAYS = 400
# 範囲の講義をまとめて取るとき(C{n}/L{a}-{b}、C{n}/L{a}-{b}/cards、by_date)に、回答役へ渡す材料の
# 1ターンの予算(estimate_tokensで数える)。回答役の材料全体の上限(MATERIALS_MAX_TOKENS=15,000)のうち、
# お知らせや検索結果のために約5,000を残す。入らなければ真ん中を削るのではなく、詳しさの段階を下げる
# (要約+トピック要約 → 要約+トピック名 → タイトルだけ)。カードは残りの予算で各講義に均等に配る。
# 2026-11-06: Formal logicの10月の7講義で、要約+トピック要約が約3,800、カード(core_why・gotcha)が約13,400。
RANGE_MATERIAL_BUDGET = 10_000
''')

# 2. 呼び名 C{n}/L{a}-{b}
rep('_MULTI_CARDS_RE = re.compile(r"^(C\\d+)/L(\\d+)-(\\d+)/cards$")\n',
    '_MULTI_CARDS_RE = re.compile(r"^(C\\d+)/L(\\d+)-(\\d+)/cards$")\n'
    '_LEC_RANGE_RE = re.compile(r"^(C\\d+)/L(\\d+)-(\\d+)$")\n')
rep('''        return ParsedHandle(kind="multi_lecture_cards", course=c, lecture_start=min(a, b), lecture_end=max(a, b))
''', '''        return ParsedHandle(kind="multi_lecture_cards", course=c, lecture_start=min(a, b), lecture_end=max(a, b))
    m_range = _LEC_RANGE_RE.match(h)
    if m_range:
        c, l1, l2 = m_range.groups()
        a, b = int(l1), int(l2)
        return ParsedHandle(kind="lecture_range", course=c, lecture_start=min(a, b), lecture_end=max(a, b))
''')
rep('''                parsed is not None and parsed.kind == "multi_lecture_cards"
''', '''                parsed is not None and parsed.kind in ("multi_lecture_cards", "lecture_range")
''')

# 3. 状態: 範囲の材料の残り予算 / 開いた結果: 使った予算
rep('''    link_sections: dict[str, tuple[str, str, str, list[tuple[int, int]]]] = field(default_factory=dict)
''', '''    link_sections: dict[str, tuple[str, str, str, list[tuple[int, int]]]] = field(default_factory=dict)
    # 範囲の講義をまとめて取る材料(by_date・C{n}/L{a}-{b}・…/cards)の、このターンの残り予算
    range_budget_left: int = RANGE_MATERIAL_BUDGET
''')
rep('''    # 次のターンに持ち越す参照(UUID)
    ref: Optional[dict] = None
''', '''    # 次のターンに持ち越す参照(UUID)
    ref: Optional[dict] = None
    # 範囲の材料の予算から使った量(estimate_tokens)
    range_tokens: int = 0
''')

# 4. by_date: 講義の一覧に、範囲の概要(要約・トピック要約・カード)を付ける
rep('''@dataclass
class DateOutcome:
    request: DateRequest
    lectures: list[MapLecture]
    course_titles: dict[str, str]

    def render(self) -> str:
        if not self.lectures:
            return f"{self.request.label()}:\\n(no lectures in this range)"
        lines = [
            f"- {lec.handle} ({lec.format_when() if hasattr(lec, 'format_when') else (lec.date.isoformat() if lec.date else 'no date')}) {self.course_titles.get(lec.course_handle, '')} / {lec.title}"
            for lec in self.lectures
        ]
        return f"{self.request.label()}:\\n" + "\\n".join(lines)
''', '''@dataclass
class DateOutcome:
    request: DateRequest
    lectures: list[MapLecture]
    course_titles: dict[str, str]
    # 回答役に渡す範囲の概要(build_range_overview)。探索役には中身ではなくoverview_noteだけ見せる
    overview_body: str = ""
    overview_tokens: int = 0
    overview_note: str = ""

    def render(self) -> str:
        if not self.lectures:
            return f"{self.request.label()}:\\n(no lectures in this range)"
        lines = [
            f"- {lec.handle} ({lec.format_when() if hasattr(lec, 'format_when') else (lec.date.isoformat() if lec.date else 'no date')}) {self.course_titles.get(lec.course_handle, '')} / {lec.title}"
            for lec in self.lectures
        ]
        note = f"\\n{self.overview_note}" if self.overview_note else ""
        return f"{self.request.label()}:\\n" + "\\n".join(lines) + note
''')
rep('''        span_str = f"{self.request.date_from} to {self.request.date_to}"
        within_str = f" in {self.request.within}" if self.request.within else ""
        body = f"Lectures recorded ({span_str}{within_str}):\\n" + "\\n".join(lines)
        return Material(
            key=f"by_date:{self.request.date_from}:{self.request.date_to}:{self.request.within or 'all'}",
            kind="lecture",
''', '''        span_str = f"{self.request.date_from} to {self.request.date_to}"
        # 回答役に渡す本文なので、コースは呼び名(C7)ではなく名前で書く
        within_str = f" in {self.course_titles.get(self.request.within, self.request.within)}" if self.request.within else ""
        if self.overview_body:
            body = f"Lectures recorded ({span_str}{within_str}):\\n\\n{self.overview_body}"
        else:
            body = f"Lectures recorded ({span_str}{within_str}):\\n" + "\\n".join(lines)
        return Material(
            key=f"by_date:{self.request.date_from}:{self.request.date_to}:{self.request.within or 'all'}",
            kind="lecture_range" if self.overview_body else "lecture",
''')

# 5. 範囲の概要を予算内で組み立てる関数(open_handleの前に置く)
rep('''async def open_handle(
    handle: str, nav_input: NavigatorInput, source: LectureSource,
    chat_source: Optional[ChatThreadSource] = None,
) -> Opened:
''', '''def _lecture_number(lec: MapLecture) -> int:
    try:
        return int(lec.handle.rsplit("/L", 1)[1])
    except (ValueError, IndexError):
        return -1


_RANGE_LEVEL_TEXT = {
    "overview": "each lecture's summary and topic summaries",
    "summary": "each lecture's summary and topic titles (topic summaries did not fit)",
    "titles": "lecture titles only (summaries did not fit)",
}


@dataclass
class RangeOverview:
    body: str
    tokens: int
    level: str  # overview / summary / titles
    lectures: int
    cards_included: int
    cards_total: int
    cards_only: bool = False

    def note(self) -> str:
        cards = (f"{self.cards_included} of {self.cards_total} key Review Cards (Core Why / Gotcha)"
                 if self.cards_total else "no key Review Cards")
        what = cards if self.cards_only else f"{_RANGE_LEVEL_TEXT[self.level]}, plus {cards}"
        return (f"Attached for the answerer ({self.lectures} lectures): {what}. Their text is not shown to you; "
                "open a single lecture or topic only if a specific part needs more detail.")


async def build_range_overview(
    lectures: list[MapLecture], m: StudentMap, source: LectureSource, budget: int, cards_only: bool = False,
) -> RangeOverview:
    """
    範囲の講義を、予算(estimate_tokens)に収まる一番詳しい段階でまとめる。段階は範囲全体でそろえる
    (要約+トピック要約 → 要約+トピック名 → タイトルだけ)。残りの予算で、カード(core_why・gotcha)を
    講義の順に1枚ずつ配る(均等になるように)。入らなかったカードの数は本文の最後に書く。
    """
    from app.services.chat_attachments import estimate_tokens
    from app.services.chat_units import strip_citations

    ids = [x.id for x in lectures]
    summaries: dict[str, str] = {}
    topics: list[list[dict]] = [[] for _ in lectures]
    if not cards_only:
        summaries, topic_lists = await asyncio.gather(
            source.lecture_summaries(ids), asyncio.gather(*[source.lecture_topics(i) for i in ids]))
        topics = list(topic_lists)
    cards_map = await source.multi_lecture_review_cards(ids, card_types=("core_why", "gotcha"))

    # 本文は回答役にだけ渡すので、呼び名(C4/L11・T1)は書かない。回答役は何も開かないので呼び名は要らず、
    # 書いてあると回答にそのまま写してしまう(生徒には意味が分からない)。探索役にはOpened.textの一覧で見せる
    def header(lec: MapLecture) -> str:
        when = lec.format_when() if hasattr(lec, "format_when") else (lec.date.isoformat() if lec.date else "no date")
        course = m.course(lec.course_handle)
        return f"### {when} — {course.title if course else ''} / {lec.title or 'untitled lecture'}"

    def block(i: int, level: str) -> str:
        parts = [header(lectures[i])]
        if level in ("overview", "summary"):
            summary = (summaries.get(ids[i]) or "").strip()
            if summary:
                parts.append(f"Summary: {summary}")
            lines = [f"- {t['title']}" + (f" — {t['summary']}" if level == "overview" and t.get("summary") else "")
                     for t in topics[i]]
            if lines:
                parts.append("Topics:\\n" + "\\n".join(lines))
        return "\\n".join(parts)

    ladder = ["titles"] if cards_only else ["overview", "summary", "titles"]
    for level in ladder:
        blocks = [block(i, level) for i in range(len(lectures))]
        used = sum(estimate_tokens(b) for b in blocks)
        if used <= budget:
            break

    queues: list[list[tuple[str, int]]] = []
    for lid in ids:
        ordered = sorted(cards_map.get(lid, []),
                         key=lambda c: (c.get("topic_number") or 0, 0 if c.get("card_type") == "core_why" else 1))
        q = []
        for c in ordered:
            text = strip_citations(format_lecture_review_cards([c]))
            q.append((text, estimate_tokens(text)))
        queues.append(q)
    chosen: list[list[str]] = [[] for _ in lectures]
    added_order: list[int] = []
    left = budget - used
    pos = [0] * len(lectures)
    added = True
    while added:
        added = False
        for i, q in enumerate(queues):
            if pos[i] >= len(q):
                continue
            text, tok = q[pos[i]]
            if tok <= left:
                chosen[i].append(text)
                added_order.append(i)
                left -= tok
                pos[i] += 1
                added = True
            else:
                pos[i] = len(q)  # この講義はここまで(残りは他の講義に回す)
    cards_total = sum(len(q) for q in queues)

    def assemble() -> str:
        sections = []
        for i in range(len(lectures)):
            sec = blocks[i]
            if chosen[i]:
                sec += f"\\nKey Review Cards ({len(chosen[i])} of {len(queues[i])}):\\n" + "\\n\\n".join(chosen[i])
            sections.append(sec)
        text = "\\n\\n".join(sections)
        left_out = cards_total - sum(len(c) for c in chosen)
        if left_out:
            text += f"\\n\\n({left_out} more key Review Cards in this range were left out to fit.)"
        return text

    # 見出し・区切りの分で予算を超えたら、最後に足したカードから外す
    body = assemble()
    while added_order and estimate_tokens(body) > budget:
        chosen[added_order.pop()].pop()
        body = assemble()
    included = sum(len(c) for c in chosen)
    return RangeOverview(body=body, tokens=estimate_tokens(body), level=level, lectures=len(lectures),
                         cards_included=included, cards_total=cards_total, cards_only=cards_only)


async def open_handle(
    handle: str, nav_input: NavigatorInput, source: LectureSource,
    chat_source: Optional[ChatThreadSource] = None, range_budget: int = RANGE_MATERIAL_BUDGET,
) -> Opened:
''')

# 6. C{n}/L{a}-{b}/cards と C{n}/L{a}-{b}: 予算内で組み立てる(真ん中を削らない)
start = s.index('    if parsed.kind == "multi_lecture_cards":\n')
end = s.index('\n    when = lec.format_when()', start)
s = s[:start] + '''    if parsed.kind in ("multi_lecture_cards", "lecture_range"):
        start_idx, end_idx = parsed.lecture_start, parsed.lecture_end
        target_lecs = sorted((x for x in course.lectures if start_idx <= _lecture_number(x) <= end_idx),
                             key=_lecture_number)
        if not target_lecs:
            return Opened(handle=handle, text=f"{handle}: (no lectures found in range L{start_idx}-L{end_idx})", material=None)
        cards_only = parsed.kind == "multi_lecture_cards"
        ov = await build_range_overview(target_lecs, m, source, range_budget, cards_only=cards_only)
        name = "Review Cards" if cards_only else "Lecture Overviews"
        listing = "\\n".join(f"- {x.handle} ({x.format_when() if hasattr(x, 'format_when') else (x.date.isoformat() if x.date else 'no date')}) {x.title}"
                            for x in target_lecs)
        # 回答役(と出典の表示)には呼び名ではなく日付の範囲で示す
        dates = [x.date for x in target_lecs if x.date]
        span = f"{min(dates).isoformat()} to {max(dates).isoformat()}" if dates else f"{len(target_lecs)} lectures"
        return Opened(
            handle=handle,
            text=f"{name} {handle}: {course.title}, L{start_idx} to L{end_idx}\\n{listing}\\n{ov.note()}",
            material=Material(
                key=f"{'review_cards' if cards_only else 'lecture_range'}:{course.id}:L{start_idx}-L{end_idx}",
                kind="review_cards" if cards_only else "lecture_range",
                label=f"{course.title} / {name} ({span})",
                content=f"# {course.title} — {name} ({span})\\n\\n{ov.body}",
                source_type="review_cards" if cards_only else "lecture_summary",
                course_id=course.id,
                handle=handle,
            ),
            surfaced=[x.handle for x in target_lecs],
            ref={"type": "course", "id": course.id},
            range_tokens=ov.tokens,
        )
''' + s[end:]

# 7. execute_lap: 範囲の材料の予算を、この周の範囲の操作で分ける。by_dateにも概要を付ける
rep('''        try:
            return await open_handle(req.handle, nav_input, tools.source, tools.chat_source)
''', '''        try:
            return await open_handle(req.handle, nav_input, tools.source, tools.chat_source, range_budget=per_range)
''')
rep('''    async def run_open(req: OpenRequest) -> Opened:
        if req.handle in state.web_pages:
''', '''    m = nav_input.student_map
    titles = {c.handle: c.title for c in m.courses}
    date_outcomes = [DateOutcome(request=r, lectures=m.lectures_between(r.date_from, r.date_to, r.within), course_titles=titles)
                     for r in dates]
    # 範囲の材料(C{n}/L{a}-{b}・…/cards・講義のあるby_date)は、このターンの残り予算をこの周の操作で等分する
    range_opens = [r for r in opens if (p := parse_handle(r.handle)) and p.kind in ("multi_lecture_cards", "lecture_range")]
    n_range = len(range_opens) + sum(1 for o in date_outcomes if o.lectures)
    per_range = state.range_budget_left // n_range if n_range else 0

    async def attach_overview(o: DateOutcome) -> None:
        try:
            ov = await build_range_overview(o.lectures, m, tools.source, per_range)
        except Exception as e:
            print(f"⚠️ [chat] by_date overview failed ({o.request.label()}): {e}")
            return
        o.overview_body, o.overview_tokens, o.overview_note = ov.body, ov.tokens, ov.note()

    async def run_open(req: OpenRequest) -> Opened:
        if req.handle in state.web_pages:
''')
rep('''    find_outcomes, web_results, *opened = await asyncio.gather(
        timed("find_ms", run_finds()) if finds else run_finds(),
        timed("web_ms", asyncio.gather(*[run_web(r) for r in web_finds])) if web_finds else asyncio.gather(),
        *[timed("open_ms", run_open(r)) for r in opens])
''', '''    find_outcomes, web_results, _dates, *opened = await asyncio.gather(
        timed("find_ms", run_finds()) if finds else run_finds(),
        timed("web_ms", asyncio.gather(*[run_web(r) for r in web_finds])) if web_finds else asyncio.gather(),
        asyncio.gather(*[attach_overview(o) for o in date_outcomes if o.lectures]),
        *[timed("open_ms", run_open(r)) for r in opens])
    state.range_budget_left = max(0, state.range_budget_left - sum(op.range_tokens for op in opened)
                                  - sum(o.overview_tokens for o in date_outcomes))
''')
rep('''    m = nav_input.student_map
    titles = {c.handle: c.title for c in m.courses}
    date_outcomes = [DateOutcome(request=r, lectures=m.lectures_between(r.date_from, r.date_to, r.within), course_titles=titles)
                     for r in dates]

    for op in opened:
''', '''    for op in opened:
''')

# 8. 探索役に残り予算を見せる
rep('''    nxt.append("Searches already run (do not repeat them): "
''', '''    nxt.append(f"Budget left for lecture-range overviews (by_date, C{{n}}/L{{a}}-{{b}}): about {state.range_budget_left:,} of "
               f"{RANGE_MATERIAL_BUDGET:,} tokens (a smaller budget gives shorter overviews)")
    nxt.append("Searches already run (do not repeat them): "
''')

P.write_text(s, encoding="utf-8")
print("patched:", P)
