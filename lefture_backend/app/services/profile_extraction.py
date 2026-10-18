# app/services/profile_extraction.py
"""
自分像プロフィール(ロードマップ「9. 自分像プロフィール」)の観察役・まとめ役・表紙の書き直し。
設計の正本は docs/chatbot_context_and_retrieval_roadmap.md の9章。

ここには DB に触らない部分(入力の組み立て・LLMの呼び出し・出力の検証・適用の計画)だけを置く。
保存・patrolからの呼び出し・本人の操作のAPIは後で足す。評価
(contents_generation/test_codes/profile_extraction_test/run_eval.py)もここの関数をそのまま使う。

- 観察役: 1スレッドの差分を読み、観察(4層)を書く。一般化はしない。惹かれた点(hook)が分からなければ空
- まとめ役: 新しい観察 + 惹かれた点が近い過去の観察 + 既存の項目などから、2層の項目・覚え書き・仮説を更新する
- 表紙: 今の表紙を土台に、2層の有効な項目で書き足して1層(自己紹介 / 興味 / 将来の夢)を書く。消すのは、前回の後に
  外れた項目に基づく文と、新しい項目で変わったことだけ。本人が書いた欄は案にとどめる

LLMの出力は必ずコード側で検証し、設計の「上げるルール」のうち機械的に守れるもの
(センシティブ・ブロックした分野・本人の文の保護・明言がない項目の下限)はここで強制する。
LLMの判断に任せる部分(根拠が十分か、どの観察を束ねるか)はプロンプトに書く。
"""

import math
import re
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any, Optional, Sequence

from app.services.helpers.helpers import _load_prompt
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM

# 2026-10-03の評価(contents_generation/test_codes/profile_extraction_test、全役割Lunaで3構成×3回)で決定。
# 観察役は推論なしでも質が落ちず(間違って上げた・観察の一般化とも0)、原価が最も安かった。
# まとめ役はmediumで十分。highは原価が上がるだけで良くならなかった。速さは要らない処理なので、
# Gemini 3.5 Flash-Lite(medium、約5倍の原価)ではなくLunaを使う。
# 2026-10-17: 観察役はlowに変更。本人の実際のチャット23スレッドを流し直すと(各2回)、推論なしは宿題の長いスレッドに
# 埋もれた本人のプロジェクト(ワークショップの企画)を2回に1回落とし、lowは毎回拾った。lowは別々の授業にまたがる
# 考え方の特徴も拾い、まとめ役がそれを確かめたい仮説に回す。原価は推論なしと同程度。
# Haiku 5.5も試したが、観察を2〜3倍書き(本人に見える観察メモが増える)、原価も3〜4倍だったので採らなかった。
OBSERVER_MODEL = "gpt-6-luna"
OBSERVER_REASONING: Optional[str] = "low"
CONSOLIDATOR_MODEL = "gpt-6-luna"
CONSOLIDATOR_REASONING: Optional[str] = "medium"
COVER_MODEL = "gpt-6-luna"
COVER_REASONING: Optional[str] = "low"

# 観察役に渡すAIの返答は文脈用なので短く切る。惹かれた点や但し書きは本人の発言にあるため、
# 本人の発言は原文のまま全部渡す(要約は渡さない。要約はこの種のニュアンスを落としやすい)
ASSISTANT_SNIPPET_CHARS = 400

CONTEXTS = ("casual", "lecture_review", "exam_prep", "consult", "onboarding")
CERTAINTIES = ("stated", "strong_implicit", "inferred")
INITIATIVES = ("user", "ai")
REACTIONS = ("strong", "moderate", "mild", "neutral")
KIND_HINTS = ("trait", "future", "record", "answer_style", "situation")
SENSITIVE_AREAS = ("religion", "health", "sexuality", "politics", "ethnicity")
ITEM_KINDS = ("trait", "record")
MEMO_KINDS = ("answer_style", "situation")
COVER_FIELDS = ("bio", "interests", "future_goals")

# 明言(stated)の根拠が1つもない項目は、別々のスレッドがこの数以上ないと作らない。
# 「どれだけ集まれば十分か」(目安3、弱ければ4〜5、ほぼ明言なら2)はまとめ役の判断に任せ、
# コードはその下限だけを守る。
MIN_THREADS_WITHOUT_STATEMENT = 2

# 「違う」と言われた項目と、新しく作ろうとした項目の文の近さ(コサイン類似度)がこれ以上なら、
# まとめ役が見落としたとみなして作らない(本人の明言が、違うと言われた日より後にある場合を除く)。
# 値は評価で調整する。評価ではここで落とした件と類似度をすべて記録する。
REJECTED_GUARD_SIMILARITY = 0.90

_LANGUAGE_NAMES = {
    "ja": "Japanese", "en": "English", "zh": "Chinese", "ko": "Korean",
    "es": "Spanish", "fr": "French", "de": "German", "pt": "Portuguese",
}

_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class ProfileValidationError(Exception):
    pass


# =========================================================
# 🧩 データ(本番ではそれぞれテーブルの行になる)
# =========================================================

@dataclass
class ObservedRound:
    """観察役に渡す1往復。dateは本人の発言の日付(「昨日」を解決するため)。"""
    number: int
    date: str
    user: str
    assistant: str


