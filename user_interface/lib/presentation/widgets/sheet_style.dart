// lib/presentation/widgets/sheet_style.dart
import 'package:flutter/material.dart';

// 下から出るシートの見た目の決まり(言語選択のシートに合わせる)。
// チャット・資料・出典・自分像のシートで揃えて、どれも同じ手触りにする。

/// 上の角の丸み。
const kSheetRadius = 24.0;

/// つまみ(ドラッグハンドル)の大きさ。
const kSheetHandleSize = Size(40, 4);

/// つまみの上の余白。
const kSheetHandleTop = 12.0;

const kSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(kSheetRadius)),
);

/// つまみ。
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kSheetHandleSize.width,
      height: kSheetHandleSize.height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(kSheetHandleSize.height / 2),
      ),
    );
  }
}

/// シートの中身の上に、つまみを足す(言語選択のシートと同じ位置・大きさ)。
Widget withSheetHandle(Widget child, {required Color handleColor}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: kSheetHandleTop),
      SheetHandle(color: handleColor),
      const SizedBox(height: 8),
      Flexible(child: child),
    ],
  );
}
