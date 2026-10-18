import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';

class _FakeShrinker implements ChatImageShrinker {
  _FakeShrinker({this.png = false, this.fail = false});

  final bool png;
  final bool fail;
  final calls = <int>[];

  @override
  Future<ShrunkImage> shrink(
    Uint8List bytes, {
    required bool keepTransparency,
  }) async {
    calls.add(bytes.length);
    if (fail) throw const ChatFileError('IMAGE_DECODE_FAILED');
    return ShrunkImage(bytes: Uint8List.fromList([1, 2, 3]), isPng: png);
  }
}

Uint8List _pptx({bool withMedia = true}) {
  final a = Archive()
    ..add(
      ArchiveFile.string(
        '[Content_Types].xml',
        '<Types><Default Extension="png" ContentType="image/png"/>'
            '<Override PartName="/ppt/media/image1.png" ContentType="image/png"/>'
            '</Types>',
      ),
    )
    ..add(
      ArchiveFile.string(
        'ppt/slides/_rels/slide1.xml.rels',
        '<Relationships><Relationship Target="../media/image1.png"/>'
            '<Relationship Target="../media/image2.jpeg"/></Relationships>',
      ),
    )
    ..add(ArchiveFile.string('ppt/slides/slide1.xml', '<p:sld/>'));
  if (withMedia) {
    // 縮める余地がある大きさ(中身は何でもよい)
    a
      ..add(ArchiveFile.bytes('ppt/media/image1.png', Uint8List(5000)))
      ..add(ArchiveFile.bytes('ppt/media/image2.jpeg', Uint8List(5000)));
  }
  return ZipEncoder().encodeBytes(a);
}

String _text(Archive a, String name) =>
    utf8.decode(a.files.firstWhere((f) => f.name == name).readBytes()!);

