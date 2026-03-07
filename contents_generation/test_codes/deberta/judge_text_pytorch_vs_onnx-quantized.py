import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
from optimum.onnxruntime import ORTModelForSequenceClassification
import json
import time

# ==========================================
# 0. テスト用データを読み込む
# ==========================================
json_file_path = "transcript_data.json"

with open(json_file_path, "r", encoding="utf-8") as f:
    transcript_data = json.load(f)

# ==========================================
# 1. パスの設定 ＆ 共通準備
# ==========================================
pytorch_model_path = "./version1/my_custom_deberta_model" 
onnx_quantized_path = "./version1/my_custom_deberta_onnx_quantized"

# トークナイザーは共通でOK
tokenizer = AutoTokenizer.from_pretrained(pytorch_model_path)

id2label = {0: "CONTENT", 1: "LOGISTICS", 2: "INTERACTION", 3: "OFF_TOPIC"}

device = torch.device("cpu")
print("🐢 Cloud Run想定：CPUモードで実行します！\n")

# ==========================================
# 2. 共通のバッチ処理ロジック（スマートバッチング）
# ==========================================
def run_benchmark(model, model_name, start_sid, end_sid, theme="Computer System Architecture", batch_size=16):
    print("=" * 70)
    print(f"🏁 【 {model_name} 】の計測をスタートします！")
    print("=" * 70)
    
    start_idx = next((i for i, item in enumerate(transcript_data) if item["sid"] == start_sid), -1)
    end_idx = next((i for i, item in enumerate(transcript_data) if item["sid"] == end_sid), -1)

    texts_with_index = []
    for i in range(start_idx, end_idx + 1):
        current_item = transcript_data[i]
        target_text = current_item["text"]
        prev_text = transcript_data[i - 1]["text"] if i > 0 else ""
        next_text = transcript_data[i + 1]["text"] if i < len(transcript_data) - 1 else ""
        
        sep = tokenizer.sep_token
        input_text = f"Target: {target_text} {sep} Theme: {theme} {sep} Prev: {prev_text} {sep} Next: {next_text}"
        texts_with_index.append((i, input_text, current_item))

    # 時間計測スタート（前処理のソートから計測に含める）
    start_time = time.time()

    texts_with_index.sort(key=lambda x: len(x[1]))
    results = []

    for i in range(0, len(texts_with_index), batch_size):
        batch = texts_with_index[i:i + batch_size]
        batch_indices = [item[0] for item in batch]
        batch_texts = [item[1] for item in batch]
        batch_items = [item[2] for item in batch]
        
        inputs = tokenizer(batch_texts, return_tensors="pt", padding=True, truncation=True, max_length=512)
        # CPUの場合は送らなくてもデフォルトでCPUですが、一応明示
        inputs = {k: v.to(device) for k, v in inputs.items()}
        
        # PyTorchモデルかONNXモデルかに関わらず、同じコードで推論可能！
        # (Optimumライブラリが裏側で自動的にONNXエンジンに切り替えてくれます)
        model.eval() if hasattr(model, 'eval') else None # ONNXはeval不要なので安全対策
        
        with torch.no_grad():
            outputs = model(**inputs)
            
        probabilities = torch.nn.functional.softmax(outputs.logits, dim=-1)
        
        for j in range(len(batch)):
            probs = probabilities[j]
            predicted_id = torch.argmax(probs).item()
            results.append((batch_indices[j], batch_items[j], predicted_id, probs))

    results.sort(key=lambda x: x[0])
    
    end_time = time.time()
    total_time = end_time - start_time
    num_items = len(texts_with_index)
    
    print(f"✅ 【 {model_name} 】処理完了！")
    print(f"⏱️ 合計時間: {total_time:.2f} 秒 ({num_items}文)")
    print(f"⚡ 1文あたり: {total_time / num_items:.4f} 秒\n")

# ==========================================
# 3. いざ、頂上決戦！！！
# ==========================================

# 選手1: 重戦車 PyTorch (CPU)
print("📦 PyTorchモデルを読み込んでいます...")
model_pt = AutoModelForSequenceClassification.from_pretrained(pytorch_model_path)
model_pt.to(device)
run_benchmark(model_pt, "PyTorch (CPU)", start_sid="s000001", end_sid="s000704", batch_size=16)

# メモリ解放のおまじない
del model_pt

# 選手2: 軽量F1カー ONNX Quantized (CPU)
print("📦 ONNX量子化モデルを読み込んでいます...")
# ★ Optimumの ORTModelForSequenceClassification を使うのが魔法の鍵！
model_onnx = ORTModelForSequenceClassification.from_pretrained(onnx_quantized_path, file_name="model_quantized.onnx")
# ONNXモデルはデフォルトでCPU上で高速動作するようにセットアップされます
run_benchmark(model_onnx, "ONNX Quantized (CPU)", start_sid="s000001", end_sid="s000704", batch_size=16)