@dataclass
class Observation:
    id: str
    thread_id: str
    observed_at: str
    note: str
    topic: str
    hook: Optional[str]
    caveat: Optional[str]
    reaction: str
    initiative: str
    certainty: str
    context: str
    kind_hint: str
    sensitive: str  # "none" または SENSITIVE_AREAS のどれか
    rounds: list[int]
    quote: Optional[str] = None
    occurred_at: Optional[str] = None
    ends_at: Optional[str] = None
    # open: まだ項目に使われていない / used: 項目の根拠になった / discounted: 根拠の項目が「違う」と言われた
    status: str = "open"
    embedding: Optional[list[float]] = None

    def embedding_input(self) -> str:
        """
        束ねる鍵は「話題」ではなく「惹かれた点」なので、hookだけを埋め込む(hookが無ければnote)。
        titleに話題を入れると、話題が同じもの同士が近くなってしまうので入れない。
        """
        return f"title: none | text: {self.hook or self.note}"


@dataclass
class Category:
    id: str
    name: str
    description: str
    kind: str  # trait | record
    parent_id: Optional[str] = None


@dataclass
class Item:
    id: str
    category_id: str
    kind: str  # trait | record
    content: str
    origin: str  # ai | user
    # active | pending_confirm(センシティブの確認待ち) | rejected(違う) | archived | orphaned(根拠が全部消えた)
    status: str
    sensitive: str = "none"
    evidence: list[str] = field(default_factory=list)
    first_seen_at: Optional[str] = None
    last_seen_at: Optional[str] = None
    occurred_at: Optional[str] = None
    versions: list[dict] = field(default_factory=list)
    rejected_at: Optional[str] = None
    rejected_reason: Optional[str] = None
    embedding: Optional[list[float]] = None


@dataclass
class Memo:
    id: str
    kind: str  # answer_style | situation
    content: str
    expires_at: Optional[str] = None
    evidence: list[str] = field(default_factory=list)
    created_at: Optional[str] = None

    def is_active(self, today: str) -> bool:
        return self.expires_at is None or self.expires_at >= today


@dataclass
class Hypothesis:
    id: str
    content: str
    status: str = "open"  # open | confirmed | refuted | expired
    evidence: list[str] = field(default_factory=list)
    created_at: Optional[str] = None


def _json_options(model: str, schema: dict, reasoning_effort: Optional[str], max_output_tokens: int) -> LLMOptions:
    if model == "gpt-6-luna":
        # gpt-6-lunaはtemperatureの既定値(1)以外を受け付けない。推論のトークンも出力の上限に含まれる
        return LLMOptions(output_type="json", json_schema=schema, temperature=1.0,
                          max_completion_tokens=max_output_tokens, reasoning_effort=reasoning_effort)
    return LLMOptions(output_type="json", json_schema=schema, max_tokens=max_output_tokens,
                      reasoning_effort=reasoning_effort)


def output_language_name(language: str) -> str:
    return _LANGUAGE_NAMES.get(language, language)


def _clean(s: Any) -> str:
    return s.strip() if isinstance(s, str) else ""


def _valid_date(s: Any) -> Optional[str]:
    s = _clean(s)
    return s if _DATE_RE.match(s) else None


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


# =========================================================
# 👀 観察役
# =========================================================

OBSERVER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "observations": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "note": {"type": "string"},
                    "topic": {"type": "string"},
                    "hook": {"type": "string"},
                    "caveat": {"type": "string"},
                    "quote": {"type": "string"},
                    "reaction": {"type": "string", "enum": list(REACTIONS)},
                    "initiative": {"type": "string", "enum": list(INITIATIVES)},
                    "certainty": {"type": "string", "enum": list(CERTAINTIES)},
                    "context": {"type": "string", "enum": list(CONTEXTS)},
                    "kind_hint": {"type": "string", "enum": list(KIND_HINTS)},
                    "sensitive": {"type": "string", "enum": ["none", *SENSITIVE_AREAS]},
                    "occurred_at": {"type": "string"},
                    "ends_at": {"type": "string"},
                    "rounds": {"type": "array", "items": {"type": "integer"}},
                },
                "required": [
                    "note", "topic", "hook", "caveat", "quote", "reaction", "initiative", "certainty",
                    "context", "kind_hint", "sensitive", "occurred_at", "ends_at", "rounds",
                ],
            },
        },
        "hypothesis_updates": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "hypothesis": {"type": "string"},
                    # unanswered: 話題には触れたが本人の言葉で答えが出ていない(検証で捨てて、仮説は開いたまま)。
                    # 2択しかないと、答えが出ていなくてもどちらかを選んで閉じてしまっていた(2026-10-17、実データの流し直し)
                    "status": {"type": "string", "enum": ["confirmed", "refuted", "unanswered"]},
                    "rounds": {"type": "array", "items": {"type": "integer"}},
                    "note": {"type": "string"},
                },
                "required": ["hypothesis", "status", "rounds", "note"],
            },
        },
    },
    "required": ["observations", "hypothesis_updates"],
}


