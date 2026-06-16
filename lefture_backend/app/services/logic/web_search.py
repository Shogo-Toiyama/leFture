import os
import asyncio
from typing import Any, Dict, List
from tavily import TavilyClient
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine

class WebSearchService:
    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.logger = logger
        self.billing = billing
        api_key = os.getenv("TAVILY_API_KEY")
        self.client = TavilyClient(api_key=api_key) if api_key else None

    async def run(self, fun_fact_seed: Dict[str, Any]) -> List[Dict[str, Any]]:
        self.logger.log("   [Logic] Starting Web Search via Tavily")
        
        if not self.client:
            self.logger.log("   [Logic] ⚠️ TAVILY_API_KEY is missing. Skipping search.")
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
                # シンプルな検索を実行 (必要に応じて search_depth="advanced" も可能)
                response = await asyncio.to_thread(
                    self.client.search,
                    query=q,
                    max_results=3
                )
                
                # 検索1回ごとにコストを記録
                self.billing.add_count_cost("tavily/search", 1, note=f"Search query: {q}")
                
                # 結果を格納 (タイトル、URL、内容の断片)
                for res in response.get("results", []):
                    search_results.append({
                        "query": q,
                        "title": res.get("title"),
                        "url": res.get("url"),
                        "content": res.get("content")
                    })
            except Exception as e:
                # 💡 「検索が失敗しても止めない」ポリシー
                self.logger.log(f"   [Logic] ⚠️ Tavily Search failed for '{q}': {e}")
                continue

        self.logger.log(f"   [Logic] Web Search finished. Found {len(search_results)} snippets.")
        return search_results