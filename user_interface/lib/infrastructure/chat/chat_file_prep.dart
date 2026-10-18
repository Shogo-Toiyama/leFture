// lib/infrastructure/chat/chat_file_prep.dart
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lefture/domain/entities/chat.dart';

/// チャットに添付するファイルを、アップロードの前に端末で整える。
/// webappの chatFiles.ts / chatFileShrink.ts の移植(バックエンド: chat_files.py)。
///
/// 画像は長辺2048pxのJPEGに、docx・pptxは中の画像を同じように縮めて開ける正しいファイルのまま
/// 作り直す(2026-10-06の検証で、37枚のスクショのpptxが32MB → 5.4MB、読み取りの精度は変わらなかった)。
/// PDFはそのまま送る(上限が大きい)。テキスト・コードのファイルは、アップロードせずに中身を読んで
/// テキストの資料にする。作り直すとEXIF(撮影場所など)は消える。

/// 端末で選んだファイル(ファイル選択・写真・カメラ)。
class PickedChatFile {
  const PickedChatFile({required this.path, required this.name, this.mimeType});

  final String path;
  final String name;
  final String? mimeType;
}

/// 準備に失敗した理由。codeは文言の表(chatFileErrorCopy)の鍵で、バックエンドのerror_codeと同じ。
class ChatFileError implements Exception {
  const ChatFileError(this.code, [this.detail = const {}]);

  final String code;
  final Map<String, dynamic> detail;

  @override
  String toString() => 'ChatFileError($code, $detail)';
}

/// 画像・docx/pptxの中の画像を縮める長辺と、JPEGの画質。
const chatImageLongSide = 2048;
const chatJpegQuality = 85;

const _kindByExtension = <String, ChatFileKind>{
  'pdf': ChatFileKind.pdf,
  'docx': ChatFileKind.docx,
  'pptx': ChatFileKind.pptx,
  'jpg': ChatFileKind.image,
  'jpeg': ChatFileKind.image,
  'png': ChatFileKind.image,
  'webp': ChatFileKind.image,
  'gif': ChatFileKind.image,
  'bmp': ChatFileKind.image,
  'heic': ChatFileKind.image,
  'heif': ChatFileKind.image,
};

/// 中身をそのまま読んでテキストの資料にするファイル(授業の課題・自分のコードなど)。
const chatTextExtensions = <String>{
  'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml', 'toml', //
  'ini', 'log', 'tex', 'bib', 'rst',
  'html', 'htm', 'css', 'scss', 'js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'vue',
  'svelte',
  'py', 'ipynb', 'java', 'kt', 'kts', 'scala', 'c', 'h', 'cc', 'cpp', 'hpp',
  'cs', 'go', 'rs', 'swift', 'm', 'mm',
  'rb', 'php', 'pl', 'lua', 'r', 'jl', 'hs', 'ml', 'ex', 'exs', 'erl', 'clj',
  'lisp', 'scm', 'rkt', 'dart',
  'sql', 'sh', 'bash', 'zsh', 'ps1', 'bat', 'asm', 's', 'v', 'sv', 'vhd',
  'vhdl', 'mat', 'gradle', 'cmake',
};

/// テキストのファイルとして読む大きさの上限(10万字の日本語でも収まる)。
const chatMaxTextFileBytes = 2 * 1024 * 1024;

/// ファイル選択に渡す拡張子(ドットなし)。
List<String> get chatPickableExtensions => [
  ..._kindByExtension.keys,
  ...chatTextExtensions,
];

String _extensionOf(String name) {
  final i = name.lastIndexOf('.');
  return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
}

/// アップロードして読むファイルの種類。テキストとして読むもの・未対応はnull。
ChatFileKind? chatFileKindFor(String name, {String? mimeType}) {
  final byExtension = _kindByExtension[_extensionOf(name)];
  if (byExtension != null) return byExtension;
  // 名前に拡張子が無いスクショなどは、種類でも判定する
  if (mimeType != null && mimeType.startsWith('image/')) {
    return ChatFileKind.image;
  }
  return null;
}

bool isChatTextFile(String name, {String? mimeType}) =>
    chatTextExtensions.contains(_extensionOf(name)) ||
    ((mimeType?.startsWith('text/') ?? false) &&
        chatFileKindFor(name, mimeType: mimeType) == null);

