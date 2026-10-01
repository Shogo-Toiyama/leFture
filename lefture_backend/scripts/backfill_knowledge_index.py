#!/usr/bin/env python3
"""
横断チャットボット 段階0: knowledge_chunksへの初回バックフィル。

一度きりのローカル実行専用スクリプト。デプロイは不要(trigger_analysis.py
と同じ位置づけ)。既存の全コンテンツ(Review Card/Deep Notes/Keyword/
Announcement/Fun Fact/講義サマリー/トピック要約/トランスクリプト/
Lecture Moment)をknowledge_index_queueに積んでから、本番のpatrol/
FINALIZE_JOBと全く同じdrain_knowledge_index_queue()をこの場で繰り返し
呼んで消化する。本番と同じ処理経路を通るので、ここだけの特別なロジックは
「既存行をキューに積む」部分だけ。

使い方 (lefture_backend/ から実行):
    python scripts/backfill_knowledge_index.py --smoke-test
        まずこれで、Embedding APIのモデル名/次元数の疎通確認だけ行う。
        (GEMINI_API_KEYが.envに無い場合はCloud Run側の環境変数を
        一時的に.envにコピーしてから実行すること)

    python scripts/backfill_knowledge_index.py --user-id <uid>
        1ユーザーだけを対象に実施。本番の全ユーザー分をやる前の確認用。

    python scripts/backfill_knowledge_index.py
        全ユーザー分を対象に実施。件数が多い場合は時間がかかる
        (Embedding 2は $0.20/100万トークン、概算コストは実行前に
        件数から見積もること)。

    python scripts/backfill_knowledge_index.py --source-types transcript_topic
        種類を絞って積み直す。2026-09-30: 文字起こしのチャンクに文の範囲
        (metadata.sid_start / sid_end)を足したときに使う。本文は変えていないので
        content_hashが一致し、埋め込みAPIは呼ばれずmetadataだけ書き換わる(費用ゼロ)。

    途中で止めても安全: 再実行すると、まだ処理されていない分だけが
    再度キューに積まれ直す(content_hashが変わっていない行は埋め込み
    APIを呼ばずスキップされる)。
"""
import argparse
import asyncio
import os
import sys
import time

# lefture_backend/ をsys.pathに入れ、どこから実行してもapp.*をimportできるようにする
_BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _BACKEND_ROOT not in sys.path:
    sys.path.insert(0, _BACKEND_ROOT)

from dotenv import load_dotenv
load_dotenv(os.path.join(_BACKEND_ROOT, ".env"))

from app.core.supabase import get_supabase_client  # noqa: E402
from app.services.helpers.llm_unified import PRICE_MATRIX  # noqa: E402
from app.services.knowledge_index import (  # noqa: E402
    drain_knowledge_index_queue,
    embed_document,
    embed_queries,
    get_embedding_token_usage,
    reset_embedding_token_usage,
    ChunkDraft,
    KNOWLEDGE_EMBEDDING_MODEL,
    KNOWLEDGE_EMBEDDING_DIMENSIONS,
)

_EMBEDDING_PRICE_PER_1M = PRICE_MATRIX["tokens"][KNOWLEDGE_EMBEDDING_MODEL]["input"]


def _print_cost_so_far() -> None:
    tokens = get_embedding_token_usage()
    cost = (tokens / 1_000_000) * _EMBEDDING_PRICE_PER_1M
    print(f"   💰 ここまでの入力トークン合計: {tokens:,} 件 ≒ ${cost:.4f}（オンライン料金 ${_EMBEDDING_PRICE_PER_1M}/100万トークン換算、バッチなら半額目安）")

# (テーブル名, source_type) の一覧。lecture_topicsだけ1テーブルから
# topic_summary/transcript_topicの2種類のsource_typeを生む
# (knowledge_index.pyのビルダー側で使い分ける)。
SOURCE_TABLES = [
    ("review_cards", "review_card"),
    ("deep_notes", "deep_note"),
    ("keywords", "keyword"),
    ("announcements", "announcement"),
    ("fun_facts", "fun_fact"),
    ("lectures", "lecture_summary"),
    ("lecture_topics", "topic_summary"),
    ("lecture_topics", "transcript_topic"),
    ("lecture_moments", "lecture_moment"),
    ("chat_messages", "chat_turn"),
]

# chat_messagesは他のテーブルと違い、対象行がrole='assistant' AND status='complete'
# だけ(userの発言・生成中・断った/危機対応/失敗は積まない)。
EXTRA_FILTERS: dict[str, dict[str, str]] = {
    "chat_messages": {"role": "assistant", "status": "complete"},
}

PAGE_SIZE = 500


