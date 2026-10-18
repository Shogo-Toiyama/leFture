# app/services/profile_store.py
"""
自分像プロフィール(ロードマップ 9章)の保存と、非同期処理の本体。

LLMまわり(入力の組み立て・出力の検証・コード側で守るルール)は profile_extraction.py にあり、
ここはそれをDBにつなぐ。評価(contents_generation/test_codes/profile_extraction_test/run_eval.py)の
メモリ上の ProfileState がやっていることを、テーブルに対して行う。

流れ(すべてCloud Tasksのワーカーから。チャットの応答には関係しない):
  patrol → observe_thread_task(スレッドごと)→ 未処理の観察がたまったら consolidate_user_task(ユーザーごと)
         → 2層が十分変わったら write_cover_task(同じタスクの中で続けて)
本人の操作(違う・直す・残したくない・確認トレイ・書き直し案・覚え書きの削除)もここにある。

費用はユーザーに請求しない(運営が付加価値として非同期で行う処理のため)。原価は usage_records に
metadata.kind 付きで記録し、管理画面の原価の集計に入るようにする。チャットの要約(CHAT_SUMMARY)は
会話の直後に起きてその後の会話を安くする作業なので課金している。この線引きはロードマップ9章のとおり。
"""

import asyncio
import json
from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional

from app.core.supabase import get_supabase_client
from app.services.chat_summary import pair_turns, summary_language
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM
from app.services.knowledge_index import KNOWLEDGE_EMBEDDING_MODEL, _embed
from app.services.profile_extraction import (
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
    guard_against_rejected,
    observe_thread,
    write_cover,
)

# まとめ役を動かす条件: まだ渡していない観察がこの件数以上、またはいちばん古いものがこの日数以上たった
CONSOLIDATE_MIN_NEW_OBSERVATIONS = 5
CONSOLIDATE_MAX_WAIT_DAYS = 7
# 1回のまとめ役に「新しい観察」として渡す上限(古い順)。残りは次の回に回る
CONSOLIDATE_MAX_NEW = 40
# まとめ役に渡す「近い過去の観察」: 新しい観察1件ごとの件数と合計の上限
RELATED_PER_NEW = 5
RELATED_MAX_TOTAL = 30
# 記録はたまり続けるので、新しい観察に近いものだけを渡す。傾向は全部渡す(上限つき)
RECORDS_PER_NEW = 3
RECORDS_MAX_TOTAL = 30
TRAITS_MAX = 80
REJECTED_MAX = 30
# 表紙を書き直す条件: 前回から2層の項目がこの数以上、作られた・書き直された
COVER_MIN_CHANGES = 3
# 観察役が1回に読む往復の上限(長い会話は古い方から何回かに分けて読む)
OBSERVE_MAX_TURNS = 40

_OBS_COLUMNS = ("id, thread_id, source_message_ids, observed_at, occurred_at, ends_at, note, topic, hook, caveat, quote, "
                "reaction, initiative, certainty, context, kind_hint, sensitive, status, consolidated_at, embedding")
_ITEM_COLUMNS = ("id, category_id, kind, content, origin, status, sensitive, first_seen_at, last_seen_at, occurred_at, "
                 "rejected_at, rejected_reason, embedding")


def _today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _db(fn):
    return await asyncio.to_thread(fn)


def _vec(v: Any) -> Optional[list[float]]:
    """pgvectorの列はPostgREST経由だと "[0.1,0.2,...]" の文字列で返ってくる。"""
    if v is None:
        return None
    if isinstance(v, str):
        return json.loads(v)
    return list(v)


def _obs_from_row(r: dict) -> Observation:
    return Observation(
        id=r["id"], thread_id=r["thread_id"], observed_at=r["observed_at"], note=r["note"], topic=r.get("topic") or "",
        hook=r.get("hook"), caveat=r.get("caveat"), reaction=r["reaction"], initiative=r["initiative"],
        certainty=r["certainty"], context=r["context"], kind_hint=r["kind_hint"], sensitive=r["sensitive"],
        rounds=[], quote=r.get("quote"), occurred_at=r.get("occurred_at"), ends_at=r.get("ends_at"),
        status=r["status"], embedding=_vec(r.get("embedding")),
    )


def _item_from_row(r: dict, evidence: list[str]) -> Item:
    return Item(
        id=r["id"], category_id=r.get("category_id") or "", kind=r["kind"], content=r["content"], origin=r["origin"],
        status=r["status"], sensitive=r["sensitive"], evidence=evidence, first_seen_at=r.get("first_seen_at"),
        last_seen_at=r.get("last_seen_at"), occurred_at=r.get("occurred_at"), rejected_at=r.get("rejected_at"),
        rejected_reason=r.get("rejected_reason"), embedding=_vec(r.get("embedding")),
    )


async def _embed_documents(texts: list[str], billing: Optional[BillingEngine] = None) -> list[list[float]]:
    if not texts:
        return []
    vectors, tokens = await _embed(texts)
    if billing is not None:
        billing.add_token_cost(KNOWLEDGE_EMBEDDING_MODEL, tokens, 0)
    return vectors


def _item_embedding_input(content: str) -> str:
    return f"title: none | text: {content}"


async def _record_cost(admin_client, user_id: str, kind: str, billing: BillingEngine, metadata: dict) -> float:
    """請求しない原価の記録。チャット原価との比率を管理画面で見るため、kindを付けて usage_records に入れる。"""
    cost = sum(r.cost_usd for r in billing.records if r.dimension == "tokens")
    if cost <= 0:
        return 0.0
    try:
        await _db(lambda: admin_client.table("usage_records").insert({
            "user_id": user_id,
            "cost_usd": cost,
            "cost_breakdown": [vars(r) for r in billing.records],
            "metadata": {"kind": kind, "charged": False, **metadata},
            # このテーブルの micro_credits_charged は「実コストどおり課金していたら」の参考値の列だが、
            # 自分像プロフィールは請求しない処理なので 0 を入れる
            "micro_credits_charged": 0,
        }).execute())
    except Exception as e:
        print(f"⚠️ [profile] failed to record cost ({kind}) for user {user_id}: {e}")
    return cost