/// 画像の名前の拡張子を.jpgにする(縮めた後の名前)。
String chatJpegName(String name) {
  final i = name.lastIndexOf('.');
  final base = i > 0 ? name.substring(0, i) : (name.isEmpty ? 'image' : name);
  return '$base.jpg';
}

/// テキスト・コードのファイルの中身を、テキストの資料にする文字列にする。
/// 長すぎれば ATTACHMENT_TOO_LONG、空なら FILE_EMPTY。
String readChatTextBytes(Uint8List bytes) {
  const tooLong = ChatFileError('ATTACHMENT_TOO_LONG', {
    'max_chars': chatMaxAttachmentChars,
  });
  if (bytes.length > chatMaxTextFileBytes) throw tooLong;
  final text = utf8.decode(bytes, allowMalformed: true).replaceAll('\r\n', '\n');
  // 先頭のBOMは文字としては要らない
  final clean = text.startsWith('﻿') ? text.substring(1) : text;
  if (clean.trim().isEmpty) throw const ChatFileError('FILE_EMPTY');
  if (clean.length > chatMaxAttachmentChars) throw tooLong;
  return clean;
}

// ---------------------------------------------------------------------------
// 画像を縮める(実装は端末のネイティブ。テストでは差し替える)
// ---------------------------------------------------------------------------

class ShrunkImage {
  const ShrunkImage({required this.bytes, required this.isPng});

  final Uint8List bytes;
  final bool isPng;
}

abstract class ChatImageShrinker {
  /// 画像を長辺[chatImageLongSide]に縮める。[keepTransparency]なら、透明な部分がある画像はPNGのまま
  /// (docx・pptxの中のロゴや図をJPEGにすると、透明な部分が白い四角になるため)。それ以外はJPEG。
  /// 読めない画像は[ChatFileError]('IMAGE_DECODE_FAILED')。
  Future<ShrunkImage> shrink(Uint8List bytes, {required bool keepTransparency});
}

// ---------------------------------------------------------------------------
// docx・pptxの中の画像を縮める
// ---------------------------------------------------------------------------

String _mediaDir(ChatFileKind kind) =>
    kind == ChatFileKind.docx ? 'word/media/' : 'ppt/media/';

final _shrinkableMedia = RegExp(r'\.(png|jpe?g|bmp)$', caseSensitive: false);

/// 縮める候補の画像(zipの中の名前と中身)。docx・pptx以外や壊れたzipは[ChatFileError]('FILE_CORRUPT')。
List<({String name, Uint8List bytes})> listOfficeMedia(
  Uint8List file,
  ChatFileKind kind,
) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(file);
  } catch (_) {
    throw const ChatFileError('FILE_CORRUPT');
  }
  // 壊れたファイルは、例外ではなく空のarchiveとして読まれることがある
  if (archive.files.isEmpty) throw const ChatFileError('FILE_CORRUPT');
  final dir = _mediaDir(kind);
  return [
    for (final f in archive.files)
      if (f.isFile && f.name.startsWith(dir) && _shrinkableMedia.hasMatch(f.name))
        (name: f.name, bytes: f.readBytes() ?? Uint8List(0)),
  ];
}

/// 縮めた画像の差し替え。[newName]が[name]と違うとき、参照(.relsのTarget・[Content_Types].xml)も書き換える。
class OfficeMediaReplacement {
  const OfficeMediaReplacement({
    required this.name,
    required this.newName,
    required this.bytes,
  });

  final String name;
  final String newName;
  final Uint8List bytes;
}

void _removeFile(Archive archive, String name) {
  final f = archive.files.where((x) => x.name == name).firstOrNull;
  if (f != null) archive.removeFile(f);
}

