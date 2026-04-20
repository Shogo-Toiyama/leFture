# app/services/logic/role_classification.py
import os
import time
import httpx
from typing import Any, Dict, List

from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import BillingEngine

class RoleClassificationService:
    def __init__(self, billing: BillingEngine, logger: TaskLogger):
        self.billing = billing
        self.logger = logger
        self.modal_url = os.getenv("MODAL_ROLE_CLASSIFIER_URL")
        
    async def run_from_memory(
        self, 
        transcript_data: List[Dict[str, Any]], 
        core_data: Dict[str, Any], 
        theme: str = "Computer Science"
    ) -> List[Dict[str, Any]]:
        
        self.logger.log(f"   [Logic] Starting Role Classification via Modal (DeBERTa)")
        
        if not self.modal_url:
            raise ValueError("MODAL_ROLE_CLASSIFIER_URL environment variable is not set!")

        # ==========================================
        # 1. フィルタリングの準備 (LOGISTICSの範囲を特定)
        # ==========================================
        logistics_ranges = []
        for topic in core_data.get("topics", []):
            if topic.get("topic_type") == "LOGISTICS":
                try:
                    # "s000015" のような文字列から数値(15)だけを取り出す
                    start_idx = int(topic["start_sid"][1:])
                    end_idx = int(topic["end_sid"][1:])
                    logistics_ranges.append((start_idx, end_idx))
                except (ValueError, KeyError, TypeError):
                    continue

        # ==========================================
        # 2. データの仕分け (ACADEMIC vs LOGISTICS)
        # ==========================================
        academic_data = []
        
        for item in transcript_data:
            sid_str = item.get("sid", "")
            is_logistics = False
            
            if sid_str.startswith("s"):
                try:
                    sid_num = int(sid_str[1:])
                    # この文がLOGISTICSの範囲内に入っているかチェック
                    is_logistics = any(start <= sid_num <= end for start, end in logistics_ranges)
                except ValueError:
                    pass
            
            # DeBERTaで推論すべき(ACADEMICな)文だけを抽出
            if not is_logistics:
                academic_data.append(item)

        self.logger.log(f"📦 Total sentences: {len(transcript_data)} | Academic (Sending to Modal): {len(academic_data)} | Logistics (Skipped): {len(transcript_data) - len(academic_data)}")

        # ==========================================
        # 3. Modal(DeBERTa)への送信とコスト記録
        # ==========================================
        academic_map = {} # 後で合体するための辞書
        
        if academic_data:
            payload = {
                "transcript_data": academic_data,
                "theme": theme,
                "batch_size": 32
            }

            start_time = time.perf_counter()
            
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(self.modal_url, json=payload)
                response.raise_for_status()
                result = response.json()

            elapsed_time = time.perf_counter() - start_time
            
            # 💰 コスト記録 (Modalの純粋なGPU時間 ＋ CloudRunの待機時間)
            gpu_time = result.get('processing_time_seconds', 0.0)
            self.billing.add_time_cost("modal/t4", gpu_time, note="DeBERTa GPU processing")
            self.billing.add_time_cost("cloudrun/self", elapsed_time, note="Role Classification Wait")

            # 帰ってきたデータを sid をキーにした辞書に変換しておく（爆速で検索するため）
            returned_academic = result.get("transcript_data", [])
            academic_map = {item["sid"]: item for item in returned_academic if "sid" in item}

        # ==========================================
        # 4. データの合体 (マージ)
        # ==========================================
        final_transcript = []
        
        for item in transcript_data:
            sid_str = item.get("sid", "")
            new_item = item.copy() # 元データを汚さないようにコピー
            
            # Modalに送ったデータ（ACADEMIC）なら、DeBERTaの結果をマージ
            if sid_str in academic_map:
                new_item["role"] = academic_map[sid_str].get("role", "CONTENT")
                new_item["role_confidence"] = academic_map[sid_str].get("role_confidence", 0.0)
                if "all_probabilities" in academic_map[sid_str]:
                    new_item["all_probabilities"] = academic_map[sid_str]["all_probabilities"]
            
            # Modalに送らなかったデータ（LOGISTICS）なら、直接ラベルを付与
            else:
                new_item["role"] = "LOGISTICS"
                new_item["role_confidence"] = 1.0 # Core Extractionが丸ごと指定したので確度100%とする

            final_transcript.append(new_item)

        self.logger.log(f"✅ Role Classification finished. Returned {len(final_transcript)} sentences.")
        return final_transcript