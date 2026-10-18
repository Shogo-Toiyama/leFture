import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_pipeline.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';

/// ファイル添付のテスト用の偽物(バックエンド・画像の縮小・アップロード)。

class FakeFileRepo extends Fake implements ChatRepository {
  var nextId = 0;
  Object? extractError;
  final removed = <String>[];

  @override
  Future<ChatUploadTarget> requestUpload({
    required String fileName,
    required int fileSize,
  }) async => ChatUploadTarget(
    attachmentId: 'att-${++nextId}',
    uploadUrl: 'https://r2.example/put',
    contentType: 'application/pdf',
    kind: ChatFileKind.pdf,
    maxBytes: 1,
  );

  @override
  Future<ChatFileInfo> extractAttachment(String attachmentId) async {
    if (extractError != null) throw extractError!;
    return ChatFileInfo(
      id: attachmentId,
      kind: ChatFileKind.pdf,
      fileName: 'a.pdf',
      fileSize: 3,
      pageCount: 4,
      textChars: 100,
      estimatedChars: 100,
      visionCount: 0,
      estimatedTokens: 50,
    );
  }

  @override
  Future<void> removeAttachment(String attachmentId) async {
    removed.add(attachmentId);
  }
}

class FakeShrinker implements ChatImageShrinker {
  FakeShrinker([Uint8List? out]) : out = out ?? Uint8List.fromList([1, 2]);

  /// 縮めた結果として返す画像(画面に出すテストでは、読める画像を渡す)。
  final Uint8List out;

  @override
  Future<ShrunkImage> shrink(
    Uint8List bytes, {
    required bool keepTransparency,
  }) async => ShrunkImage(bytes: out, isPng: false);
}

class FakeUploader implements ChatFileUploader {
  /// 非nullなら、これが終わるまでアップロードを止める。
  Completer<void>? gate;

  @override
  Future<void> upload({
    required String path,
    required String url,
    required String contentType,
    required void Function(double ratio) onProgress,
    required ChatCancelToken cancel,
  }) async {
    onProgress(.25);
    final g = gate;
    if (g != null) {
      cancel.onCancel(() {
        if (!g.isCompleted) g.completeError(const ChatFileCancelled());
      });
      await g.future;
    }
  }
}