void main() {
  group('file kinds', () {
    test('by extension, case-insensitive', () {
      expect(chatFileKindFor('A.PDF'), ChatFileKind.pdf);
      expect(chatFileKindFor('deck.pptx'), ChatFileKind.pptx);
      expect(chatFileKindFor('report.docx'), ChatFileKind.docx);
      expect(chatFileKindFor('photo.HEIC'), ChatFileKind.image);
      expect(chatFileKindFor('notes.txt'), isNull);
    });

    test('a nameless screenshot is an image by mime type', () {
      expect(
        chatFileKindFor('image', mimeType: 'image/png'),
        ChatFileKind.image,
      );
      expect(chatFileKindFor('image', mimeType: 'text/plain'), isNull);
    });

    test('text files', () {
      expect(isChatTextFile('main.py'), isTrue);
      expect(isChatTextFile('index.HTML'), isTrue);
      expect(isChatTextFile('a.pdf'), isFalse);
      expect(isChatTextFile('data', mimeType: 'text/plain'), isTrue);
      expect(isChatTextFile('pic', mimeType: 'image/png'), isFalse);
    });

    test('jpeg name', () {
      expect(chatJpegName('shot.png'), 'shot.jpg');
      expect(chatJpegName('a.b.heic'), 'a.b.jpg');
      expect(chatJpegName(''), 'image.jpg');
      expect(chatJpegName('noext'), 'noext.jpg');
    });
  });

  group('readChatTextBytes', () {
    test('decodes utf8, normalizes CRLF and drops the BOM', () {
      final bytes = Uint8List.fromList(utf8.encode('﻿こんにちは\r\nworld'));
      expect(readChatTextBytes(bytes), 'こんにちは\nworld');
    });

    test('rejects empty text', () {
      expect(
        () => readChatTextBytes(Uint8List.fromList(utf8.encode('  \n '))),
        throwsA(
          isA<ChatFileError>().having((e) => e.code, 'code', 'FILE_EMPTY'),
        ),
      );
    });

    test('rejects text over the attachment limit', () {
      final long = Uint8List.fromList(
        utf8.encode('a' * (chatMaxAttachmentChars + 1)),
      );
      expect(
        () => readChatTextBytes(long),
        throwsA(
          isA<ChatFileError>().having(
            (e) => e.code,
            'code',
            'ATTACHMENT_TOO_LONG',
          ),
        ),
      );
    });

    test('rejects files over the size limit without decoding them', () {
      expect(
        () => readChatTextBytes(Uint8List(chatMaxTextFileBytes + 1)),
        throwsA(isA<ChatFileError>()),
      );
    });
  });

  group('office shrinking', () {
    test('lists only shrinkable media of the right directory', () {
      final media = listOfficeMedia(_pptx(), ChatFileKind.pptx);
      expect(media.map((m) => m.name), [
        'ppt/media/image1.png',
        'ppt/media/image2.jpeg',
      ]);
      expect(listOfficeMedia(_pptx(), ChatFileKind.docx), isEmpty);
    });

    test('a corrupt zip is FILE_CORRUPT', () {
      expect(
        () => listOfficeMedia(
          Uint8List.fromList([1, 2, 3, 4]),
          ChatFileKind.pptx,
        ),
        throwsA(
          isA<ChatFileError>().having((e) => e.code, 'code', 'FILE_CORRUPT'),
        ),
      );
    });

    test('png to jpeg rewrites the references', () async {
      final original = _pptx();
      final out = await shrinkOfficeFile(
        original,
        ChatFileKind.pptx,
        _FakeShrinker(),
      );
      expect(out.length, lessThan(original.length));
      final a = ZipDecoder().decodeBytes(out);
      final names = a.files.map((f) => f.name).toSet();
      expect(names, contains('ppt/media/image1.jpg'));
      expect(names, isNot(contains('ppt/media/image1.png')));
      // jpegの名前のものは同じ名前で差し替わる
      expect(names, contains('ppt/media/image2.jpeg'));
      final rels = _text(a, 'ppt/slides/_rels/slide1.xml.rels');
      expect(rels, contains('../media/image1.jpg"'));
      expect(rels, isNot(contains('image1.png')));
      final ct = _text(a, '[Content_Types].xml');
      expect(
        ct,
        contains(
          '<Override PartName="/ppt/media/image1.jpg" ContentType="image/jpeg"',
        ),
      );
      expect(
        ct,
        contains('<Default Extension="jpg" ContentType="image/jpeg"/>'),
      );
      // slideの本文は触らない
      expect(_text(a, 'ppt/slides/slide1.xml'), '<p:sld/>');
    });

    test('a transparent png stays a png under the same name', () async {
      final out = await shrinkOfficeFile(
        _pptx(),
        ChatFileKind.pptx,
        _FakeShrinker(png: true),
      );
      final names = ZipDecoder().decodeBytes(out).files.map((f) => f.name);
      expect(names, contains('ppt/media/image1.png'));
      expect(names, isNot(contains('ppt/media/image1.jpg')));
    });

    test(
      'no change when nothing gets smaller or nothing can be read',
      () async {
        final original = _pptx();
        expect(
          await shrinkOfficeFile(
            original,
            ChatFileKind.pptx,
            _FakeShrinker(fail: true),
          ),
          same(original),
        );
        final noMedia = _pptx(withMedia: false);
        expect(
          await shrinkOfficeFile(noMedia, ChatFileKind.pptx, _FakeShrinker()),
          same(noMedia),
        );
      },
    );

    test('reports progress up to 1', () async {
      final seen = <double>[];
      await shrinkOfficeFile(
        _pptx(),
        ChatFileKind.pptx,
        _FakeShrinker(),
        onProgress: seen.add,
      );
      expect(seen.last, 1);
    });

    test('a name clash picks another name', () {
      final a = Archive()
        ..add(ArchiveFile.bytes('ppt/media/a.png', Uint8List(5000)))
        ..add(ArchiveFile.bytes('ppt/media/a.jpg', Uint8List(5000)));
      final out = rebuildOffice(ZipEncoder().encodeBytes(a), [
        OfficeMediaReplacement(
          name: 'ppt/media/a.png',
          newName: 'ppt/media/a.jpg',
          bytes: Uint8List.fromList([1]),
        ),
      ]);
      final names = ZipDecoder().decodeBytes(out).files.map((f) => f.name);
      expect(names, containsAll(['ppt/media/a.jpg', 'ppt/media/a_c.jpg']));
    });
  });
}
