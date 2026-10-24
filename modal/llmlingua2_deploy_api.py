import re
import time
from typing import Any, Dict, List

import modal

# ==========================================
# 1. 定数とモデル設定（軽量版 700MB mBERT）
# ==========================================
APP_NAME = "lefture-llmlingua2"
MODEL_ID = "microsoft/llmlingua-2-bert-base-multilingual-cased-meetingbank"

# 自然言語圧縮時に絶対に落とさない否定・制約トークン
DEFAULT_FORCE_TOKENS = ["\n", "not", "don't", "doesn't", "cannot", "never", "unless", "except"]

# ==========================================
# 2. イメージビルド定義（事前ダウンロード Bake-in）
# ==========================================
def download_model():
    from huggingface_hub import snapshot_download
    from llmlingua import PromptCompressor
    print(f"📥 Building image: Downloading {MODEL_ID} and assets...")
    snapshot_download(repo_id=MODEL_ID)
    _ = PromptCompressor(model_name=MODEL_ID, device_map="cpu", use_llmlingua2=True)
    print("✅ Model & assets pre-download complete!")


image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(
        "torch",
        "transformers",
        "llmlingua",
        "huggingface-hub[hf_transfer]",
        "fastapi[standard]",
    )
    .env({"HF_HUB_ENABLE_HF_TRANSFER": "1"})
    .run_function(download_model)
)

app = modal.App(APP_NAME)


# ==========================================
# 3. 補助関数（ブロック保護 & チャンク分割 & CJK後処理）
# ==========================================
def split_into_chunks(text: str) -> List[str]:
    """空行区切りでブロック・段落に分割する。"""
    return [c.strip() for c in re.split(r"\n\s*\n", text) if c.strip()]


def should_protect_block(chunk: str) -> bool:
    """
    以下の要素を含むブロックは 100% 無修正で保護（退避）する：
    - フェンス付きコードブロック (```)
    - Markdown テーブル (| :--- |) または ASCII パケット図 (+-+-+)
    - プログラミング演算子・ビットシフト (<<, >>, &, |, ^, ==, <=, >=, !=)
    - C言語/システム構文 (#define, typedef struct, uint\d+_t, recvfrom, ntohl など)
    - インラインコードの多用 (` が 4 つ以上)
    """
    if "```" in chunk:
        return True
    if "+-+-+-+" in chunk or "| :---" in chunk or chunk.count("|") >= 4:
        return True

    op_pattern = r"(?:<<|>>|&|\||\^|==|<=|>=|!=|#define|typedef\s+struct|uint\d+_t|recvfrom|sendto|ntohl|htonl|\bMSS\b)"
    if re.search(op_pattern, chunk):
        return True

    if chunk.count("`") >= 4:
        return True

    return False


def clean_cjk_spaces(text: str) -> str:
    """
    mBERT (WordPiece) 特有の、漢字・仮名などの CJK 文字間に挟まってしまった
    不自然な空白（例: '信 頼 性' -> '信頼性'）を綺麗に除去する。
    """
    cjk_pattern = r"(?<=[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff])\s+(?=[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff])"
    return re.sub(cjk_pattern, "", text)


def estimate_tokens(text: str) -> int:
    """
    トークン概算（Orbit バックエンド標準式）：
    ceil(ASCII / 4) + non_ASCII
    """
    non_ascii = sum(1 for ch in text if ord(ch) > 127)
    return -(-(len(text) - non_ascii) // 4) + non_ascii


# ==========================================
# 4. クラスベースの API 定義（T4 GPU + 逐次最適化版）
# ==========================================
@app.cls(
    image=image,
    gpu="T4",
    scaledown_window=2,  # 2秒アイドルで即時停止
    enable_memory_snapshot=True,
    experimental_options={"enable_gpu_snapshot": True},
)
class LLMLingua2API:

    @modal.enter(snap=True)
    def load_model(self):
        import torch
        from llmlingua import PromptCompressor

        print(f"🔥 [Container Init] Loading LLMLingua-2 ({MODEL_ID}) onto GPU...")
        t0 = time.perf_counter()

        self.compressor = PromptCompressor(
            model_name=MODEL_ID,
            device_map="cuda",
            use_llmlingua2=True,
        )

        elapsed = time.perf_counter() - t0
        print(f"✅ [Container Init] Model loaded in {elapsed:.2f}s! Ready for inference.")

    @modal.fastapi_endpoint(method="POST")
    def compress(self, data: Dict[str, Any]):
        """
        テキストをチャンクごとに安全にソフト圧縮するエンドポイント。
        リクエスト body:
        {
            "text": str,           # 圧縮対象のテキスト
            "rate": float,         # 圧縮率（既定 0.7 = 約25%カット目標）
            "force_tokens": list   # 追加保護トークン（任意）
        }
        """
        t_start = time.perf_counter()
        text = data.get("text", "")
        rate = float(data.get("rate", 0.7))
        custom_force = data.get("force_tokens", [])
        force_tokens = list(set(DEFAULT_FORCE_TOKENS + custom_force))

        if not text or not text.strip():
            return {
                "compressed_text": "",
                "original_chars": 0,
                "compressed_chars": 0,
                "original_tokens": 0,
                "compressed_tokens": 0,
                "reduction_pct": 0.0,
                "protected_chunks": 0,
                "compressed_chunks": 0,
                "processing_time_ms": 0.0,
            }

        orig_tokens = estimate_tokens(text)
        chunks = split_into_chunks(text)
        processed_chunks = []
        protected_count = 0
        compressed_count = 0

        # チャンクごとに処理（実測最速かつ正確な削減率を実現）
        for chunk in chunks:
            if should_protect_block(chunk):
                # コード・表・演算子ブロックは 100% 原型維持
                processed_chunks.append(chunk)
                protected_count += 1
            else:
                # 自然言語ブロックのみソフト圧縮
                c_res = self.compressor.compress_prompt(
                    chunk,
                    rate=rate,
                    force_tokens=force_tokens,
                    force_reserve_digit=True,
                    chunk_end_tokens=[".", "\n", "。", "！", "？"],
                )
                comp_chunk = c_res.get("compressed_prompt", chunk)
                # mBERT特有の漢字・仮名間の不要な空白を綺麗に整形
                comp_chunk = clean_cjk_spaces(comp_chunk)
                processed_chunks.append(comp_chunk)
                compressed_count += 1

        compressed_text = "\n\n".join(processed_chunks)
        comp_tokens = estimate_tokens(compressed_text)
        reduction_pct = round((1.0 - (comp_tokens / max(1, orig_tokens))) * 100.0, 1)
        proc_time_ms = round((time.perf_counter() - t_start) * 1000.0, 1)

        print(
            f"⚡ [Compress] {len(text)} chars ({orig_tokens} tok) -> {len(compressed_text)} chars "
            f"({comp_tokens} tok) | -{reduction_pct}% | {proc_time_ms}ms "
            f"(Protected: {protected_count}, Compressed: {compressed_count})"
        )

        return {
            "compressed_text": compressed_text,
            "original_chars": len(text),
            "compressed_chars": len(compressed_text),
            "original_tokens": orig_tokens,
            "compressed_tokens": comp_tokens,
            "reduction_pct": reduction_pct,
            "protected_chunks": protected_count,
            "compressed_chunks": compressed_count,
            "processing_time_ms": proc_time_ms,
        }