@dataclass
class ObserverResult:
    observations: list[dict]          # Observationの材料(id・thread_id・embeddingは呼び出し側で付ける)
    hypothesis_updates: list[dict]    # {"hypothesis_id", "status", "rounds", "note"}
    dropped: list[dict]               # コードが落としたもの(評価・ログ用)


def build_observer_messages(
    rounds: list[ObservedRound],
    language: str,
    category_names: list[str],
    open_hypotheses: list[Hypothesis],
    blocked_areas: list[str],
) -> tuple[list[Message], dict[str, str]]:
    """(messages, 仮説の短い呼び名 → id) を返す。"""
    system = _load_prompt("profile_observer_prompt.txt").replace(
        "${OUTPUT_LANGUAGE}", output_language_name(language)
    )
    hyp_refs = {f"H{i}": h.id for i, h in enumerate(open_hypotheses, start=1)}
    hyp_text = "\n".join(f"- {ref}: {h.content}" for ref, h in zip(hyp_refs, open_hypotheses)) or "(none)"
    cats_text = "\n".join(f"- {n}" for n in category_names) or "(none yet)"
    blocked_text = ", ".join(blocked_areas) if blocked_areas else "(none)"

    rounds_text = "\n\n".join(
        f"[round {r.number} · {r.date}] Student: {r.user}\n"
        f"[round {r.number} · {r.date}] Assistant: {_snippet(r.assistant)}"
        for r in rounds
    )
    user_content = (
        f"<blocked_areas>\n{blocked_text}\n</blocked_areas>\n\n"
        f"<existing_profile_categories>\n{cats_text}\n</existing_profile_categories>\n\n"
        f"<open_hypotheses>\n{hyp_text}\n</open_hypotheses>\n\n"
        f"<thread>\n{rounds_text}\n</thread>"
    )
    return [Message(role="system", content=system), Message(role="user", content=user_content)], hyp_refs


def _snippet(text: str) -> str:
    text = text.strip()
    return text if len(text) <= ASSISTANT_SNIPPET_CHARS else text[:ASSISTANT_SNIPPET_CHARS] + "…"


def validate_observer_output(
    raw: Any,
    rounds: list[ObservedRound],
    hyp_refs: dict[str, str],
    blocked_areas: list[str],
) -> ObserverResult:
    if not isinstance(raw, dict) or not isinstance(raw.get("observations"), list):
        raise ProfileValidationError("output is not the expected object")

    round_numbers = {r.number for r in rounds}
    round_dates = {r.number: r.date for r in rounds}
    dropped: list[dict] = []
    observations: list[dict] = []

    for ob in raw["observations"]:
        note = _clean(ob.get("note"))
        if not note:
            raise ProfileValidationError(f"observation without note: {ob!r}")
        obs_rounds = sorted({n for n in ob.get("rounds") or [] if isinstance(n, int)})
        if not obs_rounds or not set(obs_rounds) <= round_numbers:
            raise ProfileValidationError(f"observation rounds {obs_rounds} outside this thread {sorted(round_numbers)}")
        for key, allowed in (("reaction", REACTIONS), ("initiative", INITIATIVES), ("certainty", CERTAINTIES),
                             ("context", CONTEXTS), ("kind_hint", KIND_HINTS)):
            if ob.get(key) not in allowed:
                raise ProfileValidationError(f"observation {key}={ob.get(key)!r} is not one of {allowed}")
        sensitive = ob.get("sensitive") if ob.get("sensitive") in SENSITIVE_AREAS else "none"

        # ブロックした分野は、プロンプトで書かないよう指示したうえで、コードでも落とす(二重の防御)
        if sensitive in blocked_areas:
            dropped.append({"reason": "blocked_area", "sensitive": sensitive})
            continue

        observations.append({
            "note": note,
            "topic": _clean(ob.get("topic")),
            "hook": _clean(ob.get("hook")) or None,
            "caveat": _clean(ob.get("caveat")) or None,
            "quote": _clean(ob.get("quote")) or None,
            "reaction": ob["reaction"],
            "initiative": ob["initiative"],
            "certainty": ob["certainty"],
            "context": ob["context"],
            "kind_hint": ob["kind_hint"],
            "sensitive": sensitive,
            "occurred_at": _valid_date(ob.get("occurred_at")) or round_dates[obs_rounds[0]],
            "ends_at": _valid_date(ob.get("ends_at")),
            "rounds": obs_rounds,
            "observed_at": round_dates[obs_rounds[-1]],
        })

    updates = []
    for up in raw.get("hypothesis_updates") or []:
        ref = _clean(up.get("hypothesis"))
        if ref not in hyp_refs:
            dropped.append({"reason": "unknown_hypothesis", "ref": ref})
            continue
        if up.get("status") not in ("confirmed", "refuted"):
            continue
        updates.append({
            "hypothesis_id": hyp_refs[ref],
            "status": up["status"],
            "rounds": sorted({n for n in up.get("rounds") or [] if n in round_numbers}),
            "note": _clean(up.get("note")),
        })

    return ObserverResult(observations=observations, hypothesis_updates=updates, dropped=dropped)


