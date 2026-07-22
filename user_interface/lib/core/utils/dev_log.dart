// core/utils/dev_log.dart
//
// dart:developerのlog()は、DevToolsのLoggingページを開いて能動的に見ていないと
// 中身が見えない(`flutter run`の素のターミナルには出てこない)。それだけだと
// ターミナル出力をそのまま貼って診断する普段の使い方と噛み合わないため、
// debugPrint()でも同じ内容を出す(`flutter run`のターミナルにそのまま出る)。
// 加えて、実機単体でも診断できるよう、直近のログをメモリ上に保持しておく
// 軽量なリングバッファも維持する。中身自体はテスト機能に依存しない汎用
// ユーティリティなので dev_tools/ には置かない(見た目のオーバーレイ表示だけが
// isTestMode限定)。
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class DevLog {
  DevLog._();

  static const int maxLines = 300;

  static final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>([]);

  static void add(String message) {
    developer.log(message);

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final timestamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final line = '$timestamp $message';

    debugPrint('[DevLog] $line');

    final updated = [...lines.value, line];
    if (updated.length > maxLines) {
      updated.removeRange(0, updated.length - maxLines);
    }
    lines.value = updated;
  }
}
