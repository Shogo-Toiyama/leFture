// lib/application/chat/chat_threads.dart
import 'dart:async';

import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/infrastructure/local_db/repositories/chat_cache_drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_threads.g.dart';

/// スレッド一覧(最近動いた順)。端末のキャッシュを監視するので、開いた瞬間に前回の一覧が出る。
/// サーバーの最新に追いつくのは[ChatThreadActions.refresh]。
@riverpod
Stream<List<ChatThread>> chatThreadList(Ref ref) {
  final uid = ref.watch(chatRepositoryProvider).currentUserId;
  if (uid == null) return const Stream.empty();
  return ref.watch(chatCacheDriftProvider).watchThreads(uid);
}

/// スレッド一覧の操作。書き込みはバックエンド経由で、成功してからキャッシュに反映する。
@Riverpod(keepAlive: true)
class ChatThreadActions extends _$ChatThreadActions {
  @override
  void build() {}

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  ChatCacheDrift get _cache => ref.read(chatCacheDriftProvider);

  /// 一覧をサーバーの内容で丸ごと置き換える。通信に失敗したら例外(古い一覧はそのまま残る)。
  Future<void> refresh() async {
    final uid = _repo.currentUserId;
    if (uid == null) return;
    final rows = await _repo.fetchThreadRows();
    await _cache.replaceThreads(uid, rows);
  }

  Future<void> rename(String threadId, String title) async {
    final uid = _repo.currentUserId;
    await _repo.renameThread(threadId, title);
    if (uid != null) await _cache.renameThread(uid, threadId, title);
  }

  /// スレッドを削除する。今開いている会話なら、画面からも外す。
  Future<void> delete(String threadId) async {
    final uid = _repo.currentUserId;
    await _repo.deleteThread(threadId);
    if (uid != null) await _cache.deleteThread(uid, threadId);
    if (ref.read(chatConversationProvider).threadId == threadId) {
      ref.read(chatConversationProvider.notifier).clearConversation();
    }
  }

  /// ゴミ箱のスレッドを復元し、一覧を読み直す(復元したスレッドを一覧に戻すため)。
  Future<void> restore(String threadId) async {
    await _repo.restoreThread(threadId);
    await refresh();
  }

  /// ゴミ箱のスレッドを完全に削除する。ゴミ箱のスレッドは端末のキャッシュに無いので、消すのはサーバーだけ。
  Future<void> hardDelete(String threadId) => _repo.hardDeleteThread(threadId);
}