async def observe_thread(
    llm: UnifiedLLM,
    rounds: list[ObservedRound],
    language: str,
    category_names: list[str],
    open_hypotheses: list[Hypothesis],
    blocked_areas: list[str],
    model: str = OBSERVER_MODEL,
    reasoning_effort: Optional[str] = OBSERVER_REASONING,
) -> ObserverResult:
    messages, hyp_refs = build_observer_messages(rounds, language, category_names, open_hypotheses, blocked_areas)
    options = _json_options(model, OBSERVER_SCHEMA, reasoning_effort, 8000)
    last_error: Optional[Exception] = None
    for attempt in range(2):
        result = await llm.generate(model, messages, options)
        try:
            return validate_observer_output(result.output_json, rounds, hyp_refs, blocked_areas)
        except ProfileValidationError as e:
            print(f"⚠️ [profile-observer] invalid output (attempt {attempt + 1}): {e}")
            last_error = e
    raise last_error


# =========================================================
# 🧱 まとめ役
# =========================================================

CONSOLIDATOR_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "new_categories": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "ref": {"type": "string"},
                    "name": {"type": "string"},
                    "description": {"type": "string"},
                    "kind": {"type": "string", "enum": list(ITEM_KINDS)},
                    "parent": {"type": "string"},
                },
                "required": ["ref", "name", "description", "kind", "parent"],
            },
        },
        "item_ops": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "op": {"type": "string", "enum": ["create", "update", "add_evidence", "archive"]},
                    "item": {"type": "string"},
                    "category": {"type": "string"},
                    "kind": {"type": "string", "enum": list(ITEM_KINDS)},
                    "content": {"type": "string"},
                    "occurred_at": {"type": "string"},
                    "sensitive": {"type": "string", "enum": ["none", *SENSITIVE_AREAS]},
                    "evidence": {"type": "array", "items": {"type": "string"}},
                    "reason": {"type": "string"},
                },
                "required": ["op", "item", "category", "kind", "content", "occurred_at", "sensitive", "evidence", "reason"],
            },
        },
        "memo_ops": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "op": {"type": "string", "enum": ["create", "update", "remove"]},
                    "memo": {"type": "string"},
                    "kind": {"type": "string", "enum": list(MEMO_KINDS)},
                    "content": {"type": "string"},
                    "expires_at": {"type": "string"},
                    "evidence": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["op", "memo", "kind", "content", "expires_at", "evidence"],
            },
        },
        "hypothesis_ops": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "op": {"type": "string", "enum": ["create", "close"]},
                    "hypothesis": {"type": "string"},
                    "content": {"type": "string"},
                    "status": {"type": "string", "enum": ["confirmed", "refuted", "expired", "open"]},
                    "evidence": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["op", "hypothesis", "content", "status", "evidence"],
            },
        },
    },
    "required": ["new_categories", "item_ops", "memo_ops", "hypothesis_ops"],
}


@dataclass
class ConsolidationInput:
    """まとめ役に渡すもの。どれを渡すか(近い順に何件まで等)は呼び出し側が決める。"""
    today: str
    language: str
    new_observations: list[Observation]
    related_observations: list[Observation]
    categories: list[Category]
    items: list[Item]                 # active / pending_confirm(本人の文も含む)
    rejected_items: list[Item]
    memos: list[Memo]                 # 期限切れは除いておく
    hypotheses: list[Hypothesis]      # open のもの
    blocked_areas: list[str]


@dataclass
class ConsolidationPlan:
    new_categories: list[dict]   # {"ref", "name", "description", "kind", "parent_id" or "parent_ref"}
    item_creates: list[dict]     # {"category_id" or "category_ref", "kind", "content", "evidence", "sensitive", "status", "occurred_at"}
    item_updates: list[dict]     # {"item_id", "content"(Noneなら文は変えない), "add_evidence"}
    item_archives: list[str]
    memo_creates: list[dict]
    memo_updates: list[dict]
    memo_removes: list[str]
    hypothesis_creates: list[dict]
    hypothesis_closes: list[dict]
    dropped: list[dict]


@dataclass
class _Refs:
    obs: dict[str, Observation]
    items: dict[str, Item]
    rejected: dict[str, Item]
    cats: dict[str, Category]
    memos: dict[str, Memo]
    hyps: dict[str, Hypothesis]


def _make_refs(inp: ConsolidationInput) -> _Refs:
    all_obs = inp.new_observations + inp.related_observations
    return _Refs(
        obs={f"O{i}": o for i, o in enumerate(all_obs, start=1)},
        items={f"I{i}": it for i, it in enumerate(inp.items, start=1)},
        rejected={f"R{i}": it for i, it in enumerate(inp.rejected_items, start=1)},
        cats={f"C{i}": c for i, c in enumerate(inp.categories, start=1)},
        memos={f"M{i}": m for i, m in enumerate(inp.memos, start=1)},
        hyps={f"H{i}": h for i, h in enumerate(inp.hypotheses, start=1)},
    )


