"""
自分像プロフィール(docs/chatbot_context_and_retrieval_roadmap.md 9章)の評価ハーネス。

本番のコード(app/services/profile_extraction.py の observe_thread / consolidate /
guard_against_rejected / write_cover)をそのまま使う。DB・patrol・本人の操作のAPIの部分だけを、
メモリ上の状態(ProfileState)と scenarios/*.json の時系列で置き換えている。

流れ(シナリオごと、時系列の順に):
  thread      → 観察役。観察を埋め込み、仮説の更新を反映
  consolidate → まとめ役(+「違う」項目との近さのガード)。計画を状態に適用し、その時点の状態を記録
  user_action → 本人の操作(違う / 直す / 確認トレイで残さない)を状態に適用
  cover       → 表紙の書き直し。空欄・AIが書いた欄は書き込み、本人が書いた欄は案にする
最後に、判定役(LLM)と機械的なチェックで期待値と照合して results/ に保存する。

実行:
  python run_eval.py                          # 全シナリオ
  python run_eval.py p1_precision_ja p4_traps_ja
  python run_eval.py --consolidator-model gpt-6-luna --tag luna   # 結果は results/luna/ に
"""

import argparse
import asyncio
import json
import sys
from dataclasses import asdict
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM  # noqa: E402
from app.services.knowledge_index import KNOWLEDGE_EMBEDDING_MODEL, _embed  # noqa: E402
from app.services.profile_extraction import (  # noqa: E402
    CONSOLIDATOR_MODEL,
    COVER_FIELDS,
    COVER_MODEL,
    OBSERVER_MODEL,
    Category,
    ConsolidationInput,
    ConsolidationPlan,
    Hypothesis,
    Item,
    Memo,
    Observation,
    ObservedRound,
    consolidate,
    cosine,
    guard_against_rejected,
    observe_thread,
    write_cover,
)

TEST_DIR = Path(__file__).resolve().parent
SCENARIO_DIR = TEST_DIR / "scenarios"
RESULTS_DIR = TEST_DIR / "results"

JUDGE_MODEL = "gemini/gemini-3.5-flash-lite"

# まとめ役に渡す「近い過去の観察」: 新しい観察1件ごとに近い順でこの件数、合計の上限
RELATED_PER_NEW = 5
RELATED_MAX_TOTAL = 30

JUDGE_SCHEMA = {
    "type": "object",
    "properties": {
        "must_results": {"type": "array", "items": {"type": "object", "properties": {
            "index": {"type": "integer"}, "satisfied": {"type": "boolean"},
            "matched_ids": {"type": "array", "items": {"type": "string"}}, "note": {"type": "string"},
        }, "required": ["index", "satisfied", "matched_ids", "note"]}},
        "must_not_results": {"type": "array", "items": {"type": "object", "properties": {
            "index": {"type": "integer"}, "violated": {"type": "boolean"},
            "matched_ids": {"type": "array", "items": {"type": "string"}}, "note": {"type": "string"},
        }, "required": ["index", "violated", "matched_ids", "note"]}},
        "allowed_results": {"type": "array", "items": {"type": "object", "properties": {
            "index": {"type": "integer"}, "matched_ids": {"type": "array", "items": {"type": "string"}},
        }, "required": ["index", "matched_ids"]}},
    },
    "required": ["must_results", "must_not_results", "allowed_results"],
}

MATCH_SCHEMA = {
    "type": "object",
    "properties": {"id": {"type": "string"}, "note": {"type": "string"}},
    "required": ["id", "note"],
}


# =========================================================
# メモリ上の状態(本番ではテーブル)
# =========================================================

