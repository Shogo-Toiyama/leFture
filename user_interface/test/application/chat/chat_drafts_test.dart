import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/application/chat/chat_drafts.dart';
import 'package:lefture/core/utils/chat_composer_mentions.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_pipeline.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';

import 'fake_chat_files.dart';

void main() {
  late Directory work;
  late Directory temp;
  late FakeFileRepo repo;
  late FakeUploader uploader;
  late ChatDraftsController controller;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('chat_drafts_work');
    temp = await Directory.systemTemp.createTemp('chat_drafts_temp');
    repo = FakeFileRepo();
    uploader = FakeUploader();
    controller = ChatDraftsController(
      repository: repo,
      pipeline: ChatFilePipeline(
        repository: repo,
        shrinker: FakeShrinker(),
        uploader: uploader,
        tempDirectory: () async => temp,
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    await work.delete(recursive: true);
    await temp.delete(recursive: true);
  });

  Future<PickedChatFile> file(String name, List<int> bytes) async {
    final f = File('${work.path}/$name');
    await f.writeAsBytes(bytes);
    return PickedChatFile(path: f.path, name: name);
  }

  /// 準備(縮める→アップロード→取り出し)が終わるまで待つ。
  Future<void> settle() async {
    for (var i = 0; i < 200 && controller.filesPending; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  ChatFileDraft fileDraft(int i) => controller.drafts[i] as ChatFileDraft;

  test('a text file becomes a text draft with its content', () async {
    final result = await controller.addFiles([
      await file('main.py', 'print(1)\r\n'.codeUnits),
    ]);
    expect(result.notice, isNull);
    final draft = result.added.single as ChatTextDraft;
    expect(draft.title, 'main.py');
    expect(draft.content, 'print(1)\n');
    expect(controller.filesPending, isFalse);
    expect(controller.toNewAttachments().single, isA<ChatTextAttachment>());
    expect(controller.tokenIdFor(DraftMention(draft.localId)), draft.localId);
  });

  test('an unsupported file is refused with a notice', () async {
    final result = await controller.addFiles([
      await file('movie.mp4', [1, 2, 3]),
    ]);
    expect(result.added, isEmpty);
    expect(
      (result.notice as ChatNoticeFileError).code,
      'UNSUPPORTED_FILE_TYPE',
    );
  });

  test('an empty text file is refused', () async {
    final result = await controller.addFiles([
      await file('empty.txt', [32, 10]),
    ]);
    expect(result.added, isEmpty);
    expect((result.notice as ChatNoticeFileError).code, 'FILE_EMPTY');
  });

  test('a pdf goes compressing -> ready and can be sent', () async {
    final result = await controller.addFiles([
      await file('a.pdf', [1, 2, 3]),
    ]);
    final draft = result.added.single as ChatFileDraft;
    expect(draft.stage, ChatFileStage.compressing);
    expect(draft.localPath, isNotNull);
    expect(controller.filesPending, isTrue);
    // 準備中は送る資料に入らない
    expect(controller.toNewAttachments(), isEmpty);

    await settle();
    final ready = fileDraft(0);
    expect(ready.stage, ChatFileStage.ready);
    expect(ready.info!.pageCount, 4);
    expect(ready.attachmentId, 'att-1');
    final sent = controller.toNewAttachments().single as ChatFileAttachment;
    expect(sent.attachmentId, 'att-1');
    expect(sent.fileName, 'a.pdf');
    expect(sent.fileKind, ChatFileKind.pdf);
    expect(controller.tokenIdFor(DraftMention(ready.localId)), 'att-1');
  });

  test('an image gets its preview and a jpg name', () async {
    await controller.addFiles([
      await file('shot.png', [1]),
    ]);
    await settle();
    final d = fileDraft(0);
    expect(d.previewBytes, [1, 2]);
    expect(d.fileName, 'shot.png');
    expect(d.stage, ChatFileStage.ready);
  });

  test('a failed file stays as an error until removed', () async {
    repo.extractError = const ChatRequestException('PDF_ENCRYPTED', 'x');
    await controller.addFiles([
      await file('a.pdf', [1, 2, 3]),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final d = fileDraft(0);
    expect(d.stage, ChatFileStage.error);
    expect(d.errorCode, 'PDF_ENCRYPTED');
    expect(controller.filesPending, isTrue);

    controller.remove(d.localId);
    expect(controller.drafts, isEmpty);
    // アップロード先を頼んだ後なので、サーバーの下書きも消す
    expect(repo.removed, ['att-1']);
  });

  test(
    'removing while uploading cancels and deletes the server draft',
    () async {
      uploader.gate = Completer<void>();
      await controller.addFiles([
        await file('a.pdf', [1, 2, 3]),
      ]);
      // アップロードが始まるまで待つ
      for (
        var i = 0;
        i < 100 && fileDraft(0).stage != ChatFileStage.uploading;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(fileDraft(0).progress, .25);
      controller.remove(controller.drafts.single.localId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.drafts, isEmpty);
      expect(repo.removed, ['att-1']);
    },
  );

  test('stops at the per-message limit with a notice', () async {
    final files = [
      for (var i = 0; i < chatMaxAttachmentsPerMessage + 1; i++)
        await file('f$i.txt', 'text $i'.codeUnits),
    ];
    final result = await controller.addFiles(files);
    expect(result.added, hasLength(chatMaxAttachmentsPerMessage));
    expect(
      (result.notice as ChatNoticeLimit).max,
      chatMaxAttachmentsPerMessage,
    );
    expect(controller.isFull, isTrue);
    expect(controller.addText(title: 'x', content: 'y'), isNull);
  });

  test('edits a text draft in place', () {
    final d = controller.addText(title: 'a', content: 'b')!;
    controller.updateText(d.localId, title: 'c', content: 'd');
    final now = controller.drafts.single as ChatTextDraft;
    expect((now.title, now.content), ('c', 'd'));
    expect(now.localId, d.localId);
  });

  test(
    'clearAfterSend keeps the server rows (they became sent materials)',
    () async {
      await controller.addFiles([
        await file('a.pdf', [1]),
      ]);
      await settle();
      controller.clearAfterSend();
      expect(controller.drafts, isEmpty);
      controller.dispose();
      expect(repo.removed, isEmpty);
    },
  );

  test('closing the composer deletes unsent file drafts', () async {
    await controller.addFiles([
      await file('a.pdf', [1]),
    ]);
    await settle();
    controller.dispose();
    expect(repo.removed, ['att-1']);
  });

  test('restore brings back text and uploaded files as ready', () {
    controller.restore([
      const ChatTextAttachment(localId: 't1', title: 'n', content: 'c'),
      const ChatFileAttachment(
        attachmentId: 'att-9',
        fileName: 'x.pdf',
        fileKind: ChatFileKind.pdf,
      ),
    ]);
    expect(controller.drafts, hasLength(2));
    expect(fileDraft(1).stage, ChatFileStage.ready);
    expect(controller.filesPending, isFalse);
    expect(controller.toNewAttachments(), hasLength(2));
  });
}
