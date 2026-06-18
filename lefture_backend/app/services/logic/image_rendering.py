import os
import base64
import asyncio
import httpx
from typing import Any, Dict, List

from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine
from app.core.r2_storage import storage_service # R2保存用

class ImageRenderingService:
    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.logger = logger
        self.billing = billing
        self.account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID")
        self.api_token = os.getenv("CLOUDFLARE_API_KEY")
        self.model = "@cf/black-forest-labs/flux-2-klein-4b"

    async def render_single_image(self, uid: str, lecture_id: str, topic: dict, client: httpx.AsyncClient) -> dict:
        topic_idx = topic.get("topic_idx", "unknown")
        
        # IMAGE_PROMPT_GENERATIONで生成されたプロンプトを取得
        prompt_text = (
            topic.get("flux_prompt")
            or topic.get("visual_prompt")
            or topic.get("prompt")
        )
        if not prompt_text:
            raise ValueError(f"No image prompt found for Topic {topic_idx}. Expected flux_prompt.")
        
        # 💡 パラメーター設定 (デフォルト 横384, 縦512)
        width = 384
        height = 512
        steps = 4
        # 切り上げでタイル数を計算
        tiles = ((width + 511) // 512) * ((height + 511) // 512)

        url = f"https://api.cloudflare.com/client/v4/accounts/{self.account_id}/ai/run/{self.model}"
        headers = {
            "Authorization": f"Bearer {self.api_token}"
        }
        # flux-2-klein-4b requires multipart/form-data
        files = {
            "prompt": (None, prompt_text),
            "width": (None, str(width)),
            "height": (None, str(height))
        }

        self.logger.log(f"   [Logic] Requesting image for Topic {topic_idx} (Tiles: {tiles})")
        
        try:
            # タイムアウトは長め(60秒)に設定
            response = await client.post(url, headers=headers, files=files, timeout=60.0)
            response.raise_for_status()

            content_type = response.headers.get("Content-Type", "")
            image_bytes = None

            # ✅ ユーザーの堅牢なパース処理をそのまま採用！
            if "application/json" in content_type:
                data = response.json()
                if data.get("success"):
                    image_bytes = base64.b64decode(data["result"]["image"])
                else:
                    raise ValueError(f"Cloudflare API Error: {data}")
            elif "image/" in content_type:
                image_bytes = response.content
            else:
                raise ValueError(f"Unknown response format: {content_type}")

            # 💰 コストの記録 (Tile数で計算)
            self.billing.add_image_cost("cloudflare/flux-2-klein-4b", tiles=tiles, steps=steps, note=f"Topic {topic_idx}")

            # 💾 R2にバイナリデータとして保存 (※storage_serviceにsave_binary系のメソッドが必要)
            file_name = f"images/topic_{topic_idx}.jpg"
            r2_path = storage_service.save_binary(uid, lecture_id, file_name, image_bytes, content_type="image/jpeg")

            self.logger.log(f"   [Logic] ✅ Image for Topic {topic_idx} successfully generated and saved to R2!")
            return {"topic_idx": topic_idx, "image_path": r2_path}

        except Exception as e:
            self.logger.log(f"   [Logic] ❌ Failed to generate image for Topic {topic_idx}: {e}")
            return {"topic_idx": topic_idx, "image_path": None, "error": str(e)}

    async def run(self, uid: str, lecture_id: str, image_prompts: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        self.logger.log(f"   [Logic] Starting parallel Image Rendering for {len(image_prompts)} topics.")
        
        if not self.account_id or not self.api_token:
            self.logger.log("   [Logic] ⚠️ Cloudflare credentials missing. Skipping image rendering.")
            return []

        results = []
        # httpxのAsyncClientを使い回して、全プロンプトを並列で叩く
        async with httpx.AsyncClient() as client:
            tasks = [self.render_single_image(uid, lecture_id, prompt_data, client) for prompt_data in image_prompts]
            # asyncio.gather で一気に実行！ (Cloudflareの720RPMなら5枚同時でも全く問題なし)
            results = await asyncio.gather(*tasks)

        return results