class ProfileState:
    def __init__(self, scenario: dict, billing: BillingEngine):
        self.language = scenario["language"]
        self.billing = billing
        self.observations: dict[str, Observation] = {}
        self.consolidated: set[str] = set()   # まとめ役に「新しい観察」として渡し終えた観察
        self.categories: dict[str, Category] = {}
        self.items: dict[str, Item] = {}
        self.memos: dict[str, Memo] = {}
        self.hypotheses: dict[str, Hypothesis] = {}
        self.blocked_areas: list[str] = []
        self.cover = {f: dict(scenario["initial_profile"][f]) for f in COVER_FIELDS}
        self.initial_cover = {f: dict(v) for f, v in self.cover.items()}
        self.proposals: dict[str, str] = {}
        self.today = "1970-01-01"
        self._seq = 0

    def new_id(self, prefix: str) -> str:
        self._seq += 1
        return f"{prefix}{self._seq}"

    async def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        vectors, tokens = await _embed(texts)
        self.billing.add_token_cost(KNOWLEDGE_EMBEDDING_MODEL, tokens, 0)
        return vectors

    def category_path(self, cid: str) -> str:
        c = self.categories.get(cid)
        if c is None:
            return "?"
        p = self.categories.get(c.parent_id) if c.parent_id else None
        return f"{p.name} › {c.name}" if p else c.name

    def active_memos(self) -> list[Memo]:
        return [m for m in self.memos.values() if m.is_active(self.today)]

    def open_hypotheses(self) -> list[Hypothesis]:
        return [h for h in self.hypotheses.values() if h.status == "open"]

    def thread_of(self, obs_id: str) -> str:
        o = self.observations.get(obs_id)
        return o.thread_id if o else "?"

    def snapshot(self) -> dict:
        def item_view(it: Item) -> dict:
            return {
                "id": it.id, "category": self.category_path(it.category_id), "kind": it.kind, "content": it.content,
                "origin": it.origin, "status": it.status, "sensitive": it.sensitive,
                "occurred_at": it.occurred_at, "first_seen_at": it.first_seen_at, "last_seen_at": it.last_seen_at,
                "evidence_threads": sorted({self.thread_of(e) for e in it.evidence}),
                "versions": it.versions, "rejected_reason": it.rejected_reason,
            }
        return {
            "today": self.today,
            "categories": [{"id": c.id, "path": self.category_path(c.id), "kind": c.kind} for c in self.categories.values()],
            "items": [item_view(it) for it in self.items.values()],
            "memos": [asdict(m) | {"active": m.is_active(self.today)} for m in self.memos.values()],
            "hypotheses": [asdict(h) for h in self.hypotheses.values()],
            "blocked_areas": list(self.blocked_areas),
            "cover": {f: dict(v) for f, v in self.cover.items()},
            "proposals": dict(self.proposals),
            "observation_status": {o.id: o.status for o in self.observations.values()},
        }

    def all_stored_text(self) -> dict[str, str]:
        """stored_content_must_not 用: 場所ごとに保存されている文字列を全部つなげたもの。"""
        def obs_text(o: Observation) -> str:
            return " ".join(filter(None, [o.note, o.topic, o.hook, o.caveat, o.quote]))
        return {
            "items": " ".join(it.content + " " + " ".join(v.get("content", "") for v in it.versions) for it in self.items.values()),
            "observations": " ".join(obs_text(o) for o in self.observations.values()),
            "hypotheses": " ".join(h.content for h in self.hypotheses.values()),
            "memos": " ".join(m.content for m in self.memos.values()),
            "blocked_areas": " ".join(self.blocked_areas),
        }


def _obs_view(o: Observation) -> dict:
    d = asdict(o)
    d.pop("embedding", None)
    return d


# =========================================================
# イベントの実行
# =========================================================

async def run_thread(llm: UnifiedLLM, state: ProfileState, ev: dict, models: dict) -> dict:
    state.today = ev["date"]
    rounds = [ObservedRound(number=r["round"], date=ev["date"], user=r["user"], assistant=r["assistant"]) for r in ev["rounds"]]
    open_hyps = state.open_hypotheses()
    result = await observe_thread(
        llm, rounds, state.language,
        [state.category_path(c) for c in state.categories],
        open_hyps, state.blocked_areas, model=models["observer"], reasoning_effort=models["observer_reasoning"],
    )
    new_obs: list[Observation] = []
    for d in result.observations:
        new_obs.append(Observation(id=f"{ev['id']}.o{len(new_obs) + 1}", thread_id=ev["id"], **d))
    vectors = await state.embed([o.embedding_input() for o in new_obs])
    for o, v in zip(new_obs, vectors):
        o.embedding = v
        state.observations[o.id] = o

    for up in result.hypothesis_updates:
        h = state.hypotheses.get(up["hypothesis_id"])
        if h is None:
            continue
        h.status = up["status"]
        h.evidence += [o.id for o in new_obs if set(o.rounds) & set(up["rounds"])]

    return {
        "type": "thread", "id": ev["id"], "date": ev["date"],
        "observations": [_obs_view(o) for o in new_obs],
        "hypothesis_updates": [up | {"hypothesis": state.hypotheses[up["hypothesis_id"]].content}
                               for up in result.hypothesis_updates if up["hypothesis_id"] in state.hypotheses],
        "dropped": result.dropped,
    }


def _related(state: ProfileState, new: list[Observation]) -> list[Observation]:
    """新しい観察それぞれに、惹かれた点(hook)が近い過去の観察を近い順に集める(本番ではpgvector)。"""
    new_ids = {o.id for o in new}
    pool = [o for o in state.observations.values()
            if o.id not in new_ids and o.status != "discounted" and o.embedding is not None]
    picked: dict[str, tuple[float, Observation]] = {}
    for n in new:
        ranked = sorted(pool, key=lambda o: cosine(n.embedding, o.embedding), reverse=True)[:RELATED_PER_NEW]
        for o in ranked:
            sim = cosine(n.embedding, o.embedding)
            if o.id not in picked or picked[o.id][0] < sim:
                picked[o.id] = (sim, o)
    ordered = sorted(picked.values(), key=lambda t: t[0], reverse=True)[:RELATED_MAX_TOTAL]
    return sorted((o for _, o in ordered), key=lambda o: (o.observed_at, o.id))


