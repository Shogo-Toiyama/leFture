#!/usr/bin/env bash
set -euo pipefail

experiment="$(cd "$(dirname "$0")" && pwd)"
cd "$experiment/../../../user_interface"
flutter test --no-pub test/presentation/widgets/ai_chat/chat_conversation_view_test.dart \
  --name '生成完了後は' --reporter expanded 2>&1 \
  | tee "$experiment/results/flutter_$(date +%Y%m%d_%H%M%S).log"
