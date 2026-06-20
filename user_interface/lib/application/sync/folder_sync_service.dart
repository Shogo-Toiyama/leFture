import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

String _requireUid() {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw StateError('Not authenticated');
  return uid;
}

class FolderSyncService {
  static const _table = 'lecture_folders';

  final AppDatabase db;
  FolderSyncService(this.db);

  /// 1) Pull: updated_at > lastPullAt の差分を取ってローカルへupsert
  /// lastPullAtはとりあえず端末保存（後で server_now に改善可能）
  Future<void> pull({required DateTime? lastPullAt}) async {
    final uid = _requireUid();

    var query = supabase
        .from(_table)
        .select('id, user_id, name, parent_id, type, icon, color, is_favorite, sort_order, created_at, updated_at, deleted_at')
        .eq('user_id', uid);

    if (lastPullAt != null) {
      query = query.gt('updated_at', lastPullAt.toUtc().toIso8601String());
    }

    final rows = await query;

    final companions = (rows as List).map((e) {
      final m = e as Map<String, dynamic>;
      return LocalLectureFoldersCompanion(
        id: Value(m['id'] as String),
        userId: Value(m['user_id'] as String),
        name: Value((m['name'] as String?) ?? ''),
        parentId: Value(m['parent_id'] as String?),
        type: Value((m['type'] as String?) ?? 'binder'),
        icon: Value(m['icon'] as String?),
        color: Value(m['color'] as String?),
        isFavorite: Value((m['is_favorite'] as bool?) ?? false),
        sortOrder: Value((m['sort_order'] as int?) ?? 0),
        createdAt: Value(DateTime.parse(m['created_at'] as String).toUtc()),
        updatedAt: Value(DateTime.parse(m['updated_at'] as String).toUtc()),
        deletedAt: Value(m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String).toUtc()),
        needsSync: const Value(false),
      );
    }).toList();

    if (companions.isNotEmpty) {
      await db.upsertFoldersFromCloud(companions);
    }
  }

  /// 2) Push: outbox を順に流して Supabaseへ反映
  Future<void> pushOutbox() async {
    final uid = _requireUid();

    final items = await db.dequeueBatch(limit: 50);
    print('📤 outbox items = ${items.length}');
    if (items.isEmpty) return;

    final succeededIds = <int>[];

    for (final item in items) {
      try {
        final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;

        switch (item.op) {
          case 'create':
            // idはクライアント生成でinsert（衝突時はon conflict updateが欲しいが、まずはinsert）
            await supabase.from(_table).insert({
              'id': payload['id'],
              'name': payload['name'],
              'user_id': uid,
              'parent_id': payload['parent_id'],
              'type': payload['type'],
              // user_idはDB default auth.uid() が理想
              // ただし id指定insertでdefaultが効かない設定があるなら user_id入れる
            });
            break;

          case 'rename':
            await supabase
                .from(_table)
                .update({'name': payload['name']})
                .eq('id', item.entityId)
                .eq('user_id', uid);
            break;

          case 'favorite':
            await supabase
                .from(_table)
                .update({'is_favorite': payload['is_favorite']})
                .eq('id', item.entityId)
                .eq('user_id', uid);
            break;

          case 'delete':
            await supabase
                .from(_table)
                .update({'deleted_at': payload['deleted_at']})
                .eq('id', item.entityId)
                .eq('user_id', uid);
            break;

          default:
            throw StateError('Unknown op: ${item.op}');
        }

        succeededIds.add(item.id);

        // 成功したものは needsSync を落とす（雑に全部落としてOK）
        await (db.update(db.localLectureFolders)..where((t) => t.id.equals(item.entityId)))
            .write(const LocalLectureFoldersCompanion(needsSync: Value(false)));
      } catch (e, st) {
        print('❌ pushOutbox failed on item id=${item.id} op=${item.op} entityId=${item.entityId}');
        print('❌ error: $e');
        print(st.toString());
        break;
      }
    }

    if (succeededIds.isNotEmpty) {
      await db.deleteOutboxIds(succeededIds);
    }
  }

  Future<void> resetLocalToCloudBase() async {
    final uid = _requireUid();

    // まず outbox を全消し（Supabaseには触れない）
    await db.deleteAllOutbox();

    // ローカルフォルダを自分の分だけ消す
    await db.deleteAllLocalFolders(userId: uid);
  }

}
