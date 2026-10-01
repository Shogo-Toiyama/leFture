import os
import asyncio
import requests
from typing import Any, Dict, List
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine

BRAVE_LLM_CONTEXT_URL = "https://api.search.brave.com/res/v1/llm/context"


async def brave_search(query: str, billing: BillingEngine, timeout: float = 15) -> List[Dict[str, Any]]:
    """
    Braveに1クエリ投げて、ページごとに {title, url, snippets} を返す(Fun Factとチャットで共有)。
    LLM Context APIなので、Brave側でHTML除去・関連する断片の抽出まで済んでいる(追加の通信は不要)。
    失敗(キーが無い・通信・HTTPエラー)は例外のまま返す。止めるかどうかは呼び出し側の方針。
    課金は成功した検索1回ごとに記録する。
    """
    api_key = os.getenv("BRAVE_API_KEY")
    if not api_key:
        raise RuntimeError("BRAVE_API_KEY is missing")
    response = await asyncio.to_thread(
        requests.get,
        BRAVE_LLM_CONTEXT_URL,
        headers={"X-Subscription-Token": api_key},
        params={"q": query},
        timeout=timeout,
    )
    response.raise_for_status()
    data = response.json()
    billing.add_count_cost("brave/llm_context", 1, note=f"Search query: {query}")
    return [
        {"title": page.get("title") or "", "url": page.get("url") or "", "snippets": page.get("snippets") or []}
        for page in data.get("grounding", {}).get("generic", [])
    ]


class WebSearchService:
    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.logger = logger
        self.billing = billing
        self.api_key = os.getenv("BRAVE_API_KEY")

    async def run(self, fun_fact_seed: Dict[str, Any]) -> List[Dict[str, Any]]:
        self.logger.log("   [Logic] Starting Web Search via Brave")

        if not self.api_key:
            self.logger.log("   [Logic] ⚠️ BRAVE_API_KEY is missing. Skipping search.")
            return []

        needs_search = fun_fact_seed.get("needs_web_search", False)
        queries = fun_fact_seed.get("search_queries", [])

        if not needs_search or not queries:
            self.logger.log("   [Logic] No search needed for this Fun Fact.")
            return []

        search_results = []
        for q in queries:
            try:
                self.logger.log(f"   [Logic] Searching for: '{q}'")
                pages = await brave_search(q, self.billing)
                # 結果を格納 (タイトル、URL、内容の断片)
                for page in pages:
                    search_results.append({
                        "query": q,
                        "title": page["title"],
                        "url": page["url"],
                        "content": "\n".join(page["snippets"]),
                    })
            except Exception as e:
                # 💡 「検索が失敗しても止めない」ポリシー
                self.logger.log(f"   [Logic] ⚠️ Brave Search failed for '{q}': {e}")
                continue

        self.logger.log(f"   [Logic] Web Search finished. Found {len(search_results)} snippets.")
        return search_results
