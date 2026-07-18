# app/services/logic/role_classification.py
import os
import time
import httpx
from typing import Any, Dict, List

from app.services.helpers.helpers import TaskLogger, _sid_to_int
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
                start_sid = topic.get("start_sid")
                end_sid = topic.get("end_sid")
                start_idx = _sid_to_int(start_sid) if isinstance(start_sid, str) else None
                end_idx = _sid_to_int(end_sid) if isinstance(end_sid, str) else None
                if start_idx is None or end_idx is None:
                    raise ValueError(f"Invalid LOGISTICS SID range in core_data: {topic}")
                if start_idx > end_idx:
                    raise ValueError(f"Invalid LOGISTICS range order: {topic}")
                logistics_ranges.append((start_idx, end_idx))

        # ==========================================
        # 2. データの仕分け (ACADEMIC vs LOGISTICS)
        # ==========================================
        academic_data = []
        academic_sids = set()
        logistics_sids = set()
        
        for item in transcript_data:
            sid_str = item.get("sid", "")
            is_logistics = False

            sid_num = _sid_to_int(sid_str)
            if sid_num is not None:
                # この文がLOGISTICSの範囲内に入っているかチェック
                is_logistics = any(start <= sid_num <= end for start, end in logistics_ranges)
            
            # DeBERTaで推論すべき(ACADEMICな)文だけを抽出
            if not is_logistics:
                academic_data.append(item)
                academic_sids.add(sid_str)
            else:
                logistics_sids.add(sid_str)

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
            
            async with httpx.AsyncClient(timeout=300.0) as client:
                response = await client.post(self.modal_url, json=payload)
                response.raise_for_status()
                result = response.json()

            elapsed_time = time.perf_counter() - start_time
            
            # 💰 コスト記録 (Modalの純粋なGPU時間 ＋ スケールダウン待機時間2秒)
            gpu_time = result.get('processing_time_seconds', 0.0) + 2.0
            self.billing.add_time_cost("modal/t4", gpu_time, note="DeBERTa GPU processing (incl. scaledown)")
            self.billing.add_time_cost("cloudrun/self", elapsed_time, note="Role Classification Wait")

            # 帰ってきたデータを sid をキーにした辞書に変換しておく（爆速で検索するため）
            returned_academic = result.get("transcript_data", [])

            if not isinstance(returned_academic, list):
                raise ValueError("Modal response field 'transcript_data' must be a list.")

            academic_map = {item["sid"]: item for item in returned_academic if "sid" in item}

            returned_sids = set(academic_map.keys())
            missing_sids = academic_sids - returned_sids
            unexpected_sids = returned_sids - academic_sids

            if missing_sids:
                sample = sorted(missing_sids)[:10]
                raise ValueError(
                    f"Modal response is missing {len(missing_sids)} classified academic sentences. "
                    f"Sample missing SIDs: {sample}"
                )

            if unexpected_sids:
                sample = sorted(unexpected_sids)[:10]
                raise ValueError(
                    f"Modal response returned {len(unexpected_sids)} unexpected SIDs. "
                    f"Sample unexpected SIDs: {sample}"
                )

            for sid, classified_item in academic_map.items():
                role = classified_item.get("role")
                if not isinstance(role, str) or not role:
                    raise ValueError(f"Modal response item for {sid} is missing a valid role.")
                role_confidence = classified_item.get("role_confidence", 0.0)
                if not isinstance(role_confidence, (int, float)):
                    raise ValueError(f"Modal response item for {sid} has invalid role_confidence.")

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
            elif sid_str in logistics_sids:
                new_item["role"] = "LOGISTICS"
                new_item["role_confidence"] = 1.0 # Core Extractionが丸ごと指定したので確度100%とする
            else:
                raise ValueError(
                    f"SID {sid_str} was neither classified by Modal nor marked as LOGISTICS."
                )

            final_transcript.append(new_item)

        self.logger.log(f"✅ Role Classification finished. Returned {len(final_transcript)} sentences.")
        return final_transcript