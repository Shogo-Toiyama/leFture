// lib/infrastructure/chat/chat_file_pipeline.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';
import 'package:lefture/infrastructure/chat/chat_image_shrinker.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'chat_file_pipeline.g.dart';

@Riverpod(keepAlive: true)
ChatFilePipeline chatFilePipeline(Ref ref) => ChatFilePipeline(
  repository: ref.watch(chatRepositoryProvider),
  shrinker: const NativeChatImageShrinker(),
  uploader: BackgroundChatFileUploader(),
);

/// ファイルを送れる状態にするまでの段階(webappの ChatFileDraft.stage と同じ)。
enum ChatFileStage { compressing, uploading, reading, ready, error }

/// 準備の取り消し(入力欄から外した・入力欄を閉じた)。
class ChatCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get cancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final fn in _listeners) {
      fn();
    }
  }

  void onCancel(void Function() fn) {
    if (_cancelled) {
      fn();
    } else {
      _listeners.add(fn);
    }
  }
}

/// 取り消されたので途中でやめた(失敗ではない)。
class ChatFileCancelled implements Exception {
  const ChatFileCancelled();
}

/// ファイルをアップロード先(R2)へPUTする。
abstract class ChatFileUploader {
  /// 失敗したら[ChatFileError]('UPLOAD_FAILED', {status})、取り消されたら[ChatFileCancelled]。
  Future<void> upload({
    required String path,
    required String url,
    required String contentType,
    required void Function(double ratio) onProgress,
    required ChatCancelToken cancel,
  });
}

/// OSのバックグラウンド転送(background_downloader)で送る。録音のアップロードと同じ仕組みで、
/// 画面を閉じて(アプリを裏に回して)も転送は続く。進み具合を見ながら待つので、group は内部の
/// 'await' に置き換わり、録音のアップロードの通知とは混ざらない。
class BackgroundChatFileUploader implements ChatFileUploader {
  @override
  Future<void> upload({
    required String path,
    required String url,
    required String contentType,
    required void Function(double ratio) onProgress,
    required ChatCancelToken cancel,
  }) async {
    final (baseDir, directory, filename) = await Task.split(filePath: path);
    final task = UploadTask(
      taskId: const Uuid().v4(),
      url: url,
      filename: filename,
      baseDirectory: baseDir,
      directory: directory,
      httpRequestMethod: 'PUT',
      post: 'binary',
      // binaryアップロードのContent-TypeはheadersではなくmimeTypeから決まる。署名したContent-Typeと
      // 食い違うとR2が403を返す(録音のアップロードで実機確認済みの落とし穴)。
      mimeType: contentType,
      // 空文字で、プラグインが既定で付けるContent-Dispositionを省く(署名に含まれていないため)。
      headers: const {'Content-Disposition': ''},
      retries: 2,
      updates: Updates.statusAndProgress,
    );
    cancel.onCancel(() => FileDownloader().cancelTaskWithId(task.taskId));
    final result = await FileDownloader().upload(
      task,
      onProgress: (ratio) {
        if (ratio >= 0) onProgress(ratio);
      },
    );
    switch (result.status) {
      case TaskStatus.complete:
        return;
      case TaskStatus.canceled:
        throw const ChatFileCancelled();
      default:
        throw ChatFileError('UPLOAD_FAILED', {
          'status': result.responseStatusCode ?? 0,
        });
    }
  }
}

/// 選んだファイルを、送れる状態(アップロード済み・中身の取り出し済み)にする。
///
/// 選ぶ → 端末で縮める → アップロード先を頼む(draftの行) → R2へ直接PUT → バックエンドが中身を取り出す
/// (LLMなし)。webappの prepareChatFile と同じ流れ。段階が進むたびにコールバックで知らせる。
class ChatFilePipeline {
  ChatFilePipeline({
    required this.repository,
    required this.shrinker,
    required this.uploader,
    this.tempDirectory = _defaultTempDirectory,
  });

  final ChatRepository repository;
  final ChatImageShrinker shrinker;
  final ChatFileUploader uploader;
  final Future<Directory> Function() tempDirectory;

