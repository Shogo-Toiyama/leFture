import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_pipeline.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';

class _Repo extends Fake implements ChatRepository {
  final requests = <({String name, int size})>[];
  final extracted = <String>[];
  Object? uploadError;

  @override
  Future<ChatUploadTarget> requestUpload({
    required String fileName,
    required int fileSize,
  }) async {
    requests.add((name: fileName, size: fileSize));
    if (uploadError != null) throw uploadError!;
    return ChatUploadTarget(
      attachmentId: 'att-1',
      uploadUrl: 'https://r2.example/put',
      contentType: 'image/jpeg',
      kind: ChatFileKind.image,
      maxBytes: 1,
    );
  }

  @override
  Future<ChatFileInfo> extractAttachment(String attachmentId) async {
    extracted.add(attachmentId);
    return ChatFileInfo(
      id: attachmentId,
      kind: ChatFileKind.image,
      fileName: 'x.jpg',
      fileSize: 3,
      textChars: 0,
      estimatedChars: 0,
      visionCount: 1,
      estimatedTokens: 10,
    );
  }
}

class _Shrinker implements ChatImageShrinker {
  _Shrinker(this.out);
  final Uint8List out;

  @override
  Future<ShrunkImage> shrink(
    Uint8List bytes, {
    required bool keepTransparency,
  }) async => ShrunkImage(bytes: out, isPng: false);
}

class _Uploader implements ChatFileUploader {
  Object? error;
  String? path;
  Uint8List? uploaded;
  String? contentType;

  @override
  Future<void> upload({
    required String path,
    required String url,
    required String contentType,
    required void Function(double ratio) onProgress,
    required ChatCancelToken cancel,
  }) async {
    this.path = path;
    this.contentType = contentType;
    uploaded = await File(path).readAsBytes();
    onProgress(.5);
    if (error != null) throw error!;
  }
}