async def _user_language(admin_client, user_id: str, fallback: str = "en") -> str:
    res = await _db(lambda: admin_client.table("user_profiles").select("metadata").eq("id", user_id).maybe_single().execute())
    meta = ((res.data if res else None) or {}).get("metadata") or {}
    return meta.get("display_language") or fallback


async def _blocked_areas(admin_client, user_id: str) -> list[str]:
    res = await _db(lambda: admin_client.table("profile_blocked_areas").select("area").eq("user_id", user_id).execute())
    return [r["area"] for r in res.data or []]


async def _categories(admin_client, user_id: str) -> list[Category]:
    res = await _db(lambda: admin_client.table("profile_categories")
                    .select("id, name, description, kind, parent_id, merged_into")
                    .eq("user_id", user_id).is_("merged_into", "null").order("created_at").execute())
    return [Category(id=r["id"], name=r["name"], description=r["description"] or "", kind=r["kind"],
                     parent_id=r.get("parent_id")) for r in res.data or []]


def _category_path(categories: list[Category], cid: str) -> str:
    by_id = {c.id: c for c in categories}
    c = by_id.get(cid)
    if c is None:
        return "?"
    parent = by_id.get(c.parent_id) if c.parent_id else None
    return f"{parent.name} › {c.name}" if parent else c.name


async def _open_hypotheses(admin_client, user_id: str) -> list[Hypothesis]:
    res = await _db(lambda: admin_client.table("profile_hypotheses")
                    .select("id, content, status, evidence_observation_ids, created_at")
                    .eq("user_id", user_id).eq("status", "open").order("created_at").execute())
    return [Hypothesis(id=r["id"], content=r["content"], status=r["status"],
                       evidence=list(r.get("evidence_observation_ids") or []), created_at=r["created_at"][:10])
            for r in res.data or []]


# =========================================================
# 👀 観察役(スレッドごと)
# =========================================================

async def observe_thread_task(thread_id: str) -> dict:
    """
    スレッドのまだ観察していない部分を読み、観察を保存する。
    戻り値の consolidate_user_id が入っていれば、呼び出し側がまとめ役のタスクを積む。

    - 「どこまで読んだか」(chat_threads.profile_observed_until)を先に進めてから観察を保存する。
      同じ差分を2つの実行が読んで観察が二重になるのを防ぐため。保存に失敗したら位置を戻して例外を投げる
      (Cloud Tasksのリトライでもう一度読む)
    - 危機対応(crisis)の返答を含む差分は読まない(位置だけ進める)
    """
    admin_client = get_supabase_client()
    t_res = await _db(lambda: admin_client.table("chat_threads")
                      .select("id, user_id, deleted_at, profile_observed_until")
                      .eq("id", thread_id).maybe_single().execute())
    thread = t_res.data if t_res else None
    if not thread or thread.get("deleted_at"):
        return {"status": "skipped", "reason": "thread_missing_or_deleted"}
    user_id = thread["user_id"]
    prev_cursor = thread.get("profile_observed_until")

    q = admin_client.table("chat_messages").select("id, role, content, status, router, created_at") \
        .eq("thread_id", thread_id).is_("deleted_at", "null")
    if prev_cursor:
        q = q.gt("created_at", prev_cursor)
    rows = (await _db(lambda: q.order("created_at").execute())).data or []
    # 生成中の返答がある間は読まない(返答が完成してからまとめて読む)
    if not rows or any(r.get("status") == "streaming" for r in rows):
        return {"status": "skipped", "reason": "nothing_new_or_streaming"}

    turns = pair_turns(rows)
    if len(turns) > OBSERVE_MAX_TURNS:
        turns = turns[:OBSERVE_MAX_TURNS]
        last_assistant_id = turns[-1].assistant_message_id
        cut = next(i for i, r in enumerate(rows) if r["id"] == last_assistant_id)
        rows = rows[:cut + 1]
    new_cursor = rows[-1]["created_at"]

    advanced = await _advance_cursor(admin_client, thread_id, prev_cursor, new_cursor)
    if not advanced:
        return {"status": "skipped", "reason": "another_run_took_it"}

    if any(r.get("status") == "crisis" for r in rows) or not turns:
        return {"status": "skipped", "reason": "crisis_or_no_complete_turns"}

    try:
        saved, cost = await _observe_and_save(admin_client, user_id, thread_id, turns, rows)
    except Exception:
        await _db(lambda: admin_client.table("chat_threads").update({"profile_observed_until": prev_cursor})
                  .eq("id", thread_id).eq("profile_observed_until", new_cursor).execute())
        raise

    pending = await _db(lambda: admin_client.table("profile_observations").select("id", count="exact")
                        .eq("user_id", user_id).is_("deleted_at", "null").is_("consolidated_at", "null")
                        .neq("status", "discounted").limit(1).execute())
    pending_count = pending.count or 0
    print(f"👀 [profile-observe] thread={thread_id} turns={len(turns)} observations={saved} "
          f"pending={pending_count} cost=${cost:.6f}")
    return {
        "status": "success",
        "observations": saved,
        "consolidate_user_id": user_id if pending_count >= CONSOLIDATE_MIN_NEW_OBSERVATIONS else None,
    }


async def _advance_cursor(admin_client, thread_id: str, prev_cursor: Optional[str], new_cursor: str) -> bool:
    """前回の位置が変わっていないときだけ進める(同時に走った別の実行と二重に読まないため)。"""
    q = admin_client.table("chat_threads").update({"profile_observed_until": new_cursor}).eq("id", thread_id)
    q = q.eq("profile_observed_until", prev_cursor) if prev_cursor else q.is_("profile_observed_until", "null")
    res = await _db(lambda: q.execute())
    return bool(res.data)