def _obs_line(ref: str, o: Observation, thread_label: str) -> str:
    parts = [
        f"{ref} [{o.observed_at} · thread {thread_label} · {o.context} · {o.certainty} · initiative={o.initiative} · reaction={o.reaction}"
        f" · kind_hint={o.kind_hint}" + (f" · sensitive={o.sensitive}" if o.sensitive != "none" else "") + "]",
        f"   note: {o.note}",
        f"   topic: {o.topic}" if o.topic else "",
        f"   hook: {o.hook if o.hook else '(unknown)'}",
        f"   caveat: {o.caveat}" if o.caveat else "",
        f"   quote: \"{o.quote}\"" if o.quote else "",
        f"   occurred_at: {o.occurred_at}" if o.kind_hint == "record" and o.occurred_at else "",
        f"   ends_at: {o.ends_at}" if o.ends_at else "",
    ]
    return "\n".join(p for p in parts if p)


def build_consolidator_messages(inp: ConsolidationInput) -> tuple[list[Message], _Refs]:
    refs = _make_refs(inp)
    system = _load_prompt("profile_consolidator_prompt.txt").replace(
        "${OUTPUT_LANGUAGE}", output_language_name(inp.language)
    )
    cat_ref_by_id = {c.id: ref for ref, c in refs.cats.items()}
    obs_ref_by_id = {o.id: ref for ref, o in refs.obs.items()}
    n_new = len(inp.new_observations)

    def cat_line(ref: str, c: Category) -> str:
        parent = f" (child of {cat_ref_by_id[c.parent_id]})" if c.parent_id in cat_ref_by_id else ""
        return f"- {ref} [{c.kind}] {c.name}{parent}: {c.description}"

    def item_line(ref: str, it: Item) -> str:
        cat = cat_ref_by_id.get(it.category_id, "?")
        ev = ", ".join(obs_ref_by_id.get(e, "older") for e in it.evidence) or "-"
        flags = [it.kind, f"origin={it.origin}"]
        if it.status == "pending_confirm":
            flags.append("pending_confirm")
        if it.occurred_at and it.kind == "record":
            flags.append(f"occurred_at={it.occurred_at}")
        return f"- {ref} in {cat} [{' · '.join(flags)}] {it.content}  (evidence: {ev}; last seen {it.last_seen_at})"

    obs_items = list(refs.obs.items())
    # スレッドはIDではなく短い呼び名で示す(「別の会話かどうか」が分かれば十分で、UUIDはトークンの無駄)
    thread_labels: dict[str, str] = {}
    for _, o in obs_items:
        thread_labels.setdefault(o.thread_id, f"T{len(thread_labels) + 1}")
    new_text = "\n".join(_obs_line(r, o, thread_labels[o.thread_id]) for r, o in obs_items[:n_new]) or "(none)"
    related_text = "\n".join(_obs_line(r, o, thread_labels[o.thread_id]) for r, o in obs_items[n_new:]) or "(none)"
    cats_text = "\n".join(cat_line(r, c) for r, c in refs.cats.items()) or "(none yet)"
    items_text = "\n".join(item_line(r, it) for r, it in refs.items.items()) or "(none yet)"
    rejected_text = "\n".join(
        f"- {r} {it.content}  (rejected on {it.rejected_at}" + (f"; student said: \"{it.rejected_reason}\"" if it.rejected_reason else "") + ")"
        for r, it in refs.rejected.items()
    ) or "(none)"
    memos_text = "\n".join(
        f"- {r} [{m.kind}] {m.content}" + (f" (until {m.expires_at})" if m.expires_at else "")
        for r, m in refs.memos.items()
    ) or "(none)"
    hyps_text = "\n".join(f"- {r} {h.content}" for r, h in refs.hyps.items()) or "(none)"
    blocked_text = ", ".join(inp.blocked_areas) if inp.blocked_areas else "(none)"

    user_content = (
        f"<today>{inp.today}</today>\n\n"
        f"<blocked_areas>\n{blocked_text}\n</blocked_areas>\n\n"
        f"<new_observations>\n{new_text}\n</new_observations>\n\n"
        f"<related_past_observations>\n{related_text}\n</related_past_observations>\n\n"
        f"<categories>\n{cats_text}\n</categories>\n\n"
        f"<items>\n{items_text}\n</items>\n\n"
        f"<rejected_items>\n{rejected_text}\n</rejected_items>\n\n"
        f"<memos>\n{memos_text}\n</memos>\n\n"
        f"<open_hypotheses>\n{hyps_text}\n</open_hypotheses>"
    )
    return [Message(role="system", content=system), Message(role="user", content=user_content)], refs