void main() {
  late Directory work;
  late Directory temp;
  late _Repo repo;
  late _Uploader uploader;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('chat_pipeline_work');
    temp = await Directory.systemTemp.createTemp('chat_pipeline_temp');
    repo = _Repo();
    uploader = _Uploader();
  });

  tearDown(() async {
    await work.delete(recursive: true);
    await temp.delete(recursive: true);
  });

  Future<String> source(String name, List<int> bytes) async {
    final f = File('${work.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  ChatFilePipeline pipeline(Uint8List shrunk) => ChatFilePipeline(
    repository: repo,
    shrinker: _Shrinker(shrunk),
    uploader: uploader,
    tempDirectory: () async => temp,
  );

  test('an image is shrunk, uploaded as a jpg and read', () async {
    final stages = <ChatFileStage>[];
    final progress = <double>[];
    String? target;
    Uint8List? preview;
    final info = await pipeline(Uint8List.fromList([9, 8, 7])).prepare(
      path: await source('shot.png', [1, 2, 3, 4, 5, 6]),
      name: 'shot.png',
      kind: ChatFileKind.image,
      cancel: ChatCancelToken(),
      onStage: stages.add,
      onProgress: progress.add,
      onTarget: (id) => target = id,
      onPreview: (b) => preview = b,
    );

    expect(stages, [
      ChatFileStage.compressing,
      ChatFileStage.uploading,
      ChatFileStage.reading,
    ]);
    expect(repo.requests.single, (name: 'shot.jpg', size: 3));
    expect(uploader.uploaded, [9, 8, 7]);
    expect(uploader.contentType, 'image/jpeg');
    expect(progress, [0, .5]);
    expect(target, 'att-1');
    expect(preview, [9, 8, 7]);
    expect(info.id, 'att-1');
    expect(repo.extracted, ['att-1']);
    // 縮めた一時ファイルは残さない
    expect(temp.listSync(), isEmpty);
  });

  test('a pdf is uploaded as it is, without a temp copy', () async {
    final path = await source('a.pdf', [1, 2, 3]);
    await pipeline(Uint8List(0)).prepare(
      path: path,
      name: 'a.pdf',
      kind: ChatFileKind.pdf,
      cancel: ChatCancelToken(),
      onStage: (_) {},
      onProgress: (_) {},
      onTarget: (_) {},
    );
    expect(uploader.path, path);
    expect(repo.requests.single, (name: 'a.pdf', size: 3));
    expect(File(path).existsSync(), isTrue);
  });

  test(
    'an image over the limit is refused before asking for a target',
    () async {
      await expectLater(
        pipeline(Uint8List(31 * 1024 * 1024)).prepare(
          path: await source('big.png', [1]),
          name: 'big.png',
          kind: ChatFileKind.image,
          cancel: ChatCancelToken(),
          onStage: (_) {},
          onProgress: (_) {},
          onTarget: (_) {},
        ),
        throwsA(
          isA<ChatFileError>()
              .having((e) => e.code, 'code', 'FILE_TOO_LARGE')
              .having((e) => e.detail['max_bytes'], 'max', 30 * 1024 * 1024),
        ),
      );
      expect(repo.requests, isEmpty);
      expect(temp.listSync(), isEmpty);
    },
  );

  test('backend errors keep their code and detail', () async {
    repo.uploadError = const ChatRequestException(
      'TOO_MANY_DRAFTS',
      'x',
      detail: {'max': 5},
    );
    await expectLater(
      pipeline(Uint8List.fromList([1])).prepare(
        path: await source('a.png', [1]),
        name: 'a.png',
        kind: ChatFileKind.image,
        cancel: ChatCancelToken(),
        onStage: (_) {},
        onProgress: (_) {},
        onTarget: (_) {},
      ),
      throwsA(
        isA<ChatFileError>()
            .having((e) => e.code, 'code', 'TOO_MANY_DRAFTS')
            .having((e) => e.detail['max'], 'max', 5),
      ),
    );
    expect(temp.listSync(), isEmpty);
  });

  test('an upload failure is reported with its status and cleans up', () async {
    uploader.error = const ChatFileError('UPLOAD_FAILED', {'status': 403});
    String? target;
    await expectLater(
      pipeline(Uint8List.fromList([1])).prepare(
        path: await source('a.png', [1]),
        name: 'a.png',
        kind: ChatFileKind.image,
        cancel: ChatCancelToken(),
        onStage: (_) {},
        onProgress: (_) {},
        onTarget: (id) => target = id,
      ),
      throwsA(
        isA<ChatFileError>()
            .having((e) => e.code, 'code', 'UPLOAD_FAILED')
            .having((e) => e.detail['status'], 'status', 403),
      ),
    );
    // アップロード先を頼んだ後の失敗は、下書きの行のidが渡っている(呼び出し側が消せる)
    expect(target, 'att-1');
    expect(repo.extracted, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test('cancelling stops the work and is not an error', () async {
    final cancel = ChatCancelToken()..cancel();
    await expectLater(
      pipeline(Uint8List.fromList([1])).prepare(
        path: await source('a.png', [1]),
        name: 'a.png',
        kind: ChatFileKind.image,
        cancel: cancel,
        onStage: (_) {},
        onProgress: (_) {},
        onTarget: (_) {},
      ),
      throwsA(isA<ChatFileCancelled>()),
    );
    expect(repo.requests, isEmpty);
  });

  test('an unreadable source becomes UPLOAD_FAILED', () async {
    await expectLater(
      pipeline(Uint8List(0)).prepare(
        path: '${work.path}/missing.png',
        name: 'missing.png',
        kind: ChatFileKind.image,
        cancel: ChatCancelToken(),
        onStage: (_) {},
        onProgress: (_) {},
        onTarget: (_) {},
      ),
      throwsA(
        isA<ChatFileError>().having((e) => e.code, 'code', 'UPLOAD_FAILED'),
      ),
    );
  });

  test('cancel token calls late listeners immediately', () {
    final token = ChatCancelToken();
    var called = 0;
    token.onCancel(() => called++);
    token.cancel();
    token.cancel();
    token.onCancel(() => called++);
    expect(called, 2);
  });
}