async def _observe_and_save(admin_client, user_id: str, thread_id: str, turns, rows) -> tuple[int, float]:
    created_at_by_id = {r["id"]: r["created_at"] for r in rows}
    rounds = [
        ObservedRound(
            number=t.number,
            date=(created_at_by_id.get(t.user_message_id) or t.assistant_created_at or _now_iso())[:10],
            user=t.user_content,
            assistant=t.assistant_content,
        )
        for t in turns
    ]
    user_message_by_round = {t.number: t.user_message_id for t in turns}

    blocked = await _blocked_areas(admin_client, user_id)
    categories = await _categories(admin_client, user_id)
    hypotheses = await _open_hypotheses(admin_client, user_id)

    billing = BillingEngine(task_type="PROFILE_OBSERVE")
    result = await observe_thread(
        UnifiedLLM(billing), rounds, summary_language(turns),
        [_category_path(categories, c.id) for c in categories], hypotheses, blocked,
    )

    vectors = await _embed_documents(
        [f"title: none | text: {o['hook'] or o['note']}" for o in result.observations], billing,
    )
    inserted_ids_by_round: dict[int, list[str]] = {}
    if result.observations:
        payload = []
        for o, vec in zip(result.observations, vectors):
            payload.append({
                "user_id": user_id,
                "thread_id": thread_id,
                "source_message_ids": [user_message_by_round[n] for n in o["rounds"] if n in user_message_by_round],
                "observed_at": o["observed_at"],
                "occurred_at": o["occurred_at"] if o["kind_hint"] == "record" else None,
                "ends_at": o["ends_at"],
                "note": o["note"], "topic": o["topic"], "hook": o["hook"], "caveat": o["caveat"], "quote": o["quote"],
                "reaction": o["reaction"], "initiative": o["initiative"], "certainty": o["certainty"],
                "context": o["context"], "kind_hint": o["kind_hint"], "sensitive": o["sensitive"],
                "embedding": vec, "embedding_model": KNOWLEDGE_EMBEDDING_MODEL, "model": OBSERVER_MODEL,
            })
        res = await _db(lambda: admin_client.table("profile_observations").insert(payload).execute())
        for o, row in zip(result.observations, res.data or []):
            for n in o["rounds"]:
                inserted_ids_by_round.setdefault(n, []).append(row["id"])

    by_id = {h.id: h for h in hypotheses}
    for up in result.hypothesis_updates:
        h = by_id.get(up["hypothesis_id"])
        if h is None:
            continue
        evidence = h.evidence + [oid for n in up["rounds"] for oid in inserted_ids_by_round.get(n, [])]
        await _db(lambda: admin_client.table("profile_hypotheses")
                  .update({"status": up["status"], "evidence_observation_ids": sorted(set(evidence))})
                  .eq("id", h.id).eq("user_id", user_id).execute())

    cost = await _record_cost(admin_client, user_id, "PROFILE_OBSERVE", billing, {"thread_id": thread_id})
    return len(result.observations), cost


# =========================================================
# 🧱 まとめ役(ユーザーごと) + 表紙
# =========================================================

async def consolidate_user_task(user_id: str) -> dict:
    """まだまとめ役に渡していない観察をまとめ、2層・覚え書き・仮説を更新する。続けて必要なら表紙も書き直す。"""
    admin_client = get_supabase_client()
    new_rows = (await _db(lambda: admin_client.table("profile_observations").select(_OBS_COLUMNS)
                          .eq("user_id", user_id).is_("deleted_at", "null").is_("consolidated_at", "null")
                          .neq("status", "discounted").order("created_at").limit(CONSOLIDATE_MAX_NEW).execute())).data or []
    if not new_rows:
        return {"status": "skipped", "reason": "no_new_observations"}
    new_obs = [_obs_from_row(r) for r in new_rows]
    today = _today()

    related = await _related_observations(admin_client, user_id, new_obs)
    items = await _items_for_consolidation(admin_client, user_id, new_obs)
    rejected = await _rejected_items(admin_client, user_id)
    memos = await _active_memos(admin_client, user_id, today)
    inp = ConsolidationInput(
        today=today,
        language=await _user_language(admin_client, user_id),
        new_observations=new_obs,
        related_observations=related,
        categories=await _categories(admin_client, user_id),
        items=items,
        rejected_items=rejected,
        memos=memos,
        hypotheses=await _open_hypotheses(admin_client, user_id),
        blocked_areas=await _blocked_areas(admin_client, user_id),
    )

    billing = BillingEngine(task_type="PROFILE_CONSOLIDATE")
    plan = await consolidate(UnifiedLLM(billing), inp)
    obs_by_id = {o.id: o for o in new_obs + related}
    guard = await guard_against_rejected(plan, rejected, obs_by_id, lambda texts: _embed_documents(texts, billing))
    changes = await _apply_plan(admin_client, user_id, plan, obs_by_id, billing, today)

    consolidated_ids = [o.id for o in new_obs]
    await _db(lambda: admin_client.table("profile_observations").update({"consolidated_at": _now_iso()})
              .in_("id", consolidated_ids).execute())
    state = await _bump_state(admin_client, user_id, changes)
    cost = await _record_cost(admin_client, user_id, "PROFILE_CONSOLIDATE", billing,
                              {"new_observations": len(new_obs), "item_changes": changes,
                               "dropped": [d["reason"] for d in plan.dropped],
                               "rejected_guard_blocked": sum(1 for g in guard if g["blocked"])})
    print(f"🧱 [profile-consolidate] user={user_id} new={len(new_obs)} related={len(related)} "
          f"creates={len(plan.item_creates)} updates={len(plan.item_updates)} dropped={len(plan.dropped)} cost=${cost:.6f}")

    cover = None
    if state["items_changed_since_cover"] >= COVER_MIN_CHANGES or (changes > 0 and await _cover_has_empty_field(admin_client, user_id)):
        cover = await write_cover_task(user_id)
    return {"status": "success", "item_changes": changes, "cover": cover}