def validate_consolidator_output(raw: Any, inp: ConsolidationInput, refs: _Refs) -> ConsolidationPlan:
    """
    まとめ役の出力を検証し、適用の計画に変える。形が壊れているときだけ例外(やり直し)にし、
    ルール違反の操作は1つずつ落として dropped に理由を残す(他の操作は生かす)。
    """
    for key in ("new_categories", "item_ops", "memo_ops", "hypothesis_ops"):
        if not isinstance(raw, dict) or not isinstance(raw.get(key), list):
            raise ProfileValidationError(f"output is missing {key}")

    dropped: list[dict] = []

    def drop(op: dict, reason: str) -> None:
        dropped.append({"op": op, "reason": reason})

    # ---- カテゴリ ----
    new_categories: list[dict] = []
    new_cat_refs: dict[str, dict] = {}
    for c in raw["new_categories"]:
        ref, name = _clean(c.get("ref")), _clean(c.get("name"))
        if not ref or not name or ref in refs.cats or ref in new_cat_refs or c.get("kind") not in ITEM_KINDS:
            drop(c, "invalid_category")
            continue
        parent = _clean(c.get("parent"))
        entry = {"ref": ref, "name": name, "description": _clean(c.get("description")), "kind": c["kind"],
                 "parent_id": None, "parent_ref": None}
        if parent:
            if parent in refs.cats:
                # 親子は2段まで: 親がすでに子なら付けられない
                if refs.cats[parent].parent_id is not None:
                    drop(c, "too_deep")
                    continue
                entry["parent_id"] = refs.cats[parent].id
            elif parent in new_cat_refs and new_cat_refs[parent]["parent_id"] is None and new_cat_refs[parent]["parent_ref"] is None:
                entry["parent_ref"] = parent
            else:
                drop(c, "unknown_or_too_deep_parent")
                continue
        new_cat_refs[ref] = entry
        new_categories.append(entry)

    def resolve_obs(ev_refs: list) -> Optional[list[Observation]]:
        out = []
        for r in ev_refs or []:
            if r not in refs.obs:
                return None
            out.append(refs.obs[r])
        return out

    # ---- 項目 ----
    item_creates: list[dict] = []
    item_updates: list[dict] = []
    item_archives: list[str] = []
    for op in raw["item_ops"]:
        kind = op.get("op")
        evidence = resolve_obs(op.get("evidence"))
        if evidence is None:
            drop(op, "unknown_evidence")
            continue
        content = _clean(op.get("content"))

        if kind == "create":
            cat = _clean(op.get("category"))
            if cat not in refs.cats and cat not in new_cat_refs:
                drop(op, "unknown_category")
                continue
            if not content or op.get("kind") not in ITEM_KINDS or not evidence:
                drop(op, "missing_content_kind_or_evidence")
                continue
            if any(o.status == "discounted" for o in evidence):
                drop(op, "discounted_evidence")
                continue
            sensitive = op.get("sensitive") if op.get("sensitive") in SENSITIVE_AREAS else "none"
            sensitive = _strictest_sensitive(sensitive, evidence)
            stated = any(o.certainty == "stated" for o in evidence)
            if sensitive != "none":
                if sensitive in inp.blocked_areas:
                    drop(op, "blocked_area")
                    continue
                # センシティブは推測からは上げない。本人の明言だけ、確認待ちとして作る
                if not any(o.certainty == "stated" and o.sensitive == sensitive for o in evidence):
                    drop(op, "sensitive_without_statement")
                    continue
            if op["kind"] == "trait" and not stated:
                threads = {o.thread_id for o in evidence}
                if len(threads) < MIN_THREADS_WITHOUT_STATEMENT:
                    drop(op, f"not_enough_threads_without_statement ({len(threads)})")
                    continue
            entry = {
                "kind": op["kind"],
                "content": content,
                "evidence": [o.id for o in evidence],
                "sensitive": sensitive,
                "status": "pending_confirm" if sensitive != "none" else "active",
                "occurred_at": _valid_date(op.get("occurred_at")) if op["kind"] == "record" else None,
                "reason": _clean(op.get("reason")),
            }
            if cat in refs.cats:
                entry["category_id"] = refs.cats[cat].id
            else:
                entry["category_ref"] = cat
            item_creates.append(entry)

        elif kind in ("update", "add_evidence"):
            ref = _clean(op.get("item"))
            if ref not in refs.items:
                drop(op, "unknown_item")
                continue
            item = refs.items[ref]
            new_content: Optional[str] = content if kind == "update" and content and content != item.content else None
            if new_content is not None and item.origin == "user":
                # 本人が書いた・直した文はAIが書き換えない。根拠の追加だけ生かす
                drop(op, "user_authored_content_kept")
                new_content = None
            add = [o.id for o in evidence if o.id not in item.evidence and o.status != "discounted"]
            if new_content is None and not add:
                continue
            item_updates.append({"item_id": item.id, "content": new_content, "add_evidence": add,
                                 "reason": _clean(op.get("reason"))})

        elif kind == "archive":
            ref = _clean(op.get("item"))
            if ref not in refs.items:
                drop(op, "unknown_item")
                continue
            if refs.items[ref].origin == "user":
                drop(op, "user_authored_item_kept")
                continue
            item_archives.append(refs.items[ref].id)
        else:
            drop(op, "unknown_op")

    # ---- 覚え書き ----
    memo_creates: list[dict] = []
    memo_updates: list[dict] = []
    memo_removes: list[str] = []
    for op in raw["memo_ops"]:
        kind = op.get("op")
        evidence = resolve_obs(op.get("evidence"))
        if evidence is None:
            drop(op, "unknown_evidence")
            continue
        expires = _valid_date(op.get("expires_at"))
        content = _clean(op.get("content"))
        if kind == "create":
            if not content or op.get("kind") not in MEMO_KINDS:
                drop(op, "invalid_memo")
                continue
            if any(o.sensitive != "none" for o in evidence):
                drop(op, "sensitive_memo")
                continue
            if op["kind"] == "situation" and not expires:
                # 今の状況には必ず期限をつける。分からなければ今日から30日
                expires = (date.fromisoformat(inp.today) + timedelta(days=30)).isoformat()
            memo_creates.append({"kind": op["kind"], "content": content,
                                 "expires_at": expires if op["kind"] == "situation" else None,
                                 "evidence": [o.id for o in evidence]})
        elif kind == "update":
            ref = _clean(op.get("memo"))
            if ref not in refs.memos or not content:
                drop(op, "unknown_memo")
                continue
            m = refs.memos[ref]
            memo_updates.append({"memo_id": m.id, "content": content,
                                 "expires_at": expires if m.kind == "situation" else None,
                                 "add_evidence": [o.id for o in evidence if o.id not in m.evidence]})
        elif kind == "remove":
            ref = _clean(op.get("memo"))
            if ref not in refs.memos:
                drop(op, "unknown_memo")
                continue
            memo_removes.append(refs.memos[ref].id)
        else:
            drop(op, "unknown_op")

    # ---- 仮説 ----
    hypothesis_creates: list[dict] = []
    hypothesis_closes: list[dict] = []
    for op in raw["hypothesis_ops"]:
        kind = op.get("op")
        evidence = resolve_obs(op.get("evidence"))
        if evidence is None:
            drop(op, "unknown_evidence")
            continue
        if kind == "create":
            content = _clean(op.get("content"))
            if not content:
                drop(op, "invalid_hypothesis")
                continue
            if any(o.sensitive != "none" for o in evidence):
                drop(op, "sensitive_hypothesis")
                continue
            hypothesis_creates.append({"content": content, "evidence": [o.id for o in evidence]})
        elif kind == "close":
            ref = _clean(op.get("hypothesis"))
            status = op.get("status")
            if ref not in refs.hyps or status not in ("confirmed", "refuted", "expired"):
                drop(op, "unknown_hypothesis_or_status")
                continue
            hypothesis_closes.append({"hypothesis_id": refs.hyps[ref].id, "status": status})
        else:
            drop(op, "unknown_op")

    return ConsolidationPlan(
        new_categories=new_categories, item_creates=item_creates, item_updates=item_updates,
        item_archives=item_archives, memo_creates=memo_creates, memo_updates=memo_updates,
        memo_removes=memo_removes, hypothesis_creates=hypothesis_creates,
        hypothesis_closes=hypothesis_closes, dropped=dropped,
    )


