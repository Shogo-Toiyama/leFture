// lib/infrastructure/chat/chat_image_shrinker.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';

/// PNGに透明(アルファ)を持てる形式か、透明色(tRNS)を持つか。ヘッダーだけを見る。
/// 持てなければ(JPEGやアルファの無いPNG)、ピクセルを調べるまでもなく不透明。
bool pngMayHaveTransparency(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 33) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  // IHDRの色の種類: 4=グレー+アルファ, 6=RGBA
  final colorType = bytes[25];
  if (colorType == 4 || colorType == 6) return true;
  // パレット・グレー・RGBは、IDATの前にtRNSがあれば透明色を持つ
  var pos = 8;
  while (pos + 8 <= bytes.length) {
    final length =
        (bytes[pos] << 24) |
        (bytes[pos + 1] << 16) |
        (bytes[pos + 2] << 8) |
        bytes[pos + 3];
    final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
    if (type == 'tRNS') return true;
    if (type == 'IDAT' || type == 'IEND') return false;
    pos += 12 + length;
  }
  return false;
}

/// 端末のネイティブで画像を縮める([ChatImageShrinker]の本物)。
///
/// 長辺[chatImageLongSide]に縮めて、JPEG(画質[chatJpegQuality])にする。向き(EXIF)は反映し、
/// EXIF(撮影場所など)は残さない。透明な部分がある画像は、[keepTransparency]ならPNGのまま、
/// そうでなければ白い背景に重ねてJPEGにする。
class NativeChatImageShrinker implements ChatImageShrinker {
  const NativeChatImageShrinker();

  @override
  Future<ShrunkImage> shrink(
    Uint8List bytes, {
    required bool keepTransparency,
  }) async {
    try {
      final size = await _sizeOf(bytes);
      final transparent =
          pngMayHaveTransparency(bytes) &&
          size != null &&
          await _hasTransparency(bytes, size);
      if (transparent && keepTransparency) {
        return ShrunkImage(
          bytes: await _compress(bytes, size, png: true),
          isPng: true,
        );
      }
      if (transparent) {
        // JPEGは透明を黒で塗るので、先に白い背景に重ねる
        final target = _fit(size);
        final flat = await _flattenOnWhite(bytes, target);
        return ShrunkImage(
          bytes: await _compress(flat, target, png: false),
          isPng: false,
        );
      }
      return ShrunkImage(
        bytes: await _compress(bytes, size, png: false),
        isPng: false,
      );
    } on Object {
      throw const ChatFileError('IMAGE_DECODE_FAILED');
    }
  }

  /// 画像の大きさ。この端末が読めない形式(古いAndroidのHEICなど)はnull
  /// (そのときはネイティブの縮小にまかせる)。
  Future<({int width, int height})?> _sizeOf(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return (width: descriptor.width, height: descriptor.height);
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// 長辺[chatImageLongSide]に収まる大きさ(元より大きくはしない)。
  ({int width, int height}) _fit(({int width, int height})? size) {
    if (size == null) {
      return (width: chatImageLongSide, height: chatImageLongSide);
    }
    final scale = math.min(
      1.0,
      chatImageLongSide / math.max(size.width, size.height),
    );
    return (
      width: math.max(1, (size.width * scale).round()),
      height: math.max(1, (size.height * scale).round()),
    );
  }

  Future<Uint8List> _compress(
    Uint8List bytes,
    ({int width, int height})? size, {
    required bool png,
  }) async {
    var out = await _compressOnce(bytes, _fit(size), png: png);
    // 向き(EXIF)で縦横が入れ替わる・大きさが分からなかったときは、縮めた結果の大きさで1度だけやり直す
    final result = await _sizeOf(out);
    if (result != null &&
        math.max(result.width, result.height) > chatImageLongSide * 1.05) {
      out = await _compressOnce(out, _fit(result), png: png);
    }
    return out;
  }

  Future<Uint8List> _compressOnce(
    Uint8List bytes,
    ({int width, int height}) target, {
    required bool png,
  }) async {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      // 2辺を同じ比率で指すと、長辺が[chatImageLongSide]に収まる(iOSもAndroidも)
      minWidth: target.width,
      minHeight: target.height,
      quality: chatJpegQuality,
      format: png ? CompressFormat.png : CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );
    // 端末が読めない形式のとき、例外ではなく空のバイト列が返ることがある
    if (out.isEmpty) throw StateError('flutter_image_compress returned no bytes');
    return out;
  }

  /// 透明な部分があるか(小さくして、間引いて調べる)。
  Future<bool> _hasTransparency(
    Uint8List bytes,
    ({int width, int height}) size,
  ) async {
    const probe = 256;
    final scale = math.min(1.0, probe / math.max(size.width, size.height));
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: math.max(1, (size.width * scale).round()),
      targetHeight: math.max(1, (size.height * scale).round()),
    );
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return false;
        for (var i = 3; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) < 250) return true;
        }
        return false;
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<Uint8List> _flattenOnWhite(
    Uint8List bytes,
    ({int width, int height}) target,
  ) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: target.width,
      targetHeight: target.height,
    );
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
          ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src)
          ..drawImage(image, ui.Offset.zero, ui.Paint());
        final picture = recorder.endRecording();
        final flat = await picture.toImage(image.width, image.height);
        try {
          final data = await flat.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw const ChatFileError('IMAGE_DECODE_FAILED');
          return data.buffer.asUint8List();
        } finally {
          flat.dispose();
          picture.dispose();
        }
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