async def _related_observations(admin_client, user_id: str, new_obs: list[Observation]) -> list[Observation]:
    """新しい観察それぞれに、惹かれた点(hook)が近い過去の観察を集める。"""
    new_ids = [o.id for o in new_obs]
    best: dict[str, float] = {}
    for o in new_obs:
        if o.embedding is None:
            continue
        res = await _db(lambda: admin_client.rpc("match_profile_observations", {
            "p_user_id": user_id, "query_embedding": o.embedding,
            "match_count": RELATED_PER_NEW, "exclude_ids": new_ids,
        }).execute())
        for r in res.data or []:
            best[r["id"]] = max(best.get(r["id"], -1.0), r["similarity"])
    picked = [oid for oid, _ in sorted(best.items(), key=lambda kv: kv[1], reverse=True)[:RELATED_MAX_TOTAL]]
    if not picked:
        return []
    rows = (await _db(lambda: admin_client.table("profile_observations").select(_OBS_COLUMNS)
                      .in_("id", picked).execute())).data or []
    return sorted((_obs_from_row(r) for r in rows), key=lambda o: (o.observed_at, o.id))


async def _evidence_map(admin_client, item_ids: list[str]) -> dict[str, list[str]]:
    if not item_ids:
        return {}
    res = await _db(lambda: admin_client.table("profile_item_evidence").select("item_id, observation_id")
                    .in_("item_id", item_ids).execute())
    out: dict[str, list[str]] = {}
    for r in res.data or []:
        out.setdefault(r["item_id"], []).append(r["observation_id"])
    return out


async def _items_for_consolidation(admin_client, user_id: str, new_obs: list[Observation]) -> list[Item]:
    """傾向は全部(上限つき)、記録は新しい観察に近いものだけ。確認待ちも含める(重複を作らせないため)。"""
    traits = (await _db(lambda: admin_client.table("profile_items").select(_ITEM_COLUMNS)
                        .eq("user_id", user_id).eq("kind", "trait").in_("status", ["active", "pending_confirm"])
                        .order("last_seen_at", desc=True).limit(TRAITS_MAX).execute())).data or []
    record_ids: dict[str, float] = {}
    for o in new_obs:
        if o.embedding is None:
            continue
        res = await _db(lambda: admin_client.rpc("match_profile_items", {
            "p_user_id": user_id, "query_embedding": o.embedding, "match_count": RECORDS_PER_NEW, "p_kind": "record",
        }).execute())
        for r in res.data or []:
            record_ids[r["id"]] = max(record_ids.get(r["id"], -1.0), r["similarity"])
    picked = [i for i, _ in sorted(record_ids.items(), key=lambda kv: kv[1], reverse=True)[:RECORDS_MAX_TOTAL]]
    records = []
    if picked:
        records = (await _db(lambda: admin_client.table("profile_items").select(_ITEM_COLUMNS)
                             .in_("id", picked).execute())).data or []
    rows = traits + records
    evidence = await _evidence_map(admin_client, [r["id"] for r in rows])
    return [_item_from_row(r, evidence.get(r["id"], [])) for r in rows]


async def _rejected_items(admin_client, user_id: str) -> list[Item]:
    rows = (await _db(lambda: admin_client.table("profile_items").select(_ITEM_COLUMNS)
                      .eq("user_id", user_id).eq("status", "rejected")
                      .order("rejected_at", desc=True).limit(REJECTED_MAX).execute())).data or []
    return [_item_from_row(r, []) for r in rows]


async def _active_memos(admin_client, user_id: str, today: str) -> list[Memo]:
    rows = (await _db(lambda: admin_client.table("ai_memos")
                      .select("id, kind, content, expires_at, evidence_observation_ids, created_at")
                      .eq("user_id", user_id).order("created_at").execute())).data or []
    memos = [Memo(id=r["id"], kind=r["kind"], content=r["content"], expires_at=r.get("expires_at"),
                  evidence=list(r.get("evidence_observation_ids") or []), created_at=r["created_at"][:10]) for r in rows]
    return [m for m in memos if m.is_active(today)]


async def _apply_plan(admin_client, user_id: str, plan: ConsolidationPlan, obs_by_id: dict[str, Observation],
                      billing: BillingEngine, today: str) -> int:
    """計画をテーブルに反映する。戻り値は「表紙の書き直しの判断に数える」項目の変化の数。"""
    changes = 0

    ref_to_cat: dict[str, str] = {}
    for c in plan.new_categories:
        parent = c["parent_id"] or (ref_to_cat.get(c["parent_ref"]) if c["parent_ref"] else None)
        res = await _db(lambda: admin_client.table("profile_categories").insert({
            "user_id": user_id, "name": c["name"], "description": c["description"], "kind": c["kind"],
            "parent_id": parent,
        }).execute())
        ref_to_cat[c["ref"]] = res.data[0]["id"]

    def seen_range(obs_ids: list[str]) -> tuple[str, str]:
        dates = sorted(obs_by_id[e].observed_at for e in obs_ids if e in obs_by_id)
        return (dates[0], dates[-1]) if dates else (today, today)

    used: set[str] = set()

    creates = [c for c in plan.item_creates if c.get("category_id") or ref_to_cat.get(c.get("category_ref"))]
    vectors = await _embed_documents([_item_embedding_input(c["content"]) for c in creates], billing)
    for c, vec in zip(creates, vectors):
        first, last = seen_range(c["evidence"])
        res = await _db(lambda: admin_client.table("profile_items").insert({
            "user_id": user_id,
            "category_id": c.get("category_id") or ref_to_cat[c["category_ref"]],
            "kind": c["kind"], "content": c["content"], "origin": "ai", "status": c["status"],
            "sensitive": c["sensitive"], "first_seen_at": first, "last_seen_at": last, "occurred_at": c["occurred_at"],
            "embedding": vec, "embedding_model": KNOWLEDGE_EMBEDDING_MODEL,
        }).execute())
        item_id = res.data[0]["id"]
        await _insert_evidence(admin_client, user_id, item_id, c["evidence"])
        used.update(c["evidence"])
        changes += 1

    for u in plan.item_updates:
        row = (await _db(lambda: admin_client.table("profile_items").select("id, content, origin, last_seen_at")
                         .eq("id", u["item_id"]).eq("user_id", user_id).maybe_single().execute()))
        item = row.data if row else None
        if not item:
            continue
        update: dict[str, Any] = {}
        if u["content"] is not None and item["origin"] == "ai":
            await _db(lambda: admin_client.table("profile_item_versions").insert({
                "item_id": item["id"], "user_id": user_id, "content": item["content"], "origin": item["origin"],
            }).execute())
            update["content"] = u["content"]
            update["embedding"] = (await _embed_documents([_item_embedding_input(u["content"])], billing))[0]
            # 書き直した文は新しい印を出し直す
            update["seen_by_user_at"] = None
            changes += 1
        if u["add_evidence"]:
            await _insert_evidence(admin_client, user_id, item["id"], u["add_evidence"])
            used.update(u["add_evidence"])
            _, last = seen_range(u["add_evidence"])
            if not item.get("last_seen_at") or last > item["last_seen_at"]:
                update["last_seen_at"] = last
        if update:
            await _db(lambda: admin_client.table("profile_items").update(update).eq("id", item["id"]).execute())

    if plan.item_archives:
        await _db(lambda: admin_client.table("profile_items").update({"status": "archived"})
                  .in_("id", plan.item_archives).eq("user_id", user_id).eq("origin", "ai").execute())

    if used:
        await _db(lambda: admin_client.table("profile_observations").update({"status": "used"})
                  .in_("id", sorted(used)).eq("status", "open").execute())

    for m in plan.memo_creates:
        await _db(lambda: admin_client.table("ai_memos").insert({
            "user_id": user_id, "kind": m["kind"], "content": m["content"], "expires_at": m["expires_at"],
            "evidence_observation_ids": m["evidence"],
        }).execute())
    for m in plan.memo_updates:
        await _db(lambda: admin_client.table("ai_memos").update({
            "content": m["content"], "expires_at": m["expires_at"],
        }).eq("id", m["memo_id"]).eq("user_id", user_id).execute())
    if plan.memo_removes:
        await _db(lambda: admin_client.table("ai_memos").delete().in_("id", plan.memo_removes).eq("user_id", user_id).execute())

    for h in plan.hypothesis_creates:
        await _db(lambda: admin_client.table("profile_hypotheses").insert({
            "user_id": user_id, "content": h["content"], "evidence_observation_ids": h["evidence"],
        }).execute())
    for h in plan.hypothesis_closes:
        await _db(lambda: admin_client.table("profile_hypotheses").update({"status": h["status"]})
                  .eq("id", h["hypothesis_id"]).eq("user_id", user_id).execute())

    return changes