async def run_consolidate(llm: UnifiedLLM, state: ProfileState, ev: dict, models: dict) -> dict:
    new = [o for o in state.observations.values() if o.id not in state.consolidated and o.status != "discounted"]
    related = _related(state, new)
    inp = ConsolidationInput(
        today=state.today, language=state.language, new_observations=new, related_observations=related,
        categories=list(state.categories.values()),
        items=[it for it in state.items.values() if it.status in ("active", "pending_confirm")],
        rejected_items=[it for it in state.items.values() if it.status == "rejected"],
        memos=state.active_memos(), hypotheses=state.open_hypotheses(), blocked_areas=state.blocked_areas,
    )
    plan = await consolidate(llm, inp, model=models["consolidator"], reasoning_effort=models["consolidator_reasoning"])
    guard_checks = await guard_against_rejected(plan, inp.rejected_items, state.observations, state.embed)
    await apply_plan(state, plan)
    for o in new:
        state.consolidated.add(o.id)
    return {
        "type": "consolidate", "id": ev["id"], "today": state.today,
        "input_counts": {"new": len(new), "related": len(related), "items": len(inp.items),
                         "rejected": len(inp.rejected_items), "memos": len(inp.memos)},
        "plan": {k: v for k, v in asdict(plan).items() if k != "dropped"},
        "dropped": plan.dropped,
        "rejected_guard": guard_checks,
        "state": state.snapshot(),
    }


async def apply_plan(state: ProfileState, plan: ConsolidationPlan) -> None:
    ref_to_cat: dict[str, str] = {}
    for c in plan.new_categories:
        cid = state.new_id("cat")
        parent = c["parent_id"] or (ref_to_cat.get(c["parent_ref"]) if c["parent_ref"] else None)
        state.categories[cid] = Category(id=cid, name=c["name"], description=c["description"], kind=c["kind"], parent_id=parent)
        ref_to_cat[c["ref"]] = cid

    def mark_used(obs_ids: list[str]) -> None:
        for e in obs_ids:
            if e in state.observations and state.observations[e].status == "open":
                state.observations[e].status = "used"

    def seen_range(obs_ids: list[str]) -> tuple[str, str]:
        dates = sorted(state.observations[e].observed_at for e in obs_ids if e in state.observations)
        return (dates[0], dates[-1]) if dates else (state.today, state.today)

    created: list[Item] = []
    for c in plan.item_creates:
        cat_id = c.get("category_id") or ref_to_cat.get(c.get("category_ref"))
        if cat_id is None:
            plan.dropped.append({"op": c, "reason": "category_not_created"})
            continue
        first, last = seen_range(c["evidence"])
        it = Item(id=state.new_id("item"), category_id=cat_id, kind=c["kind"], content=c["content"], origin="ai",
                  status=c["status"], sensitive=c["sensitive"], evidence=list(c["evidence"]),
                  first_seen_at=first, last_seen_at=last, occurred_at=c["occurred_at"])
        state.items[it.id] = it
        created.append(it)
        mark_used(c["evidence"])
    vectors = await state.embed([f"title: none | text: {it.content}" for it in created])
    for it, v in zip(created, vectors):
        it.embedding = v

    for u in plan.item_updates:
        it = state.items.get(u["item_id"])
        if it is None:
            continue
        if u["content"] is not None:
            it.versions.append({"content": it.content, "until": state.today})
            it.content = u["content"]
            it.embedding = (await state.embed([f"title: none | text: {it.content}"]))[0]
        it.evidence += u["add_evidence"]
        _, last = seen_range(it.evidence)
        it.last_seen_at = last
        mark_used(u["add_evidence"])

    for item_id in plan.item_archives:
        if item_id in state.items:
            state.items[item_id].status = "archived"

    for m in plan.memo_creates:
        mid = state.new_id("memo")
        state.memos[mid] = Memo(id=mid, kind=m["kind"], content=m["content"], expires_at=m["expires_at"],
                                evidence=m["evidence"], created_at=state.today)
    for m in plan.memo_updates:
        memo = state.memos.get(m["memo_id"])
        if memo:
            memo.content = m["content"]
            memo.expires_at = m["expires_at"]
            memo.evidence += m["add_evidence"]
    for mid in plan.memo_removes:
        state.memos.pop(mid, None)

    for h in plan.hypothesis_creates:
        hid = state.new_id("hyp")
        state.hypotheses[hid] = Hypothesis(id=hid, content=h["content"], evidence=h["evidence"], created_at=state.today)
    for h in plan.hypothesis_closes:
        if h["hypothesis_id"] in state.hypotheses:
            state.hypotheses[h["hypothesis_id"]].status = h["status"]