async def _smoke_test() -> None:
    print(f"モデル: {KNOWLEDGE_EMBEDDING_MODEL} / 次元数: {KNOWLEDGE_EMBEDDING_DIMENSIONS}")
    # 文書側・クエリ側の両方の前置き形式を1回ずつ通す
    doc = ChunkDraft(
        chunk_index=0,
        title="Smoke Test / Keyword",
        body="Photosynthesis: the process by which plants convert light into chemical energy.",
        user_id="00000000-0000-0000-0000-000000000000",
    )
    doc_vec = await embed_document(doc)
    query_vec = (await embed_queries(["光合成ってどういう意味？"]))[0]
    print(f"✅ 文書側: 長さ = {len(doc_vec)} / 先頭3要素: {doc_vec[:3]}")
    print(f"✅ クエリ側: 長さ = {len(query_vec)} / 先頭3要素: {query_vec[:3]}")
    # 日本語の質問と英語の文書が近いか(言語をまたぐ検索)の簡易確認
    import math
    dot = sum(a * b for a, b in zip(doc_vec, query_vec))
    norm = math.sqrt(sum(a * a for a in doc_vec)) * math.sqrt(sum(b * b for b in query_vec))
    print(f"   日本語の質問 × 英語の文書 のコサイン類似度: {dot / norm:.3f}")


def _enqueue_all(user_id: str | None, source_types: set[str] | None = None) -> int:
    admin_client = get_supabase_client()
    total_queued = 0

    for table, source_type in SOURCE_TABLES:
        if source_types and source_type not in source_types:
            continue
        offset = 0
        table_total = 0
        while True:
            query = admin_client.table(table).select("id").is_("deleted_at", "null")
            if user_id:
                query = query.eq("user_id", user_id)
            for col, val in EXTRA_FILTERS.get(table, {}).items():
                query = query.eq(col, val)
            page = query.range(offset, offset + PAGE_SIZE - 1).execute()
            rows = page.data or []
            if not rows:
                break

            queue_rows = [{"source_type": source_type, "source_id": r["id"]} for r in rows]
            try:
                admin_client.table("knowledge_index_queue").insert(queue_rows).execute()
            except Exception as e:
                # 再実行時、前回分がまだ処理待ちで残っている等でまとめ挿入が
                # 失敗することがある。1件ずつに切り替えて続行する。
                print(f"  ⚠️ 一括挿入に失敗、1件ずつ再試行します ({table}/{source_type}): {e}")
                for qr in queue_rows:
                    try:
                        admin_client.table("knowledge_index_queue").insert(qr).execute()
                    except Exception:
                        pass

            table_total += len(rows)
            total_queued += len(rows)

            if len(rows) < PAGE_SIZE:
                break
            offset += PAGE_SIZE

        print(f"  {table} ({source_type}): {table_total}件キューに追加")

    return total_queued


async def _drain_until_empty() -> None:
    reset_embedding_token_usage()
    total_succeeded = 0
    total_failed = 0
    while True:
        result = await drain_knowledge_index_queue(limit=200, concurrency=8)
        if result["claimed"] == 0:
            break
        total_succeeded += result["succeeded"]
        total_failed += result["failed"]
        print(
            f"  drain: claimed={result['claimed']} succeeded={result['succeeded']} "
            f"failed={result['failed']} (累計 succeeded={total_succeeded} failed={total_failed})"
        )
        _print_cost_so_far()
        # Embedding APIへの配慮と、ログを読みやすくするための小休止。
        # レート上限(10000 rpm)には遠く及ばないので、これは律儀さのため。
        time.sleep(0.2)

    print(f"完了。合計 succeeded={total_succeeded} failed={total_failed}")
    _print_cost_so_far()
    if total_failed:
        print(
            "⚠️ 失敗分はknowledge_index_queueにstatus='FAILED'で残っています。"
            "last_errorを確認して原因を直したら、このスクリプトをもう一度"
            "実行してください(status='FAILED'の行は自動再試行されないので、"
            "手動でstatus='PENDING'に戻すか、原因側の行を編集して"
            "トリガ経由で新しいPENDING行を作り直してください)。"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="knowledge_chunksの初回バックフィル")
    parser.add_argument("--user-id", help="このユーザーだけを対象にする(動作確認用)")
    parser.add_argument("--smoke-test", action="store_true", help="Embedding APIの疎通確認だけ行う")
    parser.add_argument(
        "--skip-enqueue",
        action="store_true",
        help="1.のenqueueを飛ばし、既にknowledge_index_queueにある分だけdrainする"
        "(前回の実行を中断した後の再開用。既存PENDING行への重複挿入で遅くなるのを避ける)",
    )
    parser.add_argument(
        "--source-types",
        help="カンマ区切り。指定した種類だけをキューに積む(例: transcript_topic)",
    )
    args = parser.parse_args()
    source_types = {t.strip() for t in args.source_types.split(",")} if args.source_types else None
    if source_types:
        unknown = source_types - {st for _, st in SOURCE_TABLES}
        if unknown:
            parser.error(f"unknown source types: {', '.join(sorted(unknown))}")

    if args.smoke_test:
        asyncio.run(_smoke_test())
        return

    if args.skip_enqueue:
        print("1. スキップ(--skip-enqueue)。既存のキューだけを処理します。")
    else:
        print("1. 既存コンテンツをknowledge_index_queueに積みます...")
        total_queued = _enqueue_all(args.user_id, source_types)
        print(f"   合計 {total_queued} 件をキューに追加しました。")

    print("2. キューを処理します(Embedding APIを呼び出します)...")
    asyncio.run(_drain_until_empty())


if __name__ == "__main__":
    main()
