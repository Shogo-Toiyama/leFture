import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';

const chatTestUid = 'user-1';

Map<String, dynamic> chatRow(
  String id,
  String role,
  String content, {
  String status = 'complete',
  String threadId = 'T1',
  String createdAt = '2026-10-18T00:00:00Z',
  Map<String, dynamic>? context,
}) => {
  'id': id,
  'thread_id': threadId,
  'role': role,
  'content': content,
  'status': status,
  'citations': const [],
  'context': context ?? const {},
  'credits_charged_micro': null,
  'created_at': createdAt,
};

/// 偽のバックエンド。テストごとに必要な部分だけ差し替える。
class FakeChatRepository extends Fake implements ChatRepository {
  @override
  String? get currentUserId => chatTestUid;

  /// スレッドごとのサーバーの行。nullを入れると読み込みの失敗になる。
  final Map<String, List<Map<String, dynamic>>?> serverRows = {};
  final Map<String, ChatMessage> messagesById = {};
  int pollCount = 0;

  /// sendMessageが流すイベント(テストが自分で操作する)。
  late StreamController<ChatStreamEvent> controller;
  ChatSendRequest? lastRequest;
  Object? sendError;

  Future<ChatMessage> Function(String id)? onStop;

  /// 報告(お問い合わせ)として送られたもの。
  final List<({String category, String message, Map<String, dynamic>? report})>
  reports = [];
  Object? reportError;

  @override
  Future<String> submitSupportReport({
    required String category,
    required String message,
    Map<String, dynamic>? report,
  }) async {
    final error = reportError;
    if (error != null) throw error;
    reports.add((category: category, message: message, report: report));
    return 'TICKET-123';
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMessageRows(String threadId) async {
    final rows = serverRows[threadId];
    if (rows == null) throw const ChatRequestException('NETWORK', 'offline');
    return rows;
  }

  /// listAttachmentsが返す資料。
  List<ChatAttachment> attachments = [];
  final List<(String, bool)> selectCalls = [];
  Object? selectError;
  final List<String> removedAttachments = [];

  @override
  Future<List<ChatAttachment>> listAttachments(String threadId) async => [
    ...attachments,
  ];

  @override
  Future<void> setAttachmentSelected(String attachmentId, bool selected) async {
    final error = selectError;
    if (error != null) throw error;
    selectCalls.add((attachmentId, selected));
  }

  @override
  Future<void> removeAttachment(String attachmentId) async {
    removedAttachments.add(attachmentId);
  }

  @override
  Future<ChatFileLink> getAttachmentFileLink(String attachmentId) async =>
      const ChatFileLink(
        url: 'https://files.example/a.pdf',
        fileName: 'a.pdf',
        kind: 'pdf',
        contentType: 'application/pdf',
      );

  @override
  Future<ChatMessage?> getMessage(String messageId) async {
    pollCount++;
    return messagesById[messageId];
  }

  @override
  Future<ChatMessage> stopMessage(String assistantMessageId) =>
      onStop!(assistantMessageId);

  @override
  Stream<ChatStreamEvent> sendMessage(ChatSendRequest request) {
    lastRequest = request;
    controller = StreamController<ChatStreamEvent>();
    final error = sendError;
    if (error != null) {
      scheduleMicrotask(() {
        controller.addError(error);
        controller.close();
      });
    }
    return controller.stream;
  }
}