async def match_target(llm: UnifiedLLM, state: ProfileState, target: str, statuses: tuple[str, ...],
                       kind: str | None = None) -> Item | None:
    candidates = [it for it in state.items.values() if it.status in statuses and (kind is None or it.kind == kind)]
    if not candidates:
        return None
    listing = "\n".join(f"- {it.id}: [{state.category_path(it.category_id)}] {it.content}" for it in candidates)
    messages = [
        Message(role="system", content=(
            "You pick which profile item a user action refers to. The item must make the SAME claim as the target "
            "(same meaning, possibly different wording). An item that is only about a related topic or event does not match. "
            "Return the id of the single matching item, or \"none\" if no item makes that claim.")),
        Message(role="user", content=f"<target>{target}</target>\n\n<items>\n{listing}\n</items>"),
    ]
    result = await llm.generate(JUDGE_MODEL, messages, LLMOptions(output_type="json", json_schema=MATCH_SCHEMA, reasoning_effort="low"))
    picked = (result.output_json or {}).get("id")
    return state.items.get(picked) if picked in state.items else None


async def run_user_action(judge_llm: UnifiedLLM, state: ProfileState, ev: dict) -> dict:
    action = ev["action"]
    out = {"type": "user_action", "id": ev["id"], "action": action, "target": ev["target"]}

    if action == "reject":
        item = await match_target(judge_llm, state, ev["target"], ("active",), ev.get("target_kind"))
        if item is None and ev.get("if_target_missing") == "inject":
            # まとめ役が作らなかった場合も、この後の振る舞いを確かめられるよう、AIが作ったものとして差し込む
            item = Item(id=state.new_id("item"), category_id="", kind="trait", content=ev["target"], origin="ai", status="active")
            item.embedding = (await state.embed([f"title: none | text: {item.content}"]))[0]
            state.items[item.id] = item
            out["injected"] = True
        if item is None:
            out["applied"] = False
            return out
        item.status = "rejected"
        item.rejected_at = state.today
        item.rejected_reason = ev.get("reason")
        for e in item.evidence:
            if e in state.observations:
                state.observations[e].status = "discounted"
        out |= {"applied": True, "item_id": item.id, "item_content": item.content}

    elif action == "edit":
        item = await match_target(judge_llm, state, ev["target"], ("active",), ev.get("target_kind"))
        if item is None:
            out["applied"] = False
            return out
        item.versions.append({"content": item.content, "until": state.today})
        out |= {"applied": True, "item_id": item.id, "before": item.content}
        item.content = ev["new_content"]
        item.origin = "user"
        item.embedding = (await state.embed([f"title: none | text: {item.content}"]))[0]

    elif action in ("confirm_discard", "confirm_keep"):
        item = await match_target(judge_llm, state, ev["target"], ("pending_confirm",))
        if item is None:
            out["applied"] = False
            return out
        out |= {"applied": True, "item_id": item.id, "item_content": item.content}
        if action == "confirm_keep":
            item.status = "active"
        else:
            # 残さない = 残したくない: 中身は消し、分野だけ覚える。その分野の観察もすべて消す
            area = item.sensitive
            del state.items[item.id]
            if area != "none" and area not in state.blocked_areas:
                state.blocked_areas.append(area)
            for oid in [o.id for o in state.observations.values() if o.sensitive == area or o.id in item.evidence]:
                del state.observations[oid]
            out["blocked_area"] = area
    else:
        raise ValueError(f"unknown action {action}")
    return out


async def run_cover(llm: UnifiedLLM, state: ProfileState, ev: dict, models: dict) -> dict:
    before = {f: dict(v) for f, v in state.cover.items()}
    plan = await write_cover(llm, state.cover, list(state.items.values()), list(state.categories.values()),
                             state.language, model=models["cover"], reasoning_effort=models["cover_reasoning"])
    for f, text in plan.applied.items():
        state.cover[f] = {"text": text, "origin": "ai"}
    state.proposals.update(plan.proposals)
    return {"type": "cover", "id": ev["id"], "before": before, "after": {f: dict(v) for f, v in state.cover.items()},
            "proposals": dict(plan.proposals), "dropped": plan.dropped}


