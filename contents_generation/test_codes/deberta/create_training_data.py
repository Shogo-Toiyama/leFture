import json
import os
import glob

# 1. ラベルを整数にマッピングする辞書（推論時もこのルールを使います）
LABEL_MAP = {
    "CONTENT": 0,
    "LOGISTICS": 1,
    "INTERACTION": 2,
    "OFF_TOPIC": 3
}

def create_training_data(input_json_path, output_jsonl_path, prev_window=3, next_window=1):
    """
    GPTでラベリングしたJSONを読み込み、DeBERTa学習用のJSONL形式に変換する
    """
    with open(input_json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    theme = data.get("theme", "")
    results = data.get("results", [])
    
    processed_data = []

    # 1文ずつループしてコンテキストを構築
    for i, item in enumerate(results):
        
        # --- 【デバッグ用】エラーが起きたら詳細をプリントして止める ---
        try:
            target_text = item["text"]
            label_str = item["label"]
        except KeyError as e:
            print("\n" + "="*50)
            print(f"🚨 エラー発生箇所を特定しました！")
            print(f"📄 ファイル名: {input_json_path}")
            print(f"🔢 場所 (インデックス): results配列の {i} 番目")
            print(f"🐛 実際のデータ: {item}")
            print(f"🔑 足りない項目: {e}")
            print("="*50 + "\n")
            raise  # エラーの詳細を出した上で、あえてここでプログラムを止めます
        # ----------------------------------------------------

        # （デバッグ用の print(f"Debug - item content: {item}") は消しても大丈夫です）

        # ラベルの変換（万が一スペルミス等があれば警告）
        if label_str not in LABEL_MAP:
            print(f"⚠️ 警告: 未知のラベル '{label_str}' がスキップされました ({input_json_path})")
            continue
            
        label_int = LABEL_MAP[label_str]

        # 2. 過去の文脈 (prev_context) を最大3文取得
        start_prev = max(0, i - prev_window)
        prev_sentences = [res["text"] for res in results[start_prev:i]]
        prev_context = " ".join(prev_sentences)

        # 3. 未来の文脈 (next_context) を最大1文取得
        end_next = min(len(results), i + 1 + next_window)
        next_sentences = [res["text"] for res in results[i+1:end_next]]
        next_context = " ".join(next_sentences)

        # 4. 学習用レコードの作成
        record = {
            "theme": theme,
            "prev_context": prev_context,
            "target": target_text,
            "next_context": next_context,
            "label": label_int
        }
        processed_data.append(record)

    # 5. JSONLファイルに追記モード（'a'）で書き込み
    with open(output_jsonl_path, 'a', encoding='utf-8') as f:
        for record in processed_data:
            f.write(json.dumps(record, ensure_ascii=False) + '\n')

    print(f"✅ {len(processed_data)}件のデータを変換し、追加しました！ ({input_json_path})")


# ==========================================
# 実行処理（フォルダ内の全JSONを一括処理）
# ==========================================

# 出力先のファイル名
output_file = "train_dataset.jsonl"

# もし前に作った古いファイルがあれば削除してリセット（追記の重複を防ぐため）
if os.path.exists(output_file):
    os.remove(output_file)

# フォルダ内の全JSONファイルを順番に処理する
json_files = glob.glob("labeled_transcripts/*.json") 

if not json_files:
    print("処理するJSONファイルが見つかりません。")
else:
    for file_path in json_files:
        create_training_data(file_path, output_file, prev_window=3, next_window=1)
    
    print(f"\n🎉 すべての処理が完了しました！最終的な学習データ: {output_file}")