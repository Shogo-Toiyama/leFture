// lib/core/utils/topic_color_utils.dart

import 'package:flutter/material.dart';

/// トピックインデックスと総数から、赤(0°)〜紫(280°)のグラデーションカラーを生成するユーティリティ。
class TopicColorUtils {
  /// トピックインデックス [index] (0-indexed) と 総件数 [totalTopics] からベースカラーを取得
  static Color getTopicColor(int index, int totalTopics) {
    if (totalTopics <= 0) return const Color(0xFFE57373); // デフォルト赤

    // 1トピックなら赤(0°)、複数なら0°〜280°を均等分割
    final double hue = totalTopics == 1
        ? 0.0
        : (index / (totalTopics - 1)).clamp(0.0, 1.0) * 280.0;

    return HSLColor.fromAHSL(1.0, hue, 0.70, 0.48).toColor();
  }

  /// トピック用の薄い背景色（淡い背景）を取得
  static Color getTopicBackgroundColor(int index, int totalTopics, {double alpha = 0.08}) {
    final baseColor = getTopicColor(index, totalTopics);
    return baseColor.withValues(alpha: alpha);
  }

  /// トピック用の枠線/アクセント色を取得
  static Color getTopicBorderColor(int index, int totalTopics, {double alpha = 0.4}) {
    final baseColor = getTopicColor(index, totalTopics);
    return baseColor.withValues(alpha: alpha);
  }
}
