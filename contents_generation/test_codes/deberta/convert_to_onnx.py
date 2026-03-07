from transformers import AutoTokenizer
from optimum.onnxruntime import ORTModelForSequenceClassification, ORTQuantizer
from optimum.onnxruntime.configuration import AutoQuantizationConfig
import os

# ==========================================
# 1. パスの設定
# ==========================================
# 元のPyTorchモデルがあるフォルダ
model_path = "./version1/my_custom_deberta_model" 

# 新しく作られるONNXモデルの保存先
onnx_save_path = "./version1/my_custom_deberta_onnx"

# さらに圧縮（量子化）された最終形態の保存先
quantized_save_path = "./version1/my_custom_deberta_onnx_quantized"

# ==========================================
# 2. PyTorch -> ONNX への変換
# ==========================================
print("🔄 1/2: ONNX形式に変換しています...（少々お待ちください）")

# export=True をつけるだけで、自動的にONNXのグラフ構造に変換してくれます
model = ORTModelForSequenceClassification.from_pretrained(model_path, export=True)
tokenizer = AutoTokenizer.from_pretrained(model_path)

# 一旦、普通のONNXとして保存
model.save_pretrained(onnx_save_path)
tokenizer.save_pretrained(onnx_save_path)
print(f"✅ ONNX変換完了！ '{onnx_save_path}' に保存しました。")

# ==========================================
# 3. ダイナミック量子化（INT8圧縮）
# ==========================================
print("🗜️ 2/2: モデルをINT8に量子化（圧縮）しています...")

# 先ほど作ったONNXモデルを読み込む
quantizer = ORTQuantizer.from_pretrained(onnx_save_path)

# Cloud Run (一般的なx86 CPU) で最も効率よく動くダイナミック量子化の設定
# is_static=False が「ダイナミック量子化（NLPに最適）」を意味します
dqconfig = AutoQuantizationConfig.avx2(is_static=False, per_channel=False)

# 量子化の実行
quantizer.quantize(save_dir=quantized_save_path, quantization_config=dqconfig)

print(f"🎉 すべて完了！究極の軽量モデルが '{quantized_save_path}' に誕生しました！")