async def run_scenario(scenario: dict, models: dict) -> dict:
    billings = {role: BillingEngine(task_type=f"PROFILE_EVAL_{role.upper()}")
                for role in ("observer", "consolidator", "cover", "embedding")}
    judge_billing = BillingEngine(task_type="PROFILE_EVAL_JUDGE")
    llms = {role: UnifiedLLM(b) for role, b in billings.items()}
    judge_llm = UnifiedLLM(judge_billing)
    state = ProfileState(scenario, billings["embedding"])
    events_out = []
    for ev in scenario["timeline"]:
        print(f"  [{scenario['id']}] {ev['type']} {ev['id']}")
        if ev["type"] == "thread":
            events_out.append(await run_thread(llms["observer"], state, ev, models))
        elif ev["type"] == "consolidate":
            events_out.append(await run_consolidate(llms["consolidator"], state, ev, models))
        elif ev["type"] == "user_action":
            events_out.append(await run_user_action(judge_llm, state, ev))
        elif ev["type"] == "cover":
            events_out.append(await run_cover(llms["cover"], state, ev, models))
    stored_text = state.all_stored_text()

    graded = await grade_scenario(judge_llm, scenario, events_out, stored_text)
    return {
        "scenario_id": scenario["id"],
        "language": scenario["language"],
        "description": scenario["description"],
        "tests": scenario["tests"],
        "models": models,
        "events": events_out,
        "grades": graded,
        "summary": summarize(graded),
        "cost_usd": _costs(billings, judge_billing),
    }


def _token_cost(b: BillingEngine) -> float:
    return round(sum(r.cost_usd for r in b.records if r.dimension == "tokens"), 6)


def _costs(billings: dict, judge_billing: BillingEngine) -> dict:
    by_role = {role: _token_cost(b) for role, b in billings.items()}
    return {
        "pipeline_tokens": round(sum(by_role.values()), 6),
        "by_role": by_role,
        "judge_tokens": _token_cost(judge_billing),
    }


# =========================================================
# 採点
# =========================================================

async def judge(llm: UnifiedLLM, records: list[tuple[str, str]], must: list[str], must_not: list[str], allowed: list[str]) -> dict:
    if not must and not must_not and not allowed:
        return {"must_results": [], "must_not_results": [], "allowed_results": []}
    system = (TEST_DIR / "judge_prompt.txt").read_text(encoding="utf-8")

    def numbered(xs: list[str]) -> str:
        return "\n".join(f"{i}. {x}" for i, x in enumerate(xs, start=1)) or "(none)"

    rec_text = "\n".join(f"- {rid}: {text}" for rid, text in records) or "(no records)"
    user_content = (f"<records>\n{rec_text}\n</records>\n\n<must>\n{numbered(must)}\n</must>\n\n"
                    f"<must_not>\n{numbered(must_not)}\n</must_not>\n\n<allowed>\n{numbered(allowed)}\n</allowed>")
    messages = [Message(role="system", content=system), Message(role="user", content=user_content)]
    options = LLMOptions(output_type="json", json_schema=JUDGE_SCHEMA, reasoning_effort="low")
    for _ in range(2):
        result = await llm.generate(JUDGE_MODEL, messages, options)
        out = result.output_json
        if isinstance(out, dict) and len(out.get("must_results", [])) == len(must) and len(out.get("must_not_results", [])) == len(must_not):
            return out
    raise RuntimeError(f"judge returned an unexpected shape: {result.output_text[:300]}")


def _expect_text(e) -> str:
    if isinstance(e, str):
        return e
    extra = []
    if e.get("kind"):
        extra.append(f"kind={e['kind']}")
    if e.get("category_hint"):
        extra.append(f"category like {e['category_hint']}")
    if e.get("occurred_at"):
        extra.append(f"occurred_at={e['occurred_at']}")
    if e.get("expires_at"):
        extra.append(f"expires around {e['expires_at']}")
    return e["content"] + (f" ({', '.join(extra)})" if extra else "")


def _obs_record(o: dict) -> str:
    parts = [f"note: {o['note']}", f"topic: {o['topic']}", f"hook: {o['hook'] or '(unknown)'}"]
    if o.get("caveat"):
        parts.append(f"caveat: {o['caveat']}")
    parts.append(f"certainty={o['certainty']}, initiative={o['initiative']}, context={o['context']}, "
                 f"kind_hint={o['kind_hint']}, sensitive={o['sensitive']}, occurred_at={o.get('occurred_at')}")
    return " | ".join(parts)


def _item_record(it: dict) -> str:
    s = f"[{it['category']} · {it['kind']} · origin={it['origin']} · status={it['status']}] {it['content']}"
    if it["kind"] == "record" and it.get("occurred_at"):
        s += f" (occurred_at={it['occurred_at']})"
    return s


def _check(name: str, ok: bool, note: str = "", severity: str = "fail") -> dict:
    return {"check": name, "ok": ok, "note": note, "severity": severity}


def _days_apart(a: str, b: str) -> int:
    return abs((date.fromisoformat(a) - date.fromisoformat(b)).days)


