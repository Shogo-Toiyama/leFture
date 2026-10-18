import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/infrastructure/chat/chat_image_shrinker.dart';

/// IHDRだけの最小のPNG(色の種類を指定)に、続くチャンクを足したもの。
Uint8List _png(int colorType, [List<String> chunks = const []]) {
  final b = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add([0, 0, 0, 13])
    ..add('IHDR'.codeUnits)
    ..add([0, 0, 0, 1, 0, 0, 0, 1, 8, colorType, 0, 0, 0])
    ..add([0, 0, 0, 0]);
  for (final c in chunks) {
    b
      ..add([0, 0, 0, 0])
      ..add(c.codeUnits)
      ..add([0, 0, 0, 0]);
  }
  return b.toBytes();
}

void main() {
  group('pngMayHaveTransparency', () {
    test('alpha color types may be transparent', () {
      expect(pngMayHaveTransparency(_png(6)), isTrue);
      expect(pngMayHaveTransparency(_png(4)), isTrue);
    });

    test('opaque color types are not, unless there is a tRNS chunk', () {
      expect(pngMayHaveTransparency(_png(2, ['IDAT', 'IEND'])), isFalse);
      expect(pngMayHaveTransparency(_png(3, ['tRNS', 'IDAT'])), isTrue);
      expect(pngMayHaveTransparency(_png(3, ['IDAT', 'tRNS'])), isFalse);
    });

    test('not a png', () {
      expect(pngMayHaveTransparency(Uint8List(100)), isFalse);
      expect(pngMayHaveTransparency(Uint8List(3)), isFalse);
    });
  });
}