async def _insert_evidence(admin_client, user_id: str, item_id: str, obs_ids: list[str]) -> None:
    if not obs_ids:
        return
    await _db(lambda: admin_client.table("profile_item_evidence").upsert(
        [{"item_id": item_id, "observation_id": oid, "user_id": user_id} for oid in obs_ids],
        on_conflict="item_id,observation_id", ignore_duplicates=True,
    ).execute())


async def _bump_state(admin_client, user_id: str, changes: int) -> dict:
    res = await _db(lambda: admin_client.table("profile_extraction_state").select("*").eq("user_id", user_id).maybe_single().execute())
    current = (res.data if res else None) or {"items_changed_since_cover": 0}
    state = {
        "user_id": user_id,
        "last_consolidated_at": _now_iso(),
        "items_changed_since_cover": (current.get("items_changed_since_cover") or 0) + changes,
    }
    await _db(lambda: admin_client.table("profile_extraction_state").upsert(state, on_conflict="user_id").execute())
    return state


async def _cover_has_empty_field(admin_client, user_id: str) -> bool:
    res = await _db(lambda: admin_client.table("user_profiles").select("bio, interests, future_goals")
                    .eq("id", user_id).maybe_single().execute())
    row = (res.data if res else None) or {}
    return any(not (row.get(f) or "").strip() for f in COVER_FIELDS)


async def _items_removed_since_cover(admin_client, user_id: str) -> list[Item]:
    """前回表紙を書いた後に外れた項目。表紙をまだ書いていなければ、消す文も無いので空。"""
    res = await _db(lambda: admin_client.table("profile_extraction_state").select("last_cover_at")
                    .eq("user_id", user_id).maybe_single().execute())
    last_cover_at = ((res.data if res else None) or {}).get("last_cover_at")
    if not last_cover_at:
        return []
    rows = (await _db(lambda: admin_client.table("profile_items").select(_ITEM_COLUMNS)
                      .eq("user_id", user_id).in_("status", ["rejected", "archived", "orphaned"])
                      .gt("updated_at", last_cover_at).order("updated_at", desc=True).limit(REJECTED_MAX).execute())).data or []
    return [_item_from_row(r, []) for r in rows]


async def write_cover_task(user_id: str) -> dict:
    """
    表紙(1層)を、今の文を土台に書き足す。空欄とAIが書いたままの欄はそのまま書き込み、本人が書いた・直した欄は書き直し案にする。
    書き込みは「書き手が読んだときのまま」の条件つきで行う(その間に本人が編集していたら上書きしない)。
    前回の表紙の後に外れた項目(違う / もう当てはまらない / 根拠の会話が消えた)も渡す。書き足し型では、
    これが表紙から文を消してよい理由になる。
    """
    admin_client = get_supabase_client()
    res = await _db(lambda: admin_client.table("user_profiles")
                    .select("bio, interests, future_goals, bio_written_by, interests_written_by, future_goals_written_by")
                    .eq("id", user_id).maybe_single().execute())
    row = res.data if res else None
    if row is None:
        return {"status": "skipped", "reason": "no_profile"}
    cover = {f: {"text": (row.get(f) or "").strip() or None, "origin": row.get(f"{f}_written_by")} for f in COVER_FIELDS}

    item_rows = (await _db(lambda: admin_client.table("profile_items").select(_ITEM_COLUMNS)
                           .eq("user_id", user_id).eq("status", "active")
                           .order("last_seen_at", desc=True).limit(TRAITS_MAX + RECORDS_MAX_TOTAL).execute())).data or []
    items = [_item_from_row(r, []) for r in item_rows]
    if not items:
        return {"status": "skipped", "reason": "no_items"}

    removed = await _items_removed_since_cover(admin_client, user_id)

    billing = BillingEngine(task_type="PROFILE_COVER")
    plan = await write_cover(UnifiedLLM(billing), cover, items, await _categories(admin_client, user_id),
                             await _user_language(admin_client, user_id), removed_items=removed)

    applied = []
    for field, text in plan.applied.items():
        q = admin_client.table("user_profiles").update({field: text, f"{field}_written_by": "ai"}).eq("id", user_id)
        before = cover[field]
        q = q.eq(f"{field}_written_by", before["origin"]) if before["origin"] else q.is_(f"{field}_written_by", "null")
        r = await _db(lambda: q.execute())
        if r.data:
            applied.append(field)
    for field, text in plan.proposals.items():
        await _db(lambda: admin_client.table("profile_cover_proposals").update({"status": "superseded", "decided_at": _now_iso()})
                  .eq("user_id", user_id).eq("field", field).eq("status", "pending").execute())
        await _db(lambda: admin_client.table("profile_cover_proposals").insert({
            "user_id": user_id, "field": field, "proposed_text": text,
        }).execute())

    await _db(lambda: admin_client.table("profile_extraction_state").upsert({
        "user_id": user_id, "items_changed_since_cover": 0, "last_cover_at": _now_iso(),
    }, on_conflict="user_id").execute())
    cost = await _record_cost(admin_client, user_id, "PROFILE_COVER", billing,
                              {"applied": applied, "proposals": list(plan.proposals), "removed_items": len(removed)})
    print(f"📇 [profile-cover] user={user_id} applied={applied} proposals={list(plan.proposals)} cost=${cost:.6f}")
    return {"applied": applied, "proposals": list(plan.proposals)}