async def grade_scenario(llm: UnifiedLLM, scenario: dict, events_out: list[dict], stored_text: dict) -> list[dict]:
    by_id = {e["id"]: e for e in events_out}
    edits = {ev["target"]: ev["new_content"] for ev in scenario["timeline"] if ev["type"] == "user_action" and ev["action"] == "edit"}
    edited_texts = set(edits.values())
    tasks = []

    for ev in scenario["timeline"]:
        out = by_id.get(ev["id"])
        if ev["type"] == "thread":
            exp = ev.get("expect_observations", {})
            records = [(f"X{i}", _obs_record(o)) for i, o in enumerate(out["observations"], start=1)]
            records += [(f"U{i}", f"hypothesis update: \"{u['hypothesis']}\" → {u['status']} ({u['note']})")
                        for i, u in enumerate(out["hypothesis_updates"], start=1)]
            tasks.append(_grade_simple(llm, ev["id"], "observations", records, exp.get("must", []), exp.get("must_not", []), []))

        elif ev["type"] == "consolidate":
            exp = ev.get("expect", {})
            state = out["state"]
            active = [it for it in state["items"] if it["status"] == "active"]
            pending = [it for it in state["items"] if it["status"] == "pending_confirm"]
            memos = [m for m in state["memos"] if m["active"]]
            tasks.append(_grade_items(llm, ev["id"], active, exp, edited_texts))
            if exp.get("pending_confirm_must") or exp.get("pending_confirm_must_not"):
                records = [(f"X{i}", _item_record(it)) for i, it in enumerate(pending, start=1)]
                tasks.append(_grade_simple(llm, ev["id"], "pending_confirm", records,
                                           exp.get("pending_confirm_must", []), exp.get("pending_confirm_must_not", []), []))
            if exp.get("memos_must") or exp.get("memos_must_not"):
                tasks.append(_grade_memos(llm, ev["id"], memos, exp))
            if exp.get("hypotheses_must") or exp.get("hypotheses_status"):
                tasks.append(_grade_hypotheses(llm, ev["id"], state["hypotheses"], exp))
            mech = []
            for area in exp.get("blocked_areas_must", []):
                mech.append(_check(f"blocked area '{area}'", area in state["blocked_areas"], f"blocked={state['blocked_areas']}"))
            scm = exp.get("stored_content_must_not")
            if scm:
                for where in scm["where"]:
                    hits = [t for t in scm["terms"] if t in stored_text.get(where, "")]
                    mech.append(_check(f"no stored '{'/'.join(scm['terms'])}' in {where}", not hits, f"found: {hits}" if hits else ""))
            if mech:
                tasks.append(_done({"event": ev["id"], "target": "mechanical", "results": [], "mechanical": mech}))

        elif ev["type"] == "cover":
            tasks.append(_grade_cover(llm, ev["id"], out, ev["expect"]))

        elif ev["type"] == "user_action":
            tasks.append(_done({"event": ev["id"], "target": "user_action", "results": [], "mechanical": [
                _check("action applied", bool(out.get("applied")), "injected" if out.get("injected") else "", severity="info"),
            ]}))

    return list(await asyncio.gather(*tasks))


async def _done(x):
    return x


async def _grade_simple(llm, event_id, target, records, must, must_not, allowed) -> dict:
    j = await judge(llm, records, must, must_not, allowed)
    results = []
    for r in j["must_results"]:
        results.append({"type": "must", "expectation": must[r["index"] - 1], "ok": r["satisfied"],
                        "matched": r["matched_ids"], "note": r["note"]})
    for r in j["must_not_results"]:
        results.append({"type": "must_not", "expectation": must_not[r["index"] - 1], "ok": not r["violated"],
                        "matched": r["matched_ids"], "note": r["note"]})
    return {"event": event_id, "target": target, "records": records, "results": results, "mechanical": []}


async def _grade_items(llm, event_id, active: list[dict], exp: dict, edited_texts: set[str]) -> dict:
    must = exp.get("items_must", [])
    must_not = exp.get("items_must_not", [])
    allowed = exp.get("items_allowed", [])
    records = [(f"X{i}", _item_record(it)) for i, it in enumerate(active, start=1)]
    rec_by_id = {f"X{i}": it for i, it in enumerate(active, start=1)}
    j = await judge(llm, records, [_expect_text(e) for e in must], must_not, allowed)
    results, mech = [], []
    explained: set[str] = set()
    for r in j["must_results"]:
        e = must[r["index"] - 1]
        matched = [rec_by_id[m] for m in r["matched_ids"] if m in rec_by_id]
        explained |= {m for m in r["matched_ids"]}
        ok = r["satisfied"]
        notes = [r["note"]]
        if ok and isinstance(e, dict) and matched:
            best = matched[0]
            if e.get("kind") and best["kind"] != e["kind"]:
                ok = False
                notes.append(f"kind is {best['kind']}, expected {e['kind']}")
            if e.get("occurred_at") and best.get("occurred_at") != e["occurred_at"]:
                ok = False
                notes.append(f"occurred_at is {best.get('occurred_at')}, expected {e['occurred_at']}")
            if e.get("origin") and best["origin"] != e["origin"]:
                ok = False
                notes.append(f"origin is {best['origin']}, expected {e['origin']}")
            if e.get("text_unchanged") and best["content"] not in edited_texts:
                ok = False
                notes.append("the student's edited wording was changed")
            want = set(e.get("evidence_threads_at_least", []))
            have = set(best["evidence_threads"])
            if want and not want <= have:
                mech.append(_check(f"evidence threads for '{e['content'][:30]}…'", False,
                                   f"missing {sorted(want - have)} (has {sorted(have)})", severity="warn"))
        results.append({"type": "must", "expectation": _expect_text(e), "ok": ok, "matched": r["matched_ids"], "note": " / ".join(notes)})
    for r in j["must_not_results"]:
        explained |= set(r["matched_ids"]) if r["violated"] else set()
        results.append({"type": "must_not", "expectation": must_not[r["index"] - 1], "ok": not r["violated"],
                        "matched": r["matched_ids"], "note": r["note"]})
    for r in j.get("allowed_results", []):
        explained |= set(r["matched_ids"])
    unexplained = [rec_by_id[rid] for rid in rec_by_id if rid not in explained]
    return {"event": event_id, "target": "items", "records": records, "results": results, "mechanical": mech,
            "unexplained_items": [_item_record(it) for it in unexplained]}