def _strictest_sensitive(declared: str, evidence: list[Observation]) -> str:
    """まとめ役が付け忘れても、根拠の観察がセンシティブならそれを引き継ぐ。"""
    if declared != "none":
        return declared
    for o in evidence:
        if o.sensitive != "none":
            return o.sensitive
    return "none"


async def guard_against_rejected(
    plan: ConsolidationPlan,
    rejected_items: list[Item],
    observations_by_id: dict[str, Observation],
    embed_texts,
) -> list[dict]:
    """
    「違う」と言われた項目と同じ意味の項目を、まとめ役が作ろうとしていないかを埋め込みで確かめ、
    近すぎるものは計画から外す。ただし、違うと言われた日より後の本人の明言が根拠にあれば通す
    (興味は変わるので、本人が言えば一生ふさがない)。
    embed_texts: list[str] -> list[list[float]](文書側の形式で埋め込む関数)。
    戻り値は確かめた全件の記録(評価で閾値を調整するため)。
    """
    targets = [r for r in rejected_items if r.embedding is not None]
    if not targets or not plan.item_creates:
        return []
    vectors = await embed_texts([f"title: none | text: {c['content']}" for c in plan.item_creates])
    checks: list[dict] = []
    kept = []
    for create, vec in zip(plan.item_creates, vectors):
        best = max(targets, key=lambda r: cosine(vec, r.embedding))
        sim = cosine(vec, best.embedding)
        restated = any(
            observations_by_id[e].certainty == "stated" and observations_by_id[e].observed_at > (best.rejected_at or "")
            for e in create["evidence"] if e in observations_by_id
        )
        blocked = sim >= REJECTED_GUARD_SIMILARITY and not restated
        checks.append({"content": create["content"], "nearest_rejected": best.content,
                       "similarity": round(sim, 4), "restated_after_rejection": restated, "blocked": blocked})
        if blocked:
            plan.dropped.append({"op": create, "reason": f"too_close_to_rejected ({sim:.3f})"})
        else:
            kept.append(create)
    plan.item_creates = kept
    return checks


async def consolidate(llm: UnifiedLLM, inp: ConsolidationInput, model: str = CONSOLIDATOR_MODEL,
                      reasoning_effort: Optional[str] = CONSOLIDATOR_REASONING) -> ConsolidationPlan:
    messages, refs = build_consolidator_messages(inp)
    options = _json_options(model, CONSOLIDATOR_SCHEMA, reasoning_effort, 24000)
    last_error: Optional[Exception] = None
    for attempt in range(2):
        result = await llm.generate(model, messages, options)
        try:
            return validate_consolidator_output(result.output_json, inp, refs)
        except ProfileValidationError as e:
            print(f"⚠️ [profile-consolidator] invalid output (attempt {attempt + 1}): {e}")
            last_error = e
    raise last_error