# =========================================================
# 🙋 本人の操作(APIから呼ぶ。すべて本人の行であることを確かめてから行う)
# =========================================================

class ProfileItemNotFound(Exception):
    pass


async def _own_item(admin_client, user_id: str, item_id: str, statuses: tuple[str, ...]) -> dict:
    res = await _db(lambda: admin_client.table("profile_items").select("id, content, origin, status, sensitive")
                    .eq("id", item_id).eq("user_id", user_id).maybe_single().execute())
    row = res.data if res else None
    if not row or row["status"] not in statuses:
        raise ProfileItemNotFound(item_id)
    return row


async def reject_item(user_id: str, item_id: str, reason: Optional[str]) -> None:
    """違う: 文は残して rejected にし(同じ意味のものを作り直させないため)、根拠の観察はもう数えない。"""
    admin_client = get_supabase_client()
    await _own_item(admin_client, user_id, item_id, ("active", "pending_confirm"))
    evidence = (await _evidence_map(admin_client, [item_id])).get(item_id, [])
    await _db(lambda: admin_client.table("profile_items").update({
        "status": "rejected", "rejected_at": _today(), "rejected_reason": (reason or "").strip()[:500] or None,
    }).eq("id", item_id).execute())
    if evidence:
        await _db(lambda: admin_client.table("profile_observations").update({"status": "discounted"})
                  .in_("id", evidence).eq("user_id", user_id).execute())


async def edit_item(user_id: str, item_id: str, content: str) -> None:
    """直す: 本人の文にする(以後AIは文を書き換えず、根拠の追加だけする)。"""
    admin_client = get_supabase_client()
    row = await _own_item(admin_client, user_id, item_id, ("active",))
    content = content.strip()
    if not content or content == row["content"]:
        return
    await _db(lambda: admin_client.table("profile_item_versions").insert({
        "item_id": item_id, "user_id": user_id, "content": row["content"], "origin": row["origin"],
    }).execute())
    vector = (await _embed_documents([_item_embedding_input(content)]))[0]
    await _db(lambda: admin_client.table("profile_items").update({
        "content": content, "origin": "user", "embedding": vector, "seen_by_user_at": _now_iso(),
    }).eq("id", item_id).execute())


async def discard_item(user_id: str, item_id: str) -> Optional[str]:
    """
    残したくない(確認トレイの「残さない」も同じ): 中身を消し、根拠の観察も消す。
    センシティブな項目なら分野だけを覚え、その分野の観察もすべて消す(以後、観察役もまとめ役も書かない)。
    中身を「書かないこと」として残すと、その情報を持ち続けることになるので残さない。
    戻り値はブロックした分野(あれば)。
    """
    admin_client = get_supabase_client()
    row = await _own_item(admin_client, user_id, item_id, ("active", "pending_confirm"))
    evidence = (await _evidence_map(admin_client, [item_id])).get(item_id, [])
    area = row["sensitive"] if row["sensitive"] != "none" else None

    await _db(lambda: admin_client.table("profile_items").delete().eq("id", item_id).execute())
    if evidence:
        await _db(lambda: admin_client.table("profile_observations").delete().in_("id", evidence).eq("user_id", user_id).execute())
    if area:
        await _db(lambda: admin_client.table("profile_blocked_areas").upsert(
            {"user_id": user_id, "area": area}, on_conflict="user_id,area", ignore_duplicates=True).execute())
        await _db(lambda: admin_client.table("profile_observations").delete().eq("user_id", user_id).eq("sensitive", area).execute())
        # 同じ分野の確認待ちも消す。本人が確認トレイで「残す」と決めた項目(active)は本人の判断なので残す
        await _db(lambda: admin_client.table("profile_items").delete().eq("user_id", user_id).eq("sensitive", area)
                  .eq("status", "pending_confirm").execute())
    return area


async def keep_pending_item(user_id: str, item_id: str) -> None:
    """確認トレイの「残す」。"""
    admin_client = get_supabase_client()
    await _own_item(admin_client, user_id, item_id, ("pending_confirm",))
    await _db(lambda: admin_client.table("profile_items").update({"status": "active", "seen_by_user_at": _now_iso()})
              .eq("id", item_id).execute())


async def mark_items_seen(user_id: str, item_ids: list[str]) -> None:
    if not item_ids:
        return
    admin_client = get_supabase_client()
    await _db(lambda: admin_client.table("profile_items").update({"seen_by_user_at": _now_iso()})
              .in_("id", item_ids).eq("user_id", user_id).is_("seen_by_user_at", "null").execute())


async def delete_memo(user_id: str, memo_id: str) -> bool:
    admin_client = get_supabase_client()
    res = await _db(lambda: admin_client.table("ai_memos").delete().eq("id", memo_id).eq("user_id", user_id).execute())
    return bool(res.data)


