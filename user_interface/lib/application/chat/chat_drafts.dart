// lib/application/chat/chat_drafts.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lefture/core/utils/chat_composer_mentions.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_file_pipeline.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:uuid/uuid.dart';

/// 入力欄で、この送信に新しく添える資料(送るまで何度でも直せる)。webappの ChatDraftAttachment。
sealed class ChatDraft {
  const ChatDraft({required this.localId, required this.title});

  final String localId;

  /// 本人が付けた名前(空なら、本文の最初の行・ファイル名で呼ぶ)
  final String title;
}

class ChatTextDraft extends ChatDraft {
  const ChatTextDraft({
    required super.localId,
    required super.title,
    required this.content,
  });

  final String content;
}

/// ファイルの下書き。選ぶ → 端末で縮める → アップロード → バックエンドが中身を取り出す(LLMなし)
/// → ready。readyになるまで送れない。
class ChatFileDraft extends ChatDraft {
  const ChatFileDraft({
    required super.localId,
    required super.title,
    required this.fileKind,
    required this.fileName,
    required this.stage,
    this.progress,
    this.attachmentId,
    this.info,
    this.errorCode,
    this.errorDetail = const {},
    this.previewBytes,
    this.localPath,
  });

  final ChatFileKind fileKind;
  final String fileName;
  final ChatFileStage stage;

  /// uploadingのときの進み具合(0〜1)
  final double? progress;

  /// アップロード先を頼んだ後(draftの行のid)
  final String? attachmentId;
  final ChatFileInfo? info;
  final String? errorCode;
  final Map<String, dynamic> errorDetail;

  /// 画像のとき: チップに出す小さな見本(縮めた後のJPEG)
  final Uint8List? previewBytes;

  /// PDFのとき: 送る前に中身を確かめるための、端末のファイル
  final String? localPath;

  ChatFileDraft copyWith({
    ChatFileStage? stage,
    double? Function()? progress,
    String? attachmentId,
    ChatFileInfo? info,
    String? errorCode,
    Map<String, dynamic>? errorDetail,
    Uint8List? previewBytes,
  }) => ChatFileDraft(
    localId: localId,
    title: title,
    fileKind: fileKind,
    fileName: fileName,
    stage: stage ?? this.stage,
    progress: progress != null ? progress() : this.progress,
    attachmentId: attachmentId ?? this.attachmentId,
    info: info ?? this.info,
    errorCode: errorCode ?? this.errorCode,
    errorDetail: errorDetail ?? this.errorDetail,
    previewBytes: previewBytes ?? this.previewBytes,
    localPath: localPath,
  );
}

/// 入力欄の上に出す案内(チップにならなかったもの)。
sealed class ChatComposerNotice {
  const ChatComposerNotice();
}

/// 1通に添えられる資料の数の上限。
class ChatNoticeLimit extends ChatComposerNotice {
  const ChatNoticeLimit(this.max);
  final int max;
}

/// ファイルを読めなかった・添えられなかった理由。
class ChatNoticeFileError extends ChatComposerNotice {
  const ChatNoticeFileError(this.code, [this.detail = const {}]);
  final String code;
  final Map<String, dynamic> detail;
}

/// ファイルを足した結果: 足した下書き(順番どおり)と、チップにならなかった理由。
class ChatAddResult {
  const ChatAddResult({this.added = const [], this.notice});

  final List<ChatDraft> added;
  final ChatComposerNotice? notice;
}

/// 入力欄の資料の下書きと、ファイルの準備(縮める→アップロード→取り出し)の進み具合を持つ。
/// 入力欄(画面)が持ち、画面が閉じられたら[dispose]で、送っていない下書きを片づける。
class ChatDraftsController extends ChangeNotifier {
  ChatDraftsController({
    required this.pipeline,
    required this.repository,
    this.maxPerMessage = chatMaxAttachmentsPerMessage,
  });

  final ChatFilePipeline pipeline;
  final ChatRepository repository;
  final int maxPerMessage;

  final _drafts = <ChatDraft>[];
  final _cancels = <String, ChatCancelToken>{};
  final _removed = <String>{};
  var _disposed = false;

  List<ChatDraft> get drafts => List.unmodifiable(_drafts);