async def _grade_memos(llm, event_id, memos: list[dict], exp: dict) -> dict:
    must = exp.get("memos_must", [])
    must_not = exp.get("memos_must_not", [])
    records = [(f"X{i}", f"[{m['kind']}] {m['content']}" + (f" (until {m['expires_at']})" if m["expires_at"] else ""))
               for i, m in enumerate(memos, start=1)]
    rec_by_id = {f"X{i}": m for i, m in enumerate(memos, start=1)}
    j = await judge(llm, records, [_expect_text(e) for e in must], must_not, [])
    results = []
    for r in j["must_results"]:
        e = must[r["index"] - 1]
        ok, notes = r["satisfied"], [r["note"]]
        matched = [rec_by_id[m] for m in r["matched_ids"] if m in rec_by_id]
        if ok and isinstance(e, dict) and matched:
            m = matched[0]
            if e.get("kind") and m["kind"] != e["kind"]:
                ok = False
                notes.append(f"kind is {m['kind']}, expected {e['kind']}")
            if e.get("expires_at") and (not m["expires_at"] or _days_apart(m["expires_at"], e["expires_at"]) > 31):
                ok = False
                notes.append(f"expires_at is {m['expires_at']}, expected around {e['expires_at']}")
        results.append({"type": "must", "expectation": _expect_text(e), "ok": ok, "matched": r["matched_ids"], "note": " / ".join(notes)})
    for r in j["must_not_results"]:
        results.append({"type": "must_not", "expectation": must_not[r["index"] - 1], "ok": not r["violated"],
                        "matched": r["matched_ids"], "note": r["note"]})
    return {"event": event_id, "target": "memos", "records": records, "results": results, "mechanical": []}


async def _grade_hypotheses(llm, event_id, hypotheses: list[dict], exp: dict) -> dict:
    must = list(exp.get("hypotheses_must", []))
    status_exp = exp.get("hypotheses_status", [])
    records = [(f"X{i}", f"[status={h['status']}] {h['content']}") for i, h in enumerate(hypotheses, start=1)]
    must_all = must + [f"{s['content']} (status={s['status']})" for s in status_exp]
    j = await judge(llm, records, must_all, [], [])
    results = [{"type": "must", "expectation": must_all[r["index"] - 1], "ok": r["satisfied"],
                "matched": r["matched_ids"], "note": r["note"]} for r in j["must_results"]]
    return {"event": event_id, "target": "hypotheses", "records": records, "results": results, "mechanical": []}


async def _grade_cover(llm, event_id, out: dict, exp: dict) -> dict:
    before, after, proposals = out["before"], out["after"], out["proposals"]
    mech, results = [], []
    for f, e in exp.items():
        action = e["action"]
        b, a = before[f], after[f]
        changed = a.get("text") != b.get("text")
        if action == "auto_fill":
            mech.append(_check(f"{f}: filled automatically", bool(a.get("text")) and a.get("origin") == "ai", f"text={bool(a.get('text'))}"))
        elif action == "auto_fill_or_leave_empty":
            mech.append(_check(f"{f}: filled by AI or left empty", not a.get("text") or a.get("origin") == "ai"))
        elif action == "leave_empty":
            mech.append(_check(f"{f}: left empty", not a.get("text"), a.get("text") or ""))
        elif action == "proposal_only":
            mech.append(_check(f"{f}: student's text kept", not changed and a.get("origin") == "user"))
        elif action == "auto_update_or_keep":
            mech.append(_check(f"{f}: no proposal for an AI-written field", f not in proposals))
        texts = [t for t in (a.get("text"), proposals.get(f)) if t]
        if texts and (e.get("must") or e.get("must_not")):
            records = [(f"X{i}", t) for i, t in enumerate(texts, start=1)]
            j = await judge(llm, records, e.get("must", []), e.get("must_not", []), [])
            for r in j["must_results"]:
                results.append({"type": "must", "expectation": f"{f}: {e['must'][r['index'] - 1]}", "ok": r["satisfied"],
                                "matched": r["matched_ids"], "note": r["note"]})
            for r in j["must_not_results"]:
                results.append({"type": "must_not", "expectation": f"{f}: {e['must_not'][r['index'] - 1]}", "ok": not r["violated"],
                                "matched": r["matched_ids"], "note": r["note"]})
        elif e.get("must") and action == "auto_fill":
            for m in e["must"]:
                results.append({"type": "must", "expectation": f"{f}: {m}", "ok": False, "matched": [], "note": "field is empty"})
    return {"event": event_id, "target": "cover", "results": results, "mechanical": mech}


