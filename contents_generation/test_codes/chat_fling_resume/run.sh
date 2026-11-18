#!/usr/bin/env bash
set -euo pipefail

experiment="$(cd "$(dirname "$0")" && pwd)"
cd "$experiment/../../../user_interface"
flutter test --no-pub test/presentation/widgets/ai_chat/chat_conversation_view_test.dart \
  --name '指を離したあと慣性|指を置くと受信中|指を離して0.5秒' --reporter expanded \
  | tee "$experiment/results/$(date +%Y%m%d_%H%M%S).log"