  bool get isFull => _drafts.length >= maxPerMessage;

  /// 準備中・失敗したファイルがある間は送れない(失敗したものは外してもらう)。
  bool get filesPending => _drafts.any(
    (d) => d is ChatFileDraft && d.stage != ChatFileStage.ready,
  );

  ChatDraft? draftById(String localId) =>
      _drafts.where((d) => d.localId == localId).firstOrNull;

  String newLocalId() => const Uuid().v4();

  // -------------------------------------------------------------------------
  // 足す・直す・外す
  // -------------------------------------------------------------------------

  /// テキストの資料を足す。上限なら足さずにnull。
  ChatTextDraft? addText({required String title, required String content}) {
    if (isFull) return null;
    final draft = ChatTextDraft(
      localId: newLocalId(),
      title: title,
      content: content,
    );
    _drafts.add(draft);
    notifyListeners();
    return draft;
  }

  void updateText(String localId, {required String title, required String content}) {
    final i = _drafts.indexWhere((d) => d.localId == localId);
    if (i < 0 || _drafts[i] is! ChatTextDraft) return;
    _drafts[i] = ChatTextDraft(localId: localId, title: title, content: content);
    notifyListeners();
  }

  /// 送れなかった送信の資料を、下書きに戻す(アップロード済みのファイルは、readyのまま戻る)。
  void restore(List<ChatNewAttachment> attachments) {
    for (final a in attachments) {
      if (isFull) break;
      switch (a) {
        case ChatTextAttachment():
          _drafts.add(
            ChatTextDraft(
              localId: a.localId,
              title: a.title,
              content: a.content,
            ),
          );
        case ChatFileAttachment():
          _drafts.add(
            ChatFileDraft(
              localId: a.attachmentId,
              title: a.title,
              fileKind: a.fileKind ?? ChatFileKind.pdf,
              fileName: a.fileName,
              stage: ChatFileStage.ready,
              attachmentId: a.attachmentId,
            ),
          );
      }
    }
    notifyListeners();
  }

  /// 選んだファイルを足す。テキスト・コードのファイルは中身を読んでテキストの資料に、そのほかは
  /// 準備(縮める→アップロード→取り出し)を始める(終わりは待たない。進み具合は[drafts]に出る)。
  Future<ChatAddResult> addFiles(List<PickedChatFile> files) async {
    final added = <ChatDraft>[];
    ChatComposerNotice? notice;
    for (final file in files) {
      if (isFull) {
        notice = ChatNoticeLimit(maxPerMessage);
        break;
      }
      final kind = chatFileKindFor(file.name, mimeType: file.mimeType);
      if (kind == null) {
        if (!isChatTextFile(file.name, mimeType: file.mimeType)) {
          notice = const ChatNoticeFileError('UNSUPPORTED_FILE_TYPE');
          continue;
        }
        try {
          final content = await pipeline.readTextFile(file.path);
          if (_disposed) return ChatAddResult(added: added, notice: notice);
          // 読んでいる間に上限に届いたら足さない
          if (isFull) {
            notice = ChatNoticeLimit(maxPerMessage);
            break;
          }
          final draft = ChatTextDraft(
            localId: newLocalId(),
            title: file.name,
            content: content,
          );
          _drafts.add(draft);
          added.add(draft);
          notifyListeners();
        } on ChatFileError catch (e) {
          notice = ChatNoticeFileError(e.code, e.detail);
        } on Object {
          notice = const ChatNoticeFileError('FILE_CORRUPT');
        }
        continue;
      }
      final draft = ChatFileDraft(
        localId: newLocalId(),
        title: '',
        fileKind: kind,
        fileName: file.name.isEmpty ? 'image' : file.name,
        stage: ChatFileStage.compressing,
        // PDFは送る前に中身を確かめられる
        localPath: kind == ChatFileKind.pdf ? file.path : null,
      );
      _drafts.add(draft);
      added.add(draft);
      notifyListeners();
      unawaited(_prepare(draft, file));
    }
    return ChatAddResult(added: added, notice: notice);
  }

