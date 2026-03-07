import modal
from typing import Dict, Any

# ==========================================
# 1. Modalアプリと環境の定義
# ==========================================
app = modal.App("lefture-role-classifier")

image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install("torch", "transformers", "fastapi[standard]")
    .add_local_dir("./my_custom_deberta_model", remote_path="/model")
)

# ==========================================
# 2. クラスベースのAPI定義（GPU "T4" を割り当て！）
# ==========================================
@app.cls(
    image=image, 
    gpu="T4", 
    scaledown_window=2,
    enable_memory_snapshot=True,
    experimental_options={"enable_gpu_snapshot": True}
)
class RoleClassifierAPI:
    
    @modal.enter(snap=True) 
    def load_model(self):
        import torch
        from transformers import AutoTokenizer, AutoModelForSequenceClassification
        
        print("🔥 コンテナ起動: GPUメモリにモデルをロード中...")
        self.device = torch.device("cuda")
        self.tokenizer = AutoTokenizer.from_pretrained("/model")
        
        # .half() でモデルをFP16（GPU専用の超高速・省メモリ形式）に変換！
        self.model = AutoModelForSequenceClassification.from_pretrained("/model").half()
        self.model.to(self.device)
        self.model.eval()
        
        self.id2label = {0: "CONTENT", 1: "LOGISTICS", 2: "INTERACTION", 3: "OFF_TOPIC"}
        print("✅ ロード完了！いつでも推論できます。")

    @modal.fastapi_endpoint(method="POST")
    def classify(self, data: Dict[str, Any]):
        import torch
        import time
        
        start_time = time.time()
        transcript_data = data.get("transcript_data", [])
        theme = data.get("theme", "General Lecture")
        batch_size = data.get("batch_size", 32)
        
        if not transcript_data:
            return {"error": "transcript_data is empty", "transcript_data": []}

        # --- スマートバッチングの前処理 ---
        texts_with_index = []
        for i, current_item in enumerate(transcript_data):
            target_text = current_item.get("text", "")
            prev_text = transcript_data[i - 1].get("text", "") if i > 0 else ""
            next_text = transcript_data[i + 1].get("text", "") if i < len(transcript_data) - 1 else ""
            
            sep = self.tokenizer.sep_token
            input_text = f"Target: {target_text} {sep} Theme: {theme} {sep} Prev: {prev_text} {sep} Next: {next_text}"
            texts_with_index.append((i, input_text, current_item))

        texts_with_index.sort(key=lambda x: len(x[1]))

        # --- GPU推論実行 ---
        for i in range(0, len(texts_with_index), batch_size):
            batch = texts_with_index[i:i + batch_size]
            batch_texts = [item[1] for item in batch]
            batch_items = [item[2] for item in batch]
            
            inputs = self.tokenizer(batch_texts, return_tensors="pt", padding=True, truncation=True, max_length=512)
            inputs = {k: v.to(self.device) for k, v in inputs.items()}
            
            with torch.no_grad():
                outputs = self.model(**inputs)
            
            probabilities = torch.nn.functional.softmax(outputs.logits, dim=-1)
            
            for j in range(len(batch)):
                probs = probabilities[j].cpu().tolist()
                predicted_id = int(torch.argmax(probabilities[j]).item())
                
                batch_items[j]["role"] = self.id2label[predicted_id]
                batch_items[j]["role_confidence"] = round(probs[predicted_id], 4)
                
                batch_items[j]["all_probabilities"] = {
                    self.id2label[k]: round(probs[k], 4) for k in range(4)
                }

        total_time = time.time() - start_time
        print(f"🚀 推論完了: {len(transcript_data)}文 (処理時間: {total_time:.2f}秒)")
        
        return {
            "processing_time_seconds": total_time,
            "count": len(transcript_data),
            "transcript_data": transcript_data
        }