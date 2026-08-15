import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// コースに紐づくアトリビュート(年度/学期/科目/学校/担当教員)のPull専用
/// サービス。[CourseSyncService]と同じ理由でPushはOutbox化していない。
class CourseAttributeSyncService {
  final AppDatabase _db;

  CourseAttributeSyncService(this._db);

  static const _entityType = 'course_attribute';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, _entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull =
        forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    var query = supabase.from('course_attributes').select().eq('user_id', uid);

    if (!needsFullPull && cursor.lastPulledAt != null) {
      final skewBuffer = cursor.lastPulledAt!.subtract(
        const Duration(minutes: 5),
      );
      query = query.gt('updated_at', skewBuffer.toIso8601String());
    }

    final List<dynamic> data = await query.timeout(networkTimeout);

    DateTime? maxUpdatedAt = cursor?.lastPulledAt;
    if (data.isNotEmpty) {
      final companions = data.map((json) {
        final updatedAt = DateTime.parse(json['updated_at']);
        if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt!)) {
          maxUpdatedAt = updatedAt;
        }
        final metadata = json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null;
        return LocalCourseAttributesCompanion(
          id: Value(json['id'] as String),
          userId: Value(json['user_id'] as String),
          attributeType: Value(json['attribute_type'] as String),
          attributeName: Value(json['attribute_name'] as String),
          metadataJson: Value(metadata != null ? jsonEncode(metadata) : null),
          createdAt: Value(DateTime.parse(json['created_at'])),
          updatedAt: Value(updatedAt),
          deletedAt: Value(
            json['deleted_at'] == null
                ? null
                : DateTime.parse(json['deleted_at'] as String),
          ),
          syncStatus: const Value('synced'),
        );
      }).toList();

      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.localCourseAttributes, companions);
      });

      DevLog.add(
        '📥 [CourseAttributeSync] Pulled ${companions.length} attribute(s) from cloud.',
      );
    }

    await _db.upsertSyncCursor(
      userId: uid,
      entityType: _entityType,
      lastPulledAt: maxUpdatedAt,
      updateLastFullPulledAt: needsFullPull,
      lastFullPulledAt: needsFullPull ? now : null,
    );
  }
}