async def forget_ai_notes(user_id: str) -> None:
    """
    AIのメモを全部消す: 観察メモ(4層)と仮説を消す。本人に見えている自分像(2層)と覚え書きは残す
    (それぞれ画面で個別に消せる)。観察を消すと項目の根拠のつながりも消えるが、項目自体は残る。
    """
    admin_client = get_supabase_client()
    await _db(lambda: admin_client.table("profile_observations").delete().eq("user_id", user_id).execute())
    await _db(lambda: admin_client.table("profile_hypotheses").delete().eq("user_id", user_id).execute())


async def decide_cover_proposal(user_id: str, proposal_id: str, accept: bool) -> bool:
    admin_client = get_supabase_client()
    res = await _db(lambda: admin_client.table("profile_cover_proposals").select("id, field, proposed_text, status")
                    .eq("id", proposal_id).eq("user_id", user_id).maybe_single().execute())
    row = res.data if res else None
    if not row or row["status"] != "pending":
        return False
    if accept:
        # 本人が受け入れた文は本人のもの(以後も自動では書き換えない)
        await _db(lambda: admin_client.table("user_profiles").update({
            row["field"]: row["proposed_text"], f"{row['field']}_written_by": "user",
        }).eq("id", user_id).execute())
    await _db(lambda: admin_client.table("profile_cover_proposals").update({
        "status": "accepted" if accept else "rejected", "decided_at": _now_iso(),
    }).eq("id", proposal_id).execute())
    return True


# =========================================================
# 🗑️ スレッドの削除に合わせる
# =========================================================

async def on_thread_deleted(user_id: str, thread_id: str) -> int:
    """
    スレッドの論理削除に合わせて、そのスレッドの観察も論理削除する。根拠が全部消えたAI由来の項目は
    orphaned にする(どこにも使わない)。本人が書いた・直した項目は残す。
    戻り値は orphaned にした項目の数。
    """
    admin_client = get_supabase_client()
    now_iso = _now_iso()
    res = await _db(lambda: admin_client.table("profile_observations").update({"deleted_at": now_iso})
                    .eq("thread_id", thread_id).eq("user_id", user_id).is_("deleted_at", "null").execute())
    deleted_ids = [r["id"] for r in res.data or []]
    if not deleted_ids:
        return 0
    links = (await _db(lambda: admin_client.table("profile_item_evidence").select("item_id")
                       .in_("observation_id", deleted_ids).execute())).data or []
    item_ids = sorted({r["item_id"] for r in links})
    orphaned = 0
    for item_id in item_ids:
        ev = (await _evidence_map(admin_client, [item_id])).get(item_id, [])
        live = (await _db(lambda: admin_client.table("profile_observations").select("id")
                          .in_("id", ev).is_("deleted_at", "null").limit(1).execute())).data or []
        if live:
            continue
        r = await _db(lambda: admin_client.table("profile_items").update({"status": "orphaned"})
                      .eq("id", item_id).eq("origin", "ai").in_("status", ["active", "pending_confirm"]).execute())
        orphaned += len(r.data or [])
    return orphaned


# =========================================================
# 💬 チャットに渡すもの(回答役のキャッシュされる先頭に置く)
# =========================================================

MEMOS_FOR_CHAT_MAX = 8
HYPOTHESES_FOR_CHAT_MAX = 3


def load_chat_memory(admin_client, user_id: str) -> tuple[list[dict], list[str]]:
    """
    (有効な覚え書き, 開いている仮説)。同期関数(chat_serviceの他の読み込みと同じくto_threadで呼ぶ)。
    覚え書きは新しい方から渡す(古い順に切ると、上限に達した後の新しい覚え書きがチャットに届かなくなる)。
    """
    today = date.today().isoformat()
    memos = admin_client.table("ai_memos").select("kind, content, expires_at") \
        .eq("user_id", user_id).order("created_at", desc=True).execute().data or []
    memos = [m for m in memos if not m.get("expires_at") or m["expires_at"] >= today][:MEMOS_FOR_CHAT_MAX]
    hyps = admin_client.table("profile_hypotheses").select("content") \
        .eq("user_id", user_id).eq("status", "open").order("created_at", desc=True) \
        .limit(HYPOTHESES_FOR_CHAT_MAX).execute().data or []
    return memos, [h["content"] for h in hyps]


# =========================================================
# 🪞 画面用の読み出し(webappの /account/profile とAIチャット設定)
# 根拠のつながりと観察メモには本人向けのRLSを置いていないので、組み立てはバックエンドで行う
# =========================================================

RECENT_DAYS = 14
RECENT_MAX = 3


def _thread_titles(admin_client, thread_ids: list[str]) -> dict[str, str]:
    if not thread_ids:
        return {}
    rows = admin_client.table("chat_threads").select("id, title").in_("id", thread_ids).execute().data or []
    return {r["id"]: r.get("title") or "" for r in rows}


