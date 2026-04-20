import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import json
import time # ★どれくらい速くなったか測るためのおまけ

# ==========================================
# 0. テスト用データを読み込む
# ==========================================
json_file_path = "transcript_data.json"

with open(json_file_path, "r", encoding="utf-8") as f:
    transcript_data = json.load(f)

# ==========================================
# 1. モデルとトークナイザーの読み込み ＆ 爆速デバイス設定
# ==========================================
model_path = "./version1/my_custom_deberta_model" 

print("🧠 賢くなったDeBERTaを叩き起こしています...")
tokenizer = AutoTokenizer.from_pretrained(model_path)
model = AutoModelForSequenceClassification.from_pretrained(model_path)

# ★ MacのGPU（MPS）が使えるかチェックして割り当てる！
if torch.backends.mps.is_available():
    device = torch.device("mps")
    print("🚀 Apple Silicon (MPS) モードで爆速起動します！")
elif torch.cuda.is_available():
    device = torch.device("cuda")
    print("🚀 GPU (CUDA) モードで起動します！")
else:
    device = torch.device("cpu")
    print("🐢 CPU モードで起動します...")

model.to(device) # モデルを専用エンジンに乗せる

id2label = {
    0: "CONTENT", 
    1: "LOGISTICS", 
    2: "INTERACTION",
    3: "OFF_TOPIC",
}

# ==========================================
# 2. 単発テスト用関数（残しておくと便利！）
# ==========================================
def judge_lecture_text(target_text, theme="", prev_text="", next_text=""):
    sep = tokenizer.sep_token
    input_text = f"Target: {target_text} {sep} Theme: {theme} {sep} Prev: {prev_text} {sep} Next: {next_text}"
    
    # ★ padding="max_length" を padding=True（動的パディング）に変更！
    inputs = tokenizer(input_text, return_tensors="pt", padding=True, truncation=True, max_length=512)
    inputs = {k: v.to(device) for k, v in inputs.items()} # デバイスに送る
    
    model.eval()
    with torch.no_grad():
        outputs = model(**inputs)
        
    probabilities = torch.nn.functional.softmax(outputs.logits, dim=-1)[0]
    predicted_id = torch.argmax(probabilities).item()
    
    print("\n" + "="*50)
    print(f"🎯 ターゲット文: '{target_text}'")
    print(f"🏆 判定結果: 【 {id2label[predicted_id]} 】")
    print("="*50 + "\n")

# ==========================================
# 3. 本番用：一括バッチ処理マシーン！！！
# ==========================================
def test_real_transcript_smart_batched(start_sid, end_sid, theme="Computer System Architecture", batch_size=16):
    
    # 時間計測スタート
    start_time = time.time()
    
    print(f"\n🚀 スマートバッチ処理開始: {start_sid} 〜 {end_sid} (テーマ: {theme})")
    print(f"📦 バッチサイズ: {batch_size}文ずつ（★長さソート最適化ON）")
    print("=" * 70)
    
    start_idx = next((i for i, item in enumerate(transcript_data) if item["sid"] == start_sid), -1)
    end_idx = next((i for i, item in enumerate(transcript_data) if item["sid"] == end_sid), -1)

    if start_idx == -1 or end_idx == -1:
        print("❌ エラー: 指定されたSIDが見つかりません！")
        return

    # ① まずは処理したい文章を「元の順番（インデックス）」と一緒に集める
    texts_with_index = []
    
    for i in range(start_idx, end_idx + 1):
        current_item = transcript_data[i]
        target_text = current_item["text"]
        prev_text = transcript_data[i - 1]["text"] if i > 0 else ""
        next_text = transcript_data[i + 1]["text"] if i < len(transcript_data) - 1 else ""
        
        sep = tokenizer.sep_token
        input_text = f"Target: {target_text} {sep} Theme: {theme} {sep} Prev: {prev_text} {sep} Next: {next_text}"
        
        # (元のインデックス, 入力テキスト, 元のデータ) のセットで保存
        texts_with_index.append((i, input_text, current_item))

    # ② 【大天才のアイデア】文章の長さ（文字数）で並び替える！！
    # こうすることで、似た長さの文章同士が同じバッチになり、無駄なパディングが消滅します
    texts_with_index.sort(key=lambda x: len(x[1]))

    results = [] # 判定結果を一時保存する箱

    # ③ 集めた文章を「batch_size」ごとに切り分けてAIに投げる！
    for i in range(0, len(texts_with_index), batch_size):
        batch = texts_with_index[i:i + batch_size]
        
        batch_indices = [item[0] for item in batch]
        batch_texts = [item[1] for item in batch]
        batch_items = [item[2] for item in batch]
        
        # padding=True が、このグループ内の最長に合わせる（長さが似ているので超エコ！）
        inputs = tokenizer(batch_texts, return_tensors="pt", padding=True, truncation=True, max_length=512)
        inputs = {k: v.to(device) for k, v in inputs.items()}
        
        model.eval()
        with torch.no_grad():
            outputs = model(**inputs)
            
        probabilities = torch.nn.functional.softmax(outputs.logits, dim=-1)
        
        # 結果を「元のインデックス」と一緒に保存する
        for j in range(len(batch)):
            probs = probabilities[j]
            predicted_id = torch.argmax(probs).item()
            results.append((batch_indices[j], batch_items[j], predicted_id, probs))

    # ④ 【超重要】出力する前に、元の順番（時系列）に並び直す！
    results.sort(key=lambda x: x[0])

    # ⑤ バッチ内の結果を順番に出力（表示部分は省略・高速化のため最後だけ表示でもOK）
    for res in results:
        original_idx, current_item, predicted_id, probs = res
        target_text = current_item["text"]
        
        print(f"\n[{current_item['sid']}] 🎯 '{target_text}'")
        print(f"🏆 判定: 【 {id2label[predicted_id]} 】")
        probs_str = " | ".join([f"{id2label[k]}: {probs[k].item() * 100:.1f}%" for k in range(4)])
        print(f"📊 脳内: {probs_str}")
        print("-" * 70)

    # 時間計測ストップ
    end_time = time.time()
    total_time = end_time - start_time
    num_items = len(texts_with_index)
    print(f"\n✅ 処理完了！ {num_items}文を {total_time:.2f}秒 で処理しました。")
    print(f"⚡ 1文あたりの平均処理時間: {total_time / num_items:.4f}秒")

# ==========================================
# 4. いざ、実行！！！
# ==========================================
# バッチ処理関数を呼び出す（16文ずつ処理）
test_real_transcript_smart_batched(start_sid="s000001", end_sid="s000010", batch_size=16)