/// 差し替えて作り直したファイル。小さくならなければ元のファイルを返す。
Uint8List rebuildOffice(
  Uint8List original,
  List<OfficeMediaReplacement> replacements,
) {
  if (replacements.isEmpty) return original;
  final archive = ZipDecoder().decodeBytes(original);
  final taken = {for (final f in archive.files) f.name};
  final renames = <(String, String)>[];

  for (final r in replacements) {
    var target = r.newName;
    final renamed = target != r.name;
    // 同じ名前が既にあれば、別の名前にする
    if (renamed && taken.contains(target)) {
      target = target.replaceFirst(RegExp(r'\.jpg$'), '_c.jpg');
    }
    _removeFile(archive, r.name);
    archive.add(ArchiveFile.bytes(target, r.bytes));
    taken.add(target);
    if (target != r.name) renames.add((r.name, target));
  }

  if (renames.isNotEmpty) {
    String base(String path) => path.substring(path.lastIndexOf('/') + 1);
    final files = [...archive.files];
    for (final f in files) {
      if (!f.isFile || !f.name.endsWith('.rels')) continue;
      var xml = utf8.decode(f.readBytes() ?? Uint8List(0), allowMalformed: true);
      var touched = false;
      for (final (from, to) in renames) {
        final needle = '/${base(from)}"';
        if (xml.contains(needle)) {
          xml = xml.split(needle).join('/${base(to)}"');
          touched = true;
        }
      }
      if (touched) {
        _removeFile(archive, f.name);
        archive.add(ArchiveFile.bytes(f.name, utf8.encode(xml)));
      }
    }
    const ctPath = '[Content_Types].xml';
    final ct = archive.files.where((f) => f.name == ctPath).firstOrNull;
    if (ct != null) {
      var xml = utf8.decode(ct.readBytes() ?? Uint8List(0), allowMalformed: true);
      for (final (from, to) in renames) {
        final part = RegExp.escape(from);
        xml = xml.replaceAllMapped(
          RegExp('(<Override[^>]*PartName="/$part"[^>]*>)'),
          (m) => m
              .group(1)!
              .replaceFirst('/$from"', '/$to"')
              .replaceFirst(
                RegExp(r'ContentType="[^"]*"'),
                'ContentType="image/jpeg"',
              ),
        );
      }
      if (!RegExp('Extension="jpg"', caseSensitive: false).hasMatch(xml)) {
        xml = xml.replaceFirst(
          '</Types>',
          '<Default Extension="jpg" ContentType="image/jpeg"/></Types>',
        );
      }
      _removeFile(archive, ctPath);
      archive.add(ArchiveFile.bytes(ctPath, utf8.encode(xml)));
    }
  }
  final out = ZipEncoder().encodeBytes(archive);
  return out.length < original.length ? out : original;
}

/// docx・pptxの中の画像を縮めて作り直す(開ける正しいファイルのまま)。PNGをJPEGにしたときは、
/// 参照も書き換える。小さくならなければ元のファイルを返す。zipの読み書きは別のisolateで行う
/// (大きなファイルで画面が止まらないように)。
Future<Uint8List> shrinkOfficeFile(
  Uint8List file,
  ChatFileKind kind,
  ChatImageShrinker shrinker, {
  void Function(double ratio)? onProgress,
}) async {
  final media = await Isolate.run(() => listOfficeMedia(file, kind));
  if (media.isEmpty) return file;

  final replacements = <OfficeMediaReplacement>[];
  for (var i = 0; i < media.length; i++) {
    onProgress?.call(i / media.length);
    final m = media[i];
    final ShrunkImage shrunk;
    try {
      shrunk = await shrinker.shrink(m.bytes, keepTransparency: true);
    } catch (_) {
      continue; // 読めない画像はそのまま
    }
    if (shrunk.bytes.length >= m.bytes.length * 0.9) continue;
    final isPng = m.name.toLowerCase().endsWith('.png');
    if (!shrunk.isPng && isPng) {
      replacements.add(
        OfficeMediaReplacement(
          name: m.name,
          newName: m.name.replaceFirst(RegExp(r'\.png$', caseSensitive: false), '.jpg'),
          bytes: shrunk.bytes,
        ),
      );
    } else {
      // 拡張子と中身の形式が食い違わないものだけ、同じ名前で差し替える
      final isJpegName = RegExp(r'\.jpe?g$', caseSensitive: false).hasMatch(m.name);
      if ((shrunk.isPng && isPng) || (!shrunk.isPng && isJpegName)) {
        replacements.add(
          OfficeMediaReplacement(name: m.name, newName: m.name, bytes: shrunk.bytes),
        );
      }
    }
  }
  onProgress?.call(1);
  if (replacements.isEmpty) return file;
  return Isolate.run(() => rebuildOffice(file, replacements));
}