def self_portrait(user_id: str) -> dict:
    """自分像ページに必要なものを一度に返す(同期関数。APIからto_threadで呼ぶ)。"""
    admin_client = get_supabase_client()
    prof = admin_client.table("user_profiles") \
        .select("bio, interests, future_goals, bio_written_by, interests_written_by, future_goals_written_by") \
        .eq("id", user_id).maybe_single().execute()
    p = (prof.data if prof else None) or {}
    cover = {f: {"text": p.get(f), "written_by": p.get(f"{f}_written_by")} for f in COVER_FIELDS}

    proposals = admin_client.table("profile_cover_proposals").select("id, field, proposed_text, created_at") \
        .eq("user_id", user_id).eq("status", "pending").order("created_at").execute().data or []
    categories = admin_client.table("profile_categories").select("id, name, description, kind, parent_id") \
        .eq("user_id", user_id).is_("merged_into", "null").order("created_at").execute().data or []
    items = admin_client.table("profile_items") \
        .select("id, category_id, kind, content, origin, status, sensitive, first_seen_at, last_seen_at, occurred_at, "
                "seen_by_user_at, created_at") \
        .eq("user_id", user_id).in_("status", ["active", "pending_confirm"]).execute().data or []
    item_ids = [it["id"] for it in items]

    evidence_rows = []
    versions = []
    if item_ids:
        evidence_rows = admin_client.table("profile_item_evidence").select("item_id, observation_id") \
            .in_("item_id", item_ids).execute().data or []
        versions = admin_client.table("profile_item_versions").select("item_id, replaced_at") \
            .in_("item_id", item_ids).execute().data or []
    obs_ids = sorted({r["observation_id"] for r in evidence_rows})
    obs = {}
    if obs_ids:
        for r in admin_client.table("profile_observations").select("id, thread_id, topic, quote, observed_at") \
                .in_("id", obs_ids).is_("deleted_at", "null").execute().data or []:
            obs[r["id"]] = r

    ev_by_item: dict[str, list[dict]] = {}
    for r in evidence_rows:
        o = obs.get(r["observation_id"])
        if o:
            ev_by_item.setdefault(r["item_id"], []).append(o)
    last_rewrite: dict[str, str] = {}
    for v in versions:
        if v["replaced_at"] > last_rewrite.get(v["item_id"], ""):
            last_rewrite[v["item_id"]] = v["replaced_at"]

    out_items = []
    for it in items:
        ev = ev_by_item.get(it["id"], [])
        changed_at = max(it["created_at"], last_rewrite.get(it["id"], ""))
        out_items.append({
            "id": it["id"], "category_id": it["category_id"], "kind": it["kind"], "content": it["content"],
            "origin": it["origin"], "status": it["status"], "sensitive": it["sensitive"],
            "first_seen_at": it["first_seen_at"], "last_seen_at": it["last_seen_at"], "occurred_at": it["occurred_at"],
            "is_new": it["seen_by_user_at"] is None,
            "changed_at": changed_at,
            "evidence_threads": len({o["thread_id"] for o in ev}),
        })

    cutoff = (datetime.now(timezone.utc) - timedelta(days=RECENT_DAYS)).isoformat()
    recent_candidates = sorted(
        (i for i in out_items if i["status"] == "active" and i["kind"] == "trait" and i["changed_at"] >= cutoff),
        key=lambda i: i["changed_at"], reverse=True,
    )[:RECENT_MAX]
    recent = []
    for i in recent_candidates:
        ev = sorted(ev_by_item.get(i["id"], []), key=lambda o: o["observed_at"])
        # 「つながった話」は別々の会話から来たときだけ出す(1つの会話の中の話題を並べても、束ねた理由にならない)
        topic_by_thread: dict[str, str] = {}
        for o in ev:
            t = (o.get("topic") or "").strip()
            if t and o["thread_id"] not in topic_by_thread:
                topic_by_thread[o["thread_id"]] = t
        topics = list(topic_by_thread.values())
        quote = next((o["quote"] for o in reversed(ev) if o.get("quote")), None)
        recent.append({"item_id": i["id"], "topics": topics[:3] if len(topics) >= 2 else [], "quote": quote})

    return {
        "cover": cover,
        "proposals": proposals,
        "categories": categories,
        "items": out_items,
        "recent": recent,
    }


def item_detail(user_id: str, item_id: str) -> Optional[dict]:
    """項目を開いたとき: 根拠になった会話(本人の言葉)と、書き直しの履歴。"""
    admin_client = get_supabase_client()
    res = admin_client.table("profile_items").select("id, content, origin, status, kind, created_at") \
        .eq("id", item_id).eq("user_id", user_id).maybe_single().execute()
    item = res.data if res else None
    if not item or item["status"] not in ("active", "pending_confirm"):
        return None
    links = admin_client.table("profile_item_evidence").select("observation_id").eq("item_id", item_id).execute().data or []
    evidence = []
    if links:
        rows = admin_client.table("profile_observations").select("id, thread_id, note, quote, observed_at") \
            .in_("id", [r["observation_id"] for r in links]).is_("deleted_at", "null") \
            .order("observed_at").execute().data or []
        titles = _thread_titles(admin_client, sorted({r["thread_id"] for r in rows}))
        evidence = [{"observation_id": r["id"], "thread_id": r["thread_id"], "thread_title": titles.get(r["thread_id"], ""),
                     "note": r["note"], "quote": r.get("quote"), "observed_at": r["observed_at"]} for r in rows]
    versions = admin_client.table("profile_item_versions").select("content, origin, replaced_at") \
        .eq("item_id", item_id).order("replaced_at", desc=True).execute().data or []
    return {"item": item, "evidence": evidence, "versions": versions}


def ai_memory(user_id: str) -> dict:
    """AIチャット設定: 覚え書き(有効なもの)と、会話ごとにまとめた観察メモ。仮説は見せない。"""
    admin_client = get_supabase_client()
    today = date.today().isoformat()
    memos = admin_client.table("ai_memos").select("id, kind, content, expires_at, created_at") \
        .eq("user_id", user_id).order("created_at").execute().data or []
    memos = [m for m in memos if not m.get("expires_at") or m["expires_at"] >= today]
    rows = admin_client.table("profile_observations").select("id, thread_id, note, observed_at") \
        .eq("user_id", user_id).is_("deleted_at", "null").order("observed_at", desc=True) \
        .order("created_at").execute().data or []
    titles = _thread_titles(admin_client, sorted({r["thread_id"] for r in rows}))
    groups: dict[str, dict] = {}
    for r in rows:
        g = groups.setdefault(r["thread_id"], {"thread_id": r["thread_id"], "thread_title": titles.get(r["thread_id"], ""),
                                                "last_observed_at": r["observed_at"], "observations": []})
        g["observations"].append({"id": r["id"], "note": r["note"], "observed_at": r["observed_at"]})
    return {"memos": memos, "observation_groups": list(groups.values()), "observation_count": len(rows)}


async def delete_observation(user_id: str, observation_id: str) -> bool:
    """
    AIのメモを1件消す。根拠のつながりも消えるが、項目そのものは残す(本人が見えているものは、
    本人が画面で個別に消す)。
    """
    admin_client = get_supabase_client()
    res = await _db(lambda: admin_client.table("profile_observations").delete()
                    .eq("id", observation_id).eq("user_id", user_id).execute())
    return bool(res.data)
