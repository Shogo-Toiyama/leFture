import io
import os
import base64
import asyncio
import httpx
from PIL import Image
from typing import Any, Dict, List
from tenacity import retry, retry_if_exception, stop_after_attempt, wait_exponential_jitter

from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine
from app.core.r2_storage import storage_service # R2保存用


def _is_retryable_cloudflare_error(exc: BaseException) -> bool:
    if isinstance(exc, httpx.HTTPStatusError):
        return exc.response.status_code == 429 or exc.response.status_code >= 500
    return isinstance(exc, httpx.RequestError)


@retry(
    retry=retry_if_exception(_is_retryable_cloudflare_error),
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(initial=1, max=8),
    reraise=True,
)
async def _post_cloudflare_flux(client: httpx.AsyncClient, url: str, headers: dict, files: dict) -> httpx.Response:
    """
    Cloudflare Flux画像生成APIを呼び出す。429/5xx/接続エラーは指数バックオフ＋ジッターで
    リトライし、それ以外のクライアントエラーはリトライしても無駄なのでそのまま送出する。
    """
    response = await client.post(url, headers=headers, files=files, timeout=60.0)
    response.raise_for_status()
    return response


# トピック画像の縮小版。アプリは講義タイル(44pt)やコラージュの仮表示に使い、
# 元の画像(384x512, 約170KB)を待たずにすぐ絵を出す。ファイル名にサイズを
# 入れているのは、サイズを変えた時に端末の古いキャッシュを使い回さないため
# (アプリ側の`topic_image_paths.dart`と同じ規則)。
THUMBNAIL_SIZE = (192, 256)
THUMBNAIL_QUALITY = 70
THUMBNAIL_SUFFIX = "_thumb192.webp"


def thumbnail_path_for(image_path: str) -> str:
    """`.../images/topic_3.jpg` -> `.../images/topic_3_thumb192.webp`"""
    base, _ext = os.path.splitext(image_path)
    return f"{base}{THUMBNAIL_SUFFIX}"


def make_thumbnail(image_bytes: bytes) -> bytes:
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    thumb = img.resize(THUMBNAIL_SIZE, Image.LANCZOS)
    buf = io.BytesIO()
    thumb.save(buf, "WEBP", quality=THUMBNAIL_QUALITY)
    return buf.getvalue()


def ensure_thumbnail(image_path: str, image_bytes: bytes | None = None) -> str | None:
    """[image_path]の縮小版がR2に無ければ作って保存し、そのパスを返す(同期処理)。
    [image_bytes]が無ければR2から元画像を読む。失敗したらNone(元画像の表示には
    影響しないので、呼び出し元はタスクを失敗させない)。"""
    thumb_path = thumbnail_path_for(image_path)
    try:
        if storage_service.object_exists(thumb_path):
            return thumb_path
        data = image_bytes if image_bytes is not None else storage_service.download_binary(image_path)
        storage_service.put_bytes(thumb_path, make_thumbnail(data), content_type="image/webp")
        return thumb_path
    except Exception:
        return None


class ImageRenderingService:
    def __init__(self, logger: TaskLogger, billing: BillingEngine):
        self.logger = logger
        self.billing = billing
        self.account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID")
        self.api_token = os.getenv("CLOUDFLARE_API_KEY")
        self.model = "@cf/black-forest-labs/flux-2-klein-4b"

    async def render_single_image(self, uid: str, lecture_id: str, topic: dict, client: httpx.AsyncClient) -> dict:
        topic_idx = topic.get("topic_idx", "unknown")
        
        # 💡 R2上に既に画像が存在するか確認（キャッシュ）
        expected_r2_path = f"{uid}/{lecture_id}/images/topic_{topic_idx}.jpg"
        exists = await asyncio.to_thread(storage_service.object_exists, expected_r2_path)
        if exists:
            self.logger.log(f"   [Cache] Topic {topic_idx}: Image already exists in R2, skipping generation.")
            thumb_path = await asyncio.to_thread(ensure_thumbnail, expected_r2_path)
            return {"topic_idx": topic_idx, "image_path": expected_r2_path, "thumb_path": thumb_path}

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
            response = await _post_cloudflare_flux(client, url, headers, files)

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

            thumb_path = await asyncio.to_thread(ensure_thumbnail, r2_path, image_bytes)
            if thumb_path is None:
                self.logger.log(f"   [Logic] ⚠️ Thumbnail for Topic {topic_idx} could not be saved (full image is fine).")
            return {"topic_idx": topic_idx, "image_path": r2_path, "thumb_path": thumb_path}

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

        # 💡 エラーが発生したトピックを収集して例外を送出する
        failed_topic_indices = [r.get("topic_idx") for r in results if r.get("image_path") is None]
        if failed_topic_indices:
            raise ValueError(
                f"Image rendering failed for {len(failed_topic_indices)} topic(s): "
                f"indices={failed_topic_indices}. "
                f"Successfully cached/generated {len(results) - len(failed_topic_indices)} topic(s). "
                f"Retry will skip cached/existing images."
            )

        return results