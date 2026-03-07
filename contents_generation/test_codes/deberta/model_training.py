# ==========================================
# 1. 必要なライブラリのインストール
# ==========================================
# !pip install transformers datasets evaluate accelerate sentencepiece scikit-learn

import pandas as pd
import numpy as np
from datasets import load_dataset
from transformers import AutoTokenizer, AutoModelForSequenceClassification, TrainingArguments, Trainer
import evaluate
from transformers import DataCollatorWithPadding

# ==========================================
# 2. データの読み込みと準備
# ==========================================
print("データを読み込んでいます...")
# アップロードしたJSONLファイルを読み込む
dataset = load_dataset('json', data_files='train_dataset.jsonl', split='train')

# AIが「自分がどれくらい賢くなったか」をテストするために、データを学習用(85%)とテスト用(15%)に分割します
split_dataset = dataset.train_test_split(test_size=0.15, seed=42)
train_dataset = split_dataset['train']
eval_dataset = split_dataset['test']

print(f"学習用データ: {len(train_dataset)}件, テスト用データ: {len(eval_dataset)}件")

# ==========================================
# 3. トークナイザー（言葉を数字に変換する辞書）の準備
# ==========================================
model_name = "microsoft/deberta-v3-small"
tokenizer = AutoTokenizer.from_pretrained(model_name)

def tokenize_function(examples):
    inputs = []
    for theme, prev, target, nxt in zip(examples['theme'], examples['prev_context'], examples['target'], examples['next_context']):
        sep = tokenizer.sep_token
        text = f"Theme: {theme} {sep} Prev: {prev} {sep} Target: {target} {sep} Next: {nxt}"
        inputs.append(text)
    
    return tokenizer(inputs, truncation=True, max_length=256)

print("データをAI用のフォーマットに変換中...")
tokenized_train = train_dataset.map(tokenize_function, batched=True)
tokenized_eval = eval_dataset.map(tokenize_function, batched=True)

# ==========================================
# 4. モデルの準備と学習設定
# ==========================================
model = AutoModelForSequenceClassification.from_pretrained(model_name, num_labels=4)
data_collator = DataCollatorWithPadding(tokenizer=tokenizer)

accuracy_metric = evaluate.load("accuracy")
def compute_metrics(eval_pred):
    logits, labels = eval_pred
    predictions = np.argmax(logits, axis=-1)
    return accuracy_metric.compute(predictions=predictions, references=labels)

# 学習のルール（ハイパーパラメータ）
training_args = TrainingArguments(
    output_dir="./results",
    learning_rate=5e-5,          
    per_device_train_batch_size=16, 
    per_device_eval_batch_size=16,
    num_train_epochs=5,          
    weight_decay=0.01,
    eval_strategy="epoch", 
    save_strategy="epoch",
    load_best_model_at_end=True, 
    metric_for_best_model="accuracy", 
    fp16=False,
    warmup_ratio=0.1,
)

trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=tokenized_train,
    eval_dataset=tokenized_eval,
    processing_class=tokenizer,
    data_collator=data_collator,
    compute_metrics=compute_metrics,
)

# ==========================================
# 5. いざ、学習スタート！！！！
# ==========================================
print("学習を開始します！頑張れDeBERTa！🚀")
trainer.train()

# ==========================================
# 6. 完成したモデルの保存
# ==========================================
save_path = "./my_custom_deberta_model"
trainer.save_model(save_path)
tokenizer.save_pretrained(save_path)
print(f"🎉 学習完了！モデルが '{save_path}' に保存されました！")