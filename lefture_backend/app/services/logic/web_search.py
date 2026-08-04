import os
import asyncio
import requests
from typing import Any, Dict, List
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine

BRAVE_LLM_CONTEXT_URL = "https://api.search.brave.com/res/v1/llm/context"

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
                # LLM Context API: Brave側でHTML除去・関連チャンク抽出済みのテキストが返る
                response = await asyncio.to_thread(
                    requests.get,
                    BRAVE_LLM_CONTEXT_URL,
                    headers={"X-Subscription-Token": self.api_key},
                    params={"q": q},
                    timeout=15,
                )
                response.raise_for_status()
                data = response.json()

                # 検索1回ごとにコストを記録
                self.billing.add_count_cost("brave/llm_context", 1, note=f"Search query: {q}")

                # 結果を格納 (タイトル、URL、内容の断片)
                for page in data.get("grounding", {}).get("generic", []):
                    search_results.append({
                        "query": q,
                        "title": page.get("title"),
                        "url": page.get("url"),
                        "content": "\n".join(page.get("snippets") or []),
                    })
            except Exception as e:
                # 💡 「検索が失敗しても止めない」ポリシー
                self.logger.log(f"   [Logic] ⚠️ Brave Search failed for '{q}': {e}")
                continue

        self.logger.log(f"   [Logic] Web Search finished. Found {len(search_results)} snippets.")
        return search_results