def summarize(grades: list[dict]) -> dict:
    s = {"false_promotions": 0, "missed": 0, "observation_misses": 0, "observation_violations": 0,
         "mechanical_failures": 0, "evidence_warnings": 0, "unexplained_items": 0, "passed": 0, "total": 0}
    for g in grades:
        for r in g["results"]:
            s["total"] += 1
            s["passed"] += r["ok"]
            if r["ok"]:
                continue
            if g["target"] == "observations":
                s["observation_violations" if r["type"] == "must_not" else "observation_misses"] += 1
            else:
                s["false_promotions" if r["type"] == "must_not" else "missed"] += 1
        for m in g.get("mechanical", []):
            if m["severity"] == "info":
                continue
            s["total"] += m["severity"] == "fail"
            if m["ok"]:
                s["passed"] += m["severity"] == "fail"
            elif m["severity"] == "warn":
                s["evidence_warnings"] += 1
            else:
                s["mechanical_failures"] += 1
        s["unexplained_items"] += len(g.get("unexplained_items", []))
    return s


# =========================================================
# main
# =========================================================

async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*")
    ap.add_argument("--observer-model", default=OBSERVER_MODEL)
    ap.add_argument("--observer-reasoning", default="none", choices=["default", "none", "low", "medium", "high"])
    ap.add_argument("--cover-reasoning", default="low", choices=["default", "none", "low", "medium", "high"])
    ap.add_argument("--consolidator-model", default=CONSOLIDATOR_MODEL)
    ap.add_argument("--consolidator-reasoning", default="medium", choices=["default", "none", "low", "medium", "high"])
    ap.add_argument("--cover-model", default=COVER_MODEL)
    ap.add_argument("--tag", default="", help="結果を results/<tag>/ に分けて保存する")
    ap.add_argument("--concurrency", type=int, default=3)
    args = ap.parse_args()

    def effort(x: str):
        return None if x == "default" else x
    models = {"observer": args.observer_model, "observer_reasoning": effort(args.observer_reasoning),
              "consolidator": args.consolidator_model, "consolidator_reasoning": effort(args.consolidator_reasoning),
              "cover": args.cover_model, "cover_reasoning": effort(args.cover_reasoning)}
    paths = sorted(SCENARIO_DIR.glob("*.json"))
    if args.scenarios:
        paths = [p for p in paths if p.stem in args.scenarios]
    out_dir = RESULTS_DIR / args.tag if args.tag else RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    sem = asyncio.Semaphore(args.concurrency)

    async def one(path: Path) -> dict:
        async with sem:
            scenario = json.loads(path.read_text(encoding="utf-8"))
            print(f"▶ {scenario['id']}")
            res = await run_scenario(scenario, models)
            (out_dir / f"{scenario['id']}.json").write_text(json.dumps(res, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            return res

    results = await asyncio.gather(*(one(p) for p in paths))

    print("\n=== summary ===")
    print(f"models: {models}")
    total = {}
    for r in results:
        s = r["summary"]
        for k, v in s.items():
            total[k] = total.get(k, 0) + v
        print(f"{r['scenario_id']:<22} passed {s['passed']}/{s['total']}  false_promotions={s['false_promotions']}  "
              f"missed={s['missed']}  obs_violations={s['observation_violations']}  obs_misses={s['observation_misses']}  "
              f"mechanical={s['mechanical_failures']}  unexplained={s['unexplained_items']}  "
              f"cost=${r['cost_usd']['pipeline_tokens']:.4f}")
    print(f"{'TOTAL':<22} passed {total.get('passed', 0)}/{total.get('total', 0)}  false_promotions={total.get('false_promotions', 0)}  "
          f"missed={total.get('missed', 0)}")
    (out_dir / "_summary.json").write_text(json.dumps({"models": models, "total": total,
                                                         "scenarios": {r["scenario_id"]: r["summary"] | {"cost_usd": r["cost_usd"]} for r in results}},
                                                        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    asyncio.run(main())
