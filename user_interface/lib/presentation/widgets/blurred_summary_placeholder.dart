import 'dart:ui';

import 'package:flutter/material.dart';

/// ロックされたコンテンツの上に置く「ぼかされたテキストの気配」。実際の内容
/// (使い回しの本文やチュートリアル文言)を出すのではなく、抽象的なバー形状を
/// ぼかすだけにして「ここに何かある」ことだけを伝える(内容そのものはフェイクに
/// しない)。DeepNotesの一覧/詳細ページなど、複数箇所で共通して使う。
class BlurredSummaryPlaceholder extends StatelessWidget {
  const BlurredSummaryPlaceholder({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(
            height: 10,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(0.9), bar(0.55)],
      ),
    );
  }
}