  static Future<Directory> _defaultTempDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/chat_upload');
    return dir.create(recursive: true);
  }

  /// [path]の1ファイルを準備して、取り出した内容を返す。失敗は[ChatFileError]、取り消しは
  /// [ChatFileCancelled]。アップロード先を頼んだ後なら[onTarget]で下書きの行のidを渡し済み
  /// (失敗・取り消しの後始末は呼び出し側が、そのidで行う)。
  Future<ChatFileInfo> prepare({
    required String path,
    required String name,
    required ChatFileKind kind,
    required ChatCancelToken cancel,
    required void Function(ChatFileStage stage) onStage,
    required void Function(double ratio) onProgress,
    required void Function(String attachmentId) onTarget,
    void Function(Uint8List bytes)? onPreview,
  }) async {
    File? madeFile;
    try {
      onStage(ChatFileStage.compressing);
      var uploadPath = path;
      var uploadName = name.isEmpty ? 'file' : name;

      if (kind == ChatFileKind.image) {
        final shrunk = await shrinker.shrink(
          await File(path).readAsBytes(),
          keepTransparency: false,
        );
        uploadName = chatJpegName(name);
        onPreview?.call(shrunk.bytes);
        madeFile = await _write(shrunk.bytes, 'jpg');
        uploadPath = madeFile.path;
      } else if (kind == ChatFileKind.docx || kind == ChatFileKind.pptx) {
        final original = await File(path).readAsBytes();
        final shrunk = await shrinkOfficeFile(original, kind, shrinker);
        if (!identical(shrunk, original)) {
          madeFile = await _write(shrunk, kind.name);
          uploadPath = madeFile.path;
        }
      }
      _throwIfCancelled(cancel);

      final size = await File(uploadPath).length();
      final max = chatMaxFileBytes[kind]!;
      if (size > max) {
        // docx・pptxが縮めても大きいのは、たいてい動画・音声が入っているとき
        throw ChatFileError(
          kind == ChatFileKind.docx || kind == ChatFileKind.pptx
              ? 'FILE_TOO_LARGE_MEDIA'
              : 'FILE_TOO_LARGE',
          {'max_bytes': max},
        );
      }
      if (size == 0) throw const ChatFileError('FILE_EMPTY');

      final target = await _guard(
        () => repository.requestUpload(fileName: uploadName, fileSize: size),
      );
      onTarget(target.attachmentId);
      onStage(ChatFileStage.uploading);
      onProgress(0);
      await uploader.upload(
        path: uploadPath,
        url: target.uploadUrl,
        contentType: target.contentType,
        onProgress: onProgress,
        cancel: cancel,
      );
      _throwIfCancelled(cancel);

      onStage(ChatFileStage.reading);
      return await _guard(() => repository.extractAttachment(target.attachmentId));
    } on ChatFileError {
      rethrow;
    } on ChatFileCancelled {
      rethrow;
    } on Object {
      throw const ChatFileError('UPLOAD_FAILED');
    } finally {
      if (madeFile != null) {
        try {
          await madeFile.delete();
        } catch (_) {}
      }
    }
  }

  /// テキスト・コードのファイルを読む(テキストの資料にする)。大きすぎるファイルは読まずに断る。
  Future<String> readTextFile(String path) async {
    final file = File(path);
    if (await file.length() > chatMaxTextFileBytes) {
      throw const ChatFileError('ATTACHMENT_TOO_LONG', {
        'max_chars': chatMaxAttachmentChars,
      });
    }
    return readChatTextBytes(await file.readAsBytes());
  }

  void _throwIfCancelled(ChatCancelToken cancel) {
    if (cancel.cancelled) throw const ChatFileCancelled();
  }

  Future<File> _write(Uint8List bytes, String extension) async {
    final dir = await tempDirectory();
    final file = File('${dir.path}/${const Uuid().v4()}.$extension');
    return file.writeAsBytes(bytes, flush: true);
  }

  /// バックエンドのエラーを[ChatFileError]にする(error_codeと詳細を残す)。
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ChatRequestException catch (e) {
      throw ChatFileError(e.code, e.detail);
    }
  }
}
