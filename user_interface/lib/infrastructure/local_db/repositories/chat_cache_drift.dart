// lib/infrastructure/local_db/repositories/chat_cache_drift.dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_cache_drift.g.dart';

@Riverpod(keepAlive: true)
ChatCacheDrift chatCacheDrift(Ref ref) =>
    ChatCacheDrift(ref.watch(appDatabaseProvider));

/// AIチャットの表示用キャッシュ(LocalChatThreads / LocalChatMessages)。
///
/// 正しいのはいつもサーバー。開いた瞬間に前回の内容を出すためだけに持ち、読み直すたびに
/// サーバーの行で丸ごと置き換える(webでの編集・再生成・削除を正しく映すため、差分のマージはしない)。
/// 書き込み(送信・編集・削除)をここに先に書くことはしない。サインアウト時は、全テーブルを空にする
/// LocalDataWipeServiceが一緒に消す。
class ChatCacheDrift {
  ChatCacheDrift(this._db);

  final AppDatabase _db;

  // ---- スレッド一覧 ----

  /// スレッド一覧(最近動いた順)を監視する。
  Stream<List<ChatThread>> watchThreads(String userId) {
    final query = _db.select(_db.localChatThreads)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.lastMessageAt)]);
    return query.watch().map((rows) => [for (final r in rows) _thread(r)]);
  }

  /// 一覧をサーバーの行で丸ごと置き換える(サーバーに無くなったスレッドはここでも消える)。
  Future<void> replaceThreads(String userId, List<Map<String, dynamic>> rows) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.localChatThreads,
      )..where((t) => t.userId.equals(userId))).go();
      await _db.batch((b) {
        b.insertAll(_db.localChatThreads, [
          for (final row in rows)
            LocalChatThreadsCompanion.insert(
              id: row['id'] as String,
              userId: userId,
              lastMessageAt: DateTime.parse(row['last_message_at'] as String),
              rowJson: jsonEncode(row),
            ),
        ], mode: InsertMode.insertOrReplace);
      });
    });
  }

  /// スレッドを1件消す(中のメッセージも)。サーバーでの削除が済んだあとに呼ぶ。
  Future<void> deleteThread(String userId, String threadId) {
    return _db.transaction(() async {
      await (_db.delete(_db.localChatMessages)..where(
            (t) => t.userId.equals(userId) & t.threadId.equals(threadId),
          ))
          .go();
      await (_db.delete(
        _db.localChatThreads,
      )..where((t) => t.userId.equals(userId) & t.id.equals(threadId))).go();
    });
  }

  /// 名前の変更をキャッシュにも反映する(サーバーでの変更が済んだあとに呼ぶ)。
  Future<void> renameThread(
    String userId,
    String threadId,
    String title,
  ) async {
    final row =
        await (_db.select(_db.localChatThreads)
              ..where((t) => t.userId.equals(userId) & t.id.equals(threadId)))
            .getSingleOrNull();
    if (row == null) return;
    final map = Map<String, dynamic>.from(jsonDecode(row.rowJson) as Map)
      ..['title'] = title;
    await (_db.update(_db.localChatThreads)
          ..where((t) => t.userId.equals(userId) & t.id.equals(threadId)))
        .write(LocalChatThreadsCompanion(rowJson: Value(jsonEncode(map))));
  }

  // ---- メッセージ ----

  /// スレッドのメッセージ(古い順)。キャッシュが無ければ空。
  Future<List<ChatMessage>> getMessages(String userId, String threadId) async {
    final rows =
        await (_db.select(_db.localChatMessages)
              ..where(
                (t) => t.userId.equals(userId) & t.threadId.equals(threadId),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return [
      for (final r in rows)
        ChatMessage.fromMap(
          Map<String, dynamic>.from(jsonDecode(r.rowJson) as Map),
        ),
    ];
  }

  /// スレッドのメッセージを、サーバーの行で丸ごと置き換える。
  Future<void> replaceMessages(
    String userId,
    String threadId,
    List<Map<String, dynamic>> rows,
  ) {
    return _db.transaction(() async {
      await (_db.delete(_db.localChatMessages)..where(
            (t) => t.userId.equals(userId) & t.threadId.equals(threadId),
          ))
          .go();
      await _db.batch((b) {
        b.insertAll(_db.localChatMessages, [
          for (final row in rows)
            LocalChatMessagesCompanion.insert(
              id: row['id'] as String,
              userId: userId,
              threadId: threadId,
              createdAt: DateTime.parse(row['created_at'] as String),
              rowJson: jsonEncode(row),
            ),
        ], mode: InsertMode.insertOrReplace);
      });
    });
  }

  ChatThread _thread(LocalChatThread r) => ChatThread.fromMap(
    Map<String, dynamic>.from(jsonDecode(r.rowJson) as Map),
  );
}
