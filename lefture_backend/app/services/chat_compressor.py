# app/services/chat_compressor.py
"""
LLMLingua-2 Prompt Compression Service via Modal API.
長文の添付資料（30k〜40kトークン）や検索・探索材料（15k〜18kトークン）を
LLMLingua-2 (mBERT) で安全にソフト圧縮し、回答役（Haiku 5.5）のプロンプト枠
（100K 課金跳ね上がり崖・65K 入力上限）内に確実に収める。
"""

import asyncio
import os
from typing import Optional, TYPE_CHECKING

import httpx

from app.services.chat_attachments import estimate_tokens

if TYPE_CHECKING:
    from app.services.helpers.llm_unified import BillingEngine

# =========================================================
# ⚙️ 設定とエンドポイント
# =========================================================

MODAL_LLMLINGUA2_URL = os.getenv(
    "MODAL_LLMLINGUA2_URL",
    "https://shogo-toiyama--lefture-llmlingua2-llmlingua2api-compress.us-east.modal.run",
)

# 添付資料（Attachments）の圧縮境界
ATTACHMENT_COMPRESS_MIN_TOKENS = 30_000  # これ以下は非圧縮
ATTACHMENT_COMPRESS_MID_TOKENS = 36_000  # 30k〜36k は Rate 0.7 (約25%カット)
ATTACHMENT_COMPRESS_MAX_TOKENS = 40_000  # 36k〜40k は Rate 0.6 (約30%カット)
# 40k 超過は too_long (要約・目次のみ)

# 材料集約（Materials）の圧縮境界
MATERIALS_COMPRESS_MIN_TOKENS = 15_000  # 15k 超過で圧縮を検討
MATERIALS_COMPRESS_MAX_TOKENS = 18_000  # 15k〜18k は Rate 0.7 で圧縮して 15k 以内へ

DEFAULT_TIMEOUT_SECONDS = 30.0


# =========================================================
# 🌐 Modal API 呼び出し
# =========================================================

async def compress_text(
    text: str,
    rate: float = 0.7,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    force_tokens: Optional[list[str]] = None,
    billing: Optional["BillingEngine"] = None,
) -> Optional[str]:
    """
    Modal の LLMLingua-2 API を非同期で呼び出してテキストをソフト圧縮する。
    万一 Modal がタイムアウトやダウンした場合は例外を握り潰して None を返し、
    呼び出し元で元のテキストを安全に使えるようにする（二重フォールバック設計）。
    """
    if not text or not text.strip():
        return text

    payload = {
        "text": text,
        "rate": rate,
    }
    if force_tokens:
        payload["force_tokens"] = force_tokens

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            res = await client.post(MODAL_LLMLINGUA2_URL, json=payload)
            if res.status_code == 200:
                data = res.json()
                comp_text = data.get("compressed_text")
                if comp_text:
                    orig_tok = data.get("original_tokens", estimate_tokens(text))
                    comp_tok = data.get("compressed_tokens", estimate_tokens(comp_text))
                    red_pct = data.get("reduction_pct", 0.0)
                    proc_ms = data.get("processing_time_ms", 0.0)
                    print(
                        f"✨ [chat_compressor] Compressed: {orig_tok} -> {comp_tok} tokens "
                        f"(-{red_pct}%) in {proc_ms:.1f}ms (rate={rate})"
                    )

                    # 💰 コスト計上 (Modalの純粋なGPU時間 ＋ スケールダウン待機時間2秒)
                    if billing is not None:
                        gpu_time = (proc_ms / 1000.0) + 2.0
                        billing.add_time_cost("modal/t4", gpu_time, note="LLMLingua-2 prompt compression (incl. scaledown)")

                    return comp_text
            print(f"⚠️ [chat_compressor] Modal API returned HTTP {res.status_code}: {res.text[:200]}")
    except Exception as e:
        print(f"⚠️ [chat_compressor] Modal compression failed or timed out: {e}")

    return None


# =========================================================
# 📄 添付資料（Attachments）のオンデマンド圧縮
# =========================================================

async def compress_attachment_content_if_needed(
    content: str,
    token_count: Optional[int] = None,
    billing: Optional["BillingEngine"] = None,
) -> tuple[str, int, bool]:
    """
    添付資料のトークン数が 30,000 を超えている場合に自動圧縮する。
    返り値: (最終テキスト, 最終トークン数, 圧縮されたか)
    - 30,000 以下: そのまま返す
    - 30,001 〜 36,000: Rate 0.7 で圧縮（約27k以下に押し込む）
    - 36,001 〜 40,000: Rate 0.6 で圧縮（約28k以下に押し込む）
    - 40,000 超過: そのまま返す（plan_pins で too_long になる）
    """
    tokens = token_count if token_count is not None else estimate_tokens(content)

    if tokens <= ATTACHMENT_COMPRESS_MIN_TOKENS or tokens > ATTACHMENT_COMPRESS_MAX_TOKENS:
        return content, tokens, False

    # レート決定
    rate = 0.7 if tokens <= ATTACHMENT_COMPRESS_MID_TOKENS else 0.6

    print(f"📦 [chat_compressor] Attachment tokens ({tokens}) in [{ATTACHMENT_COMPRESS_MIN_TOKENS}, {ATTACHMENT_COMPRESS_MAX_TOKENS}]. Triggering compression (rate={rate})...")
    compressed = await compress_text(content, rate=rate, billing=billing)

    if compressed:
        comp_tokens = estimate_tokens(compressed)
        # 圧縮によって確実にトークン数が減っている場合のみ採用
        if comp_tokens < tokens:
            return compressed, comp_tokens, True

    return content, tokens, False