  Future<void> _prepare(ChatFileDraft draft, PickedChatFile file) async {
    final id = draft.localId;
    final cancel = ChatCancelToken();
    _cancels[id] = cancel;
    try {
      final info = await pipeline.prepare(
        path: file.path,
        name: draft.fileName,
        kind: draft.fileKind,
        cancel: cancel,
        onStage: (stage) => _patch(id, (d) => d.copyWith(stage: stage)),
        onProgress: (ratio) =>
            _patch(id, (d) => d.copyWith(progress: () => ratio)),
        onTarget: (attachmentId) {
          if (_removed.contains(id)) {
            // 準備中に外された: アップロード先が分かったので、サーバーの下書きも消す
            _deleteOnServer(attachmentId);
            return;
          }
          _patch(id, (d) => d.copyWith(attachmentId: attachmentId));
        },
        onPreview: (bytes) => _patch(id, (d) => d.copyWith(previewBytes: bytes)),
      );
      if (_removed.contains(id)) {
        _deleteOnServer(info.id);
        return;
      }
      _patch(
        id,
        (d) => d.copyWith(
          stage: ChatFileStage.ready,
          info: info,
          progress: () => null,
        ),
      );
    } on ChatFileCancelled {
      // 外された・閉じられた: 後始末は外した側が行う
    } on ChatFileError catch (e) {
      if (_removed.contains(id)) return;
      _patch(
        id,
        (d) => d.copyWith(
          stage: ChatFileStage.error,
          errorCode: e.code,
          errorDetail: e.detail,
          progress: () => null,
        ),
      );
    } finally {
      _cancels.remove(id);
    }
  }

  void _patch(String localId, ChatFileDraft Function(ChatFileDraft) update) {
    if (_disposed || _removed.contains(localId)) return;
    final i = _drafts.indexWhere((d) => d.localId == localId);
    if (i < 0) return;
    final current = _drafts[i];
    if (current is! ChatFileDraft) return;
    _drafts[i] = update(current);
    notifyListeners();
  }

  /// 下書きを外す。準備中なら止め、アップロード先を頼んでいたらサーバーの下書きも消す。
  void remove(String localId) {
    final i = _drafts.indexWhere((d) => d.localId == localId);
    if (i < 0) return;
    final draft = _drafts.removeAt(i);
    if (draft is ChatFileDraft) {
      _removed.add(localId);
      _cancels[localId]?.cancel();
      final id = draft.attachmentId;
      if (id != null) _deleteOnServer(id);
    }
    notifyListeners();
  }

  void _deleteOnServer(String attachmentId) {
    unawaited(
      repository.removeAttachment(attachmentId).catchError((Object _) {}),
    );
  }

  // -------------------------------------------------------------------------
  // 送る
  // -------------------------------------------------------------------------

  /// 送るときの資料(いつも全文で添付)。readyでないファイルは含めない(送れない状態のときは呼ばない)。
  List<ChatNewAttachment> toNewAttachments() => [
    for (final d in _drafts)
      switch (d) {
        ChatTextDraft() => ChatTextAttachment(
          localId: d.localId,
          title: d.title,
          content: d.content,
        ),
        ChatFileDraft() when d.stage == ChatFileStage.ready && d.attachmentId != null =>
          ChatFileAttachment(
            attachmentId: d.attachmentId!,
            title: d.title,
            fileName: d.fileName,
            fileKind: d.fileKind,
          ),
        ChatFileDraft() => null,
      },
  ].whereType<ChatNewAttachment>().toList();

  /// 本文の「@名前」を印にするときの、下書きに対応する資料のid(テキストは仮のid、ファイルは本物のid)。
  String? tokenIdFor(DraftMention mention) {
    final d = draftById(mention.localId);
    return switch (d) {
      ChatTextDraft() => d.localId,
      ChatFileDraft() => d.attachmentId,
      null => null,
    };
  }

  /// 送った: 下書きを空にする(サーバーの行は送った資料になったので消さない)。
  void clearAfterSend() {
    _drafts.clear();
    _removed.clear();
    notifyListeners();
  }

  /// 入力欄が閉じられた: 準備中のものを止め、送っていない下書きをサーバーから消す。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final c in _cancels.values) {
      c.cancel();
    }
    for (final d in _drafts) {
      if (d is ChatFileDraft && d.attachmentId != null) {
        _deleteOnServer(d.attachmentId!);
      }
    }
    _drafts.clear();
    super.dispose();
  }
}