# =========================================================
# 📇 表紙(1層)
# =========================================================

COVER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "fields": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "field": {"type": "string", "enum": list(COVER_FIELDS)},
                    "action": {"type": "string", "enum": ["keep", "write"]},
                    "text": {"type": "string"},
                    "based_on": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["field", "action", "text", "based_on"],
            },
        },
    },
    "required": ["fields"],
}


@dataclass
class CoverPlan:
    applied: dict[str, str]     # 自動で書き込む欄(空欄 / AIが書いたまま)
    proposals: dict[str, str]   # 本人が書いた欄への書き直し案
    dropped: list[dict]


def build_cover_messages(
    cover: dict[str, dict],
    items: list[Item],
    categories: list[Category],
    language: str,
    removed_items: Sequence[Item] = (),
) -> tuple[list[Message], dict[str, Item]]:
    """
    cover: {"bio": {"text", "origin"}, ...}。items は active のものだけを渡すこと。
    removed_items: 前回表紙を書いた後に外れた項目(違う / もう当てはまらない / 根拠の会話が消えた)。
    表紙は今の文を土台に書き足すので、消してよい理由として渡す。
    戻り値の呼び名は I(有効な項目)と R(外れた項目)の両方を含む。
    """
    system = _load_prompt("profile_cover_prompt.txt").replace("${OUTPUT_LANGUAGE}", output_language_name(language))
    cat_by_id = {c.id: c for c in categories}
    item_refs = {f"I{i}": it for i, it in enumerate(items, start=1)}
    removed_refs = {f"R{i}": it for i, it in enumerate(removed_items, start=1)}

    def cat_path(cid: str) -> str:
        c = cat_by_id.get(cid)
        if c is None:
            return "?"
        parent = cat_by_id.get(c.parent_id) if c.parent_id else None
        return f"{parent.name} › {c.name}" if parent else c.name

    items_text = "\n".join(
        f"- {ref} [{cat_path(it.category_id)} · {it.kind}] {it.content}"
        + (f" ({it.occurred_at})" if it.kind == "record" and it.occurred_at else "")
        for ref, it in item_refs.items()
    ) or "(none yet)"
    fields_text = "\n".join(
        f"- {f}: " + (f"[written by {'the student' if (cover.get(f) or {}).get('origin') == 'user' else 'AI'}] {cover[f]['text']}"
                      if (cover.get(f) or {}).get("text") else "(empty)")
        for f in COVER_FIELDS
    )
    removed_reason = {"rejected": "the student said this is not them", "archived": "no longer holds",
                      "orphaned": "the conversations behind it were deleted"}
    removed_text = "\n".join(
        f"- {ref} [{cat_path(it.category_id)} · {it.kind}] {it.content} ({removed_reason.get(it.status, 'removed')}"
        + (f"; they said: \"{it.rejected_reason}\"" if it.rejected_reason else "") + ")"
        for ref, it in removed_refs.items()
    ) or "(none)"
    user_content = (f"<current_cover>\n{fields_text}\n</current_cover>\n\n<profile_items>\n{items_text}\n</profile_items>\n\n"
                    f"<removed_items>\n{removed_text}\n</removed_items>")
    return [Message(role="system", content=system), Message(role="user", content=user_content)], item_refs | removed_refs


def validate_cover_output(raw: Any, cover: dict[str, dict], item_refs: dict[str, Item]) -> CoverPlan:
    if not isinstance(raw, dict) or not isinstance(raw.get("fields"), list):
        raise ProfileValidationError("output is not the expected object")
    applied: dict[str, str] = {}
    proposals: dict[str, str] = {}
    dropped: list[dict] = []
    for f in raw["fields"]:
        name = f.get("field")
        if name not in COVER_FIELDS or f.get("action") != "write":
            continue
        text = _clean(f.get("text"))
        based_on = [r for r in f.get("based_on") or [] if r in item_refs]
        if not text or not based_on:
            dropped.append({"field": name, "reason": "empty_text_or_no_basis"})
            continue
        current = cover.get(name) or {}
        if current.get("text") and text == current["text"]:
            continue
        # 本人が書いた・直した欄は書き換えず、案として出す
        if current.get("origin") == "user" and current.get("text"):
            proposals[name] = text
        else:
            applied[name] = text
    return CoverPlan(applied=applied, proposals=proposals, dropped=dropped)


async def write_cover(llm: UnifiedLLM, cover: dict[str, dict], items: list[Item], categories: list[Category],
                      language: str, model: str = COVER_MODEL, reasoning_effort: Optional[str] = COVER_REASONING,
                      removed_items: Sequence[Item] = ()) -> CoverPlan:
    active = [it for it in items if it.status == "active"]
    messages, item_refs = build_cover_messages(cover, active, categories, language, removed_items)
    options = _json_options(model, COVER_SCHEMA, reasoning_effort, 8000)
    last_error: Optional[Exception] = None
    for attempt in range(2):
        result = await llm.generate(model, messages, options)
        try:
            return validate_cover_output(result.output_json, cover, item_refs)
        except ProfileValidationError as e:
            print(f"⚠️ [profile-cover] invalid output (attempt {attempt + 1}): {e}")
            last_error = e
    raise last_error
