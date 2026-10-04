#!/bin/zsh
# 全役割Lunaの比較(3回ずつ)。A: まとめ役medium / B: まとめ役high / D: 観察役の推論なし + まとめ役medium
cd "$(dirname "$0")"
for i in 1 2 3; do
  python3 run_eval.py --observer-model gpt-6-luna --consolidator-model gpt-6-luna --cover-model gpt-6-luna \
    --consolidator-reasoning medium --tag lunaA_r$i 2>&1 | grep -A9 "=== summary"
  python3 run_eval.py --observer-model gpt-6-luna --consolidator-model gpt-6-luna --cover-model gpt-6-luna \
    --consolidator-reasoning high --tag lunaB_r$i 2>&1 | grep -A9 "=== summary"
  python3 run_eval.py --observer-model gpt-6-luna --observer-reasoning none --consolidator-model gpt-6-luna --cover-model gpt-6-luna \
    --consolidator-reasoning medium --tag lunaD_r$i 2>&1 | grep -A9 "=== summary"
done
python3 compare.py --prefix lunaA_ lunaB_ lunaD_
